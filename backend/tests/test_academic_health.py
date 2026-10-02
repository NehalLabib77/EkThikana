"""Phase 2 — Academic Health Score + smart focus session tests.

Covers:

* ``GET /api/ai/academic-health`` (+ history + recommendations) — student
  gate, modular metrics, weight renormalisation, trend, weak areas,
  rule-based advice, daily snapshot persistence.
* The Phase 2 focus extensions in ``routers/part3.py`` — subject/topic on
  start, the interruption counter, the focus score computed at complete,
  and ``GET /api/study/focus/today``.

Every test runs against the real FastAPI app through the shared ``client``
fixture (FakeFirestore + FakeAuth).
"""

from __future__ import annotations

import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest


_BACKEND_ROOT = Path(__file__).resolve().parent.parent
if str(_BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(_BACKEND_ROOT))

from tests.conftest import bearer, seed_profile  # noqa: E402


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _day(days: int = 0) -> datetime:
    return _now() + timedelta(days=days)


def _auth(fake_auth, uid: str) -> dict[str, str]:
    return bearer(fake_auth.issue(uid))


def _metric(body: dict, key: str) -> dict:
    for metric in body["metrics"]:
        if metric["key"] == key:
            return metric
    raise AssertionError(f"metric {key} missing from {body['metrics']}")


def _seed_quiz(
    db,
    uid: str,
    doc_id: str,
    score: int,
    topics: dict[str, int],
    *,
    days_ago: int = 0,
) -> None:
    stamp = _day(-days_ago)
    db.seed(
        f"users/{uid}/quiz_results",
        doc_id,
        {
            "ownerId": uid,
            "score": score,
            "topicScores": topics,
            "subjectId": "Physics",
            "createdAt": stamp,
            "dayKey": stamp.strftime("%Y-%m-%d"),
        },
    )


def _seed_focus(
    db,
    uid: str,
    doc_id: str,
    *,
    days_ago: int = 0,
    minutes: int = 30,
    status: str = "completed",
    planned: int = 30,
    subject: str = "Physics",
    interruptions: int = 0,
    focus_score: int | None = None,
) -> None:
    day = _day(-days_ago)
    data = {
        "id": doc_id,
        "ownerId": uid,
        "status": status,
        "label": "Deep work",
        "subject": subject,
        "topic": "",
        "plannedMinutes": planned,
        "accumulatedSeconds": minutes * 60,
        "dayKey": day.strftime("%Y-%m-%d"),
        "startedAtIso": day.isoformat(),
        "interruptions": interruptions,
    }
    if focus_score is not None:
        data["focusScore"] = focus_score
    db.seed(f"users/{uid}/focus_sessions", doc_id, data)


def _seed_mistake(
    db,
    uid: str,
    doc_id: str,
    topic: str,
    *,
    occurrences: int = 1,
    due: bool = False,
    analyzed: bool = True,
) -> None:
    db.seed(
        f"users/{uid}/mistakes",
        doc_id,
        {
            "ownerId": uid,
            "topic": topic,
            "subjectId": "Physics",
            "question": "What is entropy?",
            "correctAnswer": "Disorder of particles",
            "userAnswer": "Energy of particles",
            "occurrences": occurrences,
            "nextReviewDate": (_day(-1) if due else _day(30)).strftime("%Y-%m-%d"),
            "analysisStatus": "analyzed" if analyzed else "pending",
            "createdAt": _day(-2),
        },
    )


def _seed_task(
    db,
    uid: str,
    task_id: str,
    *,
    done: bool = False,
    due_in_days: int | None = None,
    source: str | None = None,
    session_id: str | None = None,
) -> None:
    data: dict = {"ownerId": uid, "title": f"Task {task_id}", "done": done}
    if due_in_days is not None:
        data["dueAt"] = _day(due_in_days)
    if source:
        data["source"] = source
    if session_id:
        data["rescueSessionId"] = session_id
    db.seed("tasks", task_id, data)


