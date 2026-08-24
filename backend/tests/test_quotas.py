"""Quota, account-deletion, and group-leave tests."""

from __future__ import annotations

import sys
from pathlib import Path

_BACKEND_ROOT = Path(__file__).resolve().parent.parent
if str(_BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(_BACKEND_ROOT))


def _auth(fake_auth, uid):
    return {"Authorization": f"Bearer {fake_auth.issue(uid)}"}


def test_ai_route_returns_text(client, fake_db, fake_auth):
    """The AI /note endpoint returns text when the upstream generate is mocked."""
    uid = "ai-user-1"
    fake_db.seed("users", uid, {"role": "student"})

    resp = client.post(
        "/api/ai/note",
        headers=_auth(fake_auth, uid),
        json={"action": "summary", "text": "Photosynthesis is how plants make food."},
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert "text" in body or "result" in body, body


def test_ai_quota_exceeded_returns_429(client, fake_db, fake_auth, monkeypatch):
    """When AI quota is exhausted the route must return 429."""
    uid = "ai-user-2"
    fake_db.seed("users", uid, {"role": "student"})

    from fastapi import HTTPException

    async def _reject_generate(uid, prompt):
        raise HTTPException(status_code=429, detail="AI quota exhausted")

    monkeypatch.setattr(
        "app.services.ai_service.generate", _reject_generate
    )
    monkeypatch.setattr(
        "app.routers.ai.generate", _reject_generate
    )

    resp = client.post(
        "/api/ai/note",
        headers=_auth(fake_auth, uid),
        json={"action": "summary", "text": "x"},
    )
    assert resp.status_code == 429, resp.text


def test_account_deletion_cascades(client, fake_db, fake_auth, fake_storage):
    """DELETE /api/account wipes user data, materials, and storage files."""
    uid = "deleter"
    fake_db.seed("users", uid, {"role": "student"})
    fake_db.seed("materials", "m1", {"ownerId": uid, "filePath": "uploads/deleter/a.pdf"})
    fake_db.seed("materials", "m2", {"ownerId": uid, "filePath": "uploads/deleter/b.pdf"})
    fake_db.seed("notes", "n1", {"ownerId": uid, "title": "secret"})
    fake_db.seed("tasks", "t1", {"ownerId": uid})
    fake_db.seed("ai_usage", "u1", {"uid": uid})
    fake_db.seed(
        "groups",
        "g1",
        {"name": "Mine", "ownerId": uid, "adminIds": [uid], "memberIds": [uid]},
    )

    resp = client.delete(
        "/api/account",
        headers=_auth(fake_auth, uid),
    )
    assert resp.status_code in (200, 204), resp.text
    assert uid in fake_auth.deleted
    assert "m1" not in fake_db._collections.get("materials", {})
    assert "m2" not in fake_db._collections.get("materials", {})
    assert "n1" not in fake_db._collections.get("notes", {})
    assert "t1" not in fake_db._collections.get("tasks", {})
    assert "u1" not in fake_db._collections.get("ai_usage", {})
    assert "uploads/deleter/a.pdf" in fake_storage.deletes
    assert "uploads/deleter/b.pdf" in fake_storage.deletes


def test_leave_group_transfers_ownership(client, fake_db, fake_auth):
    """Leaving a group when you own it transfers ownership to the next admin."""
    owner = "leaver-owner"
    admin = "leaver-admin"
    fake_db.seed("users", owner, {"role": "student"})
    fake_db.seed("users", admin, {"role": "student"})
    fake_db.seed(
        "groups",
        "g-leave",
        {
            "name": "G",
            "ownerId": owner,
            "adminIds": [owner, admin],
            "memberIds": [owner, admin],
        },
    )

    resp = client.post(
        "/api/groups/g-leave/leave",
        headers=_auth(fake_auth, owner),
    )
    assert resp.status_code in (200, 204), resp.text

    grp = fake_db._collections["groups"]["g-leave"]
    assert owner not in grp["memberIds"]
    assert grp["ownerId"] == admin


def test_leave_group_last_member_deletes(client, fake_db, fake_auth):
    """If the leaving member is the last member, the group is deleted."""
    solo = "leaver-solo"
    fake_db.seed("users", solo, {"role": "student"})
    fake_db.seed(
        "groups",
        "g-solo",
        {
            "name": "Solo",
            "ownerId": solo,
            "adminIds": [solo],
            "memberIds": [solo],
        },
    )

    resp = client.post(
        "/api/groups/g-solo/leave",
        headers=_auth(fake_auth, solo),
    )
    assert resp.status_code in (200, 204), resp.text
    assert "g-solo" not in fake_db._collections.get("groups", {})