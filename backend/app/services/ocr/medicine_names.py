"""Cleaning up an OCR'd medicine name, and *suggesting* a correction.

The single most dangerous thing this codebase could do is quietly change a
medicine name. "Clobazam" auto-corrected to "Clonazepam" is a different drug,
a different indication and a different dose, and the patient would never see
that it happened.

So this module never replaces a name. It returns what OCR read, plus a
suggestion the reader can accept or reject, plus how good that suggestion is.
The decision stays with the person holding the prescription.

The safeguards that make a suggestion trustworthy enough to show at all:

  * **A high similarity floor.** Close is not enough; it has to be nearly
    right, consistent with an OCR slip rather than a different word.
  * **The first letter must survive.** Nearly every dangerous confusion
    between two real drugs starts differently. OCR slips rarely do.
  * **Ambiguity suppresses the suggestion.** If two known medicines are
    similarly close, there is no way to tell which was meant, and offering
    the alphabetically luckier one would be worse than offering nothing.
  * **Length has to be comparable.** "Cef" is close to many things and
    identifies none of them.

Absence from the vocabulary means nothing at all. Most prescriptions in
Bangladesh are written as brand names, which this list deliberately excludes,
so "no suggestion" is the common and entirely unremarkable case.
"""
from __future__ import annotations

import functools
import re
import unicodedata
from dataclasses import dataclass
from difflib import SequenceMatcher
from pathlib import Path

VOCABULARY_PATH = (
    Path(__file__).resolve().parent.parent.parent.parent
    / "data"
    / "medicines"
    / "common_generics.txt"
)

#: Below this, a suggestion is a guess rather than a correction.
MIN_SIMILARITY = 0.86

#: A second candidate this close to the best one makes the match ambiguous,
#: and an ambiguous drug-name suggestion is worse than none.
AMBIGUITY_MARGIN = 0.04

#: Too short to identify anything: "Tab" and "Cef" match half the list.
MIN_NAME_LENGTH = 4

#: A suggestion may not differ wildly in length from what was read.
MAX_LENGTH_RATIO = 1.4

#: Characters Tesseract routinely confuses in a Latin drug name. Applied only
#: to build a comparison key -- never to the text shown to the reader, who
#: needs to see what was actually on the page.
_OCR_CONFUSIONS = str.maketrans(
    {
        "0": "o",
        "1": "l",
        "5": "s",
        "8": "b",
        "|": "l",
        "!": "l",
        "@": "a",
        "$": "s",
    }
)

_NOISE = re.compile(r"[^a-z\s]+")
_SPACES = re.compile(r"\s+")


@dataclass(frozen=True)
class Suggestion:
    """A possible correction, and how confident we are in it."""

    suggested: str
    similarity: float

    @property
    def band(self) -> str:
        """Deliberately coarse -- a similarity ratio is not a probability."""
        if self.similarity >= 0.95:
            return "high"
        if self.similarity >= 0.90:
            return "medium"
        return "low"

    def to_dict(self) -> dict[str, object]:
        return {
            "suggested": self.suggested,
            "similarity": round(self.similarity, 3),
            "band": self.band,
            # Said explicitly so no caller can read a suggestion as a decision.
            "applied": False,
        }


@functools.lru_cache(maxsize=1)
def vocabulary() -> tuple[str, ...]:
    """Known generic names, or an empty tuple if the list is unreadable.

    An empty vocabulary disables suggestions entirely, which is the correct
    degradation: no list means no basis for proposing a change.
    """
    try:
        raw = VOCABULARY_PATH.read_text(encoding="utf-8")
    except OSError:
        return ()

    names: list[str] = []
    for line in raw.splitlines():
        entry = line.strip()
        if not entry or entry.startswith("#"):
            continue
        names.append(entry.lower())
    return tuple(dict.fromkeys(names))


def normalise(name: str) -> str:
    """A comparison key: accents folded, OCR confusions resolved, noise gone.

    This is *only* a key. The name shown to the reader is always the one that
    was actually recognised, because a cleaned-up display would hide the very
    ambiguity they are being asked to resolve.
    """
    if not name:
        return ""
    folded = unicodedata.normalize("NFKD", name)
    folded = "".join(char for char in folded if not unicodedata.combining(char))
    folded = folded.lower().translate(_OCR_CONFUSIONS)
    folded = _NOISE.sub(" ", folded)
    return _SPACES.sub(" ", folded).strip()


def _similarity(left: str, right: str) -> float:
    return SequenceMatcher(None, left, right).ratio()


def suggest(name: str, *, vocab: tuple[str, ...] | None = None) -> Suggestion | None:
    """Propose a correction, or return None when none is safe to offer."""
    known = vocabulary() if vocab is None else vocab
    if not known:
        return None

    key = normalise(name)
    if len(key) < MIN_NAME_LENGTH:
        return None

    # An exact hit needs no suggestion -- there is nothing to correct.
    if key in known:
        return None

    # Every candidate that is even plausibly the right word is scored, not
    # only those clearing the floor. The runner-up matters for the ambiguity
    # check below, and a near-miss just under the floor is exactly the kind of
    # rival that should stop us committing to the winner.
    scored: list[tuple[float, str]] = []
    for candidate in known:
        # The first letter is the cheapest and strongest guard against
        # suggesting a genuinely different drug.
        if candidate[0] != key[0]:
            continue
        ratio = max(len(candidate), len(key)) / max(1, min(len(candidate), len(key)))
        if ratio > MAX_LENGTH_RATIO:
            continue
        scored.append((_similarity(key, candidate), candidate))

    if not scored:
        return None

    scored.sort(reverse=True)
    best_score, best_name = scored[0]

    if best_score < MIN_SIMILARITY:
        return None

    # Two plausible answers means we do not know which was meant, and the
    # alphabetically luckier one is not an answer.
    if len(scored) > 1 and (best_score - scored[1][0]) < AMBIGUITY_MARGIN:
        return None

    return Suggestion(suggested=best_name, similarity=best_score)


def is_known(name: str, *, vocab: tuple[str, ...] | None = None) -> bool:
    """Whether the name matches the vocabulary exactly.

    False says only "not in this list". Most prescriptions here are written as
    brand names, which the list excludes on purpose, so False is the ordinary
    case and carries no implication about the medicine.
    """
    known = vocabulary() if vocab is None else vocab
    return bool(known) and normalise(name) in known


def annotate(name: str, *, vocab: tuple[str, ...] | None = None) -> dict[str, object]:
    """What the review screen needs in order to ask a clear question."""
    suggestion = suggest(name, vocab=vocab)
    return {
        # Always the text that was actually recognised.
        "name": name,
        "recognisedAsKnownGeneric": is_known(name, vocab=vocab),
        "suggestion": None if suggestion is None else suggestion.to_dict(),
    }


__all__ = [
    "AMBIGUITY_MARGIN",
    "MIN_NAME_LENGTH",
    "MIN_SIMILARITY",
    "Suggestion",
    "annotate",
    "is_known",
    "normalise",
    "suggest",
    "vocabulary",
]
