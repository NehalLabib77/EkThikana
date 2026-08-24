from __future__ import annotations

import re
from io import BytesIO
from typing import Any

import pytesseract
from PIL import Image, ImageEnhance, ImageFilter, ImageOps
from pdf2image import convert_from_bytes

from app.services.pdf_service import extract_pdf_text

# Common prescription tokens. We only extract what appears in the image/text;
# we never prescribe or invent a dose/time.
_DOSE_RE = re.compile(
    r"\b\d+(?:\.\d+)?\s*(?:mg|mcg|µg|g|ml|mL|iu|IU|unit|units|%)\b",
    re.IGNORECASE,
)
_TIME_RE = re.compile(
    r"\b(?:(?:0?[1-9]|1[0-2])[:.]\d{2}\s*(?:am|pm)|(?:[01]?\d|2[0-3])[:.]\d{2})\b",
    re.IGNORECASE,
)
_FREQ_RE = re.compile(
    r"\b(?:\d\s*[-+]\s*\d\s*[-+]\s*\d|OD|QD|BD|BID|TDS|TID|QID|HS|SOS|PRN)\b",
    re.IGNORECASE,
)
_PREFIX_RE = re.compile(
    r"\b(?:tab(?:let)?|cap(?:sule)?|syr(?:up)?|inj(?:ection)?|cream|ointment|drop|drops)\.?\b",
    re.IGNORECASE,
)
_INSTRUCTION_TERMS = (
    "after breakfast",
    "before breakfast",
    "after lunch",
    "before lunch",
    "after dinner",
    "before dinner",
    "after food",
    "before food",
    "morning",
    "noon",
    "evening",
    "night",
    "bedtime",
    "empty stomach",
    "খাবার পরে",
    "খাবারের পরে",
    "খাবার আগে",
    "খাবারের আগে",
    "সকালে",
    "সকাল",
    "দুপুরে",
    "দুপুর",
    "রাতে",
    "রাত",
)


def _preprocess(image: Image.Image) -> Image.Image:
    """Lightweight preprocessing inspired by the supplied OCR projects.

    Upscaling, grayscale/autocontrast and sharpening generally help phone
    photos while keeping the Render Docker image small (no OpenCV required).
    """
    img = ImageOps.exif_transpose(image).convert("RGB")
    max_side = max(img.size)
    if max_side < 2200:
        scale = min(2.0, 2200 / max(max_side, 1))
        img = img.resize(
            (max(1, int(img.width * scale)), max(1, int(img.height * scale))),
            Image.Resampling.LANCZOS,
        )
    gray = ImageOps.grayscale(img)
    gray = ImageOps.autocontrast(gray, cutoff=1)
    gray = ImageEnhance.Contrast(gray).enhance(1.35)
    gray = gray.filter(ImageFilter.SHARPEN)
    return gray


def _ocr_image(image: Image.Image) -> str:
    processed = _preprocess(image)
    try:
        available = set(pytesseract.get_languages(config=""))
    except Exception:
        available = {"eng"}

    lang = "eng+ben" if "ben" in available else "eng"
    # PSM 6 is good for a block-like prescription. If it extracts very little,
    # retry sparse text mode for uneven handwritten/printed layouts.
    text = pytesseract.image_to_string(processed, lang=lang, config="--oem 3 --psm 6")
    if len(text.strip()) < 25:
        text2 = pytesseract.image_to_string(processed, lang=lang, config="--oem 3 --psm 11")
        if len(text2.strip()) > len(text.strip()):
            text = text2
    return text.strip()


def extract_text(data: bytes, content_type: str) -> str:
    content_type = (content_type or "").lower()

    if "pdf" in content_type or data.startswith(b"%PDF-"):
        try:
            text = extract_pdf_text(data, max_chars=30000)
            if len(text.strip()) >= 40:
                return text
        except Exception:
            pass

        images = convert_from_bytes(data, first_page=1, last_page=3, dpi=220)
        return "\n\n".join(_ocr_image(img) for img in images).strip()

    image = Image.open(BytesIO(data))
    return _ocr_image(image)


def candidate_lines(text: str) -> list[str]:
    lines: list[str] = []
    for raw in text.splitlines():
        line = " ".join(raw.split())
        if len(line) >= 3:
            lines.append(line[:220])
    return lines[:100]


def _instruction_fragments(line: str) -> list[str]:
    lower = line.lower()
    found: list[str] = []
    for term in _INSTRUCTION_TERMS:
        if term.lower() in lower:
            found.append(term)
    freq = _FREQ_RE.findall(line)
    found.extend(x.strip() for x in freq if x.strip())
    return list(dict.fromkeys(found))


def _medicine_name(line: str, dose: str) -> str:
    cleaned = _PREFIX_RE.sub("", line)
    if dose:
        cleaned = cleaned.replace(dose, "")
    # Remove explicit clocks and common frequency shorthand from the name.
    cleaned = _TIME_RE.sub("", cleaned)
    cleaned = _FREQ_RE.sub("", cleaned)
    for term in _INSTRUCTION_TERMS:
        cleaned = re.sub(re.escape(term), "", cleaned, flags=re.IGNORECASE)
    cleaned = re.sub(r"^[\s\-–—:;,.\d.)]+", "", cleaned)
    cleaned = re.sub(r"[\s\-–—:;,.]+$", "", cleaned)
    cleaned = re.sub(r"\s{2,}", " ", cleaned).strip()
    return cleaned[:100]


def parse_medicine_candidates(text: str) -> list[dict[str, Any]]:
    """Extract review candidates without making medical decisions.

    Exact times are returned only when OCR sees an explicit clock value.
    Frequency shorthands/meal phrases are returned as schedule hints; the
    Flutter review step requires the user to choose/confirm actual times.
    """
    lines = candidate_lines(text)
    results: list[dict[str, Any]] = []

    for index, line in enumerate(lines):
        dose_match = _DOSE_RE.search(line)
        has_prefix = bool(_PREFIX_RE.search(line))
        has_freq = bool(_FREQ_RE.search(line))
        has_instruction = any(term.lower() in line.lower() for term in _INSTRUCTION_TERMS)

        # A likely medicine line normally has a dose or dosage-form prefix.
        # Frequency/instruction-only lines are attached to the previous item.
        if not (dose_match or has_prefix):
            if results and (has_freq or has_instruction or _TIME_RE.search(line)):
                prev = results[-1]
                hints = prev["scheduleHints"] + _instruction_fragments(line)
                prev["scheduleHints"] = list(dict.fromkeys(hints))
                prev["explicitTimes"] = list(
                    dict.fromkeys(prev["explicitTimes"] + _TIME_RE.findall(line))
                )
                prev["sourceText"] = f"{prev['sourceText']} | {line}"[:320]
            continue

        dose = dose_match.group(0) if dose_match else ""
        name = _medicine_name(line, dose)
        if len(name) < 2:
            continue

        # Filter obvious headings that accidentally contain numbers.
        if name.lower() in {"date", "age", "weight", "bp", "rx", "prescription"}:
            continue

        result = {
            "name": name,
            "dose": dose,
            "instruction": " • ".join(_instruction_fragments(line)),
            "scheduleHints": _instruction_fragments(line),
            "explicitTimes": list(dict.fromkeys(_TIME_RE.findall(line))),
            "sourceText": line,
            "lineIndex": index,
        }
        results.append(result)
        if len(results) >= 20:
            break

    return results
