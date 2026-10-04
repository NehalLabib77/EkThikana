"""Tests for Material Upload and Document Ingestion (Phase 14).

Validates material file upload, authentication requirements, file type gating,
size limits, text extraction per type, privacy, and bounded chunking.
"""

from __future__ import annotations

import sys
from pathlib import Path

_BACKEND_ROOT = Path(__file__).resolve().parent.parent
if str(_BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(_BACKEND_ROOT))

from app.core.utils import detect_supported_file_type
from app.services.document_ingestion_service import (
    MAX_UPLOAD_BYTES,
    CHUNK_CONFIG,
    _extract_from_txt,
    _split_into_chunks,
)


def _auth(fake_auth, uid: str) -> dict[str, str]:
    token = fake_auth.issue(uid)
    return {"Authorization": "Bearer " + token}


# ---------------------------------------------------------------------------
# Authentication
# ---------------------------------------------------------------------------


def test_attachment_requires_auth(client):
    """Unauthenticated material upload request must 401/403."""
    resp = client.post("/api/materials/upload")
    assert resp.status_code in (401, 403), resp.status_code


# ---------------------------------------------------------------------------
# Unsupported / rejection paths
# ---------------------------------------------------------------------------


def test_unsupported_file_type_rejects(client, fake_db, fake_auth):
    """An unsupported file type (e.g. .gif) must be rejected with 415."""
    uid = "att-gif-user"
    fake_db.seed("users", uid, {"role": "student"})

    resp = client.post(
        "/api/materials/upload",
        headers=_auth(fake_auth, uid),
        files={"file": ("photo.gif", b"GIF89a" + b"\x00" * 10, "image/gif")},
        data={"title": "Unsupported GIF material"},
    )
    assert resp.status_code == 415, resp.status_code
    assert "Only PDF, PNG, JPEG, DOC, DOCX and TXT files are allowed" in resp.json()["detail"]


def test_empty_file_rejects(client, fake_db, fake_auth):
    """Empty upload must reject with 400."""
    uid = "att-empty-user"
    fake_db.seed("users", uid, {"role": "student"})

    resp = client.post(
        "/api/materials/upload",
        headers=_auth(fake_auth, uid),
        files={"file": ("empty.pdf", b"", "application/pdf")},
        data={"title": "Empty PDF material"},
    )
    assert resp.status_code == 400, resp.status_code
    assert "empty" in resp.json()["detail"].lower()


def test_oversized_file_rejects(client, fake_db, fake_auth):
    """File exceeding MAX_UPLOAD_MB (25 MB) must reject with 413."""
    uid = "att-big-user"
    fake_db.seed("users", uid, {"role": "student"})

    oversized = b"\x00" * (MAX_UPLOAD_BYTES + 1)
    resp = client.post(
        "/api/materials/upload",
        headers=_auth(fake_auth, uid),
        files={"file": ("huge.pdf", oversized, "application/pdf")},
        data={"title": "Oversized document"},
    )
    assert resp.status_code == 413, resp.status_code
    assert "Maximum file size is 25 MB" in resp.json()["detail"]


# ---------------------------------------------------------------------------
# Extraction & Supported Types
# ---------------------------------------------------------------------------


def test_txt_extraction(client, fake_db, fake_auth, fake_storage):
    """TXT file upload succeeds and plain text extraction parses content."""
    uid = "att-txt-user"
    fake_db.seed("users", uid, {"role": "student"})

    content = b"This is a plain text file about biology.\nCovers cell structure."
    resp = client.post(
        "/api/materials/upload",
        headers=_auth(fake_auth, uid),
        files={"file": ("notes.txt", content, "text/plain")},
        data={"title": "Biology Notes"},
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert "id" in body

    blocks = _extract_from_txt(content)
    assert len(blocks) == 1
    assert "biology" in blocks[0]["text"].lower()


def test_txt_empty_content_returns_empty_blocks():
    """Empty or whitespace text extraction returns an empty block list."""
    blocks = _extract_from_txt(b"   \n  \t  ")
    assert blocks == []


def test_image_types_accepted():
    """JPG, PNG formats are accepted by detect_supported_file_type."""
    jpg_bytes = b"\xff\xd8\xff\xe0" + b"\x00" * 20
    mime, ext = detect_supported_file_type(jpg_bytes)
    assert mime == "image/jpeg"
    assert ext == ".jpg"

    png_bytes = b"\x89PNG\r\n\x1a\n" + b"\x00" * 20
    mime, ext = detect_supported_file_type(png_bytes)
    assert mime == "image/png"
    assert ext == ".png"


def test_docx_type_accepted():
    """DOCX format is accepted by detect_supported_file_type."""
    docx_bytes = b"PK\x03\x04" + b"\x00" * 100
    mime, ext = detect_supported_file_type(docx_bytes)
    assert mime == "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    assert ext == ".docx"


def test_pdf_type_accepted():
    """PDF format is accepted by detect_supported_file_type."""
    pdf_bytes = b"%PDF-1.4\n" + b"\x00" * 20
    mime, ext = detect_supported_file_type(pdf_bytes)
    assert mime == "application/pdf"
    assert ext == ".pdf"


# ---------------------------------------------------------------------------
# Privacy & Storage
# ---------------------------------------------------------------------------


def test_response_does_not_leak_storage_credentials(client, fake_db, fake_auth, fake_storage):
    """The material upload response must not contain any storage secret credentials."""
    uid = "att-noleak"
    fake_db.seed("users", uid, {"role": "student"})

    content = b"Confidential study notes."
    resp = client.post(
        "/api/materials/upload",
        headers=_auth(fake_auth, uid),
        files={"file": ("secret.txt", content, "text/plain")},
        data={"title": "Confidential Study Notes"},
    )
    assert resp.status_code == 200, resp.text
    body_str = resp.text.lower()
    assert "b2_application_key" not in body_str
    assert "b2_key_id" not in body_str
    assert "firebase_storage_bucket" not in body_str


# ---------------------------------------------------------------------------
# Bounded Chunking
# ---------------------------------------------------------------------------


def test_bounded_chunking():
    """Document chunking produces bounded chunks within limits."""
    sample_text = "Paragraph of test content for chunking verification. " * 50
    chunks = _split_into_chunks(sample_text, page=1, section="Intro", chunk_type="txt")
    assert len(chunks) > 0
    cfg = CHUNK_CONFIG["txt"]
    for chunk in chunks:
        assert len(chunk["text"]) <= cfg["max"]
        assert chunk["page"] == 1
        assert chunk["section"] == "Intro"
