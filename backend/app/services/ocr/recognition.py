"""Running Tesseract across candidate images and reporting real confidence.

Two ideas hold this module together.

**Pick the winner by measurement, not by hope.** ``preprocess.variants``
produces several renderings of the same page; each is recognised and scored on
Tesseract's own per-word confidence, and the best-scoring result is the one
returned. Choosing a preprocessing recipe in advance is guessing; running them
and comparing is not.

**Never invent a confidence.** Every number here comes from Tesseract's
``image_to_data`` output. Where Tesseract gives no confidence, this reports
``None`` and the band is ``unknown`` -- not a default, not an average, not a
plausible-looking percentage. A fabricated 87% on a misread medicine name is
precisely the failure this feature cannot afford.

The bands are deliberately coarse. Tesseract's raw score is a per-word
character-classifier confidence; it is meaningful as an ordering but not
calibrated as a probability, so presenting "82.4%" to a patient would imply a
precision the number does not have. High / Medium / Low is what it can honestly
support.
"""
from __future__ import annotations

import logging
from dataclasses import dataclass, field
from typing import Any

from PIL import Image

from app.services.ocr import preprocess
from app.services.ocr.languages import best_language

logger = logging.getLogger("gochano.ocr.recognition")

#: Tesseract page segmentation modes worth trying, in order.
#: 6 -- a uniform block of text, which most printed prescriptions are.
#: 4 -- a single column of variable-size text, which handles a prescription
#:      whose medicine list is set in a smaller face than its heading.
#: 11 -- sparse text, the fallback for a handwritten or scattered layout.
PSM_MODES = (6, 4, 11)

#: Band boundaries on Tesseract's 0-100 per-word confidence. Chosen to be
#: conservative rather than flattering: a "High" band should mean the text can
#: be read back without squinting at the image, so the bar sits well above the
#: point at which Tesseract merely stops guessing.
HIGH_CONFIDENCE = 80.0
MEDIUM_CONFIDENCE = 60.0

#: Words scoring below this are noise -- page edges, staple holes, the shadow
#: of the photographer's hand -- and are excluded from the average so they
#: cannot drag an otherwise clean read into a lower band.
NOISE_CONFIDENCE = 30.0

#: A read this short is a failure regardless of its confidence: Tesseract is
#: very sure about the four characters it found on a blank page.
MIN_USEFUL_CHARS = 25

#: Good enough to stop trying other variants.
GOOD_ENOUGH_CONFIDENCE = 85.0
GOOD_ENOUGH_CHARS = 120


def band_for(confidence: float | None) -> str:
    """High / Medium / Low, or ``unknown`` when there is nothing to band."""
    if confidence is None:
        return "unknown"
    if confidence >= HIGH_CONFIDENCE:
        return "high"
    if confidence >= MEDIUM_CONFIDENCE:
        return "medium"
    return "low"


@dataclass
class WordResult:
    """One recognised word and the confidence Tesseract gave it."""

    text: str
    confidence: float
    line_index: int


@dataclass
class RecognitionResult:
    """What one Tesseract pass produced, and how much to trust it."""

    text: str
    words: list[WordResult] = field(default_factory=list)
    variant: str = ""
    psm: int = 0
    language: str = ""

    @property
    def mean_confidence(self) -> float | None:
        """Average confidence over the words that are not noise.

        ``None`` when Tesseract reported no usable words. That is a real
        answer -- "we do not know" -- and is passed through as such.
        """
        scored = [w.confidence for w in self.words if w.confidence >= NOISE_CONFIDENCE]
        if not scored:
            return None
        return sum(scored) / len(scored)

    @property
    def band(self) -> str:
        return band_for(self.mean_confidence)

    @property
    def score(self) -> float:
        """How this result ranks against other variants of the same page.

        Confidence alone would prefer a variant that recognised three crisp
        words over one that recognised the whole prescription slightly less
        cleanly, so length is weighed in. The length term saturates: past a
        few hundred characters more text says nothing about quality.
        """
        confidence = self.mean_confidence
        if confidence is None:
            return 0.0
        useful = len(self.text.strip())
        if useful < MIN_USEFUL_CHARS:
            return 0.0
        length_factor = min(1.0, useful / 400.0)
        return confidence * (0.6 + 0.4 * length_factor)

    def confidence_for(self, fragment: str) -> float | None:
        """Confidence for a specific piece of recognised text.

        Used to say how well a *particular medicine name* was read, rather
        than reporting one number for the whole page. Returns ``None`` when
        the fragment cannot be matched back to recognised words -- which
        happens when the parser cleaned the text -- rather than substituting
        the page average and calling it the word's confidence.
        """
        wanted = [token for token in fragment.lower().split() if token]
        if not wanted:
            return None

        scores: list[float] = []
        for token in wanted:
            matches = [
                w.confidence
                for w in self.words
                if token in w.text.lower() or w.text.lower() in token
            ]
            if matches:
                scores.append(max(matches))

        if not scores:
            return None
        return sum(scores) / len(scores)

    def to_dict(self) -> dict[str, Any]:
        confidence = self.mean_confidence
        return {
            "band": self.band,
            # Rounded to a whole number: the underlying score is not
            # calibrated finely enough for a decimal to mean anything.
            "meanConfidence": None if confidence is None else round(confidence),
            "wordCount": len(self.words),
            "variant": self.variant,
            "psm": self.psm,
            "language": self.language,
        }


