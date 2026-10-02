"""Phase 5 — Ziku Focus Engine (``/api/focus/*``).

Contract under test:

* **One tracking system.** Every write the engine performs lands in the
  pre-existing ``users/{uid}/focus_sessions`` collection — no second store,
  no second goal store (``goalMinutes`` reads the Exam Rescue plan).
* **One state machine.** A session started on ``/api/focus/start`` can be
  paused / resumed on the legacy ``/api/study/focus/{id}`` route and
  completed on ``/api/focus/complete`` (and vice versa) with the same
  idempotency and no-double-count policies part3 pins.
* **Focus Score (5.3)** — rolling 7-day score from completion rate,
  consistency and session duration, with its three bands.
* **Smart behaviour (5.8)** — skip / adjust / streak / start copy.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

from app.services import focus_service
from tests.conftest import bearer, seed_profile  # noqa: F401  (fixtures)


def _auth(fake_auth, uid: str) -> dict[str, str]:
    return bearer(fake_auth.issue(uid))


def _day(offset: int = 0) -> str:
    return (datetime.now(timezone.utc) - timedelta(days=offset)).strftime("%Y-%m-%d")


def _seed_focus(
    db,
    uid: str,
    *,
    doc_id: str,
    day: str,
    status: str = "completed",
    minutes: int = 25,
    planned: int = 25,
    focus_score: int | None = None,
    interruptions: int = 0,
    subject: str = "",
    topic: str = "",
    last_resumed: str | None = None,
) -> None:
    db.seed(
        f"users/{uid}/focus_sessions",
        doc_id,
        {
            "id": doc_id,
            "ownerId": uid,
            "status": status,
            "label": "Seeded",
            "plannedMinutes": planned,
            "accumulatedSeconds": minutes * 60,
            "startedAtIso": f"{day}T06:00:00+00:00",
            "completedAtIso": f"{day}T06:30:00+00:00" if status != "running" else None,
            "lastResumedAtIso": last_resumed,
            "dayKey": day,
            "subject": subject,
            "topic": topic,
            "interruptions": interruptions,
            "focusScore": focus_score,
        },
    )


# ---------------------------------------------------------------------------
# 5.1 / 5.2 — endpoints over the single session store
# ---------------------------------------------------------------------------
def test_start_creates_a_running_session_in_the_existing_collection(
    client, fake_db, fake_auth
):
    uid = "focus-engine-start"
    seed_profile(fake_db, uid, role="student")
    fake_db.events.clear()

    resp = client.post(
        "/api/focus/start",
        json={
            "label": "Thermodynamics",
            "plannedMinutes": 50,
            "subject": "Physics",
            "topic": "Thermodynamics",
        },
        headers=_auth(fake_auth, uid),
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["status"] == "running"
    assert body["id"].startswith("focus_")
    assert body["plannedMinutes"] == 50
    assert body["subject"] == "Physics"

    stored = fake_db._collections[f"users/{uid}/focus_sessions"][body["id"]]
    assert stored["status"] == "running"
    assert stored["ownerId"] == uid
    # The engine writes the one focus store and nothing else.
    written = {collection for _op, collection, _doc in fake_db.events}
    assert written == {f"users/{uid}/focus_sessions"}


def test_engine_start_can_be_paused_and_completed_on_the_legacy_route(
    client, fake_db, fake_auth
):
    uid = "focus-engine-shared"
    seed_profile(fake_db, uid, role="student")
    h = _auth(fake_auth, uid)

    started = client.post("/api/focus/start", json={"plannedMinutes": 25}, headers=h)
    focus_id = started.json()["id"]

    paused = client.patch(
        f"/api/study/focus/{focus_id}", json={"action": "pause"}, headers=h
    )
    assert paused.status_code == 200, paused.text
    assert paused.json()["status"] == "paused"

    resumed = client.patch(
        f"/api/study/focus/{focus_id}", json={"action": "resume"}, headers=h
    )
    assert resumed.json()["status"] == "running"

    done = client.post(
        "/api/focus/complete",
        json={"focusId": focus_id, "subject": "Physics"},
        headers=h,
    )
    assert done.status_code == 200, done.text
    body = done.json()
    assert body["status"] == "completed"
    assert isinstance(body["focusScore"], int)


def test_legacy_start_completes_through_the_engine_store(
    client, fake_db, fake_auth
):
    uid = "focus-engine-reverse"
    seed_profile(fake_db, uid, role="student")
    h = _auth(fake_auth, uid)

    started = client.post(
        "/api/study/focus/start",
        json={"label": "Old route", "planned_minutes": 25},
        headers=h,
    )
    focus_id = started.json()["id"]

    done = client.post("/api/focus/complete", json={"focusId": focus_id}, headers=h)
    assert done.status_code == 200, done.text
    assert done.json()["status"] == "completed"
    assert fake_db._collections[f"users/{uid}/focus_sessions"][focus_id][
        "status"
    ] == "completed"


def test_complete_is_idempotent_and_pays_out_the_today_snapshot(
    client, fake_db, fake_auth
):
    uid = "focus-engine-idempotent"
    seed_profile(fake_db, uid, role="student")
    h = _auth(fake_auth, uid)

    focus_id = client.post("/api/focus/start", json={}, headers=h).json()["id"]
    first = client.post("/api/focus/complete", json={"focusId": focus_id}, headers=h)
    assert first.status_code == 200, first.text
    first_body = first.json()
    assert "today" in first_body
    assert first_body["today"]["dayKey"]
    assert first_body["today"]["goalMinutes"] >= 1
    assert first_body["today"]["score"] is not None
    assert first_body["today"]["nudge"]["kind"]

    second = client.post("/api/focus/complete", json={"focusId": focus_id}, headers=h)
    assert second.status_code == 200, second.text
    assert second.json()["idempotent"] is True
    assert second.json()["completedAtIso"] == first_body["completedAtIso"]
    # No double count: the finished total did not grow on the re-complete.
    assert second.json()["today"]["seconds"] == first_body["today"]["seconds"]


def test_complete_folds_the_live_running_interval(client, fake_db, fake_auth):
    uid = "focus-engine-elapsed"
    seed_profile(fake_db, uid, role="student")
    h = _auth(fake_auth, uid)

    started_at = (datetime.now(timezone.utc) - timedelta(seconds=300)).isoformat()
    _seed_focus(
        fake_db,
        uid,
        doc_id="focus_live",
        day=_day(0),
        status="running",
        minutes=0,
        last_resumed=started_at,
    )

    done = client.post("/api/focus/complete", json={"focusId": "focus_live"}, headers=h)
    assert done.status_code == 200, done.text
    elapsed = done.json()["accumulatedSeconds"]
    assert 295 <= elapsed <= 305


def test_complete_unknown_session_is_404(client, fake_db, fake_auth):
    uid = "focus-engine-404"
    seed_profile(fake_db, uid, role="student")
    resp = client.post(
        "/api/focus/complete",
        json={"focusId": "focus_does_not_exist"},
        headers=_auth(fake_auth, uid),
    )
    assert resp.status_code == 404, resp.text


def test_focus_engine_routes_are_student_only(client, fake_db, fake_auth):
    uid = "focus-engine-general"
    seed_profile(fake_db, uid, role="general")
    h = _auth(fake_auth, uid)
    for method, path in (
        ("POST", "/api/focus/start"),
        ("POST", "/api/focus/complete"),
        ("GET", "/api/focus/today"),
        ("GET", "/api/focus/history"),
    ):
        resp = client.request(method, path, json={"focusId": "x"}, headers=h)
        assert resp.status_code == 403, f"{method} {path} -> {resp.status_code}"


# ---------------------------------------------------------------------------
# GET /api/focus/today
# ---------------------------------------------------------------------------
def test_today_reports_minutes_goal_active_session_and_score(
    client, fake_db, fake_auth
):
    uid = "focus-engine-today"
    seed_profile(fake_db, uid, role="student")
    _seed_focus(fake_db, uid, doc_id="focus_t1", day=_day(0), minutes=45, focus_score=92)
    _seed_focus(
        fake_db,
        uid,
        doc_id="focus_t2",
        day=_day(0),
        status="running",
        minutes=0,
        last_resumed=(datetime.now(timezone.utc) - timedelta(seconds=600)).isoformat(),
    )

    resp = client.get("/api/focus/today", headers=_auth(fake_auth, uid))
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["minutes"] == 45
    assert body["goalMinutes"] == focus_service.DEFAULT_GOAL_MINUTES
    assert body["activeSessions"] == 1
    assert body["activeMinutes"] >= 9
    assert body["activeSessionIds"] == ["focus_t2"]
    assert body["score"]["value"] >= 60
    assert body["score"]["band"] in (
        "excellent",
        "developing",
        "needs_structure",
    )
    assert body["weekly"]["windowDays"] == 7
    assert len(body["weekly"]["days"]) == 7
    assert body["weekly"]["activeDays"] == 1
    assert body["streakDays"] >= 1


def test_goal_minutes_follows_the_active_exam_rescue_plan(
    client, fake_db, fake_auth
):
    uid = "focus-engine-goal"
    seed_profile(fake_db, uid, role="student")
    fake_db.seed(
        f"users/{uid}/exam_rescue",
        "sess_1",
        {
            "sessionId": "sess_1",
            "status": "active",
            "examDate": _day(-10),
            "dailyTargetMinutes": 90,
        },
    )

    resp = client.get("/api/focus/today", headers=_auth(fake_auth, uid))
    assert resp.status_code == 200, resp.text
    assert resp.json()["goalMinutes"] == 90


def test_today_keeps_corrupt_durations_at_zero(client, fake_db, fake_auth):
    uid = "focus-engine-corrupt"
    seed_profile(fake_db, uid, role="student")
    _seed_focus(fake_db, uid, doc_id="focus_bad", day=_day(0), minutes=0)
    # Legacy pollution: minutes masquerading as seconds. Must read as 0.
    fake_db.seed(
        f"users/{uid}/focus_sessions",
        "focus_bad",
        {
            "status": "completed",
            "dayKey": _day(0),
            "accumulatedSeconds": 354_920,
        },
    )

    resp = client.get("/api/focus/today", headers=_auth(fake_auth, uid))
    assert resp.status_code == 200, resp.text
    assert resp.json()["minutes"] == 0


def test_today_skip_nudge_when_the_goal_is_already_met(
    client, fake_db, fake_auth
):
    uid = "focus-engine-skip"
    seed_profile(fake_db, uid, role="student")
    _seed_focus(fake_db, uid, doc_id="focus_done", day=_day(0), minutes=75)

    body = client.get("/api/focus/today", headers=_auth(fake_auth, uid)).json()
    assert body["nudge"]["kind"] == "skip"
    assert "75/60" in body["nudge"]["message"]


# ---------------------------------------------------------------------------
# GET /api/focus/history
# ---------------------------------------------------------------------------
def test_history_buckets_days_and_weekly_consistency(client, fake_db, fake_auth):
    uid = "focus-engine-history"
    seed_profile(fake_db, uid, role="student")
    _seed_focus(fake_db, uid, doc_id="focus_h1", day=_day(0), minutes=30, focus_score=88)
    _seed_focus(fake_db, uid, doc_id="focus_h2", day=_day(1), minutes=20)
    _seed_focus(fake_db, uid, doc_id="focus_h3", day=_day(3), minutes=25)
    # Out of window — must not appear in the 7-day buckets.
    _seed_focus(fake_db, uid, doc_id="focus_h4", day=_day(30), minutes=60)

    resp = client.get("/api/focus/history?days=7", headers=_auth(fake_auth, uid))
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["count"] == 3
    assert len(body["days"]) == 3
    by_day = {item["day"]: item for item in body["days"]}
    assert by_day[_day(0)]["minutes"] == 30
    assert by_day[_day(1)]["minutes"] == 20
    assert by_day[_day(3)]["minutes"] == 25
    assert body["weekly"]["activeDays"] == 3
    assert body["weekly"]["streakDays"] == 2  # today + yesterday
    assert body["score"] is not None
    assert body["goalMinutes"] >= 1


def test_history_rejects_an_out_of_range_window(client, fake_db, fake_auth):
    uid = "focus-engine-window"
    seed_profile(fake_db, uid, role="student")
    h = _auth(fake_auth, uid)
    assert client.get("/api/focus/history?days=0", headers=h).status_code in (400, 422)
    assert client.get("/api/focus/history?days=4000", headers=h).status_code in (400, 422)


# ---------------------------------------------------------------------------
# 5.3 — Focus Score bands (pure function)
# ---------------------------------------------------------------------------
def _row(day: str, status: str = "completed", minutes: int = 25) -> dict:
    return {
        "status": status,
        "dayKey": day,
        "accumulatedSeconds": minutes * 60,
        "plannedMinutes": 25,
    }


def test_focus_score_perfect_week_is_excellent():
    rows = [_row(_day(i), minutes=30) for i in range(7)]
    score = focus_service.compute_focus_score(
        rows, datetime.now(timezone.utc)
    )
    assert score is not None
    assert score["value"] == 100
    assert score["band"] == "excellent"
    assert score["label"] == "Deep focus streak"


def test_focus_score_single_good_day_lands_in_the_developing_band():
    score = focus_service.compute_focus_score(
        [_row(_day(0), minutes=25)], datetime.now(timezone.utc)
    )
    assert score is not None
    # 40 (completion) + 5 (1/7 consistency) + 25 (duration) = 70
    assert score["value"] == 70
    assert score["band"] == "developing"


def test_focus_score_early_quitters_need_structure():
    score = focus_service.compute_focus_score(
        [_row(_day(0), status="cancelled", minutes=5)], datetime.now(timezone.utc)
    )
    assert score is not None
    assert score["band"] == "needs_structure"
    assert score["value"] < 60


def test_focus_score_is_none_without_finished_sessions():
    assert (
        focus_service.compute_focus_score([], datetime.now(timezone.utc)) is None
    )
    assert (
        focus_service.compute_focus_score(
            [_row(_day(0), status="running")], datetime.now(timezone.utc)
        )
        is None
    )


def test_focus_score_ignores_corrupt_durations_and_days_outside_the_window():
    rows = [
        _row(_day(0), minutes=0),
        {
            "status": "completed",
            "dayKey": _day(0),
            "accumulatedSeconds": 354_920,  # corrupt -> 0
            "plannedMinutes": 25,
        },
        _row(_day(40)),
    ]
    score = focus_service.compute_focus_score(rows, datetime.now(timezone.utc))
    assert score is not None
    assert score["parts"]["duration"] == 0.0
    assert score["sessions"] == 2


# ---------------------------------------------------------------------------
# 5.8 — smart behaviour copy
# ---------------------------------------------------------------------------
def test_nudge_skips_when_the_daily_goal_is_met():
    nudge = focus_service.smart_nudge(
        today_minutes=60, goal=60, active_minutes=0, streak_days=1
    )
    assert nudge["kind"] == "skip"
    assert "60/60" in nudge["message"]


def test_nudge_adjusts_a_long_running_session():
    nudge = focus_service.smart_nudge(
        today_minutes=10, goal=60, active_minutes=50, streak_days=1
    )
    assert nudge["kind"] == "adjust"
    assert "stand up" in nudge["message"]


def test_nudge_protects_a_streak():
    nudge = focus_service.smart_nudge(
        today_minutes=0, goal=60, active_minutes=0, streak_days=4
    )
    assert nudge["kind"] == "streak"
    assert "4-day" in nudge["message"]


def test_nudge_invites_a_fresh_start():
    nudge = focus_service.smart_nudge(
        today_minutes=0, goal=60, active_minutes=0, streak_days=0
    )
    assert nudge["kind"] == "start"
    assert "60 minute block" in nudge["message"]


# ---------------------------------------------------------------------------
# 5.1 — the engine never forks the store
# ---------------------------------------------------------------------------
def test_engine_and_legacy_routes_write_only_focus_sessions(
    client, fake_db, fake_auth
):
    uid = "focus-engine-single-store"
    seed_profile(fake_db, uid, role="student")
    h = _auth(fake_auth, uid)
    fake_db.events.clear()

    focus_id = client.post("/api/focus/start", json={}, headers=h).json()["id"]
    client.patch(f"/api/study/focus/{focus_id}", json={"action": "pause"}, headers=h)
    client.patch(f"/api/study/focus/{focus_id}", json={"action": "resume"}, headers=h)
    client.post("/api/focus/complete", json={"focusId": focus_id}, headers=h)

    written = {collection for _op, collection, _doc in fake_db.events if collection != "analytics_events"}
    assert written == {f"users/{uid}/focus_sessions"}


# ---------------------------------------------------------------------------
# 5.6 / 5.7 - coach + Academic Health read the same tracking system
# ---------------------------------------------------------------------------
def test_academic_health_reports_the_focus_consistency_metric(
    client, fake_db, fake_auth
):
    uid = "focus-engine-health"
    seed_profile(fake_db, uid, role="student")
    for i, minutes in enumerate((30, 45, 60)):
        _seed_focus(
            fake_db,
            uid,
            doc_id=f"focus_m{i}",
            day=_day(i),
            minutes=minutes,
            focus_score=88,
        )

    body = client.get("/api/ai/academic-health", headers=_auth(fake_auth, uid)).json()
    metric = next(
        (m for m in body["metrics"] if m["key"] == "focusConsistency"), None
    )
    assert metric is not None, "Phase 5 must add a fifth metric"
    assert metric["available"] is True
    assert metric["label"] == "Focus consistency"
    assert 0 < metric["score"] <= 100
    assert "study days this week" in metric["detail"]
    assert "focusConsistency" in body["coverage"]
    # The five declared weights still add up to one.
    assert abs(sum(m["weight"] for m in body["metrics"]) - 1.0) < 1e-6
    # It is a real signal, not a duplicate of today's minutes.
    assert body["signals"]["study"]["focusConsistencyPct"] == round(100 * 3 / 7, 1)


def test_academic_health_marks_focus_consistency_missing_without_sessions(
    client, fake_db, fake_auth
):
    uid = "focus-engine-health-empty"
    seed_profile(fake_db, uid, role="student")

    body = client.get("/api/ai/academic-health", headers=_auth(fake_auth, uid)).json()
    metric = next(m for m in body["metrics"] if m["key"] == "focusConsistency")
    assert metric["available"] is False
    assert "focusConsistency" in body["missing"]


def test_coach_profile_carries_focus_engine_signals(client, fake_db, fake_auth):
    uid = "focus-engine-coach"
    seed_profile(fake_db, uid, role="student")
    _seed_focus(fake_db, uid, doc_id="focus_c1", day=_day(0), minutes=45)
    _seed_focus(fake_db, uid, doc_id="focus_c2", day=_day(1), minutes=30)

    body = client.get("/api/coach/profile", headers=_auth(fake_auth, uid)).json()
    pattern = body["studyPattern"]
    assert pattern["focusConsistency"] == round(100 * 2 / 7, 1)
    assert 37 <= pattern["averageSessionMinutes"] <= 38
    assert len(pattern["focusTrend7"]) == 2
    assert pattern["focusTrend7"][_day(0)] == 45
    assert pattern["focusTrend7"][_day(1)] == 30


def test_coach_chat_context_mentions_focus_consistency(client, fake_db, fake_auth):
    from app.services.study_coach_service import chat_context

    uid = "focus-engine-coach-chat"
    seed_profile(fake_db, uid, role="student")
    _seed_focus(fake_db, uid, doc_id="focus_ch", day=_day(0), minutes=50)

    line = chat_context(uid)
    assert line is not None
    assert "focus consistency" in line
    assert "% of the last 7 days" in line


def test_weekly_report_carries_focus_engine_signals(client, fake_db, fake_auth):
    uid = "focus-engine-coach-weekly"
    seed_profile(fake_db, uid, role="student")
    _seed_focus(fake_db, uid, doc_id="focus_w1", day=_day(0), minutes=60)
    _seed_focus(fake_db, uid, doc_id="focus_w2", day=_day(2), minutes=25)

    body = client.get("/api/coach/weekly-report", headers=_auth(fake_auth, uid)).json()
    assert body["focusConsistency"] == round(100 * 2 / 7, 1)
    assert body["averageSessionMinutes"] in (42, 43)
    assert body["focusTrend7"][_day(0)] == 60
    assert body["focusTrend7"][_day(2)] == 25
    assert body["narrative"]
