"""Firebase Storage-backed object storage.

Phase 2 of the migration replaces the previous Supabase Storage dependency
with Firebase Storage.  All public call signatures are preserved so the
existing routers and services (``account``, ``ai``, ``materials``,
``ml_fare``) keep working without changes.

Behavioural contract (unchanged from Supabase era):
- ``upload_bytes(path, data, content_type)`` writes bytes under ``path``
  with the supplied content type and returns the storage object.
- ``create_signed_url(path, *, download=False) -> str`` returns a short-lived
  signed URL (TTL controlled by ``SIGNED_URL_TTL_SECONDS``).
- ``download_bytes(path) -> bytes`` returns the raw object bytes.
- ``delete_file(path)`` removes the object.

The bucket is expected to be private; URLs are minted via service-account
credentials so the backend can serve download URLs even when the bucket
itself denies public reads.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from functools import lru_cache

import firebase_admin
from firebase_admin import storage

from app.core.config import get_settings


def _ensure_firebase() -> None:
    """Initialise the default Firebase app with the supplied storage bucket.

    Re-uses the existing default app when one already exists so we do not
    collide with ``app.core.firebase`` (which handles Auth and Firestore
    initialisation).  When the app exists but has no storage bucket we
    raise so the operator can fix ``FIREBASE_STORAGE_BUCKET``.
    """
    if firebase_admin._apps:
        opts = firebase_admin.get_app().options or {}
        if not opts.get("storageBucket"):
            raise RuntimeError(
                "Firebase app is initialised without a storage bucket. "
                "Set FIREBASE_STORAGE_BUCKET before using storage_service."
            )
        return

    settings = get_settings()
    if not settings.firebase_storage_bucket:
        raise RuntimeError("FIREBASE_STORAGE_BUCKET is not configured")

    # Delegate credential bootstrap to ``app.core.firebase`` so Auth/Firestore
    # share the same default app and the service-account JSON is decoded once.
    from app.core.firebase import _ensure_firebase as _ensure_default  # noqa: WPS433

    _ensure_default()

    opts = firebase_admin.get_app().options or {}
    if not opts.get("storageBucket"):
        # Re-initialise the default app with a storageBucket option.  This is
        # the only path that attaches the bucket because ``initialize_app``
        # accepts options only on first call.
        raise RuntimeError(
            "Firebase app was initialised without a storage bucket. "
            "Add FIREBASE_STORAGE_BUCKET to the Firebase options dict in "
            "app.core.firebase._ensure_firebase()."
        )


@lru_cache
def _bucket():
    _ensure_firebase()
    settings = get_settings()
    if not settings.firebase_storage_bucket:
        raise RuntimeError("FIREBASE_STORAGE_BUCKET is not configured")
    client = storage.Client(app=firebase_admin.get_app())
    return client.bucket(settings.firebase_storage_bucket)


def _content_type_for(path: str, content_type: str | None) -> str:
    if content_type:
        return content_type
    lower = path.lower()
    if lower.endswith((".png", ".jpg", ".jpeg", ".webp", ".gif")):
        ext = lower.rsplit(".", 1)[-1]
        if ext == "jpg":
            ext = "jpeg"
        return f"image/{ext}"
    if lower.endswith(".pdf"):
        return "application/pdf"
    if lower.endswith(".txt"):
        return "text/plain; charset=utf-8"
    return "application/octet-stream"


def upload_bytes(path: str, data: bytes, content_type: str):
    """Upload ``data`` to ``path`` and return the resulting blob object."""
    bucket = _bucket()
    blob = bucket.blob(path)
    blob.upload_from_string(
        data,
        content_type=_content_type_for(path, content_type),
    )
    return blob


def create_signed_url(path: str, *, download: bool = False) -> str:
    """Mint a V4 signed URL for ``path`` with the configured TTL."""
    bucket = _bucket()
    settings = get_settings()
    blob = bucket.blob(path)
    disposition = "attachment" if download else "inline"
    return blob.generate_signed_url(
        version="v4",
        expiration=datetime.now(timezone.utc)
        + timedelta(seconds=max(1, settings.signed_url_ttl_seconds)),
        method="GET",
        response_disposition=disposition,
    )


def download_bytes(path: str) -> bytes:
    bucket = _bucket()
    blob = bucket.blob(path)
    return blob.download_as_bytes()


def delete_file(path: str) -> None:
    """Delete ``path`` idempotently.  Missing-object errors are swallowed."""
    bucket = _bucket()
    blob = bucket.blob(path)
    try:
        blob.delete()
    except Exception:
        return
