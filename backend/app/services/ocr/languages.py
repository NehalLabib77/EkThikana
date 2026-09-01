"""What Tesseract can actually read on this server.

A Bengali prescription run through an English-only Tesseract does not fail --
it returns confident-looking Latin garbage. That is the worst possible failure
mode for a medicine list, so the language pack is checked explicitly and the
answer is reported rather than assumed.

``ben.traineddata`` ships in the Docker image (``tesseract-ocr-ben`` in the
Dockerfile). This module is what proves it is there at runtime, and what tells
the app to stop claiming Bengali support when it is not.
"""
from __future__ import annotations

import logging
from typing import Any

logger = logging.getLogger("gochano.ocr.languages")

#: Without this, nothing can be read at all.
REQUIRED = ("eng",)

#: Without this, Bengali prescriptions are silently mis-read as Latin text.
RECOMMENDED = ("ben",)


def installed() -> tuple[str, ...]:
    """Language codes Tesseract reports, or an empty tuple if it cannot run.

    An empty tuple means "we could not ask", never "there are none". The
    caller has to tell those apart, so this does not substitute a default.
    """
    try:
        import pytesseract

        return tuple(sorted(pytesseract.get_languages(config="")))
    except Exception as exc:
        logger.warning("Could not list Tesseract languages: %s", type(exc).__name__)
        return ()


def tesseract_version() -> str | None:
    try:
        import pytesseract

        return str(pytesseract.get_tesseract_version())
    except Exception:
        return None


def best_language(available: tuple[str, ...] | None = None) -> str:
    """The richest language string this install actually supports.

    Bengali prescriptions in Bangladesh are overwhelmingly mixed script --
    Latin drug names beside Bengali instructions -- so both packs are used
    together when both exist.
    """
    langs = installed() if available is None else available
    if not langs:
        # Tesseract could not be queried. "eng" is the only code guaranteed to
        # exist in any install; asking for "ben" we cannot confirm would turn
        # a missing pack into a hard failure instead of a degraded read.
        return "eng"
    if "ben" in langs and "eng" in langs:
        return "eng+ben"
    if "ben" in langs:
        return "ben"
    return "eng"


def status() -> dict[str, Any]:
    """A report the app and the operator can both act on."""
    langs = installed()
    version = tesseract_version()

    if not langs and version is None:
        return {
            "available": False,
            "reason": "tesseract_not_found",
            "installedLanguages": [],
            "missingRequired": list(REQUIRED),
            "missingRecommended": list(RECOMMENDED),
            "language": None,
            "bengaliSupported": False,
            "message": (
                "Tesseract is not installed or is not on PATH, so prescription "
                "scanning cannot run on this server."
            ),
        }

    missing_required = [code for code in REQUIRED if code not in langs]
    missing_recommended = [code for code in RECOMMENDED if code not in langs]
    bengali = "ben" in langs

    if missing_required:
        message = (
            "Tesseract is installed but the English language pack is missing, "
            "so prescription scanning cannot run."
        )
    elif missing_recommended:
        message = (
            "Bengali is not installed, so only Latin-script text can be read. "
            "Bengali instructions on a prescription will be missed rather than "
            "guessed at."
        )
    else:
        message = "English and Bengali text recognition are both available."

    return {
        "available": not missing_required,
        "reason": None if not missing_required else "missing_language_pack",
        "tesseractVersion": version,
        "installedLanguages": list(langs),
        "missingRequired": missing_required,
        "missingRecommended": missing_recommended,
        "language": best_language(langs),
        "bengaliSupported": bengali,
        "message": message,
    }


__all__ = [
    "RECOMMENDED",
    "REQUIRED",
    "best_language",
    "installed",
    "status",
    "tesseract_version",
]
