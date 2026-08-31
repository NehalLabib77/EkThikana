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