def _seed_exam(
    db, uid: str, session_id: str, *, in_days: int = 3, title: str = "Physics Final"
) -> None:
    db.seed(
        f"users/{uid}/exam_rescue",
        session_id,
        {
            "sessionId": session_id,
            "ownerId": uid,
            "examTitle": title,
            "examDate": _day(in_days),
            "status": "active",
            "dailyTargetMinutes": 120,
        },
    )


# ---------------------------------------------------------------------------
# routing / auth
# ---------------------------------------------------------------------------


def test_academic_health_requires_auth(client):
    resp = client.get("/api/ai/academic-health")
    assert resp.status_code == 401, resp.text


def test_academic_health_rejects_general_role(client, fake_db, fake_auth):
    uid = "health-general"
    seed_profile(fake_db, uid, role="general")
    resp = client.get("/api/ai/academic-health", headers=_auth(fake_auth, uid))
    assert resp.status_code == 403, resp.text


def test_history_and_recommendations_are_student_only(
    client, fake_db, fake_auth
):
    uid = "health-general-2"
    seed_profile(fake_db, uid, role="general")
    h = _auth(fake_auth, uid)
    assert client.get("/api/ai/academic-health/history", headers=h).status_code == 403
    assert (
        client.get("/api/ai/academic-health/recommendations", headers=h).status_code
        == 403
    )


# ---------------------------------------------------------------------------
# the score
# ---------------------------------------------------------------------------


def test_empty_student_reads_as_no_data_not_as_failing(client, fake_db, fake_auth):
    uid = "health-empty"
    seed_profile(fake_db, uid)

    resp = client.get("/api/ai/academic-health", headers=_auth(fake_auth, uid))
    assert resp.status_code == 200, resp.text
    body = resp.json()

    assert body["hasData"] is False
    assert body["score"] == 0
    assert body["grade"] == "no_data"
    assert body["headline"]
    assert len(body["metrics"]) == 5
    assert all(m["available"] is False for m in body["metrics"])
    assert body["coverage"] == []
    assert set(body["missing"]) == {
        "consistency",
        "understanding",
        "revision",
        "examReadiness",
        "focusConsistency",
    }
    assert body["trend"]["direction"] == "new"
    assert body["weakAreas"] == []
    assert body["recommendations"], "an empty account still gets one next step"
    assert all(r["source"] == "health" for r in body["recommendations"])


def test_quiz_only_student_renormalises_onto_understanding(
    client, fake_db, fake_auth
):
    uid = "health-quiz-only"
    seed_profile(fake_db, uid)
    _seed_quiz(db := fake_db, uid, "q1", 90, {"Thermodynamics": 90})
    _seed_quiz(db, uid, "q2", 90, {"Thermodynamics": 90}, days_ago=1)
    _seed_quiz(db, uid, "q3", 90, {"Thermodynamics": 90}, days_ago=2)

    body = client.get(
        "/api/ai/academic-health", headers=_auth(fake_auth, uid)
    ).json()

    assert body["coverage"] == ["understanding"]
    assert set(body["missing"]) == {
        "consistency",
        "revision",
        "examReadiness",
        "focusConsistency",
    }
    understanding = _metric(body, "understanding")
    assert understanding["available"] is True
    # 0.7 * 90 (recent average) + 0.3 * 100 (all topics strong) = 93
    assert understanding["score"] == 93.0
    # With only one metric available its weight is the whole weight, so the
    # overall score is exactly that metric.
    assert body["score"] == 93
    assert body["grade"] == "excellent"
    assert body["hasData"] is True


