"""Deciding *which* bucket a file lives in, explicitly.

While the Firebase-to-B2 migration is in flight, a material's bytes are in one
of two places. The tempting shortcut is to try B2 and fall back to Firebase on
any failure. That shortcut is wrong twice over:

  * A genuine B2 outage stops looking like an outage. Every read quietly
    succeeds from Firebase, slowly, and nobody notices the primary provider is
    down until the legacy bucket is finally switched off.
  * A botched migration stops looking botched. Files that were never copied
    keep serving from Firebase, so the migration reports success and the
    problem only surfaces after the source is deleted.

So a record states where its file is, in a ``storageProvider`` field, and the
reader honours that statement. Records written before the field existed carry
no statement, and for those exactly one probe is done -- and the answer is
handed back to the caller so it can be recorded and never probed again.

That last part is what keeps this from being a fallback in disguise: an
unknown provider is resolved once and written down, not guessed at on every
read.
"""
from __future__ import annotations

import logging
from dataclasses import dataclass
from typing import Any

from app.services import legacy_storage, storage_service

logger = logging.getLogger("gochano.storage.provider")

#: Backblaze B2 -- where every new file goes.
B2 = "b2"

#: The old Firebase Storage bucket -- read-only, being migrated out of.
FIREBASE = "firebase"

#: The record predates the field and has not been probed yet.
UNKNOWN = "unknown"

#: The field name on a material/resource record.
FIELD = "storageProvider"


@dataclass(frozen=True)
class Resolution:
    """Where a file is, and whether that is worth writing back to the record."""

    provider: str
    path: str

    #: True when this was worked out by probing rather than read from the
    #: record. The caller should persist ``provider`` so the probe is paid
    #: once per file, not once per read.
    should_persist: bool = False

    #: Set when neither bucket has the file. Not the same as an outage: the
    #: object is genuinely absent from both.
    missing: bool = False


def declared_provider(record: dict[str, Any] | None) -> str:
    """What the record says, without probing anything."""
    if not record:
        return UNKNOWN
    value = str(record.get(FIELD) or "").strip().lower()
    return value if value in {B2, FIREBASE} else UNKNOWN


def resolve(record: dict[str, Any], *, path_field: str = "filePath") -> Resolution:
    """Where this record's file actually is.

    Probes only when the record makes no claim, and says so via
    ``should_persist`` when it had to.
    """
    path = str(record.get(path_field) or "").strip()
    declared = declared_provider(record)

    if not path:
        return Resolution(provider=UNKNOWN, path="", missing=True)

    # The record states where its file is. Believe it -- that statement is
    # the whole point of the field.
    if declared != UNKNOWN:
        return Resolution(provider=declared, path=path)

    # With no legacy bucket configured there is only one place the file can
    # be, so there is nothing to work out. Probing here would turn a
    # momentary B2 hiccup into a 404 on a file that is perfectly fine, and
    # would add a HEAD to every read for the rest of the app's life.
    if not legacy_storage.is_configured():
        return Resolution(provider=B2, path=path)

    # Two possible homes and no statement, so probe once. B2 first: it is the
    # primary provider, and a file in both has already been migrated.
    if storage_service.object_exists(path):
        return Resolution(provider=B2, path=path, should_persist=True)

    if legacy_storage.exists(path):
        logger.info("Resolved an unlabelled file to the legacy bucket: %s", path)
        return Resolution(provider=FIREBASE, path=path, should_persist=True)

    # Absent from both. Do not label it -- writing a provider for a file that
    # is not there would make a missing file look migrated.
    return Resolution(provider=UNKNOWN, path=path, missing=True)


def signed_url_for(resolution: Resolution, *, download: bool = False) -> str | None:
    """A presigned URL from whichever bucket actually holds the file."""
    if resolution.missing or not resolution.path:
        return None
    if resolution.provider == FIREBASE:
        return legacy_storage.signed_url(resolution.path, download=download)
    return storage_service.create_signed_url(resolution.path, download=download)


def download_for(resolution: Resolution) -> bytes | None:
    if resolution.missing or not resolution.path:
        return None
    if resolution.provider == FIREBASE:
        return legacy_storage.download_bytes(resolution.path)
    return storage_service.download_bytes(resolution.path)


__all__ = [
    "B2",
    "FIELD",
    "FIREBASE",
    "UNKNOWN",
    "Resolution",
    "declared_provider",
    "download_for",
    "resolve",
    "signed_url_for",
]
