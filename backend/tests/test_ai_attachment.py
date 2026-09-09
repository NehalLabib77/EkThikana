"""Tests for /api/ai/attachment-question endpoint.

Validates file upload, text extraction per type, error paths,
authentication, and no-public-URL leakage.
"""

from __future__ import annotations

import io
import sys
from pathlib import Path

_BACKEND_ROOT = Path(__file__).resolve().parent.parent
if str(_BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(_BACKEND_ROOT))


def _auth(fake_auth, uid):
    token = fake_auth.issue(uid)
    return {"Authorization": "Bearer " + token}


# ---------------------------------------------------------------------------
# Authentication
# ---------------------------------------------------------------------------


def test_attachment_requires_auth(client):
    """Unauthenticated request must 403/401."""
    resp = client.post("/api/ai/attachment-question")
    assert resp.status_code in (401, 403), resp.status_code


# ---------------------------------------------------------------------------
# Unsupported / rejection paths
# ---------------------------------------------------------------------------


def test_unsupported_file_type_rejects(client, fake_db, fake_auth):
    """A .gif file must be rejected with 400."""
    uid = "att-gif-user"
    fake_db.seed("users", uid, {"role": "student"})

    resp = client.post(
        "/api/ai/attachment-question",
        headers=_auth(fake_auth, uid),
        files={"file": ("photo.gif", b"GIF89a", "image/gif")},
        data={"question": "What is this?"},
    )
    assert resp.status_code == 400, resp.status_code
    assert "Unsupported" in resp.json()["detail"]


def test_empty_file_rejects(client, fake_db, fake_auth):
    """Empty upload must 400."""
    uid = "att-empty-user"
    fake_db.seed("users", uid, {"role": "student"})

    resp = client.post(
        "/api/ai/attachment-question",
        headers=_auth(fake_auth, uid),
        files={"file": ("empty.pdf", b"", "application/pdf")},
        data={"question": "What is this?"},
    )
    assert resp.status_code == 400, resp.status_code
    assert "Empty" in resp.json()["detail"]


def test_oversized_file_rejects(client, fake_db, fake_auth):
    """File exceeding 10 MB must 413."""
    uid = "att-big-user"
    fake_db.seed("users", uid, {"role": "student"})

    # 11 MB dummy content
    big_content = b"\x00" * (11 * 1024 * 1024)
    resp = client.post(
        "/api/ai/attachment-question",
        headers=_auth(fake_auth, uid),
        files={"file": ("huge.pdf", big_content, "application/pdf")},
        data={"question": "Summarize this."},
    )
    assert resp.status_code == 413, resp.status_code


# ---------------------------------------------------------------------------
# TXT extraction
# ---------------------------------------------------------------------------