def test_full_profile_scores_high_and_explains_every_metric(
    client, fake_db, fake_auth
):
    uid = "health-full"
    seed_profile(fake_db, uid)
    _seed_quiz(fake_db, uid, "q1", 88, {"Thermodynamics": 88, "Optics": 82})
    _seed_quiz(fake_db, uid, "q2", 92, {"Thermodynamics": 92, "Optics": 86}, days_ago=1)
    for days_ago in (0, 1, 2):
        _seed_focus(
            fake_db,
            uid,
            f"f{days_ago}",
            days_ago=days_ago,
            minutes=60 if days_ago == 0 else 45,
            focus_score=92,
        )
    _seed_mistake(fake_db, uid, "m1", "Thermodynamics", analyzed=True)
    _seed_task(fake_db, uid, "t1", done=True, due_in_days=2)

    body = client.get(
        "/api/ai/academic-health", headers=_auth(fake_auth, uid)
    ).json()

    assert body["coverage"] == [
        "consistency",
        "understanding",
        "revision",
        "examReadiness",
        "focusConsistency",
    ]
    assert body["missing"] == []
    assert 0 <= body["score"] <= 100
    assert body["grade"] in ("excellent", "good")
    for key in (
        "consistency",
        "understanding",
        "revision",
        "examReadiness",
        "focusConsistency",
    ):
        metric = _metric(body, key)
        assert metric["available"] is True, key
        assert metric["detail"], key

    assert body["signals"]["study"]["studyDays"] == 3
    assert body["signals"]["study"]["todayMinutes"] == 60
    assert body["signals"]["study"]["averageFocusScore"] == 92
    # Phase 5 - the focus metric's raw signals travel with the payload.
    assert body["signals"]["study"]["averageSessionMinutes"] == 50
    assert body["signals"]["study"]["focusConsistencyPct"] == round(100 * 3 / 7, 1)
    assert body["signals"]["study"]["weekSessions"] == 3
    assert len(body["signals"]["study"]["dailyMinutes"]) == 3
    assert body["signals"]["mistakes"]["total"] == 1
    assert body["signals"]["quizzes"]["total"] == 2
    assert body["signals"]["tasks"]["completed"] == 1


def test_due_mistakes_pull_the_revision_metric_down(client, fake_db, fake_auth):
    healthy = "health-revision-good"
    behind = "health-revision-behind"
    seed_profile(fake_db, healthy)
    seed_profile(fake_db, behind)

    for uid in (healthy, behind):
        _seed_quiz(fake_db, uid, "q1", 80, {"Optics": 80})
        _seed_focus(fake_db, uid, "f0", minutes=30)

    for i in range(4):
        _seed_mistake(
            fake_db,
            healthy,
            f"m{i}",
            "Optics",
            due=False,
            analyzed=True,
        )
        _seed_mistake(
            fake_db,
            behind,
            f"m{i}",
            "Optics",
            due=True,
            analyzed=False,
        )

    good = client.get(
        "/api/ai/academic-health", headers=_auth(fake_auth, healthy)
    ).json()
    bad = client.get(
        "/api/ai/academic-health", headers=_auth(fake_auth, behind)
    ).json()

    good_revision = _metric(good, "revision")["score"]
    bad_revision = _metric(bad, "revision")["score"]
    assert good_revision is not None and bad_revision is not None
    assert bad_revision < good_revision
    assert good["score"] > bad["score"]


def test_repeat_mistakes_show_up_as_a_high_priority_weak_area(
    client, fake_db, fake_auth
):
    uid = "health-weak"
    seed_profile(fake_db, uid)
    _seed_quiz(fake_db, uid, "q1", 41, {"Carnot Cycle": 41})
    _seed_mistake(fake_db, uid, "m1", "Carnot Cycle", occurrences=3, due=True)

    body = client.get(
        "/api/ai/academic-health", headers=_auth(fake_auth, uid)
    ).json()

    areas = body["weakAreas"]
    assert areas, "the weak topic must be surfaced"
    top = areas[0]
    assert top["topic"] == "Carnot Cycle"
    assert top["quizAverage"] == 41
    assert top["mistakes"] == 1
    # ``repeated`` counts repeated mistake *records* (occurrences >= 2);
    # ``occurrences`` is how many times the miss actually happened.
    assert top["repeated"] == 1
    assert top["occurrences"] == 3
    assert top["due"] == 1
    assert top["priority"] == "high"
    assert top["action"]


