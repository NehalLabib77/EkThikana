"""Read-only access to files still sitting in the old Firebase Storage bucket.

Gochano's file provider is Backblaze B2. Files uploaded before that switch are
still in Firebase Storage, and this module is the only way the backend reaches
them.

Three deliberate constraints:

  * **Read-only.** There is no upload here and no delete. New files go to B2;
    old files are copied out by ``scripts/migrate_firebase_to_b2.py``, which
    leaves the originals in place. Nothing in the running app may remove a
    file from the bucket it is being migrated out of.
  * **Optional.** ``FIREBASE_STORAGE_BUCKET`` unset means "there is no legacy
    bucket", which is the correct state once migration is finished. Every
    function reports that rather than raising, so removing the setting is a
    supported way to switch legacy reads off.
  * **Never a silent fallback.** Callers reach this module because a record
    says its file lives in Firebase, not because a B2 read failed. A blind
    try-B2-then-Firebase read hides a genuine B2 outage behind a slow
    fallback, and hides a botched migration behind an apparent success.
"""
from __future__ import annotations

import logging
from typing import Any

from app.core.config import get_settings

logger = logging.getLogger("gochano.storage.legacy")


def is_configured() -> bool:
    """Whether a legacy bucket is configured at all.

    False is a normal, healthy state after migration -- not an error.
    """
    return bool(get_settings().firebase_storage_bucket.strip())


def _bucket() -> Any | None:
    """The legacy bucket handle, or None when it is unavailable.

    Returns None rather than raising: a legacy read failing must degrade to
    "this file could not be fetched", not take down a request that has
    already found the record it needed.
    """
    name = get_settings().firebase_storage_bucket.strip()
    if not name:
        return None
    try:
        from firebase_admin import storage as firebase_storage

        return firebase_storage.bucket(name)
    except Exception as exc:
        logger.warning(
            "Legacy Firebase Storage bucket unavailable: %s", type(exc).__name__
        )
        return None


def exists(path: str) -> bool:
    """Whether ``path`` is present in the legacy bucket."""
    bucket = _bucket()
    if bucket is None or not path:
        return False
    try:
        return bool(bucket.blob(path).exists())
    except Exception as exc:
        logger.warning("Legacy existence check failed for %s: %s", path, type(exc).__name__)
        return False


def download_bytes(path: str) -> bytes | None:
    """Fetch ``path`` from the legacy bucket, or None if it is not readable."""
    bucket = _bucket()
    if bucket is None or not path:
        return None
    try:
        return bucket.blob(path).download_as_bytes()
    except Exception as exc:
        logger.warning("Legacy download failed for %s: %s", path, type(exc).__name__)
        return None


def metadata(path: str) -> dict[str, Any] | None:
    """Size and content type, used by the migration to verify a copy."""
    bucket = _bucket()
    if bucket is None or not path:
        return None
    try:
        blob = bucket.blob(path)
        blob.reload()
        return {
            "size": int(blob.size or 0),
            "contentType": blob.content_type or "",
            "updated": blob.updated.isoformat() if getattr(blob, "updated", None) else None,
        }
    except Exception as exc:
        logger.warning("Legacy metadata failed for %s: %s", path, type(exc).__name__)
        return None


def signed_url(path: str, *, download: bool = False) -> str | None:
    """A short-lived URL for a file that has not been migrated yet.

    Kept so a student is never told their old material is gone while the
    migration is still running.
    """
    from datetime import timedelta

    bucket = _bucket()
    if bucket is None or not path:
        return None
    settings = get_settings()
    ttl = max(1, min(int(settings.signed_url_ttl_seconds), 900))
    try:
        return bucket.blob(path).generate_signed_url(
            expiration=timedelta(seconds=ttl),
            response_disposition="attachment" if download else "inline",
        )
    except Exception as exc:
        logger.warning("Legacy signed URL failed for %s: %s", path, type(exc).__name__)
        return None


__all__ = [
    "download_bytes",
    "exists",
    "is_configured",
    "metadata",
    "signed_url",
]
