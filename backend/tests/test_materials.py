"""Material ownership, visibility, and access tests."""

from __future__ import annotations

import sys
from pathlib import Path

_BACKEND_ROOT = Path(__file__).resolve().parent.parent
if str(_BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(_BACKEND_ROOT))


def _h(fake_auth, uid):
    return {"Authorization": f"Bearer {fake_auth.issue(uid)}"}


def test_owner_can_delete_material(client, fake_db, fake_auth):
    uid = "owner-1"
    fake_db.seed("users", uid, {"role": "student"})
    material_id = "mat-1"
    fake_db.seed(
        "materials",
        material_id,
        {
            "ownerId": uid,
            "ownerName": "Owner",
            "title": "Notes",
            "filePath": "uploads/owner-1/notes.pdf",
            "visibility": "private",
        },
    )

    resp = client.delete(
        f"/api/materials/{material_id}",
        headers=_h(fake_auth, uid),
    )
    assert resp.status_code in (200, 204), resp.text
    assert material_id not in fake_db._collections.get("materials", {})


def test_non_owner_cannot_delete_material(client, fake_db, fake_auth):
    uid = "owner-2"
    fake_db.seed("users", uid, {"role": "student"})
    fake_db.seed(
        "materials",
        "mat-other",
        {"ownerId": "someone-else", "visibility": "private", "filePath": "x"},
    )

    resp = client.delete(
        "/api/materials/mat-other",
        headers=_h(fake_auth, uid),
    )
    assert resp.status_code in (403, 404), resp.text


def test_student_can_read_public_material(client, fake_db, fake_auth):
    owner = "owner-3"
    reader = "reader-1"
    fake_db.seed("users", owner, {"role": "student"})
    fake_db.seed("users", reader, {"role": "student"})
    fake_db.seed(
        "materials",
        "mat-public",
        {
            "ownerId": owner,
            "visibility": "public",
            "filePath": "uploads/owner-3/public.pdf",
            "title": "Pub",
        },
    )

    resp = client.get(
        "/api/materials/mat-public/url",
        headers=_h(fake_auth, reader),
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert "url" in body or "signedUrl" in body or "signedURL" in body, body


def test_non_member_blocked_from_group_material(client, fake_db, fake_auth):
    owner = "owner-4"
    outsider = "outsider-1"
    member = "member-1"
    group_id = "grp-1"
    fake_db.seed("users", owner, {"role": "student"})
    fake_db.seed("users", outsider, {"role": "student"})
    fake_db.seed("users", member, {"role": "student"})
    fake_db.seed(
        "groups",
        group_id,
        {
            "name": "Study Group",
            "ownerId": owner,
            "adminIds": [owner],
            "memberIds": [owner, member],
        },
    )
    fake_db.seed(
        "materials",
        "mat-group",
        {
            "ownerId": owner,
            "visibility": "group",
            "groupId": group_id,
            "filePath": "uploads/owner-4/group.pdf",
        },
    )

    resp_outside = client.get(
        "/api/materials/mat-group/url",
        headers=_h(fake_auth, outsider),
    )
    assert resp_outside.status_code in (403, 404), resp_outside.text

    resp_member = client.get(
        "/api/materials/mat-group/url",
        headers=_h(fake_auth, member),
    )
    assert resp_member.status_code == 200, resp_member.text


def test_unsupported_file_type_rejected(client, fake_db, fake_auth):
    uid = "uploader-1"
    fake_db.seed("users", uid, {"role": "student"})

    files = {"file": ("virus.exe", b"MZ\x90\x00", "application/octet-stream")}
    resp = client.post(
        "/api/materials/upload",
        headers=_h(fake_auth, uid),
        files=files,
        data={"title": "nope", "visibility": "private"},
    )
    assert resp.status_code in (400, 415, 422), resp.text