def test_active_exam_rescue_plan_feeds_exam_readiness(client, fake_db, fake_auth):
    uid = "health-exam"
    seed_profile(fake_db, uid)
    _seed_exam(fake_db, uid, "plan-1", in_days=3)
    for i in range(6):
        _seed_task(
            fake_db,
            uid,
            f"rt{i}",
            done=i < 4,
            due_in_days=i,
            source="exam_rescue",
            session_id="plan-1",
        )
    _seed_focus(fake_db, uid, "f0", minutes=45)

    body = client.get(
        "/api/ai/academic-health", headers=_auth(fake_auth, uid)
    ).json()

    exam = body["signals"]["exam"]
    assert exam["exists"] is True
    assert exam["title"] == "Physics Final"
    assert exam["daysRemaining"] == 3
    assert body["signals"]["tasks"]["rescueTotal"] == 6
    assert body["signals"]["tasks"]["rescueDone"] == 4

    readiness = _metric(body, "examReadiness")
    assert readiness["available"] is True
    assert "Physics Final" in readiness["detail"]

    titles = [r["title"] for r in body["recommendations"]]
    assert any("Physics Final" in t for t in titles), titles


def test_overdue_tasks_are_penalised_and_advised(client, fake_db, fake_auth):
    uid = "health-overdue"
    seed_profile(fake_db, uid)
    _seed_quiz(fake_db, uid, "q1", 80, {"Optics": 80})
    _seed_focus(fake_db, uid, "f0", minutes=30)
    _seed_task(fake_db, uid, "late-1", due_in_days=-2)
    _seed_task(fake_db, uid, "late-2", due_in_days=-1)

    body = client.get(
        "/api/ai/academic-health", headers=_auth(fake_auth, uid)
    ).json()

    assert body["signals"]["tasks"]["overdue"] == 2
    assert _metric(body, "examReadiness")["available"] is True
    assert any(
        r["title"].startswith("Clear 2 overdue") for r in body["recommendations"]
    ), body["recommendations"]


# ---------------------------------------------------------------------------
# trend + history
# ---------------------------------------------------------------------------


def test_trend_reads_yesterdays_snapshot(client, fake_db, fake_auth):
    uid = "health-trend"
    seed_profile(fake_db, uid)
    yesterday = (_day(-1)).strftime("%Y-%m-%d")
    fake_db.seed(
        f"users/{uid}/health_history",
        yesterday,
        {"dayKey": yesterday, "score": 50, "grade": "fair", "metrics": {}},
    )

    body = client.get(
        "/api/ai/academic-health", headers=_auth(fake_auth, uid)
    ).json()

    assert body["trend"]["previousScore"] == 50
    assert body["trend"]["direction"] == "down"
    assert body["trend"]["delta"] == body["score"] - 50


def test_identical_previous_score_is_reported_as_stable(
    client, fake_db, fake_auth
):
    uid = "health-trend-stable"
    seed_profile(fake_db, uid)
    yesterday = (_day(-1)).strftime("%Y-%m-%d")
    fake_db.seed(
        f"users/{uid}/health_history",
        yesterday,
        {"dayKey": yesterday, "score": 0, "grade": "no_data", "metrics": {}},
    )

    body = client.get(
        "/api/ai/academic-health", headers=_auth(fake_auth, uid)
    ).json()
    assert body["score"] == 0
    assert body["trend"]["direction"] == "stable"
    assert body["trend"]["delta"] == 0


def test_snapshot_is_written_for_today(client, fake_db, fake_auth):
    uid = "health-snapshot"
    seed_profile(fake_db, uid)
    _seed_quiz(fake_db, uid, "q1", 75, {"Optics": 75})

    client.get("/api/ai/academic-health", headers=_auth(fake_auth, uid))

    today = _day().strftime("%Y-%m-%d")
    stored = fake_db._collections[f"users/{uid}/health_history"][today]
    assert stored["score"] >= 0
    assert stored["grade"]
    assert "understanding" in stored["metrics"]


def test_history_endpoint_is_ordered_and_windowed(client, fake_db, fake_auth):
    uid = "health-history"
    seed_profile(fake_db, uid)
    for days_ago in (1, 3):
        key = _day(-days_ago).strftime("%Y-%m-%d")
        fake_db.seed(
            f"users/{uid}/health_history",
            key,
            {"dayKey": key, "score": 40 + days_ago, "grade": "fair", "metrics": {}},
        )

    body = client.get(
        "/api/ai/academic-health/history?days=30", headers=_auth(fake_auth, uid)
    ).json()
    assert body["count"] == 2
    assert [e["dayKey"] for e in body["history"]] == sorted(
        e["dayKey"] for e in body["history"]
    )

    windowed = client.get(
        "/api/ai/academic-health/history?days=2", headers=_auth(fake_auth, uid)
    ).json()
    assert windowed["count"] == 1


