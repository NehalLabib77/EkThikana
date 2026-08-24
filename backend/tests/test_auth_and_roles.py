"""Auth + role enforcement tests (spec sections 46 and 20)."""

from __future__ import annotations

import sys
from pathlib import Path

_BACKEND_ROOT = Path(__file__).resolve().parent.parent
if str(_BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(_BACKEND_ROOT))


def _h(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def test_no_token_returns_401(client):
    """An unauthenticated request to a protected endpoint must 401."""
    resp = client.get("/api/account/export")
    assert resp.status_code == 401, resp.text


def test_invalid_token_returns_401(client):
    """A bogus Bearer token must 401 (verifies verify_id_token wiring)."""
    resp = client.get(
        "/api/account/export",
        headers=_h("not-a-real-token"),
    )
    assert resp.status_code == 401, resp.text


def test_general_role_blocked_from_materials(client, fake_db, fake_auth):
    """General users cannot upload materials."""
    uid = "general-2"
    fake_auth.issue(uid, verified=True)
    fake_db.seed("users", uid, {"displayName": "G", "role": "general"})

    files = {"file": ("a.pdf", b"%PDF-1.4\n", "application/pdf")}
    resp = client.post(
        "/api/materials/upload",
        headers=_h(fake_auth.issue(uid)),
        files=files,
        data={"title": "x", "visibility": "private"},
    )
    assert resp.status_code in (403, 422), resp.text
