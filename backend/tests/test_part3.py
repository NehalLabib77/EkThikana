"""PART 3 — E2E FUNCTIONAL CLOSURE tests.

Covers the new endpoints introduced in PART 3:

* Group chat toggle / list / post (in `routers/groups.py`)
* DOC / DOCX mime detection (in `core/utils.py`)
* Offline material register / list / remove (in `routers/part3.py`)
* Monthly budget set / get / remaining (in `routers/part3.py`)
* Focus session start / pause / resume / complete + idempotency (in `routers/part3.py`)
* Study stats (daily/monthly minutes, streak, completed-task count) (in `routers/part3.py`)

Every test runs against the real FastAPI app via the shared `client` fixture
(which already wires `FakeFirestore`, `FakeAuth`, and `FakeSupabaseStorage`).
"""

from __future__ import annotations

import sys
from pathlib import Path

_BACKEND_ROOT = Path(__file__).resolve().parent.parent
if str(_BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(_BACKEND_ROOT))

from tests.conftest import bearer, seed_profile  # noqa: E402


# ---------------------------------------------------------------------------
# Group chat toggle / list / post
# ---------------------------------------------------------------------------


def _seed_group(db, *, owner="owner-c", admin=None, members=None, chat_enabled=False):
    admin = admin or [owner]
    members = members or [owner]
    db.seed(
        "groups",
        "grp-chat",
        {
            "name": "Chat Group",
            "ownerId": owner,
            "adminIds": admin,
            "memberIds": members,
            "chatEnabled": chat_enabled,
        },
    )
    return "grp-chat"