def test_history_endpoint_is_empty_for_a_new_student(client, fake_db, fake_auth):
    uid = "health-history-empty"
    seed_profile(fake_db, uid)
    body = client.get(
        "/api/ai/academic-health/history", headers=_auth(fake_auth, uid)
    ).json()
    assert body["history"] == []
    assert body["count"] == 0


def test_history_days_out_of_range_is_rejected(client, fake_db, fake_auth):
    uid = "health-history-range"
    seed_profile(fake_db, uid)
    resp = client.get(
        "/api/ai/academic-health/history?days=0",
        headers=_auth(fake_auth, uid),
    )
    assert resp.status_code == 422, resp.text


# ---------------------------------------------------------------------------
# exam_date parameter
# ---------------------------------------------------------------------------


def test_exam_date_parameter_is_accepted_in_both_spellings(
    client, fake_db, fake_auth
):
    uid = "health-exam-param"
    seed_profile(fake_db, uid)
    target = (_day(4)).strftime("%Y-%m-%d")

    camel = client.get(
        f"/api/ai/academic-health?examDate={target}",
        headers=_auth(fake_auth, uid),
    ).json()
    snake = client.get(
        f"/api/ai/academic-health?exam_date={target}",
        headers=_auth(fake_auth, uid),
    ).json()

    assert camel["signals"]["exam"]["examDate"] == target
    assert snake["signals"]["exam"]["examDate"] == target
    assert camel["signals"]["exam"]["daysRemaining"] == 4


def test_exam_date_parameter_rejects_garbage(client, fake_db, fake_auth):
    uid = "health-exam-param-bad"
    seed_profile(fake_db, uid)
    resp = client.get(
        "/api/ai/academic-health?examDate=soon",
        headers=_auth(fake_auth, uid),
    )
    assert resp.status_code == 400, resp.text


def test_students_do_not_see_each_others_signals(client, fake_db, fake_auth):
    a, b = "health-iso-a", "health-iso-b"
    seed_profile(fake_db, a)
    seed_profile(fake_db, b)
    _seed_quiz(fake_db, a, "qa", 95, {"Optics": 95})

    body_a = client.get("/api/ai/academic-health", headers=_auth(fake_auth, a)).json()
    body_b = client.get("/api/ai/academic-health", headers=_auth(fake_auth, b)).json()

    assert body_a["signals"]["quizzes"]["total"] == 1
    assert body_b["signals"]["quizzes"]["total"] == 0
    assert body_b["coverage"] == []


# ---------------------------------------------------------------------------
# recommendations
# ---------------------------------------------------------------------------


def test_recommendations_endpoint_merges_health_and_recommender(
    client, fake_db, fake_auth
):
    uid = "health-recs"
    seed_profile(fake_db, uid)
    _seed_quiz(fake_db, uid, "q1", 45, {"Optics": 45})
    _seed_focus(fake_db, uid, "f0", minutes=10)

    body = client.get(
        "/api/ai/academic-health/recommendations", headers=_auth(fake_auth, uid)
    ).json()

    assert body["count"] == len(body["recommendations"])
    assert body["count"] >= 1
    assert body["healthCount"] >= 1
    assert isinstance(body["aiCached"], bool)
    for item in body["recommendations"]:
        assert item["title"] and item["reason"]
        assert item["source"] in ("health", "ai")
        assert item["priority"] in ("high", "medium", "low")

    titles = [i["title"].strip().lower() for i in body["recommendations"]]
    assert len(titles) == len(set(titles)), "no duplicate advice"


