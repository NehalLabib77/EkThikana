"""Phase 8 — Ziku Personal Intelligence Layer.

Covers the layer as an **aggregator** over the systems built in Phases 1-7:

* ``GET /api/ziku/journey``            the Academic Memory Timeline (7 streams,
  90 days, improvement trends) — "Your Learning Journey"
* ``GET /api/ziku/brief``              morning headings + evening recap and the
  one AI reflection line (rule-based fallback)
* ``GET /api/ziku/profile``            preferred study time, learning style,
  strong/weak subjects
* ``GET /api/ziku/next-best-action``   five systems ranked into one action
* ``GET /api/ziku/achievements``       the scoreboard, earned stamps are
  write-once
* ``study_coach_service.chat_context`` carries the Personal OS line

The four invariants worth protecting here:

1. every read is **student-only** (``require_student`` + the hand-maintained
   prefix list),
2. the journey/personality/recommendation are **cached per day** and the
   evening half + achievement bars are rebuilt because they report *today*,
3. an achievement is **never un-earned** when a metric later regresses, and
4. a broken system degrades one line of the payload — it never raises into a
   card.

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


def _seed_quiz(
    db,
    uid: str,
    doc_id: str,
    score: int,
    topics: dict[str, int] | None = None,
    *,
    days_ago: int = 0,
    subject: str = "Physics",
) -> None:
    stamp = _day(-days_ago)
    db.seed(
        f"users/{uid}/quiz_results",
        doc_id,
        {
            "ownerId": uid,
            "score": score,
            "topicScores": topics or {},
            "subjectId": subject,
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
    hour: int = 9,
) -> None:
    started = _day(-days_ago).replace(hour=hour, minute=0, second=0, microsecond=0)
    db.seed(
        f"users/{uid}/focus_sessions",
        doc_id,
        {
            "id": doc_id,
            "ownerId": uid,
            "status": "completed",
            "label": "Deep work",
            "subject": "Physics",
            "plannedMinutes": minutes,
            "accumulatedSeconds": minutes * 60,
            "dayKey": started.strftime("%Y-%m-%d"),
            "startedAtIso": started.isoformat(),
            "interruptions": 0,
            "focusScore": 88,
        },
    )


def _seed_mistake(
    db,
    uid: str,
    doc_id: str,
    topic: str,
    *,
    occurrences: int = 1,
    days_ago: int = 0,
    due: bool = False,
) -> None:
    stamp = _day(-days_ago)
    db.seed(
        f"users/{uid}/mistakes",
        doc_id,
        {
            "ownerId": uid,
            "topic": topic,
            "subjectId": "Physics",
            "question": "What is the critical angle?",
            "correctAnswer": "angle of incidence",
            "wrongAnswer": "angle of refraction",
            "occurrences": occurrences,
            "nextReviewDate": (_day(-1) if due else _day(30)).strftime("%Y-%m-%d"),
            "analysisStatus": "analyzed",
            "firstSeenAt": stamp,
            "lastSeenAt": stamp,
            "createdAt": stamp,
        },
    )


def _seed_exam_result(
    db, uid: str, doc_id: str, percentage: float, *, days_ago: int = 0
) -> None:
    stamp = _day(-days_ago)
    db.seed(
        f"users/{uid}/exam_results",
        doc_id,
        {
            "ownerId": uid,
            "examId": "exam-1",
            "attemptId": f"attempt-{doc_id}",
            "percentage": percentage,
            "score": percentage,
            "totalMarks": 100.0,
            "correctCount": int(percentage),
            "wrongCount": 100 - int(percentage),
            "totalQuestions": 100,
            "subject": "Physics",
            "createdAt": stamp,
            "dayKey": stamp.strftime("%Y-%m-%d"),
        },
    )


def _seed_exam_rescue(db, uid: str, session_id: str, *, in_days: int = 5) -> None:
    db.seed(
        f"users/{uid}/exam_rescue",
        session_id,
        {
            "sessionId": session_id,
            "ownerId": uid,
            "examTitle": "Physics Final",
            "examDate": _day(in_days),
            "status": "active",
            "dailyTargetMinutes": 90,
        },
    )


def _seed_health(db, uid: str, day_key: str, score: int) -> None:
    db.seed(
        f"users/{uid}/health_history",
        day_key,
        {"dayKey": day_key, "score": score, "grade": "B", "metrics": {}},
    )


def _trend(body: dict, key: str) -> dict | None:
    for row in body.get("trends") or []:
        if row.get("key") == key:
            return row
    return None


# ---------------------------------------------------------------------------
# gate
# ---------------------------------------------------------------------------

PATHS = (
    "/api/ziku/journey",
    "/api/ziku/brief",
    "/api/ziku/profile",
    "/api/ziku/next-best-action",
    "/api/ziku/achievements",
)


def test_ziku_requires_auth(client):
    for path in PATHS:
        assert client.get(path).status_code == 401, path


def test_ziku_is_student_only(client, fake_db, fake_auth):
    uid = "ziku-general"
    seed_profile(fake_db, uid, role="general")
    headers = _auth(fake_auth, uid)
    for path in PATHS:
        response = client.get(path, headers=headers)
        assert response.status_code == 403, f"{path} -> {response.status_code}"


# ---------------------------------------------------------------------------
# 1. academic memory timeline
# ---------------------------------------------------------------------------


def test_journey_is_empty_but_well_formed_for_a_new_student(
    client, fake_db, fake_auth
):
    uid = "ziku-journey-empty"
    seed_profile(fake_db, uid)

    body = client.get("/api/ziku/journey", headers=_auth(fake_auth, uid)).json()

    assert body["title"] == "Your Learning Journey"
    assert body["student"] == "Test"
    assert body["hasData"] is False
    assert body["cached"] is False
    assert body["spanDays"] == 90
    assert body["trends"] == []
    assert body["improving"] == 0
    assert body["declining"] == 0
    assert body["timeline"] == []
    assert body["stats"]["quizzes"] == 0
    assert body["streams"]["studyHours"] == 0
    assert "Not enough yet" in body["headline"]


def test_journey_counts_the_seven_streams(client, fake_db, fake_auth):
    uid = "ziku-journey-streams"
    seed_profile(fake_db, uid)
    _seed_quiz(fake_db, uid, "q1", 88, {"Mechanics": 88})
    _seed_exam_result(fake_db, uid, "e1", 72.0, days_ago=1)
    _seed_mistake(fake_db, uid, "m1", "Optics")
    _seed_focus(fake_db, uid, "f1", minutes=40)
    _seed_focus(fake_db, uid, "f2", days_ago=1, minutes=30)
    fake_db.seed(
        "community_reputation",
        uid,
        {"uid": uid, "points": 12, "breakdown": {"answer_accepted": 1}},
    )
    fake_db.seed(
        "community_posts",
        "post-1",
        {"authorId": uid, "createdAtIso": _day(0).isoformat(), "title": "Doubt"},
    )

    body = client.get("/api/ziku/journey", headers=_auth(fake_auth, uid)).json()

    assert body["hasData"] is True
    stats = body["stats"]
    assert stats["quizzes"] == 1
    assert stats["exams"] == 1
    assert stats["mistakes"] == 1
    assert stats["focusSessions"] == 2
    assert stats["studyMinutes"] == 70
    assert stats["communityPosts"] == 1
    assert stats["communityPoints"] == 12
    assert stats["daysActive"] == 2
    assert stats["focusStreak"] == 2

    streams = body["streams"]
    assert streams["quizScores"] == 1
    assert streams["exams"] == 1
    assert streams["mistakes"] == 1
    assert streams["focusSessions"] == 2
    assert streams["studyHours"] == 1.2
    assert streams["communityActivity"] == 1
    assert streams["weakTopics"] >= 1

    kinds = {event["kind"] for event in body["timeline"]}
    assert {"quiz", "exam", "mistake", "focus", "community", "weakTopic"} <= kinds
    assert "active day(s)" in body["headline"]


def test_journey_trends_split_the_window_and_point_the_right_way(
    client, fake_db, fake_auth
):
    uid = "ziku-journey-trends"
    seed_profile(fake_db, uid)

    # early half (>= 46 days ago) vs late half (<= 45 days ago)
    for i, days_ago in enumerate((80, 79, 78)):
        _seed_quiz(
            fake_db, uid, f"q-early-{i}", 40, {"Optics": 40}, days_ago=days_ago
        )
        _seed_focus(fake_db, uid, f"f-early-{i}", days_ago=days_ago, minutes=60)
    for i, days_ago in enumerate((80,)):
        _seed_mistake(fake_db, uid, f"m-early-{i}", "Optics", days_ago=days_ago)
    for i, days_ago in enumerate((10, 9, 8)):
        _seed_quiz(fake_db, uid, f"q-late-{i}", 90, {"Optics": 90}, days_ago=days_ago)
        _seed_focus(fake_db, uid, f"f-late-{i}", days_ago=days_ago, minutes=30)
        _seed_mistake(fake_db, uid, f"m-late-{i}", "Optics", days_ago=days_ago)

    body = client.get("/api/ziku/journey", headers=_auth(fake_auth, uid)).json()

    quiz = _trend(body, "quizAverage")
    assert quiz is not None
    assert quiz["first"] == 40
    assert quiz["last"] == 90
    assert quiz["delta"] == 50
    assert quiz["direction"] == "up"
    assert quiz["improving"] is True

    mistakes = _trend(body, "mistakes")
    assert mistakes is not None
    assert mistakes["first"] == 1
    assert mistakes["last"] == 3
    assert mistakes["higherIsBetter"] is False
    assert mistakes["improving"] is False

    hours = _trend(body, "studyHours")
    assert hours is not None
    assert hours["first"] == 3.0
    assert hours["last"] == 1.5
    assert hours["improving"] is False

    assert body["improving"] >= 1
    assert body["declining"] >= 1


def test_journey_is_cached_per_day(client, fake_db, fake_auth):
    uid = "ziku-journey-cache"
    seed_profile(fake_db, uid)
    _seed_quiz(fake_db, uid, "q1", 70, {"Optics": 70})
    headers = _auth(fake_auth, uid)

    first = client.get("/api/ziku/journey", headers=headers).json()
    assert first["cached"] is False

    second = client.get("/api/ziku/journey", headers=headers).json()
    assert second["cached"] is True
    assert second["stats"] == first["stats"]

    forced = client.get("/api/ziku/journey?force=true", headers=headers).json()
    assert forced["cached"] is False


def test_journey_timeline_is_newest_first_and_capped(client, fake_db, fake_auth):
    uid = "ziku-journey-cap"
    seed_profile(fake_db, uid)
    for days_ago in range(85):
        _seed_quiz(fake_db, uid, f"q{days_ago}", 50, days_ago=days_ago)

    body = client.get("/api/ziku/journey", headers=_auth(fake_auth, uid)).json()

    assert body["timelineCount"] == 85
    assert len(body["timeline"]) == 80
    keys = [event["dayKey"] for event in body["timeline"]]
    assert keys == sorted(keys, reverse=True)


# ---------------------------------------------------------------------------
# 2. AI daily brief (morning + evening)
# ---------------------------------------------------------------------------


def test_brief_rejects_an_unknown_phase(client, fake_db, fake_auth):
    uid = "ziku-brief-phase"
    seed_profile(fake_db, uid)
    response = client.get(
        "/api/ziku/brief?phase=noon", headers=_auth(fake_auth, uid)
    )
    assert response.status_code == 400
    assert "phase must be one of" in response.json()["detail"]


def test_morning_brief_carries_the_four_headings(client, fake_db, fake_auth):
    uid = "ziku-brief-morning"
    seed_profile(fake_db, uid)
    _seed_quiz(fake_db, uid, "q1", 45, {"Optics": 45})
    _seed_mistake(fake_db, uid, "m1", "Optics", occurrences=4, due=True)
    _seed_focus(fake_db, uid, "f1", minutes=35)

    body = client.get(
        "/api/ziku/brief?phase=morning", headers=_auth(fake_auth, uid)
    ).json()

    assert body["phase"] == "morning"
    assert body["requestedPhase"] == "morning"
    morning = body["morning"]
    assert isinstance(morning["academicHealth"], dict)
    assert isinstance(morning["academicHealth"]["score"], (int, float))
    assert morning["priority"] is not None
    assert isinstance(morning["why"], str)
    assert isinstance(morning["mission"], list)
    assert isinstance(morning["missionCount"], int)
    assert morning["missionCount"] >= 1
    # the evening half always comes back too, so one round trip is enough
    assert isinstance(body["evening"], dict)


def test_evening_brief_reports_progress_mistakes_and_tomorrow(
    client, fake_db, fake_auth
):
    uid = "ziku-brief-evening"
    seed_profile(fake_db, uid)
    _seed_quiz(fake_db, uid, "q1", 45, {"Optics": 45})
    _seed_focus(fake_db, uid, "f1", minutes=40)
    _seed_mistake(fake_db, uid, "m1", "Optics", occurrences=3, due=True)

    body = client.get(
        "/api/ziku/brief?phase=evening", headers=_auth(fake_auth, uid)
    ).json()

    assert body["phase"] == "evening"
    evening = body["evening"]
    progress = evening["progress"]
    assert progress["quizzes"] == 1
    assert progress["focusSessions"] == 1
    assert progress["studyMinutes"] == 40
    assert progress["mistakes"] == 1

    assert evening["summary"].startswith("Today:")
    assert evening["mistakesTodayCount"] == 1
    assert evening["mistakesToday"][0]["topic"] == "Optics"
    assert evening["mistakesTotal"] >= 1

    tomorrow = evening["tomorrow"]
    assert tomorrow["title"].startswith("Start tomorrow with")
    assert tomorrow["topic"]
    assert tomorrow["why"]
    assert tomorrow["action"]
    assert tomorrow["minutes"] > 0
    assert tomorrow["destination"] in {"quiz", "review", "focus", "exam", "rescue"}

    assert isinstance(evening["reflection"], str)
    assert evening["reflection"]


def test_evening_brief_falls_back_to_rules_when_the_ai_is_silent(
    client, fake_db, fake_auth, monkeypatch
):
    from app.services import ziku_intelligence_service as intel

    uid = "ziku-brief-ai-down"
    seed_profile(fake_db, uid)
    _seed_quiz(fake_db, uid, "q1", 60, {"Optics": 60})

    async def _silent(uid_arg, facts):
        return None

    monkeypatch.setattr(intel, "_ai_reflection", _silent)

    body = client.get(
        "/api/ziku/brief?phase=evening", headers=_auth(fake_auth, uid)
    ).json()

    evening = body["evening"]
    assert evening["reflectionAi"] is False
    assert evening["reflection"], "the rule-based fallback must never blank out"
    assert "Academic Health" in evening["reflection"] or "quiet day" in evening["reflection"]


def test_brief_uses_the_ai_line_when_it_comes_back(
    client, fake_db, fake_auth, monkeypatch
):
    from app.services import ziku_intelligence_service as intel

    uid = "ziku-brief-ai-up"
    seed_profile(fake_db, uid)
    _seed_quiz(fake_db, uid, "q1", 60, {"Optics": 60})

    async def _writer(uid_arg, facts):
        return "You showed up - that is half the work."

    monkeypatch.setattr(intel, "_ai_reflection", _writer)

    body = client.get(
        "/api/ziku/brief?phase=evening", headers=_auth(fake_auth, uid)
    ).json()

    evening = body["evening"]
    assert evening["reflectionAi"] is True
    assert evening["reflection"] == "You showed up - that is half the work."


def test_brief_is_cached_for_the_day(client, fake_db, fake_auth):
    uid = "ziku-brief-cache"
    seed_profile(fake_db, uid)
    _seed_quiz(fake_db, uid, "q1", 70, {"Optics": 70})
    headers = _auth(fake_auth, uid)

    first = client.get("/api/ziku/brief?phase=morning", headers=headers).json()
    assert first["cached"] is False

    second = client.get("/api/ziku/brief?phase=morning", headers=headers).json()
    assert second["cached"] is True
    assert second["morning"]["missionCount"] == first["morning"]["missionCount"]


# ---------------------------------------------------------------------------
# 3. student learning profile (personality)
# ---------------------------------------------------------------------------


def test_personality_is_empty_but_well_formed_for_a_new_student(
    client, fake_db, fake_auth
):
    uid = "ziku-profile-empty"
    seed_profile(fake_db, uid)

    body = client.get("/api/ziku/profile", headers=_auth(fake_auth, uid)).json()

    assert body["title"] == "Student Learning Profile"
    assert body["hasData"] is False
    assert body["cached"] is False
    personality = body["personality"]
    assert personality["preferredStudyTime"]["key"] == "unknown"
    assert personality["strongSubjects"] == []
    assert personality["weakSubjects"] == []
    assert body["evidence"]["quizzes"] == 0
    assert body["label"]


def test_personality_reads_preferred_study_time_from_sessions(
    client, fake_db, fake_auth
):
    uid = "ziku-profile-time"
    seed_profile(fake_db, uid)
    for i in range(3):
        _seed_focus(fake_db, uid, f"am-{i}", days_ago=i + 1, minutes=30, hour=9)
    _seed_focus(fake_db, uid, "pm-1", days_ago=4, minutes=30, hour=22)

    body = client.get("/api/ziku/profile", headers=_auth(fake_auth, uid)).json()

    preferred = body["personality"]["preferredStudyTime"]
    assert preferred["key"] == "morning"
    assert preferred["label"] == "Morning"
    assert preferred["sharePct"] == 75.0
    assert preferred["sessions"] == 4
    assert preferred["breakdown"]["morning"] == 3
    assert preferred["breakdown"]["evening"] == 1


def test_personality_splits_strong_and_weak_subjects(client, fake_db, fake_auth):
    uid = "ziku-profile-split"
    seed_profile(fake_db, uid)
    for i in range(3):
        _seed_quiz(
            fake_db, uid, f"phy-{i}", 90, {"Mechanics": 90}, days_ago=i, subject="Physics"
        )
        _seed_quiz(
            fake_db, uid, f"chem-{i}", 40, {"Organic": 40}, days_ago=i, subject="Chemistry"
        )

    body = client.get("/api/ziku/profile", headers=_auth(fake_auth, uid)).json()

    personality = body["personality"]
    assert personality["subjectKind"] == "subject"
    assert personality["strongSubjects"][0]["name"] == "Physics"
    assert personality["strongSubjects"][0]["average"] == 90
    assert personality["weakSubjects"][0]["name"] == "Chemistry"
    assert personality["weakSubjects"][0]["average"] == 40
    assert body["evidence"]["quizzes"] == 6
    strengths = " ".join(personality["strengths"])
    assert "Physics" in strengths
    watchouts = " ".join(personality["watchouts"])
    assert "Chemistry" in watchouts


def test_personality_picks_revision_led_for_a_repeat_offender(
    client, fake_db, fake_auth
):
    uid = "ziku-profile-revision"
    seed_profile(fake_db, uid)
    for i in range(6):
        _seed_mistake(
            fake_db, uid, f"m{i}", "Optics", occurrences=3, days_ago=i, due=True
        )

    body = client.get("/api/ziku/profile", headers=_auth(fake_auth, uid)).json()

    style = body["personality"]["learningStyle"]
    assert style["key"] == "revision_led"
    assert body["label"] == "The Comeback Kid"
    assert body["evidence"]["repeatedMistakes"] == 6
    assert body["evidence"]["revisionDue"] == 6


def test_personality_is_cached_for_the_day(client, fake_db, fake_auth):
    uid = "ziku-profile-cache"
    seed_profile(fake_db, uid)
    _seed_quiz(fake_db, uid, "q1", 80, {"Optics": 80})
    headers = _auth(fake_auth, uid)

    first = client.get("/api/ziku/profile", headers=headers).json()
    assert first["cached"] is False

    second = client.get("/api/ziku/profile", headers=headers).json()
    assert second["cached"] is True
    assert second["label"] == first["label"]


# ---------------------------------------------------------------------------
# 4. smart recommendation engine
# ---------------------------------------------------------------------------

SOURCES = {
    "Study Coach",
    "Mistake Memory",
    "Exam Simulator",
    "Ziku Focus Engine",
    "Learning Community",
}


def test_next_best_action_ranks_every_system(client, fake_db, fake_auth):
    uid = "ziku-action-all"
    seed_profile(fake_db, uid)
    _seed_quiz(fake_db, uid, "q1", 55, {"Optics": 55})
    _seed_focus(fake_db, uid, "f1", minutes=20)

    body = client.get("/api/ziku/next-best-action", headers=_auth(fake_auth, uid)).json()

    action = body["action"]
    alternatives = body["alternatives"]
    assert action["source"] in SOURCES
    assert isinstance(action["title"], str) and action["title"]
    assert isinstance(action["detail"], str) and action["detail"]
    assert action["minutes"] >= 0
    assert action["destination"]
    assert len(alternatives) <= 4
    assert {action["source"]} | {a["source"] for a in alternatives} == SOURCES
    assert body["why"] == f"{action['source']}: {action['detail']}"
    assert set(body["sources"]) == {"coach", "mistakes", "exams", "focus", "community"}


def test_next_best_action_picks_the_highest_score(client, fake_db, fake_auth):
    uid = "ziku-action-ranked"
    seed_profile(fake_db, uid)
    _seed_quiz(fake_db, uid, "q1", 55, {"Optics": 55})
    _seed_focus(fake_db, uid, "f1", minutes=20)

    body = client.get("/api/ziku/next-best-action", headers=_auth(fake_auth, uid)).json()

    scores = [body["action"]["score"]] + [a["score"] for a in body["alternatives"]]
    assert scores == sorted(scores, reverse=True)


def test_next_best_action_prefers_the_imminent_exam(client, fake_db, fake_auth):
    uid = "ziku-action-exam"
    seed_profile(fake_db, uid)
    _seed_exam_rescue(fake_db, uid, "s1", in_days=2)

    body = client.get("/api/ziku/next-best-action", headers=_auth(fake_auth, uid)).json()

    action = body["action"]
    assert action["source"] == "Exam Simulator"
    assert action["key"] == "exam_rescue"
    assert action["score"] >= 90
    assert action["destination"] == "rescue"
    assert action["evidence"]["daysRemaining"] == 2
    assert body["sources"]["coach"]["examDaysRemaining"] == 2


def test_next_best_action_is_cached_per_day(client, fake_db, fake_auth):
    uid = "ziku-action-cache"
    seed_profile(fake_db, uid)
    _seed_quiz(fake_db, uid, "q1", 70, {"Optics": 70})
    headers = _auth(fake_auth, uid)

    first = client.get("/api/ziku/next-best-action", headers=headers).json()
    assert first["cached"] is False

    second = client.get("/api/ziku/next-best-action", headers=headers).json()
    assert second["cached"] is True
    assert second["action"]["key"] == first["action"]["key"]


# ---------------------------------------------------------------------------
# 5. achievement system
# ---------------------------------------------------------------------------


def test_achievements_are_bars_for_a_new_student(client, fake_db, fake_auth):
    uid = "ziku-achievements-empty"
    seed_profile(fake_db, uid)

    body = client.get("/api/ziku/achievements", headers=_auth(fake_auth, uid)).json()

    assert body["hasData"] is False
    assert body["counts"]["total"] == 16
    assert body["counts"]["earned"] == 1  # Revision Zero: nothing is overdue yet
    assert body["counts"]["locked"] == 15

    earned = {row["id"] for row in body["achievements"] if row["earned"]}
    assert "revision_clear" in earned
    assert "mcq_first" not in earned

    for row in body["achievements"]:
        assert 0.0 <= row["progress"] <= 1.0
        if row["earned"]:
            assert row["earnedAt"]
        else:
            assert row["earnedAt"] is None

    assert body["next"] is not None
    assert body["next"]["id"] != "revision_clear"


def test_achievements_cover_the_four_asks(client, fake_db, fake_auth):
    uid = "ziku-achievements-categories"
    seed_profile(fake_db, uid)

    body = client.get("/api/ziku/achievements", headers=_auth(fake_auth, uid)).json()

    keys = [row["key"] for row in body["categories"]]
    assert keys == ["mcq", "consistency", "improvement", "contribution"]
    for row in body["categories"]:
        assert row["total"] >= 1
        assert row["earned"] <= row["total"]
    assert sum(row["total"] for row in body["categories"]) == 16
    assert {row["category"] for row in body["achievements"]} == set(keys)


def test_achievements_earn_first_step(client, fake_db, fake_auth):
    uid = "ziku-achievements-first"
    seed_profile(fake_db, uid)
    _seed_quiz(fake_db, uid, "q1", 65, {"Optics": 65})

    body = client.get("/api/ziku/achievements", headers=_auth(fake_auth, uid)).json()

    earned = {row["id"] for row in body["achievements"] if row["earned"]}
    assert "mcq_first" in earned
    assert body["counts"]["earned"] >= 2

    stamped = fake_db._collections[f"users/{uid}/learning_achievements"]["current"]
    assert "mcq_first" in stamped["earned"]
    assert stamped["earned"]["mcq_first"]


def test_earned_achievements_survive_a_regression(client, fake_db, fake_auth):
    uid = "ziku-achievements-sticky"
    seed_profile(fake_db, uid)
    _seed_quiz(fake_db, uid, "q1", 65, {"Optics": 65})
    headers = _auth(fake_auth, uid)

    first = client.get("/api/ziku/achievements", headers=headers).json()
    first_row = next(r for r in first["achievements"] if r["id"] == "mcq_first")
    assert first_row["earned"] is True

    # the metric goes away (a reset, a deleted attempt): the stamp stays
    fake_db.collection("users").document(uid).collection("quiz_results").document(
        "q1"
    ).delete()

    second = client.get("/api/ziku/achievements", headers=headers).json()
    row = next(r for r in second["achievements"] if r["id"] == "mcq_first")
    assert row["earned"] is True
    assert row["earnedAt"] == first_row["earnedAt"]
    assert row["progress"] == 0.0


def test_sharpshooter_needs_ten_quizzes(client, fake_db, fake_auth):
    uid = "ziku-achievements-sharp"
    seed_profile(fake_db, uid)
    for i in range(3):
        _seed_quiz(fake_db, uid, f"q{i}", 95, {"Optics": 95}, days_ago=i)

    three = client.get("/api/ziku/achievements", headers=_auth(fake_auth, uid)).json()
    row = next(r for r in three["achievements"] if r["id"] == "mcq_sharpshooter")
    assert row["earned"] is False
    assert row["progress"] < 1.0

    for i in range(3, 10):
        _seed_quiz(fake_db, uid, f"q{i}", 95, {"Optics": 95}, days_ago=i)

    ten = client.get(
        "/api/ziku/achievements?force=true", headers=_auth(fake_auth, uid)
    ).json()
    row = next(r for r in ten["achievements"] if r["id"] == "mcq_sharpshooter")
    assert row["earned"] is True
    assert row["current"] >= 80


# ---------------------------------------------------------------------------
# 6. the Personal OS line reaches Ziku's prompt
# ---------------------------------------------------------------------------


def test_personal_os_line_reaches_the_coach_prompt(client, fake_db, fake_auth):
    from app.services import ziku_intelligence_service as intel
    from app.services.study_coach_service import chat_context

    uid = "ziku-chat-line"
    seed_profile(fake_db, uid)
    _seed_quiz(fake_db, uid, "q1", 40, {"Optics": 40})
    _seed_mistake(fake_db, uid, "m1", "Optics", occurrences=6, due=True)
    _seed_exam_rescue(fake_db, uid, "s1", in_days=5)

    cached_line = intel.chat_line(uid)
    assert cached_line is None, "nothing cached yet means no line at all"

    intel.next_best_action(uid, force=True)
    cached_line = intel.chat_line(uid)
    assert cached_line is not None
    assert cached_line.startswith("Personal OS: ")
    assert "next best action" in cached_line

    line = chat_context(uid)
    assert line is not None
    assert line.startswith("Study coach:")
    assert "Personal OS: " in line
    assert line.endswith("step(s).")


def test_no_cached_intelligence_means_no_personal_os_line(
    client, fake_db, fake_auth
):
    from app.services import ziku_intelligence_service as intel
    from app.services.study_coach_service import chat_context

    uid = "ziku-chat-quiet"
    seed_profile(fake_db, uid)
    _seed_quiz(fake_db, uid, "q1", 55, {"Optics": 55})

    assert intel.chat_line(uid) is None

    line = chat_context(uid)
    assert line is not None
    assert "Personal OS" not in line
