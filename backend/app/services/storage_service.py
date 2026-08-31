"""Backblaze B2 object storage (private bucket).

Gochano's private file provider is **Backblaze B2**, accessed through B2's
S3-compatible API with ``boto3``.  Everything a student uploads — study
materials, group resources, chat attachments, prescription scans — lands in a
private B2 bucket and is only ever handed to the client as a short-lived
presigned URL minted by this backend after an ownership/membership check.

Public call signatures are unchanged from the previous provider so every
caller (``account``, ``ai``, ``materials``, ``commute.ml_fare``) keeps working
without modification:

- ``upload_bytes(path, data, content_type)`` writes bytes under ``path``.
- ``create_signed_url(path, *, download=False) -> str`` returns a presigned
  GET URL (TTL from ``SIGNED_URL_TTL_SECONDS``, capped at 15 minutes).
- ``download_bytes(path) -> bytes`` returns the raw object bytes.
- ``delete_file(path)`` removes the object, idempotently.

Configuration (all required before any read/write; the service raises rather
than silently degrading, so a misconfigured deploy fails loudly instead of
writing user files somewhere unexpected):

    B2_BUCKET_NAME      e.g. gochano-files
    B2_ENDPOINT_URL     e.g. https://s3.us-west-004.backblazeb2.com
    B2_REGION           e.g. us-west-004
    B2_KEY_ID           application key id
    B2_APPLICATION_KEY  application key secret

The bucket must be created as **private**.  Public-bucket B2 hands out
permanent unauthenticated URLs, which would defeat the per-request ownership
checks in ``routers/materials.py``.
"""
from __future__ import annotations

import logging
from functools import lru_cache

import boto3
from botocore.client import Config as BotoConfig
from botocore.exceptions import ClientError

from app.core.config import get_settings

logger = logging.getLogger("gochano.storage")

# B2's S3 API is SigV4 over a regional endpoint. ``s3v4`` is required for
# presigned URLs to validate.
_SIGNATURE_VERSION = "s3v4"

# Spec §8.10 ceiling. ``SIGNED_URL_TTL_SECONDS`` may lower this but never
# raise it.
_MAX_SIGNED_URL_TTL = 900


class _B2Bucket:
    """A configured boto3 S3 client bound to the Gochano B2 bucket.

    Built once per process (see [_bucket]) so the TLS handshake and
    credential resolution are amortised across every upload and every
    signed-URL mint rather than paid per request.
    """

    __slots__ = ("client", "name")

    def __init__(self, client, name: str) -> None:
        self.client = client
        self.name = name


def _missing_config() -> list[str]:
    settings = get_settings()
    required = {
        "B2_BUCKET_NAME": settings.b2_bucket_name,
        "B2_ENDPOINT_URL": settings.b2_endpoint_url,
        "B2_REGION": settings.b2_region,
        "B2_KEY_ID": settings.b2_key_id,
        "B2_APPLICATION_KEY": settings.b2_application_key,
    }
    return [name for name, value in required.items() if not str(value).strip()]


@lru_cache
def _bucket() -> _B2Bucket:
    """Return the process-wide B2 bucket handle.

    Raises ``RuntimeError`` when B2 is not fully configured. Callers surface
    that as a 5xx rather than falling back to another provider — an ambiguous
    runtime storage target is exactly what spec §79 forbids.
    """
    missing = _missing_config()
    if missing:
        raise RuntimeError(
            "Backblaze B2 storage is not configured. Missing: "
            + ", ".join(missing)
        )

    settings = get_settings()
    client = boto3.client(
        "s3",
        endpoint_url=settings.b2_endpoint_url.strip(),
        region_name=settings.b2_region.strip(),
        aws_access_key_id=settings.b2_key_id.strip(),
        aws_secret_access_key=settings.b2_application_key.strip(),
        config=BotoConfig(
            signature_version=_SIGNATURE_VERSION,
            retries={"max_attempts": 3, "mode": "standard"},
            connect_timeout=15,
            read_timeout=60,
        ),
    )
    return _B2Bucket(client, settings.b2_bucket_name.strip())


def describe_active_storage() -> str:
    """One-line summary for the startup banner.

    Never includes the key id or secret.
    """
    missing = _missing_config()
    if missing:
        return f"backblaze-b2 <UNCONFIGURED: missing {','.join(missing)}>"
    settings = get_settings()
    return (
        f"backblaze-b2 bucket={settings.b2_bucket_name.strip()} "
        f"region={settings.b2_region.strip()}"
    )


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
    """Upload ``data`` to ``path``. Returns the object key on success."""
    bucket = _bucket()
    bucket.client.put_object(
        Bucket=bucket.name,
        Key=path,
        Body=data,
        ContentType=_content_type_for(path, content_type),
    )
    return path


def create_signed_url(path: str, *, download: bool = False) -> str:
    """Mint a short-lived presigned GET URL for ``path``.

    ``download=True`` forces a save dialog on the client via
    ``Content-Disposition: attachment``; otherwise the object renders inline
    (used by the in-app PDF/image reader).
    """
    bucket = _bucket()
    settings = get_settings()
    ttl = max(1, min(int(settings.signed_url_ttl_seconds), _MAX_SIGNED_URL_TTL))
    disposition = "attachment" if download else "inline"
    return bucket.client.generate_presigned_url(
        "get_object",
        Params={
            "Bucket": bucket.name,
            "Key": path,
            "ResponseContentDisposition": disposition,
        },
        ExpiresIn=ttl,
    )


def download_bytes(path: str) -> bytes:
    bucket = _bucket()
    response = bucket.client.get_object(Bucket=bucket.name, Key=path)
    return response["Body"].read()


def delete_file(path: str) -> None:
    """Delete ``path`` idempotently.

    A missing object is not an error: ``delete_file`` is called on rollback
    paths (failed upload, failed replace) where the object may never have
    been written.
    """
    bucket = _bucket()
    try:
        bucket.client.delete_object(Bucket=bucket.name, Key=path)
    except ClientError as exc:
        code = exc.response.get("Error", {}).get("Code", "")
        if code in {"NoSuchKey", "NoSuchBucket", "404"}:
            return
        logger.warning("B2 delete failed for %s: %s", path, code or exc)
    except Exception as exc:  # pragma: no cover - defensive
        logger.warning("B2 delete failed for %s: %s", path, exc)