def test_recommendations_survive_a_recommender_failure(
    client, fake_db, fake_auth, monkeypatch
):
    uid = "health-recs-fail"
    seed_profile(fake_db, uid)
    _seed_quiz(fake_db, uid, "q1", 80, {"Optics": 80})

    import app.services.ai_recommendation_service as rec_mod

    async def _boom(uid_arg: str):
        raise RuntimeError("provider down")

    monkeypatch.setattr(rec_mod, "generate_study_recommendation", _boom)

    body = client.get(
        "/api/ai/academic-health/recommendations", headers=_auth(fake_auth, uid)
    ).json()
    assert body["aiCount"] == 0
    assert body["count"] >= 1
    assert all(i["source"] == "health" for i in body["recommendations"])


# ---------------------------------------------------------------------------
# Phase 2 focus extensions
# ---------------------------------------------------------------------------


def test_focus_start_accepts_subject_and_topic(client, fake_db, fake_auth):
    uid = "focus-smart"
    seed_profile(fake_db, uid)
    resp = client.post(
        "/api/study/focus/start",
        json={"label": "Thermodynamics", "subject": "Physics", "topic": "Carnot Cycle"},
        headers=_auth(fake_auth, uid),
    )
    assert resp.status_code in (200, 201), resp.text
    body = resp.json()
    assert body["subject"] == "Physics"
    assert body["topic"] == "Carnot Cycle"

    stored = fake_db._collections[f"users/{uid}/focus_sessions"][body["id"]]
    assert stored["subject"] == "Physics"
    assert stored["topic"] == "Carnot Cycle"
    assert stored["interruptions"] == 0


def test_interruption_counter_increments_and_is_scored(
    client, fake_db, fake_auth
):
    uid = "focus-interrupt"
    seed_profile(fake_db, uid)
    h = _auth(fake_auth, uid)
    start = client.post(
        "/api/study/focus/start",
        json={"plannedMinutes": 25, "subject": "Physics"},
        headers=h,
    ).json()

    first = client.patch(
        f"/api/study/focus/{start['id']}",
        json={"action": "interruption"},
        headers=h,
    )
    assert first.status_code == 200, first.text
    assert first.json()["interruptions"] == 1

    second = client.patch(
        f"/api/study/focus/{start['id']}",
        json={"action": "interruption"},
        headers=h,
    )
    assert second.json()["interruptions"] == 2

    # A completed session can no longer record interruptions.
    fake_db._collections[f"users/{uid}/focus_sessions"][start["id"]]["status"] = (
        "completed"
    )
    blocked = client.patch(
        f"/api/study/focus/{start['id']}",
        json={"action": "interruption"},
        headers=h,
    )
    assert blocked.status_code == 409, blocked.text


def test_complete_computes_focus_score(client, fake_db, fake_auth):
    uid = "focus-score"
    seed_profile(fake_db, uid)
    h = _auth(fake_auth, uid)

    # Perfect: 25 of 25 planned minutes, no interruptions.
    perfect = client.post(
        "/api/study/focus/start",
        json={"plannedMinutes": 25},
        headers=h,
    ).json()
    fake_db._collections[f"users/{uid}/focus_sessions"][perfect["id"]][
        "accumulatedSeconds"
    ] = 1500
    done = client.patch(
        f"/api/study/focus/{perfect['id']}", json={"action": "complete"}, headers=h
    ).json()
    assert done["focusScore"] == 100
    assert done["status"] == "completed"

    # Two interruptions on the same math: 100 - 10 = 90.
    interrupted = client.post(
        "/api/study/focus/start",
        json={"plannedMinutes": 25},
        headers=h,
    ).json()
    fake_db._collections[f"users/{uid}/focus_sessions"][interrupted["id"]].update(
        {"accumulatedSeconds": 1500, "interruptions": 2}
    )
    scored = client.patch(
        f"/api/study/focus/{interrupted['id']}",
        json={"action": "complete"},
        headers=h,
    ).json()
    assert scored["focusScore"] == 90

    # Half the plan done: 50.
    half = client.post(
        "/api/study/focus/start",
        json={"plannedMinutes": 25},
        headers=h,
    ).json()
    fake_db._collections[f"users/{uid}/focus_sessions"][half["id"]][
        "accumulatedSeconds"
    ] = 750
    half_done = client.patch(
        f"/api/study/focus/{half['id']}", json={"action": "complete"}, headers=h
    ).json()
    assert half_done["focusScore"] == 50


