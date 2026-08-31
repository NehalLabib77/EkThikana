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


# ---------------------------------------------------------------------------
# P1-2: owner-only metadata edit (PATCH) + file replacement (PUT).
# ---------------------------------------------------------------------------


def test_owner_can_patch_metadata(client, fake_db, fake_auth):
    uid = "patcher-1"
    fake_db.seed("users", uid, {"role": "student"})
    fake_db.seed(
        "materials",
        "mat-patch-1",
        {
            "ownerId": uid,
            "title": "Old title",
            "subject": "Math",
            "description": "Old description",
            "filePath": "users/patcher-1/old.pdf",
            "fileName": "old.pdf",
            "visibility": "private",
            "version": 1,
        },
    )

    resp = client.patch(
        "/api/materials/mat-patch-1",
        headers=_h(fake_auth, uid),
        json={"title": "New title", "description": "New description"},
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["title"] == "New title"
    assert body["description"] == "New description"
    # Subject omitted -> preserved.
    assert body["subject"] == "Math"

    doc = fake_db._collections["materials"]["mat-patch-1"]
    assert doc["title"] == "New title"
    assert doc["description"] == "New description"
    assert doc["subject"] == "Math"
    assert "updatedAt" in doc


def test_non_owner_cannot_patch_metadata(client, fake_db, fake_auth):
    uid = "patcher-2"
    other = "patcher-3"
    fake_db.seed("users", uid, {"role": "student"})
    fake_db.seed("users", other, {"role": "student"})
    fake_db.seed(
        "materials",
        "mat-patch-2",
        {"ownerId": uid, "title": "Owner-only", "filePath": "x"},
    )

    resp = client.patch(
        "/api/materials/mat-patch-2",
        headers=_h(fake_auth, other),
        json={"title": "Hijack"},
    )
    assert resp.status_code == 403, resp.text
    assert fake_db._collections["materials"]["mat-patch-2"]["title"] == "Owner-only"


def test_patch_rejects_empty_title(client, fake_db, fake_auth):
    uid = "patcher-4"
    fake_db.seed("users", uid, {"role": "student"})
    fake_db.seed(
        "materials",
        "mat-patch-3",
        {"ownerId": uid, "title": "Real", "filePath": "x"},
    )

    resp = client.patch(
        "/api/materials/mat-patch-3",
        headers=_h(fake_auth, uid),
        json={"title": "   "},
    )
    assert resp.status_code == 400, resp.text


def test_patch_missing_material_returns_404(client, fake_db, fake_auth):
    uid = "patcher-5"
    fake_db.seed("users", uid, {"role": "student"})
    resp = client.patch(
        "/api/materials/does-not-exist",
        headers=_h(fake_auth, uid),
        json={"title": "x"},
    )
    assert resp.status_code == 404, resp.text


def test_owner_can_replace_file(client, fake_db, fake_auth, fake_storage):
    uid = "replacer-1"
    fake_db.seed("users", uid, {"role": "student"})
    fake_db.seed(
        "materials",
        "mat-replace-1",
        {
            "ownerId": uid,
            "title": "Notes",
            "filePath": "users/replacer-1/old_abc_notes.pdf",
            "fileName": "notes.pdf",
            "mimeType": "application/pdf",
            "sizeBytes": 10,
            "visibility": "private",
            "version": 1,
        },
    )

    # Small but valid PDF byte stream.
    new_pdf = b"%PDF-1.4\n%new contents\n"
    resp = client.put(
        "/api/materials/mat-replace-1/file",
        headers=_h(fake_auth, uid),
        files={"file": ("notes-v2.pdf", new_pdf, "application/pdf")},
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["id"] == "mat-replace-1"
    assert body["version"] == 2
    assert body["fileName"] == "notes-v2.pdf"
    assert body["mimeType"] == "application/pdf"
    assert body["sizeBytes"] == len(new_pdf)
    assert body["filePath"] != "users/replacer-1/old_abc_notes.pdf"

    # Firestore doc has the new metadata.
    doc = fake_db._collections["materials"]["mat-replace-1"]
    assert doc["filePath"] == body["filePath"]
    assert doc["fileName"] == "notes-v2.pdf"
    assert doc["sizeBytes"] == len(new_pdf)
    assert doc["version"] == 2

    # Storage layer recorded the new upload and the old-path delete.
    uploaded_paths = [u[0] for u in fake_storage.uploads]
    deleted_paths = list(fake_storage.deletes)
    assert body["filePath"] in uploaded_paths
    assert "users/replacer-1/old_abc_notes.pdf" in deleted_paths


def test_replace_increments_version_past_two(client, fake_db, fake_auth, fake_storage):
    uid = "replacer-2"
    fake_db.seed("users", uid, {"role": "student"})
    fake_db.seed(
        "materials",
        "mat-replace-2",
        {
            "ownerId": uid,
            "title": "Notes",
            "filePath": "users/replacer-2/old.pdf",
            "fileName": "old.pdf",
            "mimeType": "application/pdf",
            "sizeBytes": 10,
            "visibility": "private",
            "version": 7,
        },
    )
    resp = client.put(
        "/api/materials/mat-replace-2/file",
        headers=_h(fake_auth, uid),
        files={"file": ("new.pdf", b"%PDF-1.4\n%two\n", "application/pdf")},
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["version"] == 8


def test_non_owner_cannot_replace_file(client, fake_db, fake_auth, fake_storage):
    owner = "replacer-owner"
    other = "replacer-outsider"
    fake_db.seed("users", owner, {"role": "student"})
    fake_db.seed("users", other, {"role": "student"})
    fake_db.seed(
        "materials",
        "mat-replace-3",
        {
            "ownerId": owner,
            "filePath": "users/replacer-owner/secret.pdf",
            "fileName": "secret.pdf",
            "mimeType": "application/pdf",
            "sizeBytes": 10,
            "visibility": "private",
        },
    )
    resp = client.put(
        "/api/materials/mat-replace-3/file",
        headers=_h(fake_auth, other),
        files={"file": ("x.pdf", b"%PDF-1.4\n%x\n", "application/pdf")},
    )
    assert resp.status_code == 403, resp.text
    # No upload should have happened.
    assert fake_storage.uploads == []


def test_replace_missing_material_returns_404(client, fake_db, fake_auth):
    uid = "replacer-3"
    fake_db.seed("users", uid, {"role": "student"})
    resp = client.put(
        "/api/materials/nope/file",
        headers=_h(fake_auth, uid),
        files={"file": ("x.pdf", b"%PDF-1.4\n", "application/pdf")},
    )
    assert resp.status_code == 404, resp.text


def test_replace_rejects_unsupported_mime(client, fake_db, fake_auth, fake_storage):
    uid = "replacer-4"
    fake_db.seed("users", uid, {"role": "student"})
    fake_db.seed(
        "materials",
        "mat-replace-4",
        {
            "ownerId": uid,
            "filePath": "users/replacer-4/old.pdf",
            "fileName": "old.pdf",
            "mimeType": "application/pdf",
            "sizeBytes": 10,
            "visibility": "private",
        },
    )
    resp = client.put(
        "/api/materials/mat-replace-4/file",
        headers=_h(fake_auth, uid),
        files={"file": ("virus.exe", b"MZ\x90\x00", "application/octet-stream")},
    )
    assert resp.status_code == 415, resp.text
    assert fake_storage.uploads == []


def test_replace_rejects_empty_body(client, fake_db, fake_auth, fake_storage):
    uid = "replacer-5"
    fake_db.seed("users", uid, {"role": "student"})
    fake_db.seed(
        "materials",
        "mat-replace-5",
        {
            "ownerId": uid,
            "filePath": "users/replacer-5/old.pdf",
            "fileName": "old.pdf",
            "mimeType": "application/pdf",
            "sizeBytes": 10,
            "visibility": "private",
        },
    )
    resp = client.put(
        "/api/materials/mat-replace-5/file",
        headers=_h(fake_auth, uid),
        files={"file": ("empty.pdf", b"", "application/pdf")},
    )
    assert resp.status_code == 400, resp.text