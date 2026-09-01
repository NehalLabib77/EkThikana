"""An optional model pass that *organises* OCR text -- and never adds to it.

The rule-based parser in ``ocr_service`` is reliable on a tidy printed
prescription and struggles on a messy one, where a medicine and its schedule
land on different lines or a dose is written before the name. A language model
is genuinely good at that kind of re-grouping.

It is also very good at helpfully inventing a dose that was never written, and
that is the one thing this feature must never do. So the pass is fenced in:

  * **Extraction only.** The model is given the OCR text and asked to group
    it. It is told, and then independently checked, that every value it
    returns must appear in the source text.
  * **Verified, not trusted.** ``_grounded`` re-checks each returned field
    against the OCR text after the fact. A field that cannot be found is
    dropped, however plausible it looks. The prompt is a request; this is the
    enforcement.
  * **Schema-validated.** Anything malformed is discarded wholesale rather
    than partially salvaged.
  * **Never load-bearing.** Any failure -- no API key, a timeout, a bad
    response, a quota refusal -- falls back to the rule-based parser. The
    feature works with this pass switched off, which is how it ships by
    default.
  * **Still not medical advice.** Nothing here decides a schedule. Reminder
    times remain something the reader enters and confirms.
"""
from __future__ import annotations

import json
import logging
import re
from typing import Any

logger = logging.getLogger("gochano.ocr.structuring")

#: Text longer than this is truncated. A prescription is a page; anything
#: larger is a scan artefact and only costs tokens.
MAX_INPUT_CHARS = 6000

#: More entries than any real prescription has.
MAX_MEDICINES = 20

#: How much of a returned value must be traceable to the OCR text before it is
#: accepted. Not 1.0: OCR text contains line breaks and stray punctuation, so
#: an exact substring test would reject correct groupings for cosmetic
#: reasons. Every *word* still has to be present.
GROUNDING_THRESHOLD = 1.0

PROMPT = """You are reorganising text that came from OCR of a medical prescription.

Return ONLY a JSON object of this exact shape:

{"medicines": [{"name": "...", "dose": "...", "instruction": "..."}]}

Rules you must follow:
- Copy text from the source. Do not translate, correct spelling, expand
  abbreviations, or add anything that is not written there.
- If a field is not present in the source, use an empty string. Never guess.
- Do not infer clock times. Do not add a frequency that is not written.
- Do not add medicines that are not in the source.
- If the source contains no medicines, return {"medicines": []}.

Source text:
---
%s
---"""


def _words(value: str) -> list[str]:
    return [token for token in re.split(r"[^\wঀ-৿]+", value.lower()) if token]


def _grounded(value: str, haystack_words: set[str]) -> bool:
    """Whether every word of ``value`` actually appears in the OCR text.

    This is the check that stops a helpful hallucination. The model is asked
    not to invent; this is what makes that request enforceable.
    """
    tokens = _words(value)
    if not tokens:
        return True
    present = sum(1 for token in tokens if token in haystack_words)
    return present / len(tokens) >= GROUNDING_THRESHOLD


def _extract_json(raw: str) -> dict[str, Any] | None:
    """Pull the JSON object out of a model response.

    Models wrap JSON in prose and fences often enough that failing on it would
    throw away good extractions, so the object is located rather than assumed
    to be the whole reply.
    """
    text = raw.strip()
    fence = re.search(r"```(?:json)?\s*(.*?)```", text, re.DOTALL)
    if fence:
        text = fence.group(1).strip()

    start = text.find("{")
    end = text.rfind("}")
    if start == -1 or end <= start:
        return None
    try:
        parsed = json.loads(text[start : end + 1])
    except (json.JSONDecodeError, ValueError):
        return None
    return parsed if isinstance(parsed, dict) else None


def validate(payload: Any, source_text: str) -> list[dict[str, str]] | None:
    """Schema-check a model response and drop anything not in the source.

    Returns None when the response is unusable, so the caller can fall back
    rather than proceed with a half-parsed result.
    """
    if not isinstance(payload, dict):
        return None
    medicines = payload.get("medicines")
    if not isinstance(medicines, list):
        return None

    haystack = set(_words(source_text))
    out: list[dict[str, str]] = []

    for entry in medicines[:MAX_MEDICINES]:
        if not isinstance(entry, dict):
            continue

        name = str(entry.get("name") or "").strip()[:100]
        if len(name) < 2:
            continue
        # A name that is not in the OCR text is an invention, and a medicine
        # name is the worst possible thing to invent.
        if not _grounded(name, haystack):
            logger.info("Dropped an ungrounded medicine name from the model response")
            continue

        dose = str(entry.get("dose") or "").strip()[:60]
        if dose and not _grounded(dose, haystack):
            dose = ""

        instruction = str(entry.get("instruction") or "").strip()[:200]
        if instruction and not _grounded(instruction, haystack):
            instruction = ""

        out.append({"name": name, "dose": dose, "instruction": instruction})

    return out


async def structure(uid: str, text: str) -> list[dict[str, str]] | None:
    """Ask the model to group the OCR text. Returns None on any failure.

    None is not an error condition -- it is the normal answer whenever the
    model is unavailable or unconvincing, and the caller simply uses the
    rule-based parser.
    """
    source = (text or "").strip()
    if len(source) < 20:
        return None
    source = source[:MAX_INPUT_CHARS]

    try:
        from app.services.ai_service import generate

        raw = await generate(uid, PROMPT % source)
    except Exception as exc:
        # Includes a missing API key, a quota refusal and a provider outage.
        # None of them should break prescription scanning.
        logger.info("Model structuring unavailable (%s); using the parser", type(exc).__name__)
        return None

    parsed = _extract_json(raw)
    if parsed is None:
        logger.info("Model structuring returned no usable JSON; using the parser")
        return None

    validated = validate(parsed, source)
    if not validated:
        return None
    return validated


__all__ = [
    "GROUNDING_THRESHOLD",
    "MAX_INPUT_CHARS",
    "MAX_MEDICINES",
    "PROMPT",
    "structure",
    "validate",
]