def test_complete_idempotent_response_carries_the_focus_score(
    client, fake_db, fake_auth
):
    uid = "focus-score-idem"
    seed_profile(fake_db, uid)
    h = _auth(fake_auth, uid)
    start = client.post("/api/study/focus/start", json={"plannedMinutes": 10}, headers=h).json()
    fake_db._collections[f"users/{uid}/focus_sessions"][start["id"]][
        "accumulatedSeconds"
    ] = 600

    first = client.patch(
        f"/api/study/focus/{start['id']}", json={"action": "complete"}, headers=h
    ).json()
    second = client.patch(
        f"/api/study/focus/{start['id']}", json={"action": "complete"}, headers=h
    ).json()

    assert first["focusScore"] == 100
    assert second["focusScore"] == first["focusScore"]
    assert second["idempotent"] is True


def test_focus_list_exposes_the_new_session_fields(client, fake_db, fake_auth):
    uid = "focus-list-fields"
    seed_profile(fake_db, uid)
    h = _auth(fake_auth, uid)
    start = client.post(
        "/api/study/focus/start",
        json={"subject": "Chemistry", "topic": "Moles", "plannedMinutes": 20},
        headers=h,
    ).json()
    fake_db._collections[f"users/{uid}/focus_sessions"][start["id"]].update(
        {"accumulatedSeconds": 1200, "focusScore": 100}
    )
    client.patch(
        f"/api/study/focus/{start['id']}", json={"action": "complete"}, headers=h
    )

    listed = client.get("/api/study/focus/list", headers=h).json()["sessions"]
    row = next(r for r in listed if r["id"] == start["id"])
    assert row["subject"] == "Chemistry"
    assert row["topic"] == "Moles"
    assert row["focusScore"] == 100
    assert row["interruptions"] == 0


def test_focus_today_reports_minutes_and_score(client, fake_db, fake_auth):
    uid = "focus-today"
    seed_profile(fake_db, uid)
    h = _auth(fake_auth, uid)

    empty = client.get("/api/study/focus/today", headers=h).json()
    assert empty["minutes"] == 0
    assert empty["focusScore"] is None
    assert empty["sessions"] == 0

    _seed_focus(fake_db, uid, "done-1", minutes=40, subject="Physics", focus_score=88)
    _seed_focus(
        fake_db,
        uid,
        "done-2",
        minutes=20,
        subject="Mathematics",
        focus_score=76,
    )
    _seed_focus(fake_db, uid, "live-1", minutes=5, status="running")

    today = client.get("/api/study/focus/today", headers=h).json()
    assert today["minutes"] == 60
    assert today["sessions"] == 2
    assert today["focusScore"] == 82  # (88 + 76) / 2
    assert today["bySubjectMinutes"]["Physics"] == 40
    assert today["bySubjectMinutes"]["Mathematics"] == 20
    assert today["activeSessions"] == 1
    assert today["activeSeconds"] >= 0


def test_focus_today_is_scoped_to_the_calling_student(
    client, fake_db, fake_auth
):
    a, b = "focus-today-a", "focus-today-b"
    seed_profile(fake_db, a)
    seed_profile(fake_db, b)
    _seed_focus(fake_db, a, "only-a", minutes=45, focus_score=90)

    mine = client.get("/api/study/focus/today", headers=_auth(fake_auth, a)).json()
    theirs = client.get("/api/study/focus/today", headers=_auth(fake_auth, b)).json()

    assert mine["minutes"] == 45
    assert theirs["minutes"] == 0


def test_health_score_consumes_the_focus_score(client, fake_db, fake_auth):
    uid = "health-focus-score"
    seed_profile(fake_db, uid)
    _seed_focus(fake_db, uid, "f0", minutes=50, focus_score=95)

    body = client.get(
        "/api/ai/academic-health", headers=_auth(fake_auth, uid)
    ).json()
    assert body["signals"]["study"]["averageFocusScore"] == 95
    assert body["signals"]["study"]["bySubjectMinutes"]["Physics"] == 50


