"""Contract tests for the Backblaze B2 storage service.

These exercise ``app.services.storage_service`` directly with a stubbed boto3
client, rather than through a router. The router-level tests monkeypatch the
four public functions away, so without this file the actual B2 implementation
would never execute in CI.

What is asserted:
  * B2 must be fully configured or the service raises — it must never
    silently fall back to another provider (spec §79).
  * Uploads land under the exact key given, with the resolved content type.
  * Signed URLs are presigned GETs, capped at the 15-minute spec ceiling,
    and carry the right Content-Disposition for view vs. download.
  * Deletes are idempotent for a missing object.
  * The bucket handle is built once per process.
"""
from __future__ import annotations

import pytest
from botocore.exceptions import ClientError

import app.services.storage_service as storage
from app.core.config import Settings


class _StubS3:
    """Records calls the way boto3's S3 client would receive them."""

    def __init__(self, *, missing_key: bool = False) -> None:
        self.put_calls: list[dict] = []
        self.presign_calls: list[dict] = []
        self.delete_calls: list[dict] = []
        self.objects: dict[str, bytes] = {}
        self._missing_key = missing_key

    def put_object(self, **kwargs):
        self.put_calls.append(kwargs)
        self.objects[kwargs["Key"]] = kwargs["Body"]
        return {}

    def generate_presigned_url(self, operation, *, Params, ExpiresIn):
        self.presign_calls.append(
            {"operation": operation, "params": Params, "expires_in": ExpiresIn}
        )
        return f"https://b2.example/{Params['Key']}?X-Amz-Expires={ExpiresIn}"

    def get_object(self, *, Bucket, Key):
        class _Body:
            def __init__(self, data: bytes) -> None:
                self._data = data

            def read(self) -> bytes:
                return self._data

        return {"Body": _Body(self.objects.get(Key, b""))}

    def delete_object(self, **kwargs):
        self.delete_calls.append(kwargs)
        if self._missing_key:
            raise ClientError(
                {"Error": {"Code": "NoSuchKey", "Message": "not found"}},
                "DeleteObject",
            )
        self.objects.pop(kwargs["Key"], None)
        return {}


def _configured_settings(**overrides) -> Settings:
    base = {
        "b2_bucket_name": "gochano-files",
        "b2_endpoint_url": "https://s3.us-west-004.backblazeb2.com",
        "b2_region": "us-west-004",
        "b2_key_id": "test-key-id",
        "b2_application_key": "test-application-key",
        "signed_url_ttl_seconds": 900,
    }
    base.update(overrides)
    return Settings(**base)


@pytest.fixture()
def b2(monkeypatch):
    """Bind a stub S3 client into the storage service."""
    stub = _StubS3()
    monkeypatch.setattr(
        storage, "_bucket", lambda: storage._B2Bucket(stub, "gochano-files")
    )
    monkeypatch.setattr(storage, "get_settings", _configured_settings)
    return stub


# --- configuration contract ------------------------------------------------


@pytest.mark.parametrize(
    "missing",
    [
        "b2_bucket_name",
        "b2_endpoint_url",
        "b2_region",
        "b2_key_id",
        "b2_application_key",
    ],
)
def test_incomplete_b2_config_raises_rather_than_falling_back(monkeypatch, missing):
    monkeypatch.setattr(
        storage, "get_settings", lambda: _configured_settings(**{missing: ""})
    )
    storage._bucket.cache_clear()
    with pytest.raises(RuntimeError) as exc:
        storage._bucket()
    assert missing.upper() in str(exc.value)
    storage._bucket.cache_clear()


def test_describe_active_storage_never_leaks_credentials(monkeypatch):
    monkeypatch.setattr(storage, "get_settings", _configured_settings)
    described = storage.describe_active_storage()
    assert "backblaze-b2" in described
    assert "gochano-files" in described
    assert "test-key-id" not in described
    assert "test-application-key" not in described


def test_bucket_handle_is_built_once_per_process():
    assert hasattr(storage._bucket, "__wrapped__"), (
        "_bucket must be @lru_cache-wrapped so the B2 client is reused "
        "across uploads and signed-URL mints"
    )


# --- upload ----------------------------------------------------------------


def test_upload_writes_exact_key_and_content_type(b2):
    storage.upload_bytes("users/uid-1/abc.pdf", b"%PDF-1.4", "application/pdf")
    call = b2.put_calls[-1]
    assert call["Bucket"] == "gochano-files"
    assert call["Key"] == "users/uid-1/abc.pdf"
    assert call["Body"] == b"%PDF-1.4"
    assert call["ContentType"] == "application/pdf"


def test_upload_infers_content_type_when_caller_passes_none(b2):
    storage.upload_bytes("users/uid-1/scan.jpg", b"\xff\xd8", None)
    assert b2.put_calls[-1]["ContentType"] == "image/jpeg"


# --- signed URLs -----------------------------------------------------------


def test_signed_url_is_presigned_get_with_inline_disposition(b2):
    url = storage.create_signed_url("users/uid-1/abc.pdf")
    call = b2.presign_calls[-1]
    assert call["operation"] == "get_object"
    assert call["params"]["Key"] == "users/uid-1/abc.pdf"
    assert call["params"]["ResponseContentDisposition"] == "inline"
    assert url.startswith("https://b2.example/")


def test_signed_url_download_forces_attachment(b2):
    storage.create_signed_url("users/uid-1/abc.pdf", download=True)
    assert b2.presign_calls[-1]["params"]["ResponseContentDisposition"] == "attachment"


def test_signed_url_ttl_matches_configuration(b2):
    storage.create_signed_url("users/uid-1/abc.pdf")
    assert b2.presign_calls[-1]["expires_in"] == 900


def test_signed_url_ttl_is_capped_at_the_spec_ceiling(monkeypatch, b2):
    """An operator setting an over-long TTL must not widen the exposure
    window of a private file."""
    monkeypatch.setattr(
        storage,
        "get_settings",
        lambda: _configured_settings(signed_url_ttl_seconds=86400),
    )
    storage.create_signed_url("users/uid-1/abc.pdf")
    assert b2.presign_calls[-1]["expires_in"] == 900


# --- download / delete -----------------------------------------------------


def test_download_returns_object_bytes(b2):
    storage.upload_bytes("models/commute/rickshaw_quantiles.joblib", b"blob", None)
    assert storage.download_bytes("models/commute/rickshaw_quantiles.joblib") == b"blob"


def test_delete_removes_the_object(b2):
    storage.upload_bytes("users/uid-1/gone.pdf", b"x", "application/pdf")
    storage.delete_file("users/uid-1/gone.pdf")
    assert b2.delete_calls[-1]["Key"] == "users/uid-1/gone.pdf"
    assert "users/uid-1/gone.pdf" not in b2.objects


def test_delete_of_missing_object_is_not_an_error(monkeypatch):
    """Rollback paths call delete_file for objects that may never have been
    written; a NoSuchKey must not surface as a 500."""
    stub = _StubS3(missing_key=True)
    monkeypatch.setattr(
        storage, "_bucket", lambda: storage._B2Bucket(stub, "gochano-files")
    )
    storage.delete_file("users/uid-1/never-written.pdf")  # must not raise
    assert stub.delete_calls
