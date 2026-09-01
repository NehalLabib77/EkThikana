"""Live Backblaze B2 validation.

Unit tests exercise `storage_service` against a stubbed S3 client, which
proves the call shapes but not that the bucket, region, endpoint and
application key actually work together. This script proves the round trip
against the real bucket.

    python scripts/verify_b2_live.py            # full round trip
    python scripts/verify_b2_live.py --keep     # leave the probe object behind

It writes only to a dedicated probe prefix and deletes what it writes, so it
is safe to run against the production bucket. It never prints the key id or
the application key.

Exit code 0 means every check passed.
"""
from __future__ import annotations

import argparse
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

# Allow running as `python scripts/verify_b2_live.py` from backend/.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.core.config import get_settings  # noqa: E402
from app.services import storage_service  # noqa: E402

PROBE_PREFIX = "_gochano_probe"

# A tiny valid PDF, so the probe exercises the same content type as a real
# study material rather than an opaque blob.
PROBE_PDF = (
    b"%PDF-1.4\n"
    b"1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n"
    b"2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n"
    b"3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 99 9]>>endobj\n"
    b"trailer<</Root 1 0 R>>\n%%EOF\n"
)

_passed: list[str] = []
_failed: list[tuple[str, str]] = []


def check(name: str):
    """Decorator-free helper: record a pass or a failure with its reason."""

    class _Ctx:
        def __enter__(self):
            print(f"  ... {name}", end="", flush=True)
            return self

        def __exit__(self, exc_type, exc, tb):
            if exc is None:
                _passed.append(name)
                print("\r  [PASS] " + name)
            else:
                _failed.append((name, f"{type(exc).__name__}: {exc}"))
                print("\r  [FAIL] " + name)
                print(f"      {type(exc).__name__}: {exc}")
            return True  # keep going; report everything at the end

    return _Ctx()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--keep",
        action="store_true",
        help="do not delete the probe object (for manual inspection)",
    )
    args = parser.parse_args()

    settings = get_settings()
    key = f"{PROBE_PREFIX}/{int(time.time())}_probe.pdf"

    print("Backblaze B2 live validation")
    print(f"  bucket   : {settings.b2_bucket_name}")
    print(f"  endpoint : {settings.b2_endpoint_url}")
    print(f"  region   : {settings.b2_region}")
    print(f"  probe key: {key}")
    print()

    # --- configuration ----------------------------------------------------
    with check("configuration is complete"):
        described = storage_service.describe_active_storage()
        if "UNCONFIGURED" in described:
            raise RuntimeError(described)

    with check("credentials are not echoed by describe_active_storage"):
        described = storage_service.describe_active_storage()
        if settings.b2_key_id and settings.b2_key_id in described:
            raise RuntimeError("key id leaked into the storage description")
        if settings.b2_application_key and settings.b2_application_key in described:
            raise RuntimeError("application key leaked into the description")

    with check("bucket is reachable and the key can list it"):
        bucket = storage_service._bucket()
        bucket.client.list_objects_v2(Bucket=bucket.name, MaxKeys=1)

    # --- round trip -------------------------------------------------------
    with check("upload"):
        storage_service.upload_bytes(key, PROBE_PDF, "application/pdf")

    with check("download returns the same bytes"):
        got = storage_service.download_bytes(key)
        if got != PROBE_PDF:
            raise RuntimeError(
                f"round trip mismatch: sent {len(PROBE_PDF)} bytes, got {len(got)}"
            )

    signed_inline = ""
    with check("signed URL (inline) is minted"):
        signed_inline = storage_service.create_signed_url(key)
        if not signed_inline.startswith("http"):
            raise RuntimeError(f"not a URL: {signed_inline[:60]}")

    with check("signed URL actually fetches the object over HTTPS"):
        with urllib.request.urlopen(signed_inline, timeout=30) as response:
            body = response.read()
        if body != PROBE_PDF:
            raise RuntimeError(
                f"signed URL returned {len(body)} bytes, expected {len(PROBE_PDF)}"
            )

    with check("signed URL carries inline disposition"):
        with urllib.request.urlopen(signed_inline, timeout=30) as response:
            disposition = response.headers.get("Content-Disposition", "")
        if "inline" not in disposition.lower():
            raise RuntimeError(f"Content-Disposition was {disposition!r}")

    with check("download URL carries attachment disposition"):
        url = storage_service.create_signed_url(key, download=True)
        with urllib.request.urlopen(url, timeout=30) as response:
            disposition = response.headers.get("Content-Disposition", "")
        if "attachment" not in disposition.lower():
            raise RuntimeError(f"Content-Disposition was {disposition!r}")

    with check("signed URL expires within the 15-minute ceiling"):
        url = storage_service.create_signed_url(key)
        # botocore puts the lifetime in X-Amz-Expires.
        query = urllib.parse.parse_qs(urllib.parse.urlparse(url).query)
        expires = int(query.get("X-Amz-Expires", ["0"])[0])
        if not 0 < expires <= 900:
            raise RuntimeError(f"X-Amz-Expires={expires}, expected 1..900")

    with check("the object is private without a signature"):
        bucket = storage_service._bucket()
        unsigned = (
            f"{settings.b2_endpoint_url.rstrip('/')}/{bucket.name}/{key}"
        )
        try:
            with urllib.request.urlopen(unsigned, timeout=30) as response:
                code = response.status
        except urllib.error.HTTPError as exc:
            code = exc.code
        if code == 200:
            raise RuntimeError(
                "the bucket served the object WITHOUT a signature - it is "
                "PUBLIC. Make it private: a public bucket hands out permanent "
                "unauthenticated URLs and defeats every ownership check."
            )

    # --- cleanup ----------------------------------------------------------
    if not args.keep:
        with check("delete"):
            storage_service.delete_file(key)

        with check("deleting a missing object is not an error"):
            storage_service.delete_file(f"{PROBE_PREFIX}/definitely-not-here.pdf")

    # --- report -----------------------------------------------------------
    print()
    print(f"passed: {len(_passed)}   failed: {len(_failed)}")
    if _failed:
        print("\nFailures:")
        for name, reason in _failed:
            print(f"  - {name}: {reason}")
        return 1
    print("\nBackblaze B2 is live and correct.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