def _run_tesseract(
    image: Image.Image,
    *,
    language: str,
    psm: int,
) -> RecognitionResult | None:
    """One pass, returning real per-word confidences or nothing."""
    try:
        import pytesseract
        from pytesseract import Output
    except Exception:
        return None

    config = f"--oem 3 --psm {psm}"
    try:
        data = pytesseract.image_to_data(
            image, lang=language, config=config, output_type=Output.DICT
        )
    except Exception as exc:
        logger.warning("Tesseract pass failed (psm=%s): %s", psm, type(exc).__name__)
        return None

    words: list[WordResult] = []
    lines: dict[tuple, list[str]] = {}

    count = len(data.get("text", []))
    for index in range(count):
        text = str(data["text"][index]).strip()
        if not text:
            continue
        try:
            confidence = float(data["conf"][index])
        except (TypeError, ValueError):
            continue
        # Tesseract uses -1 for structural rows that carry no word.
        if confidence < 0:
            continue

        key = (
            data.get("block_num", [0] * count)[index],
            data.get("par_num", [0] * count)[index],
            data.get("line_num", [0] * count)[index],
        )
        lines.setdefault(key, []).append(text)
        words.append(WordResult(text=text, confidence=confidence, line_index=len(lines)))

    text = "\n".join(" ".join(tokens) for tokens in lines.values()).strip()
    return RecognitionResult(text=text, words=words, psm=psm, language=language)


def recognise(
    image: Image.Image,
    *,
    language: str | None = None,
    try_orientations: bool = True,
) -> RecognitionResult:
    """Read a page, choosing the preprocessing that measurably works best.

    Returns an empty result rather than raising when nothing can be read.
    "We could not read this" is a legitimate answer for a blurred photo, and
    the caller reports it as such instead of showing an empty medicine list as
    though the prescription were blank.
    """
    lang = language or best_language()
    best = RecognitionResult(text="", language=lang)
    # Every candidate that read *something*, ranked only by how much and how
    # confidently. `score` deliberately zeroes anything shorter than a
    # prescription, which is right for ranking a full page and wrong as a
    # test of existence: a crop of just the medicine list, or a single
    # Bengali instruction line, reads perfectly and scores zero. Without this
    # fallback such a page came back as "nothing was recognised".
    fallback = RecognitionResult(text="", language=lang)

    def _consider(result: RecognitionResult) -> None:
        nonlocal best, fallback
        if result.score > best.score:
            best = result
        if _fallback_rank(result) > _fallback_rank(fallback):
            fallback = result

    for variant in preprocess.variants(image):
        for psm in PSM_MODES:
            result = _run_tesseract(variant.image, language=lang, psm=psm)
            if result is None:
                continue
            result.variant = variant.name
            _consider(result)

            # A clean, complete read makes the remaining passes pointless.
            confidence = best.mean_confidence
            if (
                confidence is not None
                and confidence >= GOOD_ENOUGH_CONFIDENCE
                and len(best.text) >= GOOD_ENOUGH_CHARS
            ):
                return best

    # Only now consider that the page might be sideways: each orientation is
    # another full set of passes, and prescriptions are almost always upright.
    if try_orientations and not best.text:
        base = preprocess.normalise(image)
        for rotated in preprocess.orientations(base):
            for psm in PSM_MODES[:2]:
                result = _run_tesseract(rotated.image, language=lang, psm=psm)
                if result is None:
                    continue
                result.variant = rotated.name
                _consider(result)

    return best if best.text else fallback


def _fallback_rank(result: RecognitionResult) -> tuple[int, float]:
    """Rank a read purely on how much was recognised, then how confidently."""
    return (len(result.text.strip()), result.mean_confidence or 0.0)


__all__ = [
    "GOOD_ENOUGH_CONFIDENCE",
    "HIGH_CONFIDENCE",
    "MEDIUM_CONFIDENCE",
    "MIN_USEFUL_CHARS",
    "NOISE_CONFIDENCE",
    "PSM_MODES",
    "RecognitionResult",
    "WordResult",
    "band_for",
    "recognise",
]