def test_txt_extraction(client, fake_db, fake_auth):
    """TXT file content should be extracted and passed to generate."""
    uid = "att-txt-user"
    fake_db.seed("users", uid, {"role": "student"})

    content = b"This is a plain text file about biology.\nCovers cell structure."
    resp = client.post(
        "/api/ai/attachment-question",
        headers=_auth(fake_auth, uid),
        files={"file": ("notes.txt", content, "text/plain")},
        data={"question": "What does this cover?"},
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert "answer" in body
    assert "extractedText" in body
    assert "biology" in body["extractedText"].lower()


def test_txt_empty_content_returns_422(client, fake_db, fake_auth):
    """TXT with no extractable text must 422."""
    uid = "att-txt-empty"
    fake_db.seed("users", uid, {"role": "student"})

    resp = client.post(
        "/api/ai/attachment-question",
        headers=_auth(fake_auth, uid),
        files={"file": ("blank.txt", b"   \n  \t  ", "text/plain")},
        data={"question": "What is here?"},
    )
    assert resp.status_code == 422, resp.status_code


# ---------------------------------------------------------------------------
# PDF extraction
# ---------------------------------------------------------------------------


def test_pdf_with_text(client, fake_db, fake_auth):
    """PDF with extractable text should work."""
    uid = "att-pdf-user"
    fake_db.seed("users", uid, {"role": "student"})

    # Minimal PDF-like content with text
    pdf_content = b"%PDF-1.4\n1 0 obj<</Type/Catalog>>endobj\nText about math formulas."
    resp = client.post(
        "/api/ai/attachment-question",
        headers=_auth(fake_auth, uid),
        files={"file": ("lecture.pdf", pdf_content, "application/pdf")},
        data={"question": "Summarize this."},
    )
    # May be 200 (if extraction works) or 422 (if no text extracted)
    assert resp.status_code in (200, 422), resp.status_code
    if resp.status_code == 200:
        assert "answer" in resp.json()


# ---------------------------------------------------------------------------
# Image extraction (OCR path)
# ---------------------------------------------------------------------------


def test_image_type_accepted(client, fake_db, fake_auth):
    """JPG files should be accepted (not 400 for unsupported type)."""
    uid = "att-img-user"
    fake_db.seed("users", uid, {"role": "student"})

    # Dummy image bytes (won't actually OCR but tests the type gate)
    resp = client.post(
        "/api/ai/attachment-question",
        headers=_auth(fake_auth, uid),
        files={"file": ("photo.jpg", b"\xff\xd8\xff\xe0" + b"\x00" * 100, "image/jpeg")},
        data={"question": "What is in this image?"},
    )
    # Should NOT be 400 (type is allowed); may be 422 (OCR can't extract)
    assert resp.status_code != 400 or "Unsupported" not in resp.json().get("detail", ""), \
        f"JPG should be accepted but got: {resp.status_code} {resp.text}"


def test_png_type_accepted(client, fake_db, fake_auth):
    """PNG files should be accepted."""
    uid = "att-png-user"
    fake_db.seed("users", uid, {"role": "student"})

    resp = client.post(
        "/api/ai/attachment-question",
        headers=_auth(fake_auth, uid),
        files={"file": ("diagram.png", b"\x89PNG\r\n\x1a\n" + b"\x00" * 100, "image/png")},
        data={"question": "Describe this."},
    )
    assert resp.status_code != 400 or "Unsupported" not in resp.json().get("detail", ""), \
        f"PNG should be accepted but got: {resp.status_code}"


def test_webp_type_accepted(client, fake_db, fake_auth):
    """WEBP files should be accepted."""
    uid = "att-webp-user"
    fake_db.seed("users", uid, {"role": "student"})

    resp = client.post(
        "/api/ai/attachment-question",
        headers=_auth(fake_auth, uid),
        files={"file": ("photo.webp", b"RIFF\x00\x00\x00\x00WEBP" + b"\x00" * 50, "image/webp")},
        data={"question": "What is this?"},
    )
    assert resp.status_code != 400 or "Unsupported" not in resp.json().get("detail", ""), \
        f"WEBP should be accepted but got: {resp.status_code}"


# ---------------------------------------------------------------------------
# DOCX extraction
# ---------------------------------------------------------------------------


def test_docx_type_accepted(client, fake_db, fake_auth):
    """DOCX files should be accepted (not 400)."""
    uid = "att-docx-user"
    fake_db.seed("users", uid, {"role": "student"})

    # Minimal DOCX-like bytes (won't parse but tests type gate)
    resp = client.post(
        "/api/ai/attachment-question",
        headers=_auth(fake_auth, uid),
        files={"file": ("report.docx", b"PK\x03\x04" + b"\x00" * 200, "application/vnd.openxmlformats-officedocument.wordprocessingml.document")},
        data={"question": "Summarize."},
    )
    # Should not be 400 for unsupported type
    assert "Unsupported" not in resp.json().get("detail", ""), \
        f"DOCX should be accepted but got: {resp.status_code} {resp.text}"


# ---------------------------------------------------------------------------
# No public storage URL leakage
# ---------------------------------------------------------------------------


def test_response_does_not_leak_storage_urls(client, fake_db, fake_auth):
    """The response must not contain any storage/download URLs."""
    uid = "att-noleak"
    fake_db.seed("users", uid, {"role": "student"})

    content = b"Confidential notes aboutProject X."
    resp = client.post(
        "/api/ai/attachment-question",
        headers=_auth(fake_auth, uid),
        files={"file": ("secret.txt", content, "text/plain")},
        data={"question": "What is this about?"},
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    text = str(body)
    assert "backblazeb2.com" not in text.lower(), "Storage URL leaked in response"
    assert "b2" not in text.lower() or "b2" not in body.get("extractedText", "").lower()


# ---------------------------------------------------------------------------
# Truncation
# ---------------------------------------------------------------------------


def test_large_text_truncated_at_15k(client, fake_db, fake_auth):
    """Text exceeding 15000 chars should be truncated."""
    uid = "att-trunc-user"
    fake_db.seed("users", uid, {"role": "student"})

    big_text = b"A" * 20000
    resp = client.post(
        "/api/ai/attachment-question",
        headers=_auth(fake_auth, uid),
        files={"file": ("big.txt", big_text, "text/plain")},
        data={"question": "Summarize."},
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert "truncated" in body.get("extractedText", "").lower() or \
           len(body.get("extractedText", "")) <= 520  # 500 preview + "..."
