"""Run the whole prescription OCR pipeline against a real image.

    python scripts/verify_prescription_ocr.py [image ...]

Unit tests drive the recogniser with a scripted fake, which proves this code
reports what Tesseract said but not that Tesseract can read what we hand it.
This script closes that gap: it runs the real engine over real pixels and
prints what a student would end up reviewing.

With no arguments it renders a synthetic prescription -- English drug lines
with Bengali instructions, tilted and speckled the way a hand-held photo is --
and runs that. **Synthetic is not a substitute for a photograph of a real
prescription.** It exercises the full path end to end and shows the pipeline
works; it says nothing about handwriting. Pass real images as arguments to
test those.

Requires Tesseract on PATH. If ben.traineddata is missing, the script says so
rather than quietly reading Bengali as Latin.
"""
from __future__ import annotations

import sys
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

BACKEND = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BACKEND))

import numpy as np  # noqa: E402
from PIL import Image, ImageDraw, ImageFont  # noqa: E402

from app.services.ocr import languages, medicine_names, preprocess  # noqa: E402
from app.services.ocr.recognition import recognise  # noqa: E402
from app.services.ocr_service import parse_medicine_candidates  # noqa: E402

# A prescription as it is actually written in Dhaka: Latin drug names, a
# Bengali instruction or two, dose-frequency shorthand.
LINES = [
    ("Dr. Rahim Uddin, MBBS", False),
    ("City Medical Centre, Dhaka", False),
    ("", False),
    ("Rx", False),
    ("1. Tab. Amlodipine 5mg      1+0+0", False),
    ("   খাবারের পরে", True),
    ("2. Cap. Omeprazole 20mg     1-0-1", False),
    ("   before food", False),
    ("3. Tab. Metformin 500mg     1+0+1", False),
    ("   রাতে", True),
    ("4. Tab. Paracetamol 500mg   SOS", False),
    ("", False),
    ("Review after 2 weeks", False),
]

LATIN_FONTS = ["C:/Windows/Fonts/arial.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"]
BENGALI_FONTS = [
    "C:/Windows/Fonts/Nirmala.ttc",
    "/usr/share/fonts/truetype/lohit-bengali/Lohit-Bengali.ttf",
    "/usr/share/fonts/truetype/freefont/FreeSerif.ttf",
]


def _font(paths: list[str], size: int):
    for candidate in paths:
        if Path(candidate).exists():
            try:
                return ImageFont.truetype(candidate, size)
            except OSError:
                continue
    return None


def synthetic_page(width=1100, height=1500, angle=-2.5) -> Image.Image:
    """A printed prescription photographed slightly crooked, with sensor noise."""
    rng = np.random.default_rng(11)
    paper = np.clip(rng.normal(242, 7, size=(height, width)), 0, 255).astype(np.uint8)
    image = Image.fromarray(paper, mode="L").convert("RGB")
    draw = ImageDraw.Draw(image)

    latin = _font(LATIN_FONTS, 34)
    bengali = _font(BENGALI_FONTS, 34)
    if latin is None:
        print("  ! no Latin font found; cannot render the synthetic page")
        return image

    y = 90
    for text, is_bengali in LINES:
        if text:
            font = (bengali or latin) if is_bengali else latin
            draw.text((90, y), text, fill=(30, 30, 35), font=font)
        y += 52

    return image.rotate(angle, resample=Image.Resampling.BICUBIC, fillcolor=(242, 242, 242))


def report(image: Image.Image, label: str) -> bool:
    print()
    print("=" * 70)
    print(label)
    print("=" * 70)

    skew = preprocess.estimate_skew(preprocess.normalise(image))
    print(f"  detected skew correction   {skew:+.2f} deg")

    result = recognise(image)
    confidence = result.mean_confidence

    print(f"  winning variant            {result.variant or '(none)'}")
    print(f"  page segmentation mode     {result.psm}")
    print(f"  language                   {result.language}")
    print(f"  words recognised           {len(result.words)}")
    print(
        "  confidence                 "
        + (f"{confidence:.0f} ({result.band})" if confidence is not None else "unknown")
    )

    if not result.text.strip():
        print("\n  nothing was recognised")
        return False

    print("\n  --- recognised text ---")
    for line in result.text.splitlines()[:24]:
        print(f"  | {line}")

    medicines = parse_medicine_candidates(result.text, result)
    print(f"\n  --- {len(medicines)} medicine candidate(s) ---")
    for item in medicines:
        band = item.get("nameConfidence", {}).get("band", "unknown")
        value = item.get("nameConfidence", {}).get("value")
        confidence_text = "unknown" if value is None else f"{value} ({band})"
        print(f"  * {item['name']!r}  dose={item['dose']!r}  confidence={confidence_text}")
        if item["scheduleHints"]:
            print(f"      hints: {', '.join(item['scheduleHints'])}")
        if item["explicitTimes"]:
            print(f"      explicit times: {', '.join(item['explicitTimes'])}")
        if item.get("recognisedAsKnownGeneric"):
            print("      matches a known generic name")
        suggestion = item.get("suggestion")
        if suggestion:
            print(
                f"      suggestion: {suggestion['suggested']!r} "
                f"({suggestion['band']}, applied={suggestion['applied']})"
            )

    return bool(medicines)


def main(argv: list[str]) -> int:
    status = languages.status()
    print("Tesseract")
    print(f"  version    {status.get('tesseractVersion')}")
    print(f"  languages  {', '.join(status['installedLanguages']) or '(none)'}")
    print(f"  using      {status['language']}")
    print(f"  {status['message']}")

    if not status["available"]:
        print("\nCannot verify OCR without a working Tesseract install.")
        return 2
    if not status["bengaliSupported"]:
        print("\n  ! Bengali instructions in the synthetic page will not be read.")

    ok = 0
    total = 0

    if argv:
        for path in argv:
            total += 1
            try:
                image = Image.open(path)
            except Exception as exc:
                print(f"\n  could not open {path}: {exc}")
                continue
            ok += bool(report(image, f"{path}"))
    else:
        total = 1
        ok += bool(report(synthetic_page(), "Synthetic prescription (rendered, tilted -2.5 deg)"))

    print()
    print("=" * 70)
    print(f"extracted medicines from {ok}/{total} image(s)")
    if not argv:
        print(
            "This is a rendered page, not a photograph. It verifies the pipeline "
            "end to end; it says nothing about handwriting accuracy."
        )
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