# ---------------------------------------------------------------------------
# Ziku context — the score reaching the chat prompt (Phase 2)
# ---------------------------------------------------------------------------


def test_ziku_prompt_has_no_health_line_by_default():
    """The prompt builder keeps working with no arguments at all."""
    from app.services.ai_service import build_chat_system_prompt

    prompt = build_chat_system_prompt()
    assert "Current academic health" not in prompt
    assert "Never reply in Banglish" in prompt


def test_ziku_prompt_appends_the_health_line_when_given():
    from app.services.ai_service import build_chat_system_prompt

    prompt = build_chat_system_prompt(
        academic_health="Current academic health: score 76/100."
    )
    assert "Current academic health: score 76/100." in prompt
    assert "personalise advice" in prompt
    assert "Never reply in Banglish" in prompt, "health must not displace policy"


def test_chat_context_is_none_without_any_signal(client, fake_db, fake_auth):
    from app.services.academic_health_service import chat_context_line

    uid = "ziku-empty"
    seed_profile(fake_db, uid)
    assert chat_context_line(uid) is None


def test_chat_context_summarises_score_weak_topic_and_revision_queue(
    client, fake_db, fake_auth
):
    from app.services.academic_health_service import chat_context_line

    uid = "ziku-context"
    seed_profile(fake_db, uid)
    _seed_quiz(fake_db, uid, "q1", 44, {"Networking": 44})
    _seed_focus(fake_db, uid, "f0", minutes=25)
    _seed_mistake(fake_db, uid, "m1", "Networking", due=True, analyzed=True)

    line = chat_context_line(uid)

    assert line is not None
    assert line.startswith("Current academic health:")
    assert "score " in line and "/100" in line
    assert "Networking" in line
    assert "mistake(s) due for revision" in line
    assert "deep work today" in line


def test_chat_context_does_not_write_a_snapshot(client, fake_db, fake_auth):
    """Reading context for Ziku must not count as a scoring run."""
    from app.services.academic_health_service import chat_context_line

    uid = "ziku-nosnap"
    seed_profile(fake_db, uid)
    _seed_quiz(fake_db, uid, "q1", 70, {"Optics": 70})

    chat_context_line(uid)

    history_key = f"users/{uid}/health_history"
    stored = fake_db._collections.get(history_key, {})
    assert not stored, (
        "chat context must not persist a health_history snapshot"
    )


def test_chat_context_swallows_a_scoring_failure(client, fake_db, fake_auth, monkeypatch):
    from app.services import academic_health_service

    uid = "ziku-broken"

    def _boom(*_args, **_kwargs):
        raise RuntimeError("firestore is having a day")

    monkeypatch.setattr(academic_health_service, "get_academic_health", _boom)
    assert academic_health_service.chat_context_line(uid) is None


@pytest.mark.asyncio
async def test_chat_generate_hands_the_health_line_to_the_provider(
    client, fake_db, fake_auth
):
    from unittest.mock import AsyncMock, MagicMock, patch

    from app.services import ai_service as ai_service_module

    uid = "ziku-chat"
    seed_profile(fake_db, uid)
    _seed_quiz(fake_db, uid, "q1", 44, {"Networking": 44})
    _seed_focus(fake_db, uid, "f0", minutes=25)

    settings = MagicMock()
    settings.groq_api_key = "g-key"
    settings.gemini_api_key = ""
    settings.openrouter_api_key = ""

    with patch(
        "app.services.ai_service.get_settings", return_value=settings
    ), patch("app.services.ai_service._consume_quota"), patch(
        "app.services.ai_service._groq_chat",
        new_callable=AsyncMock,
        return_value="Revise Networking first.",
    ) as mock_chat:
        result = await ai_service_module.chat_generate(
            uid, [{"role": "user", "content": "help me revise tonight"}]
        )

    assert result["reply"] == "Revise Networking first."
    assert mock_chat.await_count == 1
    _, system_prompt = mock_chat.await_args.args
    assert "Current academic health:" in system_prompt
    assert "Networking" in system_prompt
