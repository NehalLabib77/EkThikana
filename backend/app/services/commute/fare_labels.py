"""Turning internal dataset identifiers into something a student can read.

The CommuteBD dataset tracks where every fare came from with ids like
``SRC_CNG_2015``, ``SRC_BRTA_METRO_FARES`` and ``USER_PROVIDED_ASSUMPTION``.
Those are exactly right for a data pipeline and exactly wrong on a phone: they
were being rendered verbatim on the fare cards, so a student was shown
``USER_PROVIDED_ASSUMPTION`` beside a price and left to guess what it meant.

The ids are kept — they are how the dataset stays auditable — but they are
translated here on the way out. Anything unrecognised falls back to a plain
statement of how confident the number is, never to the raw id: a source we
have no wording for is precisely the one a student should not be shown.
"""
from __future__ import annotations

import re

#: Human wording for each source id in the shipped dataset.
_SOURCE_LABELS: dict[str, str] = {
    "SRC_BRTA_METRO_FARES": "Official BRTA fare table",
    "SRC_BRTA_FARES": "Official BRTA fare table",
    "SRC_DMTCL_FARES": "Official metro fare table",
    "SRC_CNG_2015": "Government CNG meter rule (2015)",
    "SRC_TAXI_2014": "Government taxi meter rule (2014)",
    "USER_PROVIDED_ASSUMPTION": "Distance-based estimate",
    "USER_PROVIDED": "Distance-based estimate",
}

#: Wording by fare type, used when the source id is unknown or absent.
_TYPE_LABELS: dict[str, str] = {
    "official": "Official fare table",
    "calculated": "Calculated from the official rate",
    "crowdsourced": "Reported by riders",
    "historical": "Older government rule",
    "estimated": "Distance-based estimate",
    "unverified": "Distance-based estimate",
    "none": "",
}

#: An identifier rather than prose: SCREAMING_SNAKE, or prefixed like a key.
_LOOKS_INTERNAL = re.compile(r"^[A-Z][A-Z0-9]*(?:_[A-Z0-9]+)+$")


def source_label(source: str | None, fare_type: str | None = None) -> str:
    """A sentence describing where a fare came from.

    Never returns an internal identifier. When the source is unrecognised the
    fare type decides the wording, and when that is unknown too the result is
    empty — showing nothing beats showing a token that means nothing.
    """
    raw = (source or "").strip()

    if raw:
        mapped = _SOURCE_LABELS.get(raw.upper())
        if mapped:
            return mapped
        # Free text that a human already wrote (an OSM attribution, a note)
        # passes through; an identifier does not.
        if not _LOOKS_INTERNAL.match(raw):
            return raw

    return _TYPE_LABELS.get((fare_type or "").strip().lower(), "")


def clean_option(option: dict) -> dict:
    """Strip pipeline detail out of one fare option before it is sent.

    ``source`` becomes readable, and the raw confidence word is dropped: the
    provenance badge already tells a student how far to trust the number, and
    "Confidence: Low" beside it read as a second, vaguer verdict on the same
    thing.

    The internal values stay available under ``debug`` for the data tools that
    need them; nothing in the app reads that key.
    """
    out = dict(option)
    raw_source = out.get("source")
    raw_confidence = out.get("confidence")

    out["source"] = source_label(
        None if raw_source is None else str(raw_source),
        None if out.get("fareType") is None else str(out.get("fareType")),
    )
    out.pop("confidence", None)

    debug = {
        key: value
        for key, value in (("sourceId", raw_source), ("confidence", raw_confidence))
        if value is not None
    }
    if debug:
        out["debug"] = debug
    return out


__all__ = ["clean_option", "source_label"]
