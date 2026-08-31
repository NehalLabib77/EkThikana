"""End-to-end tests for /api/ai/pdf-question and /api/ai/image-question.

P1-3 closed the gap between Flutter's ``AiAssistantScreen`` upload flow and
the two backend question routes. The image-question endpoint was previously
unreachable from any UI call site — the picker accepted PNG/JPEG/WEBP but
every file was funnelled through ``askPdf``. These tests pin the contract
the Flutter caller now relies on.
"""

from __future__ import annotations

import base64
import sys
from pathlib import Path

_BACKEND_ROOT = Path(__file__).resolve().parent.parent
if str(_BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(_BACKEND_ROOT))


def _auth(fake_auth, uid):
    return {"Authorization": f"Bearer {fake_auth.issue(uid)}"}


# ---------------------------------------------------------------------------
# pdf-question
# ---------------------------------------------------------------------------


def test_pdf_question_owner_happy_path(client, fake_db, fake_auth, fake_storage):
    """Owner asks a question about their own PDF; answer comes from generate."""
    uid = "pdf-q-owner"
    fake_db.seed("users", uid, {"role": "student"})
    fake_db.seed(
        "materials",
        "m-pdf-owner",
        {
            "ownerId": uid,
            "visibility": "private",
            "fileName": "lecture.pdf",
            "mimeType": "application/pdf",
            "filePath": "users/pdf-q-owner/lecture.pdf",
        },
    )
    fake_storage.set_bytes("users/pdf-q-owner/lecture.pdf", b"%PDF-1.4\nTopic 1\nTopic 2\n")

    resp = client.post(
        "/api/ai/pdf-question",
        headers=_auth(fake_auth, uid),
        json={"material_id": "m-pdf-owner", "question": "What does this lecture cover?"},
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert isinstance(body.get("answer"), str)
    # The fake_generate echoes prompt length so we know real generate was bypassed.
    assert body["answer"].startswith("echo(")


def test_pdf_question_rejects_image_material(client, fake_db, fake_auth, fake_storage):
    """Uploading a PNG and pointing pdf-question at it must 400."""
    uid = "pdf-q-img-user"
    fake_db.seed("users", uid, {"role": "student"})
    fake_db.seed(
        "materials",
        "m-png-as-pdf",
        {
            "ownerId": uid,
            "visibility": "private",
            "fileName": "photo.png",
            "mimeType": "image/png",
            "filePath": "users/pdf-q-img-user/photo.png",
        },
    )
    fake_storage.set_bytes("users/pdf-q-img-user/photo.png", b"\x89PNG\r\n\x1a\nfake")

    resp = client.post(
        "/api/ai/pdf-question",
        headers=_auth(fake_auth, uid),
        json={"material_id": "m-png-as-pdf", "question": "what?"},
    )
    assert resp.status_code == 400, resp.text
    assert "PDF" in resp.json().get("detail", "")


def test_pdf_question_404_on_missing_material(client, fake_db, fake_auth):
    uid = "pdf-q-missing"
    fake_db.seed("users", uid, {"role": "student"})
    resp = client.post(
        "/api/ai/pdf-question",
        headers=_auth(fake_auth, uid),
        json={"material_id": "no-such-id", "question": "what?"},
    )
    assert resp.status_code in (404, 403), resp.text


# ---------------------------------------------------------------------------
# image-question
# ---------------------------------------------------------------------------


# 1x1 transparent PNG header + IHDR + IDAT + IEND; safe fixture bytes.
_PNG_BYTES = (
    b"\x89PNG\r\n\x1a\n"
    b"\x00\x00\x00\rIHDR"
    b"\x00\x00\x00\x01\x00\x00\x00\x01"
    b"\x08\x06\x00\x00\x00\x1f\x15\xc4\x89"
    b"\x00\x00\x00\rIDATx\x9cc\xfc\xff\xff?\x03\x00\x05\xfe\x02\xfe\xa3\x35\x9d?x00\x00\x00\x00IEND\xaeB`\x82"
)
_JPEG_BYTES = b"\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00\xff\xd9"
_WEBP_BYTES = b"RIFF\x00\x10\x00\x00WEBPVP8 \x00\x00\x00\x00"


def test_image_question_owner_happy_path(client, fake_db, fake_auth, fake_storage, monkeypatch):
    """Owner asks a question about their own PNG; answer echoes multipart shape."""
    uid = "img-q-owner"
    fake_db.seed("users", uid, {"role": "student"})
    fake_db.seed(
        "materials",
        "m-img-owner",
        {
            "ownerId": uid,
            "visibility": "private",
            "fileName": "diagram.png",
            "mimeType": "image/png",
            "filePath": "users/img-q-owner/diagram.png",
        },
    )
    fake_storage.set_bytes("users/img-q-owner/diagram.png", _PNG_BYTES)

    # Capture what the AI service received so we can assert the inline_data shape.
    import app.services.ai_service as ai_mod

    seen = {"parts": None}

    async def _capture(uid_, parts):
        seen["parts"] = parts
        return "ok"

    monkeypatch.setattr(ai_mod, "generate_multimodal", _capture)
    monkeypatch.setattr("app.routers.ai.generate_multimodal", _capture)

    resp = client.post(
        "/api/ai/image-question",
        headers=_auth(fake_auth, uid),
        json={"material_id": "m-img-owner", "question": "What does the diagram show?"},
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["answer"] == "ok"

    parts = seen["parts"]
    assert parts is not None and len(parts) == 2
    inline, text_part = parts
    assert "inline_data" in inline
    assert inline["inline_data"]["mime_type"] == "image/png"
    # Base64 round-trip must produce the exact fixture bytes.
    assert base64.b64decode(inline["inline_data"]["data"]) == _PNG_BYTES
    assert "diagram show" in text_part["text"]


def test_image_question_jpeg_uses_correct_mime(client, fake_db, fake_auth, fake_storage, monkeypatch):
    """JPEG mime is preserved end-to-end (no PNG fallback)."""
    uid = "img-q-jpeg"
    fake_db.seed("users", uid, {"role": "student"})
    fake_db.seed(
        "materials",
        "m-jpeg",
        {
            "ownerId": uid,
            "visibility": "private",
            "fileName": "snap.jpg",
            # Some uploads don't record a MIME — the router must fall back to extension.
            "mimeType": "",
            "filePath": "users/img-q-jpeg/snap.jpg",
        },
    )
    fake_storage.set_bytes("users/img-q-jpeg/snap.jpg", _JPEG_BYTES)

    import app.services.ai_service as ai_mod

    captured_mime = {"value": None}

    async def _capture(uid_, parts):
        for p in parts:
            if isinstance(p, dict) and "inline_data" in p:
                captured_mime["value"] = p["inline_data"]["mime_type"]
        return "ok"

    monkeypatch.setattr(ai_mod, "generate_multimodal", _capture)
    monkeypatch.setattr("app.routers.ai.generate_multimodal", _capture)

    resp = client.post(
        "/api/ai/image-question",
        headers=_auth(fake_auth, uid),
        json={"material_id": "m-jpeg", "question": "what?"},
    )
    assert resp.status_code == 200, resp.text
    assert captured_mime["value"] == "image/jpeg"


def test_image_question_webp_supported(client, fake_db, fake_auth, fake_storage, monkeypatch):
    """WEBP is in the backend allowlist even though Flutter's picker doesn't expose it yet."""
    uid = "img-q-webp"
    fake_db.seed("users", uid, {"role": "student"})
    fake_db.seed(
        "materials",
        "m-webp",
        {
            "ownerId": uid,
            "visibility": "private",
            "fileName": "scan.webp",
            "mimeType": "image/webp",
            "filePath": "users/img-q-webp/scan.webp",
        },
    )
    fake_storage.set_bytes("users/img-q-webp/scan.webp", _WEBP_BYTES)

    import app.services.ai_service as ai_mod

    async def _capture(uid_, parts):
        return "ok"

    monkeypatch.setattr(ai_mod, "generate_multimodal", _capture)
    monkeypatch.setattr("app.routers.ai.generate_multimodal", _capture)

    resp = client.post(
        "/api/ai/image-question",
        headers=_auth(fake_auth, uid),
        json={"material_id": "m-webp", "question": "what?"},
    )
    assert resp.status_code == 200, resp.text


def test_image_question_rejects_pdf_material(client, fake_db, fake_auth, fake_storage):
    """A PDF is not an image — must 400."""
    uid = "img-q-pdf-user"
    fake_db.seed("users", uid, {"role": "student"})
    fake_db.seed(
        "materials",
        "m-pdf-img",
        {
            "ownerId": uid,
            "visibility": "private",
            "fileName": "report.pdf",
            "mimeType": "application/pdf",
            "filePath": "users/img-q-pdf-user/report.pdf",
        },
    )
    fake_storage.set_bytes("users/img-q-pdf-user/report.pdf", b"%PDF-1.4\n%fake")

    resp = client.post(
        "/api/ai/image-question",
        headers=_auth(fake_auth, uid),
        json={"material_id": "m-pdf-img", "question": "what?"},
    )
    assert resp.status_code == 400, resp.text
    detail = resp.json().get("detail", "")
    assert "image" in detail.lower() or "PNG" in detail or "JPEG" in detail


def test_image_question_rejects_oversized_image(client, fake_db, fake_auth, fake_storage, monkeypatch):
    """Images above the configured cap must 413 before reaching Gemini.

    The router reads ``ai_image_max_bytes`` via ``getattr(settings, ..., default)``.
    To avoid mutating the real Settings (pydantic frozen model), we patch the
    ai router's own helper to return a tiny cap. The size check still has to
    run on the real byte length, so we seed an oversized blob.
    """
    uid = "img-q-big"
    fake_db.seed("users", uid, {"role": "student"})
    fake_db.seed(
        "materials",
        "m-big-png",
        {
            "ownerId": uid,
            "visibility": "private",
            "fileName": "huge.png",
            "mimeType": "image/png",
            "filePath": "users/img-q-big/huge.png",
        },
    )
    # The router uses `getattr(settings, "ai_image_max_bytes", 6*1024*1024)`.
    # Patch get_settings inside the ai router module to return a stub with
    # a 1 KiB cap. The default is irrelevant for this assertion.
    import app.routers.ai as ai_router_mod

    class _TinyCapSettings:
        ai_image_max_bytes = 1024

    monkeypatch.setattr(ai_router_mod, "get_settings", lambda: _TinyCapSettings)
    fake_storage.set_bytes("users/img-q-big/huge.png", _PNG_BYTES + b"\x00" * 4096)

    resp = client.post(
        "/api/ai/image-question",
        headers=_auth(fake_auth, uid),
        json={"material_id": "m-big-png", "question": "what?"},
    )
    assert resp.status_code == 413, resp.text


def test_image_question_rejects_empty_image(client, fake_db, fake_auth, fake_storage):
    """An empty storage object must 422, not silently call Gemini."""
    uid = "img-q-empty"
    fake_db.seed("users", uid, {"role": "student"})
    fake_db.seed(
        "materials",
        "m-empty-img",
        {
            "ownerId": uid,
            "visibility": "private",
            "fileName": "blank.png",
            "mimeType": "image/png",
            "filePath": "users/img-q-empty/blank.png",
        },
    )
    fake_storage.set_bytes("users/img-q-empty/blank.png", b"")

    resp = client.post(
        "/api/ai/image-question",
        headers=_auth(fake_auth, uid),
        json={"material_id": "m-empty-img", "question": "what?"},
    )
    assert resp.status_code == 422, resp.text


def test_image_question_404_on_missing_material(client, fake_db, fake_auth):
    uid = "img-q-missing"
    fake_db.seed("users", uid, {"role": "student"})
    resp = client.post(
        "/api/ai/image-question",
        headers=_auth(fake_auth, uid),
        json={"material_id": "nope", "question": "what?"},
    )
    assert resp.status_code in (404, 403), resp.text
