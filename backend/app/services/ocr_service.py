"""Reading a prescription and proposing -- never deciding -- what it says.

Recognition itself now lives in ``app.services.ocr``: several preprocessing
variants are tried and the one Tesseract is measurably most confident about
wins. This module turns recognised text into review candidates, and its rule
has not changed -- it extracts only what is visibly written. It does not
prescribe, does not infer a schedule, and does not invent a clock time the
prescription did not state.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from io import BytesIO
from typing import Any

from PIL import Image
from pdf2image import convert_from_bytes

from app.services.ocr import medicine_names
from app.services.ocr.recognition import RecognitionResult, band_for, recognise
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
# A dose whose digits OCR mangled: "5mg" read as "omg", "10ml" as "lOml".
# The unit survives even when the number does not, and text ending in a dose
# unit is a dose rather than part of the medicine's name. Bare "g" is excluded
# deliberately -- it would truncate real names.
_GARBLED_DOSE_TAIL_RE = re.compile(
    r"\s*\S{0,6}(?:mg|mcg|ml|iu|units?)\.?$",
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


@dataclass
class Extraction:
    """Recognised text plus how well it was actually read.

    ``recognition`` is None when the text came from a PDF's own text layer
    rather than from OCR. That distinction matters: an embedded text layer is
    exact, so attaching an OCR confidence band to it would be inventing
    uncertainty as surely as inventing certainty.
    """

    text: str
    recognition: RecognitionResult | None = None
    pages: list[RecognitionResult] = field(default_factory=list)
    source: str = "ocr"  # "ocr" | "pdf_text"

    def quality(self) -> dict[str, Any]:
        if self.source == "pdf_text":
            return {
                "source": "pdf_text",
                "band": "high",
                "meanConfidence": None,
                "note": "Read from the PDF's own text layer, not from OCR.",
            }
        if self.recognition is None:
            return {
                "source": "ocr",
                "band": "unknown",
                "meanConfidence": None,
                "note": "Text recognition did not report a confidence.",
            }
        payload = self.recognition.to_dict()
        payload["source"] = "ocr"
        return payload


def _ocr_image(image: Image.Image) -> str:
    """Recognised text only, for callers that do not need the quality."""
    return recognise(image).text


def extract(data: bytes, content_type: str) -> Extraction:
    """Read a prescription, reporting how confidently it was read."""
    content_type = (content_type or "").lower()

    if "pdf" in content_type or data.startswith(b"%PDF-"):
        # A PDF carrying its own text layer needs no OCR, and running it would
        # replace exact text with a recognition of a rendering of that text.
        try:
            text = extract_pdf_text(data, max_chars=30000)
            if len(text.strip()) >= 40:
                return Extraction(text=text, source="pdf_text")
        except Exception:
            pass

        images = convert_from_bytes(data, first_page=1, last_page=3, dpi=220)
        pages = [recognise(img) for img in images]
        combined = "\n\n".join(page.text for page in pages).strip()
        # The weakest page governs: a prescription is only as readable as the
        # page carrying the medicine list, and averaging would hide that.
        weakest = min(
            (page for page in pages if page.mean_confidence is not None),
            key=lambda page: page.mean_confidence,
            default=None,
        )
        return Extraction(text=combined, recognition=weakest, pages=pages)

    image = Image.open(BytesIO(data))
    result = recognise(image)
    return Extraction(text=result.text, recognition=result, pages=[result])


def extract_text(data: bytes, content_type: str) -> str:
    """Recognised text only. Kept for callers that do not need the quality."""
    return extract(data, content_type).text


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

    # Only when something is left over: stripping the tail off a one-word
    # line would delete the medicine rather than its dose.
    stripped = _GARBLED_DOSE_TAIL_RE.sub("", cleaned).strip()
    if stripped and len(stripped) >= 3 and " " in cleaned:
        cleaned = stripped

    return cleaned[:100]


def parse_medicine_candidates(
    text: str,
    recognition: RecognitionResult | None = None,
) -> list[dict[str, Any]]:
    """Extract review candidates without making medical decisions.

    Exact times are returned only when OCR sees an explicit clock value.
    Frequency shorthands and meal phrases are returned as schedule hints; the
    review step in the app requires the reader to choose and confirm the
    actual reminder times.

    When ``recognition`` is supplied, each candidate also carries how well its
    own name was read and, where one is safe to offer, a spelling suggestion.
    Both are advisory. The name returned is always the text that was actually
    recognised -- a silently corrected medicine name is the one mistake this
    feature must never make.
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

        result: dict[str, Any] = {
            "name": name,
            "dose": dose,
            "instruction": " • ".join(_instruction_fragments(line)),
            "scheduleHints": _instruction_fragments(line),
            "explicitTimes": list(dict.fromkeys(_TIME_RE.findall(line))),
            "sourceText": line,
            "lineIndex": index,
        }
        result.update(medicine_names.annotate(name))

        if recognition is not None:
            # The confidence for *this name*, not for the page. None when the
            # name cannot be traced back to recognised words -- reporting the
            # page average there would attach a number this name never earned.
            confidence = recognition.confidence_for(name)
            result["nameConfidence"] = {
                "band": band_for(confidence),
                "value": None if confidence is None else round(confidence),
            }
        results.append(result)
        if len(results) >= 20:
            break

    return results