def test_chat_toggle_admin_can_enable(client, fake_db, fake_auth):
    owner = "owner-c1"
    seed_profile(fake_db, owner, role="student")
    _seed_group(fake_db, owner=owner, admin=[owner], members=[owner], chat_enabled=False)

    resp = client.post(
        "/api/groups/grp-chat/chat/toggle",
        json={"chatEnabled": True},
        headers=bearer(fake_auth.issue(owner)),
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["chatEnabled"] is True
    assert body["groupId"] == "grp-chat"
    # The group doc should be updated.
    grp = fake_db._collections["groups"]["grp-chat"]
    assert grp["chatEnabled"] is True


def test_chat_toggle_non_admin_forbidden(client, fake_db, fake_auth):
    owner = "owner-c2"
    member = "member-c2"
    seed_profile(fake_db, owner, role="student")
    seed_profile(fake_db, member, role="student")
    _seed_group(fake_db, owner=owner, admin=[owner], members=[owner, member])

    resp = client.post(
        "/api/groups/grp-chat/chat/toggle",
        json={"chatEnabled": True},
        headers=bearer(fake_auth.issue(member)),
    )
    assert resp.status_code == 403, resp.text


def test_chat_post_blocked_when_disabled(client, fake_db, fake_auth):
    owner = "owner-c3"
    seed_profile(fake_db, owner, role="student")
    _seed_group(fake_db, owner=owner, admin=[owner], members=[owner], chat_enabled=False)

    resp = client.post(
        "/api/groups/grp-chat/chat",
        json={"text": "hello"},
        headers=bearer(fake_auth.issue(owner)),
    )
    assert resp.status_code == 403, resp.text


def test_chat_post_non_member_forbidden(client, fake_db, fake_auth):
    owner = "owner-c4"
    outsider = "outsider-c4"
    seed_profile(fake_db, owner, role="student")
    seed_profile(fake_db, outsider, role="student")
    _seed_group(fake_db, owner=owner, admin=[owner], members=[owner], chat_enabled=True)

    resp = client.post(
        "/api/groups/grp-chat/chat",
        json={"text": "hello"},
        headers=bearer(fake_auth.issue(outsider)),
    )
    assert resp.status_code == 403, resp.text


def test_chat_post_text_only_success(client, fake_db, fake_auth):
    owner = "owner-c5"
    seed_profile(fake_db, owner, role="student")
    _seed_group(fake_db, owner=owner, admin=[owner], members=[owner], chat_enabled=True)

    resp = client.post(
        "/api/groups/grp-chat/chat",
        json={"text": "hi team"},
        headers=bearer(fake_auth.issue(owner)),
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["groupId"] == "grp-chat"
    assert body["senderId"] == owner
    assert body["text"] == "hi team"


def test_chat_post_rejects_empty_payload(client, fake_db, fake_auth):
    owner = "owner-c6"
    seed_profile(fake_db, owner, role="student")
    _seed_group(fake_db, owner=owner, admin=[owner], members=[owner], chat_enabled=True)

    resp = client.post(
        "/api/groups/grp-chat/chat",
        json={},
        headers=bearer(fake_auth.issue(owner)),
    )
    assert resp.status_code == 400, resp.text


def test_chat_post_accepts_image_attachment(client, fake_db, fake_auth):
    owner = "owner-c7"
    seed_profile(fake_db, owner, role="student")
    _seed_group(fake_db, owner=owner, admin=[owner], members=[owner], chat_enabled=True)

    resp = client.post(
        "/api/groups/grp-chat/chat",
        json={
            "text": "see pic",
            "attachmentUrl": "https://fake/x.png",
            "attachmentFilename": "pic.png",
            "attachmentMime": "image/png",
            "attachmentSize": 1024,
        },
        headers=bearer(fake_auth.issue(owner)),
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["attachment"]["filename"] == "pic.png"


def test_chat_post_rejects_bad_mime(client, fake_db, fake_auth):
    owner = "owner-c8"
    seed_profile(fake_db, owner, role="student")
    _seed_group(fake_db, owner=owner, admin=[owner], members=[owner], chat_enabled=True)

    resp = client.post(
        "/api/groups/grp-chat/chat",
        json={
            "attachmentUrl": "https://fake/x.exe",
            "attachmentFilename": "virus.exe",
            "attachmentMime": "application/octet-stream",
            "attachmentSize": 1024,
        },
        headers=bearer(fake_auth.issue(owner)),
    )
    assert resp.status_code == 415, resp.text


def test_chat_list_only_returns_group_messages(client, fake_db, fake_auth):
    owner = "owner-c9"
    member = "member-c9"
    seed_profile(fake_db, owner, role="student")
    seed_profile(fake_db, member, role="student")
    _seed_group(fake_db, owner=owner, admin=[owner], members=[owner, member], chat_enabled=True)

    # Seed two messages in the right group + one in another group.
    fake_db.seed(
        "group_messages",
        "msg-1",
        {"groupId": "grp-chat", "senderId": owner, "text": "first", "createdAt": "2026-01-01T00:00:00Z"},
    )
    fake_db.seed(
        "group_messages",
        "msg-2",
        {"groupId": "grp-chat", "senderId": member, "text": "second", "createdAt": "2026-01-02T00:00:00Z"},
    )
    fake_db.seed(
        "group_messages",
        "msg-3",
        {"groupId": "grp-other", "senderId": owner, "text": "noise"},
    )

    resp = client.get(
        "/api/groups/grp-chat/chat?limit=10",
        headers=bearer(fake_auth.issue(owner)),
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["chatEnabled"] is True
    assert body["groupId"] == "grp-chat"
    ids = {m["id"] for m in body["messages"]}
    assert ids == {"msg-1", "msg-2"}


def test_chat_list_non_member_forbidden(client, fake_db, fake_auth):
    owner = "owner-c10"
    outsider = "outsider-c10"
    seed_profile(fake_db, owner, role="student")
    seed_profile(fake_db, outsider, role="student")
    _seed_group(fake_db, owner=owner, admin=[owner], members=[owner], chat_enabled=True)

    resp = client.get(
        "/api/groups/grp-chat/chat",
        headers=bearer(fake_auth.issue(outsider)),
    )
    assert resp.status_code == 403, resp.text


# ---------------------------------------------------------------------------
# DOC / DOCX upload mime detection
# ---------------------------------------------------------------------------


def _post_material(client, headers, *, name, header_bytes, mime, title="doc", visibility="private"):
    files = {"file": (name, header_bytes, mime)}
    return client.post(
        "/api/materials/upload",
        headers=headers,
        files=files,
        data={"title": title, "visibility": visibility},
    )


def test_docx_upload_accepted(client, fake_db, fake_auth):
    uid = "uploader-docx"
    seed_profile(fake_db, uid, role="student")
    # ZIP / PK\x03\x04 — Word .docx
    payload = b"PK\x03\x04" + b"\x00" * 64
    resp = _post_material(
        client,
        bearer(fake_auth.issue(uid)),
        name="notes.docx",
        header_bytes=payload,
        mime="application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        title="Docx Test",
    )
    assert resp.status_code in (200, 201), resp.text


def test_doc_upload_accepted(client, fake_db, fake_auth):
    uid = "uploader-doc"
    seed_profile(fake_db, uid, role="student")
    # OLE compound file signature — Word .doc
    payload = b"\xD0\xCF\x11\xE0\xA1\xB1\x1A\xE1" + b"\x00" * 64
    resp = _post_material(
        client,
        bearer(fake_auth.issue(uid)),
        name="legacy.doc",
        header_bytes=payload,
        mime="application/msword",
        title="Doc Test",
    )
    assert resp.status_code in (200, 201), resp.text


def test_unsupported_mime_still_rejected(client, fake_db, fake_auth):
    uid = "uploader-bad"
    seed_profile(fake_db, uid, role="student")
    files = {"file": ("bad.exe", b"MZ\x90\x00", "application/octet-stream")}
    resp = client.post(
        "/api/materials/upload",
        headers=bearer(fake_auth.issue(uid)),
        files=files,
        data={"title": "nope", "visibility": "private"},
    )
    assert resp.status_code in (400, 415, 422), resp.text


# ---------------------------------------------------------------------------
# Offline material register / list / remove
# ---------------------------------------------------------------------------


def test_offline_register_and_list(client, fake_db, fake_auth):
    uid = "user-off1"
    seed_profile(fake_db, uid, role="student")
    h = bearer(fake_auth.issue(uid))

    resp = client.post(
        "/api/offline/register",
        json={
            "materialId": "mat-offline-1",
            "title": "Offline Notes",
            "size": 4096,
            "localPath": "offline/mat-offline-1.bin",
        },
        headers=h,
    )
    assert resp.status_code in (200, 201), resp.text

    resp = client.get("/api/offline/list", headers=h)
    assert resp.status_code == 200, resp.text
    items = resp.json()["items"]
    assert any(it["materialId"] == "mat-offline-1" for it in items)


def test_offline_register_merges_existing(client, fake_db, fake_auth):
    uid = "user-off2"
    seed_profile(fake_db, uid, role="student")
    h = bearer(fake_auth.issue(uid))

    client.post(
        "/api/offline/register",
        json={
            "materialId": "mat-x",
            "title": "first",
            "size": 1024,
            "localPath": "offline/mat-x.bin",
        },
        headers=h,
    )
    client.post(
        "/api/offline/register",
        json={
            "materialId": "mat-x",
            "title": "renamed",
            "size": 2048,
            "localPath": "offline/mat-x.bin",
        },
        headers=h,
    )

    resp = client.get("/api/offline/list", headers=h)
    items = [it for it in resp.json()["items"] if it["materialId"] == "mat-x"]
    assert len(items) == 1
    assert items[0]["title"] == "renamed"
    assert items[0]["size"] == 2048


def test_offline_remove(client, fake_db, fake_auth):
    uid = "user-off3"
    seed_profile(fake_db, uid, role="student")
    h = bearer(fake_auth.issue(uid))

    client.post(
        "/api/offline/register",
        json={
            "materialId": "mat-rm",
            "title": "to-remove",
            "size": 100,
            "localPath": "offline/mat-rm.bin",
        },
        headers=h,
    )
    resp = client.delete("/api/offline/remove/mat-rm", headers=h)
    assert resp.status_code in (200, 204), resp.text

    resp = client.get("/api/offline/list", headers=h)
    assert all(it["materialId"] != "mat-rm" for it in resp.json()["items"])


def test_offline_list_isolates_users(client, fake_db, fake_auth):
    a, b = "user-off-a", "user-off-b"
    seed_profile(fake_db, a, role="student")
    seed_profile(fake_db, b, role="student")

    client.post(
        "/api/offline/register",
        json={"materialId": "mat-a", "title": "a", "size": 1, "localPath": "x"},
        headers=bearer(fake_auth.issue(a)),
    )
    resp = client.get("/api/offline/list", headers=bearer(fake_auth.issue(b)))
    assert resp.status_code == 200
    assert resp.json()["items"] == []


# ---------------------------------------------------------------------------
# Monthly budget set / get / remaining
# ---------------------------------------------------------------------------


def test_monthly_budget_set_and_get(client, fake_db, fake_auth):
    uid = "user-money1"
    seed_profile(fake_db, uid, role="student")
    h = bearer(fake_auth.issue(uid))

    resp = client.post(
        "/api/budget/monthly",
        json={"monthKey": "2026-01", "availableAmount": 15000},
        headers=h,
    )
    assert resp.status_code in (200, 201), resp.text

    resp = client.get("/api/budget/monthly?month_key=2026-01", headers=h)
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["availableAmount"] == 15000
    assert body["monthKey"] == "2026-01"


def test_monthly_budget_month_isolation(client, fake_db, fake_auth):
    uid = "user-money2"
    seed_profile(fake_db, uid, role="student")
    h = bearer(fake_auth.issue(uid))

    client.post(
        "/api/budget/monthly",
        json={"monthKey": "2026-01", "availableAmount": 10000},
        headers=h,
    )
    client.post(
        "/api/budget/monthly",
        json={"monthKey": "2026-02", "availableAmount": 20000},
        headers=h,
    )

    j = client.get("/api/budget/monthly?month_key=2026-01", headers=h).json()
    f = client.get("/api/budget/monthly?month_key=2026-02", headers=h).json()
    assert j["availableAmount"] == 10000
    assert f["availableAmount"] == 20000


def test_monthly_remaining_subtracts_only_confirmed(client, fake_db, fake_auth):
    uid = "user-money3"
    seed_profile(fake_db, uid, role="student")
    h = bearer(fake_auth.issue(uid))

    client.post(
        "/api/budget/monthly",
        json={"monthKey": "2026-01", "availableAmount": 15000},
        headers=h,
    )
    # Seed ACTUAL confirmed transactions (e.g. Daily Expenses, Medicine taken).
    # Estimated commute and pending medicine are status="estimated" so they
    # MUST NOT contribute to confirmed/remaining.
    #
    # The rows below carry `monthKey`, which is what the Flutter
    # `FinancialService` actually stamps on every ledger mirror. This test
    # used to seed `createdAtIso` instead — a field no client has ever
    # written — which is why it passed against a query that matched nothing
    # in production.
    fake_db.seed(
        "financial_transactions",
        "tx-1",
        {
            "ownerId": uid,
            "amount": 4000,
            "status": "confirmed",
            "source": "daily_expense",
            "monthKey": "2026-01",
            "dateKey": "2026-01-10",
        },
    )
    fake_db.seed(
        "financial_transactions",
        "tx-2",
        {
            "ownerId": uid,
            "amount": 4000,
            "status": "confirmed",
            "source": "medicine_taken",
            "monthKey": "2026-01",
            "dateKey": "2026-01-12",
        },
    )
    fake_db.seed(
        "financial_transactions",
        "tx-3",
        {
            "ownerId": uid,
            "amount": 999,
            "status": "estimated",
            "source": "commute",
            "monthKey": "2026-01",
            "dateKey": "2026-01-15",
        },
    )
    # A different month must not leak into this month's total.
    fake_db.seed(
        "financial_transactions",
        "tx-4",
        {
            "ownerId": uid,
            "amount": 5000,
            "status": "confirmed",
            "source": "daily_expense",
            "monthKey": "2026-02",
            "dateKey": "2026-02-03",
        },
    )

    resp = client.get("/api/budget/remaining?month_key=2026-01", headers=h)
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["available"] == 15000
    assert body["confirmedSpending"] == 8000
    assert body["remaining"] == 7000


def test_monthly_remaining_counts_rows_written_by_the_flutter_client(
    client, fake_db, fake_auth
):
    """Regression: the ledger row shape Flutter actually writes must count.

    `FinancialService._financialData` stamps ownerId/userId/type/source/
    sourceRecordId/category/title/amount/date/dateKey/monthKey/status. It has
    never written `createdAtIso`. While `/api/budget/remaining` range-filtered
    on that field, the query matched zero documents for every user, so
    `remaining` always equalled the untouched monthly budget regardless of how
    much had been spent.
    """
    uid = "user-money-client-shape"
    seed_profile(fake_db, uid, role="student")
    h = bearer(fake_auth.issue(uid))

    client.post(
        "/api/budget/monthly",
        json={"monthKey": "2026-05", "availableAmount": 10000},
        headers=h,
    )

    # Exactly the field set the Flutter client writes - note: no createdAtIso.
    fake_db.seed(
        "financial_transactions",
        "daily_abc123",
        {
            "ownerId": uid,
            "userId": uid,
            "type": "expense",
            "source": "daily",
            "sourceRecordId": "abc123",
            "category": "Lunch",
            "title": "Rice and curry",
            "amount": 120.0,
            "dateKey": "2026-05-04",
            "monthKey": "2026-05",
            "status": "confirmed",
        },
    )

    body = client.get("/api/budget/remaining?month_key=2026-05", headers=h).json()
    assert body["confirmedSpending"] == 120.0, body
    assert body["remaining"] == 9880.0, body
    assert body["bySource"]["daily"] == 120.0, body


def test_monthly_remaining_treats_a_legacy_row_without_status_as_confirmed(
    client, fake_db, fake_auth
):
    """Rows written before the client stamped `status` must still count.

    Gochano only mirrors a ledger row once the underlying expense/purchase/
    dose/fare is real, so an untagged historical row is a confirmed one.
    """
    uid = "user-money-legacy"
    seed_profile(fake_db, uid, role="student")
    h = bearer(fake_auth.issue(uid))

    client.post(
        "/api/budget/monthly",
        json={"monthKey": "2026-06", "availableAmount": 2000},
        headers=h,
    )
    fake_db.seed(
        "financial_transactions",
        "legacy-1",
        {
            "ownerId": uid,
            "amount": 300.0,
            "source": "bazar",
            "monthKey": "2026-06",
        },
    )

    body = client.get("/api/budget/remaining?month_key=2026-06", headers=h).json()
    assert body["confirmedSpending"] == 300.0, body
    assert body["remaining"] == 1700.0, body


def test_monthly_remaining_returns_zero_when_no_budget(client, fake_db, fake_auth):
    uid = "user-money4"
    seed_profile(fake_db, uid, role="student")
    h = bearer(fake_auth.issue(uid))

    resp = client.get("/api/budget/remaining?month_key=2026-03", headers=h)
    assert resp.status_code == 200
    body = resp.json()
    assert body["available"] == 0
    assert body["remaining"] == 0


# ---------------------------------------------------------------------------
# Focus session lifecycle + idempotency
# ---------------------------------------------------------------------------


def test_focus_start_returns_running(client, fake_db, fake_auth):
    uid = "user-focus1"
    seed_profile(fake_db, uid, role="student")
    h = bearer(fake_auth.issue(uid))

    resp = client.post(
        "/api/study/focus/start",
        json={"label": "Read chapter 1"},
        headers=h,
    )
    assert resp.status_code in (200, 201), resp.text
    body = resp.json()
    assert body["status"] == "running"
    assert "id" in body
    assert body["label"] == "Read chapter 1"


def test_focus_pause_requires_running(client, fake_db, fake_auth):
    uid = "user-focus2"
    seed_profile(fake_db, uid, role="student")
    h = bearer(fake_auth.issue(uid))

    resp = client.post("/api/study/focus/start", json={}, headers=h)
    fid = resp.json()["id"]

    # Pause -> should succeed
    resp = client.patch(
        f"/api/study/focus/{fid}",
        json={"action": "pause"},
        headers=h,
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["status"] == "paused"

    # Second pause -> should reject (already paused)
    resp = client.patch(
        f"/api/study/focus/{fid}",
        json={"action": "pause"},
        headers=h,
    )
    assert resp.status_code in (400, 409), resp.text


def test_focus_resume_requires_paused(client, fake_db, fake_auth):
    uid = "user-focus3"
    seed_profile(fake_db, uid, role="student")
    h = bearer(fake_auth.issue(uid))

    resp = client.post("/api/study/focus/start", json={}, headers=h)
    fid = resp.json()["id"]

    # Resume before pause -> reject
    resp = client.patch(
        f"/api/study/focus/{fid}",
        json={"action": "resume"},
        headers=h,
    )
    assert resp.status_code in (400, 409), resp.text


def test_focus_complete_is_idempotent(client, fake_db, fake_auth):
    uid = "user-focus4"
    seed_profile(fake_db, uid, role="student")
    h = bearer(fake_auth.issue(uid))

    resp = client.post("/api/study/focus/start", json={}, headers=h)
    fid = resp.json()["id"]

    resp = client.patch(
        f"/api/study/focus/{fid}",
        json={"action": "complete"},
        headers=h,
    )
    assert resp.status_code == 200, resp.text
    first_body = resp.json()
    assert first_body["status"] == "completed"
    first_completed_at = first_body.get("completedAtIso") or first_body.get("completedAt")

    # Second complete -> idempotent
    resp = client.patch(
        f"/api/study/focus/{fid}",
        json={"action": "complete"},
        headers=h,
    )
    assert resp.status_code == 200, resp.text
    second_body = resp.json()
    assert second_body.get("idempotent") is True
    second_completed_at = second_body.get("completedAtIso") or second_body.get("completedAt")
    assert second_completed_at == first_completed_at


def test_focus_cancel(client, fake_db, fake_auth):
    uid = "user-focus5"
    seed_profile(fake_db, uid, role="student")
    h = bearer(fake_auth.issue(uid))

    resp = client.post("/api/study/focus/start", json={}, headers=h)
    fid = resp.json()["id"]

    resp = client.patch(
        f"/api/study/focus/{fid}",
        json={"action": "cancel"},
        headers=h,
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["status"] == "cancelled"


def test_focus_list_returns_only_user_sessions(client, fake_db, fake_auth):
    a, b = "user-focus-a", "user-focus-b"
    seed_profile(fake_db, a, role="student")
    seed_profile(fake_db, b, role="student")

    client.post("/api/study/focus/start", json={"label": "a1"}, headers=bearer(fake_auth.issue(a)))
    client.post("/api/study/focus/start", json={"label": "b1"}, headers=bearer(fake_auth.issue(b)))

    resp = client.get(
        "/api/study/focus/list",
        headers=bearer(fake_auth.issue(a)),
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    labels = [s["label"] for s in body["sessions"]]
    assert labels == ["a1"]


# ---------------------------------------------------------------------------
# Legacy-data safety net (clamp impossibly large accumulatedSeconds)
#
# Bug background: a small number of students produced focus-session rows whose
# accumulatedSeconds value is the duration expressed in **minutes**, not
# seconds. The most visible symptom was a single session row reading 98h 37m
# and a Profile "this month" stat reading 5_917 min — i.e. ~354_000 seconds,
# which is plausible only when the writer dropped minutes into a seconds
# column.
#
# These tests pin the defensive coercion: every read path now clamps anything
# above 24h down to 24h, so a single corrupted row cannot poison /study/stats
# or the focus history list.
# ---------------------------------------------------------------------------


def _seed_focus_session(db, uid: str, *, status: str, accumulated_seconds, day_key: str = "2026-09-01") -> str:
    doc_id = "focus_legacy_test"
    db.seed(
        f"users/{uid}/focus_sessions",
        doc_id,
        {
            "id": doc_id,
            "ownerId": uid,
            "status": status,
            "label": "Legacy row",
            "plannedMinutes": 25,
            "accumulatedSeconds": accumulated_seconds,
            # Mark the session complete some time today so dayKey == today is
            # preserved across the stats walk.
            "dayKey": day_key,
            "startedAtIso": f"{day_key}T00:00:00+00:00",
            "completedAtIso": f"{day_key}T00:25:00+00:00",
        },
    )
    return doc_id


def test_focus_list_drops_impossibly_large_accumulated_seconds_to_zero(
    client, fake_db, fake_auth
):
    uid = "user-focus-legacy-1"
    seed_profile(fake_db, uid, role="student")
    h = bearer(fake_auth.issue(uid))

    # 354_920 seconds = 5_917 minutes = the reported "5917 min" pollution,
    # stored in a single focus-session row.
    _seed_focus_session(fake_db, uid, status="completed", accumulated_seconds=354_920)

    resp = client.get("/api/study/focus/list", headers=h)
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert len(body["sessions"]) == 1
    # Policy: corrupt / impossible legacy values are surfaced as 0 — NEVER
    # clamped up to 86_400 (which would itself be a "1440 min" phantom
    # session in the UI). The user did not study 24 hours; the only honest
    # answer is 0.
    assert body["sessions"][0]["accumulatedSeconds"] == 0


def test_focus_list_tolerates_string_accumulated_seconds(
    client, fake_db, fake_auth
):
    uid = "user-focus-legacy-2"
    seed_profile(fake_db, uid, role="student")
    h = bearer(fake_auth.issue(uid))

    # Firestore has historically handed numeric fields back as strings on a
    # handful of SDK versions; the reader must coerce, not throw.
    _seed_focus_session(fake_db, uid, status="completed", accumulated_seconds="1500")

    resp = client.get("/api/study/focus/list", headers=h)
    assert resp.status_code == 200, resp.text
    assert resp.json()["sessions"][0]["accumulatedSeconds"] == 1500


def test_focus_list_negative_accumulated_seconds_clamped_to_zero(
    client, fake_db, fake_auth
):
    uid = "user-focus-legacy-3"
    seed_profile(fake_db, uid, role="student")
    h = bearer(fake_auth.issue(uid))

    # Negative values are nonsense for a duration counter; treat as 0 rather
    # than letting them propagate into /study/stats as a poisoned daily total.
    _seed_focus_session(fake_db, uid, status="completed", accumulated_seconds=-300)

    resp = client.get("/api/study/focus/list", headers=h)
    assert resp.status_code == 200, resp.text
    assert resp.json()["sessions"][0]["accumulatedSeconds"] == 0


def test_study_stats_drops_corrupt_legacy_row_to_zero(
    client, fake_db, fake_auth
):
    """A 354_920-second legacy row must NOT inflate today's or this month's
    totals.

    Policy: corrupt historical values collapse to 0. The stats aggregator
    therefore sees 0 seconds contributed by this row, and
    ``todayMinutes`` / ``monthMinutes`` are both 0 — never 1_440 (which
    would itself be a phantom 24h session in the Profile card).
    """
    from datetime import datetime, timezone

    uid = "user-focus-legacy-stats"
    seed_profile(fake_db, uid, role="student")
    h = bearer(fake_auth.issue(uid))

    # /study/stats aggregates by the row's own ``dayKey``; to exercise
    # todaySeconds/monthSeconds we have to land the row on today's UTC key,
    # otherwise it lands on a historical bucket the router never returns.
    today_key = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    _seed_focus_session(
        fake_db,
        uid,
        status="completed",
        accumulated_seconds=354_920,
        day_key=today_key,
    )

    resp = client.get("/api/study/stats", headers=h)
    assert resp.status_code == 200, resp.text
    body = resp.json()
    # Corrupt row → 0 minutes today and 0 minutes this month.
    # The historical ~5_917 pollution is dropped, never clamped to 1_440.
    assert body["todayMinutes"] == 0
    assert body["monthMinutes"] == 0


def test_focus_complete_is_idempotent_for_completed_session(
    client, fake_db, fake_auth
):
    """Repeated complete calls must not double-count elapsed time.

    This is the "re-finishing a session inflates the duration" defensive
    test: the second complete must report the exact same
    ``accumulatedSeconds`` as the first, even if the client retries on a
    flaky network. The existing idempotency test only checks status /
    completedAtIso, not the numeric payload.
    """
    uid = "user-focus-idem"
    seed_profile(fake_db, uid, role="student")
    h = bearer(fake_auth.issue(uid))

    resp = client.post("/api/study/focus/start", json={}, headers=h)
    fid = resp.json()["id"]

    first = client.patch(f"/api/study/focus/{fid}", json={"action": "complete"}, headers=h).json()
    second = client.patch(f"/api/study/focus/{fid}", json={"action": "complete"}, headers=h).json()

    assert first["status"] == "completed"
    assert second["status"] == "completed"
    assert second.get("idempotent") is True
    assert second["accumulatedSeconds"] == first["accumulatedSeconds"]
    # And, critically, the on-disk value did not move.
    stored = fake_db._collections[f"users/{uid}/focus_sessions"][fid]["accumulatedSeconds"]
    assert stored == first["accumulatedSeconds"]


def test_focus_patch_complete_discards_huge_run_interval(
    client, fake_db, fake_auth
):
    """A row whose ``lastResumedAtIso`` is years in the past must discard the
    interval rather than fabricate a 24-hour duration.

    A stuck "running" session whose resume stamp is from two years ago must
    preserve the already-sanitized accumulated value.
    """
    uid = "user-focus-stuck"
    seed_profile(fake_db, uid, role="student")
    h = bearer(fake_auth.issue(uid))

    resp = client.post("/api/study/focus/start", json={}, headers=h)
    fid = resp.json()["id"]

    # Backdate lastResumedAtIso to 2020 and pretend accumulatedSeconds is 0.
    fake_db._collections[f"users/{uid}/focus_sessions"][fid].update(
        {"lastResumedAtIso": "2020-01-01T00:00:00+00:00", "accumulatedSeconds": 0}
    )

    body = client.patch(f"/api/study/focus/{fid}", json={"action": "complete"}, headers=h).json()
    assert body["status"] == "completed"
    assert body["accumulatedSeconds"] == 0


def test_fold_running_interval_discards_stale_and_overflowing_intervals():
    from datetime import datetime, timedelta, timezone

    from app.routers.part3 import _fold_running_interval

    now = datetime.now(timezone.utc)
    assert _fold_running_interval(
        now, now - timedelta(seconds=300), 0
    )[0] == 300
    assert _fold_running_interval(
        now, now - timedelta(seconds=90_000), 0
    )[0] == 0
    assert _fold_running_interval(
        now, now - timedelta(seconds=90_000), 600
    )[0] == 600
    assert _fold_running_interval(
        now, now - timedelta(seconds=1_000), 86_000
    )[0] == 86_000


# ---------------------------------------------------------------------------
# Elapsed-time preservation regression tests (bug: completed/cancelled
# sessions saved 0 seconds).
#
# Symptom: a user who started a focus session and then stopped / cancelled /
# finished it at any duration (37 sec, 2 min, 7 min, 25 min, 1 hour, ...) saw
# 0 min in Focus history instead of the real elapsed time.
#
# Canonical field is ``accumulatedSeconds``; the router must return exact
# integer seconds — never rounded minutes.
#
# These tests assert the contract from the API surface: PATCH
# /api/study/focus/{id} with action in {complete, cancel, pause} must persist
# ``accumulatedSeconds`` so a follow-up GET /api/study/focus/list returns the
# real elapsed time.
#
# Timestamps are mocked by manipulating ``lastResumedAtIso`` /
# ``accumulatedSeconds`` directly in the fake DB — tests never literally wait.
# ---------------------------------------------------------------------------


def _start_session(client, fake_auth, uid: str) -> str:
    h = bearer(fake_auth.issue(uid))
    resp = client.post("/api/study/focus/start", json={}, headers=h)
    assert resp.status_code in (200, 201), resp.text
    return resp.json()["id"]


def _set_running(
    fake_db, uid: str, fid: str, *, last_resumed_iso: str, accumulated_seconds: int = 0
) -> None:
    fake_db._collections[f"users/{uid}/focus_sessions"][fid].update(
        {
            "status": "running",
            "lastResumedAtIso": last_resumed_iso,
            "accumulatedSeconds": accumulated_seconds,
        }
    )


def test_focus_complete_preserves_37_seconds(client, fake_db, fake_auth):
    """A 37-second focus session must save as 37 seconds, not 0."""
    uid = "user-focus-arb-37"
    seed_profile(fake_db, uid, role="student")
    h = bearer(fake_auth.issue(uid))

    fid = _start_session(client, fake_auth, uid)
    # Started 37 seconds before "now": mock by stamping lastResumedAtIso to
    # 37 seconds in the past. Reset accumulatedSeconds to 0 so the assertion
    # is unambiguous.
    from datetime import datetime, timedelta, timezone

    now = datetime.now(timezone.utc)
    started = now - timedelta(seconds=37)
    _set_running(
        fake_db,
        uid,
        fid,
        last_resumed_iso=started.isoformat(),
        accumulated_seconds=0,
    )

    body = client.patch(
        f"/api/study/focus/{fid}", json={"action": "complete"}, headers=h
    ).json()
    assert body["status"] == "completed"
    assert body["accumulatedSeconds"] == 37, body


def test_focus_complete_preserves_125_seconds(client, fake_db, fake_auth):
    """A 2-minute 5-second focus session must save as 125 seconds."""
    uid = "user-focus-arb-125"
    seed_profile(fake_db, uid, role="student")
    h = bearer(fake_auth.issue(uid))

    fid = _start_session(client, fake_auth, uid)
    from datetime import datetime, timedelta, timezone

    started = datetime.now(timezone.utc) - timedelta(seconds=125)
    _set_running(
        fake_db,
        uid,
        fid,
        last_resumed_iso=started.isoformat(),
        accumulated_seconds=0,
    )

    body = client.patch(
        f"/api/study/focus/{fid}", json={"action": "complete"}, headers=h
    ).json()
    assert body["accumulatedSeconds"] == 125, body

    # Listing must reflect the same value.
    listed = client.get("/api/study/focus/list", headers=h).json()
    assert listed["sessions"][0]["accumulatedSeconds"] == 125


def test_focus_complete_preserves_330_seconds(client, fake_db, fake_auth):
    """5m30s → 330 seconds exact (not rounded to 5 or 6 minutes)."""
    uid = "user-focus-arb-330"
    seed_profile(fake_db, uid, role="student")
    h = bearer(fake_auth.issue(uid))

    fid = _start_session(client, fake_auth, uid)
    from datetime import datetime, timedelta, timezone

    started = datetime.now(timezone.utc) - timedelta(seconds=330)
    _set_running(
        fake_db,
        uid,
        fid,
        last_resumed_iso=started.isoformat(),
        accumulated_seconds=0,
    )

    body = client.patch(
        f"/api/study/focus/{fid}", json={"action": "complete"}, headers=h
    ).json()
    assert body["accumulatedSeconds"] == 330, body


def test_focus_complete_preserves_475_seconds(client, fake_db, fake_auth):
    """7m55s → 475 seconds exact."""
    uid = "user-focus-arb-475"
    seed_profile(fake_db, uid, role="student")
    h = bearer(fake_auth.issue(uid))

    fid = _start_session(client, fake_auth, uid)
    from datetime import datetime, timedelta, timezone

    started = datetime.now(timezone.utc) - timedelta(seconds=475)
    _set_running(
        fake_db,
        uid,
        fid,
        last_resumed_iso=started.isoformat(),
        accumulated_seconds=0,
    )

    body = client.patch(
        f"/api/study/focus/{fid}", json={"action": "complete"}, headers=h
    ).json()
    assert body["accumulatedSeconds"] == 475, body


def test_focus_complete_preserves_1500_seconds(client, fake_db, fake_auth):
    """25 minutes (1500 seconds) must save as exactly 1500 — not 24*60+59."""
    uid = "user-focus-arb-1500"
    seed_profile(fake_db, uid, role="student")
    h = bearer(fake_auth.issue(uid))

    fid = _start_session(client, fake_auth, uid)
    from datetime import datetime, timedelta, timezone

    started = datetime.now(timezone.utc) - timedelta(seconds=1500)
    _set_running(
        fake_db,
        uid,
        fid,
        last_resumed_iso=started.isoformat(),
        accumulated_seconds=0,
    )

    body = client.patch(
        f"/api/study/focus/{fid}", json={"action": "complete"}, headers=h
    ).json()
    assert body["accumulatedSeconds"] == 1500, body
    # The display math: 1500 sec → 25 min, not 0 or 1500/60 rounded.
    assert body["accumulatedSeconds"] // 60 == 25


def test_focus_complete_preserves_4080_seconds_one_hour_eight_min(client, fake_db, fake_auth):
    """1h8m = 4080 seconds must save as 4080 — not 0."""
    uid = "user-focus-arb-4080"
    seed_profile(fake_db, uid, role="student")
    h = bearer(fake_auth.issue(uid))

    fid = _start_session(client, fake_auth, uid)
    from datetime import datetime, timedelta, timezone

    started = datetime.now(timezone.utc) - timedelta(seconds=4080)
    _set_running(
        fake_db,
        uid,
        fid,
        last_resumed_iso=started.isoformat(),
        accumulated_seconds=0,
    )

    body = client.patch(
        f"/api/study/focus/{fid}", json={"action": "complete"}, headers=h
    ).json()
    assert body["accumulatedSeconds"] == 4080, body


def test_focus_complete_after_pause_preserves_total(client, fake_db, fake_auth):
    """pause -> complete: the running portion added during pause must remain.

    On pause the router folds ``now - lastResumedAtIso`` into
    ``accumulatedSeconds`` and clears ``lastResumedAtIso``. The subsequent
    complete must not double-count the paused portion: total stays exactly
    the running portion, with no further addition.
    """
    uid = "user-focus-pause-stop"
    seed_profile(fake_db, uid, role="student")
    h = bearer(fake_auth.issue(uid))

    fid = _start_session(client, fake_auth, uid)
    from datetime import datetime, timedelta, timezone

    started = datetime.now(timezone.utc) - timedelta(seconds=300)
    _set_running(
        fake_db,
        uid,
        fid,
        last_resumed_iso=started.isoformat(),
        accumulated_seconds=0,
    )

    pause_body = client.patch(
        f"/api/study/focus/{fid}", json={"action": "pause"}, headers=h
    ).json()
    assert pause_body["status"] == "paused"
    # The pause response itself must surface the running interval.
    assert pause_body["accumulatedSeconds"] == 300, pause_body

    # Now complete while paused — the total must remain 300, not 0 or 600.
    body = client.patch(
        f"/api/study/focus/{fid}", json={"action": "complete"}, headers=h
    ).json()
    assert body["status"] == "completed"
    assert body["accumulatedSeconds"] == 300, body


def test_focus_complete_after_pause_resume_adds_both_intervals(
    client, fake_db, fake_auth
):
    """pause -> resume -> complete: total = first_running + resumed_running.

    Mocks two non-overlapping intervals (200s, 250s) by stamping
    lastResumedAtIso to 250s in the past before completion, while
    accumulatedSeconds already carries the 200s from a prior pause.
    """
    uid = "user-focus-pause-resume-stop"
    seed_profile(fake_db, uid, role="student")
    h = bearer(fake_auth.issue(uid))

    fid = _start_session(client, fake_auth, uid)
    from datetime import datetime, timedelta, timezone

    # Simulate a previous pause that already folded 200s into accumulatedSeconds.
    fake_db._collections[f"users/{uid}/focus_sessions"][fid].update(
        {
            "status": "running",
            "accumulatedSeconds": 200,
            "lastResumedAtIso": (
                datetime.now(timezone.utc) - timedelta(seconds=250)
            ).isoformat(),
        }
    )

    body = client.patch(
        f"/api/study/focus/{fid}", json={"action": "complete"}, headers=h
    ).json()
    assert body["status"] == "completed"
    assert body["accumulatedSeconds"] == 450, body  # 200 + 250


def test_focus_cancel_preserves_elapsed_time(client, fake_db, fake_auth):
    """The "Focus History shows 0 min" bug — cancel must not lose the running interval.

    Before this was fixed, ``cancel`` set ``status=cancelled`` without ever
    reading or updating ``accumulatedSeconds``, so a user who ran a 7-minute
    session and then cancelled saw 0 min in history.

    After the fix, cancelling while running must persist the running interval
    and surface it in the cancel response + list.
    """
    uid = "user-focus-cancel-preserve"
    seed_profile(fake_db, uid, role="student")
    h = bearer(fake_auth.issue(uid))

    fid = _start_session(client, fake_auth, uid)
    from datetime import datetime, timedelta, timezone

    started = datetime.now(timezone.utc) - timedelta(seconds=475)  # 7m55s
    _set_running(
        fake_db,
        uid,
        fid,
        last_resumed_iso=started.isoformat(),
        accumulated_seconds=0,
    )

    # Cancel.
    cancel_body = client.patch(
        f"/api/study/focus/{fid}", json={"action": "cancel"}, headers=h
    ).json()
    assert cancel_body["status"] == "cancelled"
    # The cancel response now carries accumulatedSeconds.
    assert cancel_body.get("accumulatedSeconds") == 475, cancel_body

    # Listed history reflects the same value.
    listed = client.get("/api/study/focus/list", headers=h).json()
    matching = [s for s in listed["sessions"] if s["id"] == fid]
    assert len(matching) == 1
    assert matching[0]["status"] == "cancelled"
    assert matching[0]["accumulatedSeconds"] == 475, matching[0]


def test_focus_cancel_while_paused_preserves_accumulated_seconds(
    client, fake_db, fake_auth
):
    """cancel after pause: only the persisted accumulatedSeconds remains, no running gap."""
    uid = "user-focus-cancel-paused"
    seed_profile(fake_db, uid, role="student")
    h = bearer(fake_auth.issue(uid))

    fid = _start_session(client, fake_auth, uid)
    from datetime import datetime, timedelta, timezone

    started = datetime.now(timezone.utc) - timedelta(seconds=200)
    _set_running(
        fake_db,
        uid,
        fid,
        last_resumed_iso=started.isoformat(),
        accumulated_seconds=0,
    )

    pause_body = client.patch(
        f"/api/study/focus/{fid}", json={"action": "pause"}, headers=h
    ).json()
    assert pause_body["accumulatedSeconds"] == 200

    cancel_body = client.patch(
        f"/api/study/focus/{fid}", json={"action": "cancel"}, headers=h
    ).json()
    assert cancel_body["status"] == "cancelled"
    assert cancel_body["accumulatedSeconds"] == 200, cancel_body


def test_repeated_complete_is_idempotent_on_accumulated_seconds(
    client, fake_db, fake_auth
):
    """Two complete calls in a row must report the same accumulatedSeconds.

    The second call must NOT re-add the now - lastResumedAtIso gap (which was
    cleared by the first complete), nor corrupt the on-disk value.
    """
    uid = "user-focus-repeat-complete"
    seed_profile(fake_db, uid, role="student")
    h = bearer(fake_auth.issue(uid))

    fid = _start_session(client, fake_auth, uid)
    from datetime import datetime, timedelta, timezone

    started = datetime.now(timezone.utc) - timedelta(seconds=330)
    _set_running(
        fake_db,
        uid,
        fid,
        last_resumed_iso=started.isoformat(),
        accumulated_seconds=0,
    )

    first = client.patch(
        f"/api/study/focus/{fid}", json={"action": "complete"}, headers=h
    ).json()
    assert first["accumulatedSeconds"] == 330, first

    second = client.patch(
        f"/api/study/focus/{fid}", json={"action": "complete"}, headers=h
    ).json()
    assert second.get("idempotent") is True
    # Critical: the second call does not re-add a phantom interval.
    assert second["accumulatedSeconds"] == 330, second


def test_repeated_cancel_is_idempotent_on_accumulated_seconds(
    client, fake_db, fake_auth
):
    """Two cancel calls in a row must not double-count or under-count."""
    uid = "user-focus-repeat-cancel"
    seed_profile(fake_db, uid, role="student")
    h = bearer(fake_auth.issue(uid))

    fid = _start_session(client, fake_auth, uid)
    from datetime import datetime, timedelta, timezone

    started = datetime.now(timezone.utc) - timedelta(seconds=150)
    _set_running(
        fake_db,
        uid,
        fid,
        last_resumed_iso=started.isoformat(),
        accumulated_seconds=0,
    )

    first = client.patch(
        f"/api/study/focus/{fid}", json={"action": "cancel"}, headers=h
    ).json()
    assert first["accumulatedSeconds"] == 150, first

    # Second cancel while already cancelled: must remain 150, not 0 or 300.
    second = client.patch(
        f"/api/study/focus/{fid}", json={"action": "cancel"}, headers=h
    ).json()
    assert second["status"] == "cancelled"
    assert second["accumulatedSeconds"] == 150, second


def test_complete_does_not_double_count_paused_interval(
    client, fake_db, fake_auth
):
    """A session paused for a long time and then completed must not
    double-count the paused gap. Pause clears lastResumedAtIso, so the
    complete handler must NOT add zero — and must NOT add elapsed time from
    the pause stamp either.
    """
    uid = "user-focus-paused-no-double"
    seed_profile(fake_db, uid, role="student")
    h = bearer(fake_auth.issue(uid))

    fid = _start_session(client, fake_auth, uid)
    from datetime import datetime, timedelta, timezone

    started = datetime.now(timezone.utc) - timedelta(seconds=180)
    _set_running(
        fake_db,
        uid,
        fid,
        last_resumed_iso=started.isoformat(),
        accumulated_seconds=0,
    )

    # Pause first — folds 180s into accumulatedSeconds and clears lastResumedAtIso.
    pause_body = client.patch(
        f"/api/study/focus/{fid}", json={"action": "pause"}, headers=h
    ).json()
    assert pause_body["accumulatedSeconds"] == 180

    # Now wait an absurd amount of "paused" time by simply not changing the
    # lastResumedAtIso — pause already cleared it. Complete must not
    # magically add time from anything.
    body = client.patch(
        f"/api/study/focus/{fid}", json={"action": "complete"}, headers=h
    ).json()
    assert body["status"] == "completed"
    assert body["accumulatedSeconds"] == 180, body


def test_cancel_drops_corrupt_legacy_accumulated_seconds_to_zero(
    client, fake_db, fake_auth
):
    """A pre-existing poisoned row must NEVER surface as a real-looking value.

    A row carrying 354_920 seconds (≈ 5_917 min — the "5917 min" pollution on
    the Profile study-stats card, and the "98h 37m" focus history row) must
    surface as 0 on cancel — NOT 86_400 (which would itself be a "1440 min"
    bug) and NOT 354_920. The user did not study 24 hours; the value is
    corrupt and the only honest answer is 0.
    """
    uid = "user-focus-cancel-clamps"
    seed_profile(fake_db, uid, role="student")
    h = bearer(fake_auth.issue(uid))

    fid = _start_session(client, fake_auth, uid)
    fake_db._collections[f"users/{uid}/focus_sessions"][fid].update(
        {"status": "running", "accumulatedSeconds": 354_920}
    )

    body = client.patch(
        f"/api/study/focus/{fid}", json={"action": "cancel"}, headers=h
    ).json()
    assert body["status"] == "cancelled"
    # 354_920 is corrupt → 0, never 86_400. Clamping up to a real-looking
    # number would re-introduce the very bug class this regression exists
    # to prevent.
    assert body["accumulatedSeconds"] == 0, body

    # And the list endpoint must agree — no 1440-min phantom session.
    listed = client.get("/api/study/focus/list", headers=h).json()
    assert listed["sessions"][0]["accumulatedSeconds"] == 0


def test_complete_drops_corrupt_legacy_accumulated_seconds_to_zero(
    client, fake_db, fake_auth
):
    """Corrupt historical values must also collapse to 0 on complete.

    Mirror of the cancel test: a row with 354_920 accumulatedSeconds on
    complete must return 0 — not 86_400, not 354_920.
    """
    uid = "user-focus-complete-corrupt"
    seed_profile(fake_db, uid, role="student")
    h = bearer(fake_auth.issue(uid))

    fid = _start_session(client, fake_auth, uid)
    fake_db._collections[f"users/{uid}/focus_sessions"][fid].update(
        {"status": "running", "accumulatedSeconds": 354_920}
    )

    body = client.patch(
        f"/api/study/focus/{fid}", json={"action": "complete"}, headers=h
    ).json()
    assert body["status"] == "completed"
    assert body["accumulatedSeconds"] == 0, body


def test_negative_and_malformed_accumulated_seconds_collapse_to_zero(
    client, fake_db, fake_auth
):
    """Defensive read sanity: every malformed stored value becomes 0.

    ``accumulatedSeconds`` can be any of: -5 (legacy bug, never negative),
    "not-a-number" (manual write, Firestore import glitch), or an absurdly
    large number (the 5917-min pollution). All must surface as 0 on read —
    never as a positive real-looking duration.
    """
    uid = "user-focus-malformed"
    seed_profile(fake_db, uid, role="student")
    h = bearer(fake_auth.issue(uid))

    for poisoned in (-5, "not-a-number", 1_000_000):
        fid = _start_session(client, fake_auth, uid)
        fake_db._collections[f"users/{uid}/focus_sessions"][fid].update(
            {"status": "running", "accumulatedSeconds": poisoned}
        )
        body = client.patch(
            f"/api/study/focus/{fid}", json={"action": "cancel"}, headers=h
        ).json()
        assert body["status"] == "cancelled", poisoned
        assert body["accumulatedSeconds"] == 0, (poisoned, body)


def test_complete_with_missing_resume_stamp_does_not_double_count(
    client, fake_db, fake_auth
):
    """Missing ``lastResumedAtIso`` must NOT cause double-counting.

    The previous fix used ``startedAtIso`` as a fallback when
    ``lastResumedAtIso`` was missing — but if ``accumulatedSeconds``
    already contains folded pause/resume intervals, adding
    ``now - startedAtIso`` on top of them double-counts the entire start→now
    span. The safe policy is: keep ``accumulatedSeconds`` unchanged and
    surface the already-folded value.
    """
    uid = "user-focus-no-resume-stamp-complete"
    seed_profile(fake_db, uid, role="student")
    h = bearer(fake_auth.issue(uid))

    fid = _start_session(client, fake_auth, uid)
    from datetime import datetime, timedelta, timezone

    started = datetime.now(timezone.utc) - timedelta(hours=2)
    # Row says running, lastResumedAtIso missing, accumulatedSeconds already
    # holds 600 seconds from a prior pause/resume cycle. The previous fix
    # would have added the entire 7200-second start→now gap on top of 600
    # and produced 7800 — almost 2 hours of phantom focus time on a session
    # that the user only ran for ten minutes.
    fake_db._collections[f"users/{uid}/focus_sessions"][fid].update(
        {
            "status": "running",
            "lastResumedAtIso": None,
            "startedAtIso": started.isoformat(),
            "accumulatedSeconds": 600,
        }
    )

    body = client.patch(
        f"/api/study/focus/{fid}", json={"action": "complete"}, headers=h
    ).json()
    assert body["status"] == "completed"
    # Safe answer: keep the already-folded 600. Never 7800.
    assert body["accumulatedSeconds"] == 600, body


def test_cancel_with_missing_resume_stamp_does_not_double_count(
    client, fake_db, fake_auth
):
    """Mirror of the complete test for the cancel branch.

    Cancel must follow the same rule: a row with ``status=running`` but no
    ``lastResumedAtIso`` and a non-zero ``accumulatedSeconds`` must keep the
    already-folded value, not add the entire start→now span.
    """
    uid = "user-focus-no-resume-stamp-cancel"
    seed_profile(fake_db, uid, role="student")
    h = bearer(fake_auth.issue(uid))

    fid = _start_session(client, fake_auth, uid)
    from datetime import datetime, timedelta, timezone

    started = datetime.now(timezone.utc) - timedelta(hours=2)
    fake_db._collections[f"users/{uid}/focus_sessions"][fid].update(
        {
            "status": "running",
            "lastResumedAtIso": None,
            "startedAtIso": started.isoformat(),
            "accumulatedSeconds": 600,
        }
    )

    body = client.patch(
        f"/api/study/focus/{fid}", json={"action": "cancel"}, headers=h
    ).json()
    assert body["status"] == "cancelled"
    assert body["accumulatedSeconds"] == 600, body


def test_complete_with_missing_resume_stamp_and_zero_accumulated_returns_zero(
    client, fake_db, fake_auth
):
    """The degenerate case must also be deterministic.

    A row with ``status=running``, no resume stamp, AND
    ``accumulatedSeconds=0`` — e.g. a brand-new session that crashed before
    any heartbeat landed. The safe answer is still 0, never a fabricated
    7200-second "you focused for 2 hours" value derived from startedAtIso.
    """
    uid = "user-focus-degenerate-complete"
    seed_profile(fake_db, uid, role="student")
    h = bearer(fake_auth.issue(uid))

    fid = _start_session(client, fake_auth, uid)
    from datetime import datetime, timedelta, timezone

    started = datetime.now(timezone.utc) - timedelta(hours=2)
    fake_db._collections[f"users/{uid}/focus_sessions"][fid].update(
        {
            "status": "running",
            "lastResumedAtIso": None,
            "startedAtIso": started.isoformat(),
            "accumulatedSeconds": 0,
        }
    )

    body = client.patch(
        f"/api/study/focus/{fid}", json={"action": "complete"}, headers=h
    ).json()
    assert body["status"] == "completed"
    assert body["accumulatedSeconds"] == 0, body


# ---------------------------------------------------------------------------
# Study stats (daily/monthly minutes + streak + completed-task counts)
# ---------------------------------------------------------------------------


def test_study_stats_empty_user(client, fake_db, fake_auth):
    uid = "user-stats-empty"
    seed_profile(fake_db, uid, role="student")
    h = bearer(fake_auth.issue(uid))

    resp = client.get("/api/study/stats", headers=h)
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["streakDays"] == 0
    assert body["completedTaskCount"] == 0


def test_study_stats_completed_focus_increments_streak(client, fake_db, fake_auth):
    uid = "user-stats-1"
    seed_profile(fake_db, uid, role="student")
    h = bearer(fake_auth.issue(uid))

    # Start -> complete a focus session; this should land on today's day-key.
    resp = client.post("/api/study/focus/start", json={}, headers=h)
    fid = resp.json()["id"]
    client.patch(f"/api/study/focus/{fid}", json={"action": "complete"}, headers=h)

    # Add a completed task so we also exercise the task-count branch.
    fake_db.seed(
        "tasks",
        "task-stat-1",
        {"ownerId": uid, "completed": True, "completedAt": "2026-08-27T10:00:00Z"},
    )

    resp = client.get("/api/study/stats", headers=h)
    body = resp.json()
    assert body["streakDays"] >= 1
    assert body["completedTaskCount"] >= 1
    assert "todayMinutes" in body
    assert "monthMinutes" in body


def test_study_stats_counts_completed_tasks(client, fake_db, fake_auth):
    uid = "user-stats-2"
    seed_profile(fake_db, uid, role="student")
    h = bearer(fake_auth.issue(uid))

    # Three completed tasks today.
    for i in range(3):
        fake_db.seed(
            "tasks",
            f"task-{i}",
            {
                "ownerId": uid,
                "completed": True,
                "completedAt": "2026-01-15T10:00:00Z",
            },
        )
    # One incomplete task should NOT count.
    fake_db.seed(
        "tasks",
        "task-open",
        {"ownerId": uid, "completed": False},
    )
    # One completed task for a different user should NOT count.
    fake_db.seed(
        "tasks",
        "task-other",
        {"ownerId": "someone-else", "completed": True},
    )

    resp = client.get("/api/study/stats", headers=h)
    body = resp.json()
    # Note: streak math only walks today's completed day, so we cannot assert
    # on streak >= 1 with a hardcoded 2026 date. Just assert count math.
    assert body["completedTaskCount"] == 3


# ---------------------------------------------------------------------------
# Auth gate
# ---------------------------------------------------------------------------


def test_chat_toggle_requires_auth(client, fake_db):
    _seed_group(fake_db, owner="owner-x", admin=["owner-x"], members=["owner-x"], chat_enabled=False)
    resp = client.post("/api/groups/grp-chat/chat/toggle", json={"enabled": True})
    assert resp.status_code in (401, 403), resp.text


def test_offline_register_requires_auth(client, fake_db):
    resp = client.post(
        "/api/offline/register",
        json={"materialId": "x", "title": "x", "size": 1, "localPath": "x"},
    )
    assert resp.status_code in (401, 403), resp.text


def test_focus_start_requires_auth(client, fake_db):
    resp = client.post("/api/study/focus/start", json={})
    assert resp.status_code in (401, 403), resp.text


def test_budget_requires_auth(client, fake_db):
    resp = client.post(
        "/api/budget/monthly",
        json={"monthKey": "2026-01", "availableAmount": 1},
    )
    assert resp.status_code in (401, 403), resp.text
