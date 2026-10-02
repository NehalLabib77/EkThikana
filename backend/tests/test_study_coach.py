"""Phase 4 — Ziku Personal Study Coach.

Covers the coach as an **aggregator** over the systems built in Phases 1-3:

* ``GET  /api/coach/profile``         learning profile + daily cache
* ``GET  /api/coach/daily``           the mission (priority, why, steps)
* ``GET  /api/coach/weekly-report``   7-day summary + one AI narrative
* ``POST /api/coach/recalculate``     forced rebuild
* ``study_coach_service.weakness_analysis`` — High/Medium/Low urgency
* ``study_coach_service.chat_context`` — the line Ziku's prompt now carries

The two invariants worth protecting here:

1. the coach **never writes a Phase 2 snapshot** (reading advice must not
   double as a scoring run), and
2. every read is a cache-first, offline-safe rule — AI is spent once per
   student per week and falls back to prose the rules can write themselves.

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


def _seed_quiz(db, uid: str, doc_id: str, score: int, topics: dict[str, int]) -> None:
    stamp = _day(0)
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


def _seed_focus(db, uid: str, doc_id: str, *, days_ago: int = 0, minutes: int = 30) -> None:
    day = _day(-days_ago)
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
            "dayKey": day.strftime("%Y-%m-%d"),
            "startedAtIso": day.isoformat(),
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
    due: bool = False,
) -> None:
    db.seed(
        f"users/{uid}/mistakes",
        doc_id,
        {
            "ownerId": uid,
            "topic": topic,
            "subjectId": "Physics",
            "question": "What is the critical angle?",
            "correctAnswer": "angle of incidence",
            "userAnswer": "angle of refraction",
            "occurrences": occurrences,
            "nextReviewDate": (_day(-1) if due else _day(30)).strftime("%Y-%m-%d"),
            "analysisStatus": "analyzed",
            "createdAt": _day(-2),
        },
    )


def _seed_exam(db, uid: str, session_id: str, *, in_days: int = 5) -> None:
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


def _topics(profile: dict) -> list[str]:
    return [t["topic"] for t in profile.get("weakTopics") or []]


# ---------------------------------------------------------------------------
# gate
# ---------------------------------------------------------------------------


def test_coach_requires_auth(client):
    assert client.get("/api/coach/profile").status_code == 401
    assert client.get("/api/coach/daily").status_code == 401
    assert client.get("/api/coach/weekly-report").status_code == 401
    assert client.post("/api/coach/recalculate").status_code == 401


def test_coach_is_student_only(client, fake_db, fake_auth):
    uid = "coach-general"
    seed_profile(fake_db, uid, role="general")
    headers = _auth(fake_auth, uid)
    assert client.get("/api/coach/profile", headers=headers).status_code == 403
    assert client.get("/api/coach/daily", headers=headers).status_code == 403
    assert (
        client.get("/api/coach/weekly-report", headers=headers).status_code == 403
    )
    assert client.post("/api/coach/recalculate", headers=headers).status_code == 403


# ---------------------------------------------------------------------------
# 1. learning profile
# ---------------------------------------------------------------------------


def test_profile_is_empty_but_well_formed_for_a_new_student(
    client, fake_db, fake_auth
):
    uid = "coach-empty"
    seed_profile(fake_db, uid)

    body = client.get("/api/coach/profile", headers=_auth(fake_auth, uid)).json()

    assert body["student"] == "Test"
    assert body["hasData"] is False
    assert body["weakTopics"] == []
    assert body["strongTopics"] == []
    assert body["healthScore"] == 0
    assert body["averageFocusTime"] == 0
    assert body["examReadiness"] is None
    assert body["upcomingExam"] is None
    assert body["cached"] is False


def test_profile_is_cached_for_the_day(client, fake_db, fake_auth, monkeypatch):
    from app.services import study_coach_service as coach

    uid = "coach-cache"
    seed_profile(fake_db, uid)
    headers = _auth(fake_auth, uid)

    first = client.get("/api/coach/profile", headers=headers).json()
    assert first["cached"] is False

    calls = {"n": 0}
    real = coach._read_health

    def _counting(uid_arg):
        calls["n"] += 1
        return real(uid_arg)

    monkeypatch.setattr(coach, "_read_health", _counting)
    second = client.get("/api/coach/profile", headers=headers).json()

    assert second["cached"] is True
    assert calls["n"] == 0, "a same-day read must not rebuild the profile"

    forced = client.get("/api/coach/profile?force=true", headers=headers).json()
    assert forced["cached"] is False
    assert calls["n"] == 1


def test_profile_does_not_write_a_health_snapshot(client, fake_db, fake_auth):
    """Advice must not double as a scoring run (Phase 2 owns the snapshots)."""
    uid = "coach-nosnap"
    seed_profile(fake_db, uid)
    _seed_quiz(fake_db, uid, "q1", 40, {"Optics": 40})
    _seed_focus(fake_db, uid, "f0", minutes=30)

    client.get("/api/coach/profile", headers=_auth(fake_auth, uid))

    stored = fake_db._collections.get(f"users/{uid}/health_history", {})
    assert not stored, "building a profile must not persist a health_history row"


def test_profile_assembles_weak_strong_focus_and_readiness(
    client, fake_db, fake_auth
):
    uid = "coach-full"
    seed_profile(fake_db, uid)
    _seed_quiz(fake_db, uid, "q1", 35, {"Optics": 35})
    _seed_quiz(fake_db, uid, "q2", 92, {"Mechanics": 92})
    _seed_focus(fake_db, uid, "f0", minutes=45)
    _seed_focus(fake_db, uid, "f1", days_ago=1, minutes=25)
    _seed_mistake(fake_db, uid, "m1", "Optics", occurrences=3, due=True)
    _seed_exam(fake_db, uid, "s1", in_days=5)

    body = client.get("/api/coach/profile", headers=_auth(fake_auth, uid)).json()

    assert body["hasData"] is True
    assert body["healthScore"] > 0

    optics = next(t for t in body["weakTopics"] if t["topic"] == "Optics")
    assert optics["quizAverage"] == 35
    assert optics["mistakes"] == 1
    assert optics["repeated"] == 1
    assert optics["due"] == 1

    assert [t["topic"] for t in body["strongTopics"]] == ["Mechanics"]
    assert body["strongTopics"][0]["averageScore"] == 92

    # 45 min today + 25 min yesterday = 70 minutes over 2 study days.
    assert body["averageFocusTime"] == 35
    assert body["studyPattern"]["weekMinutes"] == 70
    assert body["studyPattern"]["averageFocusScore"] == 88

    assert isinstance(body["examReadiness"], int)
    assert body["upcomingExam"]["daysRemaining"] == 5
    assert body["upcomingExam"]["title"] == "Physics Final"
    assert body["totalMistakes"] == 1
    assert body["repeatedMistakes"] == 1
    assert body["revisionDue"] == 1


# ---------------------------------------------------------------------------
# 2. weakness analysis
# ---------------------------------------------------------------------------


def _priority(profile: dict, topic: str) -> dict:
    from app.services import study_coach_service as coach

    analysis = coach.weakness_analysis("unused", profile=profile)
    for item in analysis["priorities"]:
        if item["topic"] == topic:
            return item
    raise AssertionError(f"{topic} missing from {analysis['priorities']}")


def test_repeated_mistake_with_a_near_exam_is_high(client, fake_db, fake_auth):
    uid = "coach-high"
    seed_profile(fake_db, uid)
    _seed_quiz(fake_db, uid, "q1", 45, {"Optics": 45})
    _seed_mistake(fake_db, uid, "m1", "Optics", occurrences=4, due=True)
    _seed_exam(fake_db, uid, "s1", in_days=4)

    from app.services import study_coach_service as coach

    profile = coach.build_learning_profile(uid)
    item = _priority(profile, "Optics")

    assert item["priority"] == "high"
    assert "exam in 4 day(s)" in item["reasons"]
    assert item["repeated"] == 1
    assert item["due"] == 1


def test_repeated_mistake_without_an_exam_is_medium(client, fake_db, fake_auth):
    uid = "coach-medium"
    seed_profile(fake_db, uid)
    # Above the weak bar (so no exam is needed to justify today) but below the
    # strong floor, so the topic stays on the list.
    _seed_quiz(fake_db, uid, "q1", 65, {"Optics": 65})
    _seed_mistake(fake_db, uid, "m1", "Optics", occurrences=3)

    from app.services import study_coach_service as coach

    item = _priority(coach.build_learning_profile(uid), "Optics")
    assert item["priority"] == "medium"
    assert item["quizAverage"] == 65
    assert item["occurrences"] == 3


def test_low_quiz_score_without_mistakes_is_medium(client, fake_db, fake_auth):
    uid = "coach-lowscore"
    seed_profile(fake_db, uid)
    _seed_quiz(fake_db, uid, "q1", 30, {"Integration": 30})

    from app.services import study_coach_service as coach

    item = _priority(coach.build_learning_profile(uid), "Integration")
    assert item["priority"] == "medium"
    assert item["mistakes"] == 0
    assert any("quiz average 30%" in reason for reason in item["reasons"])


def test_improved_old_gap_is_low(client, fake_db, fake_auth):
    uid = "coach-low"
    seed_profile(fake_db, uid)
    # Above the weak bar on quizzes, one stale recorded mistake: keep it on
    # the list, do not spend today on it.
    _seed_quiz(fake_db, uid, "q1", 65, {"Thermodynamics": 65})
    _seed_mistake(fake_db, uid, "m1", "Thermodynamics", occurrences=1)

    from app.services import study_coach_service as coach

    item = _priority(coach.build_learning_profile(uid), "Thermodynamics")
    assert item["priority"] == "low"


def test_strong_topic_is_never_prioritised(client, fake_db, fake_auth):
    uid = "coach-strong"
    seed_profile(fake_db, uid)
    _seed_quiz(fake_db, uid, "q1", 95, {"Mechanics": 95})
    _seed_quiz(fake_db, uid, "q2", 40, {"Optics": 40})

    from app.services import study_coach_service as coach

    analysis = coach.weakness_analysis("unused", profile=coach.build_learning_profile(uid))
    topics = [item["topic"] for item in analysis["priorities"]]
    assert "Mechanics" not in topics
    assert "Optics" in topics
    assert analysis["medium"] + analysis["high"] + analysis["low"] == len(topics)


# ---------------------------------------------------------------------------
# 3. daily brief
# ---------------------------------------------------------------------------


def test_daily_brief_carries_greeting_priority_and_mission(
    client, fake_db, fake_auth
):
    uid = "coach-daily"
    seed_profile(fake_db, uid)
    _seed_quiz(fake_db, uid, "q1", 40, {"Optics": 40})
    _seed_mistake(fake_db, uid, "m1", "Optics", occurrences=3, due=True)
    _seed_focus(fake_db, uid, "f0", minutes=30)

    body = client.get("/api/coach/daily", headers=_auth(fake_auth, uid)).json()

    assert body["greetingKey"] in {"morning", "afternoon", "evening"}
    assert body["hasData"] is True
    assert body["healthScore"] > 0

    assert body["priority"]["topic"] == "Optics"
    assert "weakest topic" in body["why"]
    assert "recent mistakes" in body["why"]

    keys = [step["key"] for step in body["mission"]]
    assert keys == ["review", "quiz", "focus"]
    assert body["missionCount"] == 3
    assert body["mission"][0]["title"] == "Review Optics"
    assert body["mission"][1]["title"] == "Solve 15 MCQ on Optics"
    assert body["mission"][2]["minutes"] == 25

    # Persisted for the day so chat and the Home card read a cache.
    stored = fake_db._collections.get(f"users/{uid}/daily_coach_recommendations", {})
    assert body["dayKey"] in stored


def test_daily_brief_is_cached_per_day(client, fake_db, fake_auth):
    uid = "coach-daily-cache"
    seed_profile(fake_db, uid)
    headers = _auth(fake_auth, uid)

    first = client.get("/api/coach/daily", headers=headers).json()
    assert first["cached"] is False

    second = client.get("/api/coach/daily", headers=headers).json()
    assert second["cached"] is True
    assert second["dayKey"] == first["dayKey"]

    forced = client.get("/api/coach/daily?force=true", headers=headers).json()
    assert forced["cached"] is False


def test_daily_mission_keeps_the_focus_step_without_any_signal(
    client, fake_db, fake_auth
):
    uid = "coach-daily-blank"
    seed_profile(fake_db, uid)

    body = client.get("/api/coach/daily", headers=_auth(fake_auth, uid)).json()

    assert body["priority"] is None
    assert body["exam"] is None
    assert [step["key"] for step in body["mission"]] == ["focus"]
    assert "Take one quiz today" in body["why"]


def test_rescue_step_joins_the_mission_in_the_final_week(
    client, fake_db, fake_auth
):
    uid = "coach-daily-rescue"
    seed_profile(fake_db, uid)
    _seed_quiz(fake_db, uid, "q1", 40, {"Optics": 40})
    _seed_mistake(fake_db, uid, "m1", "Optics", occurrences=3)
    _seed_exam(fake_db, uid, "s1", in_days=3)

    body = client.get("/api/coach/daily", headers=_auth(fake_auth, uid)).json()

    keys = [step["key"] for step in body["mission"]]
    assert keys == ["rescue", "review", "quiz", "focus"]
    assert body["mission"][0]["title"] == "Follow today's Exam Rescue plan"
    assert body["mission"][0]["minutes"] == 90
    # Exam close → the drill is the heavier set, and the list stays capped.
    assert body["mission"][2]["title"] == "Solve 20 MCQ on Optics"
    assert body["missionCount"] == 4
    assert body["exam"]["daysRemaining"] == 3


def test_daily_endpoint_serves_what_the_cache_holds(client, fake_db, fake_auth):
    uid = "coach-daily-seed"
    seed_profile(fake_db, uid)
    headers = _auth(fake_auth, uid)

    live = client.get("/api/coach/daily", headers=headers).json()
    fake_db.seed(
        f"users/{uid}/daily_coach_recommendations",
        live["dayKey"],
        {**live, "why": "edited by hand"},
    )

    cached = client.get("/api/coach/daily", headers=headers).json()
    assert cached["why"] == "edited by hand"
    assert cached["cached"] is True


# ---------------------------------------------------------------------------
# 4. weekly report
# ---------------------------------------------------------------------------


def _week_key() -> str:
    today = _now().date()
    iso = today.isocalendar()
    return f"{iso.year}-W{iso.week:02d}"


def test_weekly_report_summarises_the_window(client, fake_db, fake_auth):
    uid = "coach-week"
    seed_profile(fake_db, uid)
    _seed_quiz(fake_db, uid, "q1", 40, {"Organic Chemistry": 40})
    _seed_focus(fake_db, uid, "f0", minutes=120)
    _seed_focus(fake_db, uid, "f1", days_ago=2, minutes=60)
    _seed_mistake(fake_db, uid, "m1", "Organic Chemistry", occurrences=2)

    body = client.get("/api/coach/weekly-report", headers=_auth(fake_auth, uid)).json()

    assert body["weekKey"] == _week_key()
    assert body["studyMinutes"] == 180
    assert body["studyDays"] == 2
    assert body["weakArea"] == "Organic Chemistry"
    assert body["weakReason"] == "1 mistake(s) recorded"
    assert body["recommendation"] == "Spend the next 3 days revising Organic Chemistry."
    assert body["narrative"]
    assert body["cached"] is False

    stored = fake_db._collections.get(f"users/{uid}/weekly_reports", {})
    assert _week_key() in stored


def test_weekly_report_is_cached_per_iso_week(client, fake_db, fake_auth):
    uid = "coach-week-cache"
    seed_profile(fake_db, uid)
    headers = _auth(fake_auth, uid)

    first = client.get("/api/coach/weekly-report", headers=headers).json()
    assert first["cached"] is False

    second = client.get("/api/coach/weekly-report", headers=headers).json()
    assert second["cached"] is True
    assert second["weekKey"] == first["weekKey"]

    forced = client.get("/api/coach/weekly-report?force=true", headers=headers).json()
    assert forced["cached"] is False


def test_weekly_report_counts_score_delta_from_health_history(
    client, fake_db, fake_auth
):
    uid = "coach-week-delta"
    seed_profile(fake_db, uid)
    _seed_quiz(fake_db, uid, "q1", 40, {"Optics": 40})

    today = _now().date()
    for days_ago, score in ((5, 61), (1, 74)):
        fake_db.seed(
            f"users/{uid}/health_history",
            (today - timedelta(days=days_ago)).isoformat(),
            {
                "dayKey": (today - timedelta(days=days_ago)).isoformat(),
                "score": score,
                "grade": "good",
                "metrics": {"understanding": score},
            },
        )

    body = client.get("/api/coach/weekly-report", headers=_auth(fake_auth, uid)).json()

    assert body["previousScore"] == 61
    assert body["score"] == 74
    assert body["scoreDelta"] == 13
    assert any(
        item["key"] == "understanding" and item["delta"] == 13
        for item in body["improvement"]
    )


@pytest.mark.asyncio
async def test_weekly_report_uses_the_ai_narrative_when_available(
    client, fake_db, fake_auth, monkeypatch
):
    from unittest.mock import AsyncMock, patch

    uid = "coach-week-ai"
    seed_profile(fake_db, uid)
    _seed_quiz(fake_db, uid, "q1", 40, {"Optics": 40})
    _seed_focus(fake_db, uid, "f0", minutes=90)

    with patch(
        "app.services.ai_service.generate",
        new_callable=AsyncMock,
        return_value="You put in 1.5h and Optics is the gap to close next week.",
    ) as mocked:
        body = client.get(
            "/api/coach/weekly-report", headers=_auth(fake_auth, uid)
        ).json()

    assert mocked.await_count == 1
    assert body["aiGenerated"] is True
    assert body["narrative"].startswith("You put in 1.5h")
    assert body["cached"] is False


def test_weekly_report_falls_back_when_the_ai_call_explodes(
    client, fake_db, fake_auth
):
    from unittest.mock import AsyncMock, patch

    uid = "coach-week-ai-down"
    seed_profile(fake_db, uid)
    _seed_focus(fake_db, uid, "f0", minutes=60)

    with patch(
        "app.services.ai_service.generate",
        new_callable=AsyncMock,
        side_effect=RuntimeError("no quota left"),
    ):
        body = client.get(
            "/api/coach/weekly-report", headers=_auth(fake_auth, uid)
        ).json()

    assert body["aiGenerated"] is False
    assert body["narrative"]
    assert "no quota" not in body["narrative"]


# ---------------------------------------------------------------------------
# 5. recalculate
# ---------------------------------------------------------------------------


def test_recalculate_rebuilds_profile_and_mission(client, fake_db, fake_auth):
    uid = "coach-recalc"
    seed_profile(fake_db, uid)
    headers = _auth(fake_auth, uid)

    first = client.get("/api/coach/profile", headers=headers).json()
    assert first["cached"] is False  # first read builds today's profile
    assert client.get("/api/coach/profile", headers=headers).json()["cached"] is True
    assert client.get("/api/coach/daily", headers=headers).json()["cached"] is False

    body = client.post("/api/coach/recalculate", headers=headers).json()

    assert body["profile"]["cached"] is False
    assert body["daily"]["cached"] is False
    assert body["profile"]["dayKey"] == body["daily"]["dayKey"]
    assert "recalculatedAt" in body


# ---------------------------------------------------------------------------
# 6. Ziku chat context (Phase 4.5)
# ---------------------------------------------------------------------------


def test_chat_context_is_none_without_any_signal(client, fake_db, fake_auth):
    from app.services.study_coach_service import chat_context

    uid = "coach-chat-empty"
    seed_profile(fake_db, uid)

    assert chat_context(uid) is None


def test_chat_context_summarises_mission_exam_and_health(
    client, fake_db, fake_auth
):
    from app.services.study_coach_service import chat_context

    uid = "coach-chat"
    seed_profile(fake_db, uid)
    _seed_quiz(fake_db, uid, "q1", 40, {"Optics": 40})
    _seed_mistake(fake_db, uid, "m1", "Optics", occurrences=6)
    _seed_exam(fake_db, uid, "s1", in_days=5)

    line = chat_context(uid)

    assert line is not None
    assert line.startswith("Study coach:")
    assert "Academic Health" in line
    assert "today's focus is Optics" in line
    assert "6 mistake(s)" in line
    assert "Physics Final in 5 day(s)" in line
    assert line.endswith("step(s).")


def test_chat_context_reads_the_cache_first(client, fake_db, fake_auth, monkeypatch):
    from app.services import study_coach_service as coach

    uid = "coach-chat-cache"
    seed_profile(fake_db, uid)

    calls = {"n": 0}
    real = coach.daily_recommendation

    def _counting(uid_arg, **kwargs):
        calls["n"] += 1
        return real(uid_arg, **kwargs)

    monkeypatch.setattr(coach, "daily_recommendation", _counting)

    # Nothing to advise on yet: the first read builds (and caches) today's
    # brief, the second must be served straight from that cache.
    assert coach.chat_context(uid) is None
    assert coach.chat_context(uid) is None
    assert calls["n"] == 1, "the second read must come from the cache"


def test_ziku_prompt_includes_the_coach_line():
    from app.services.ai_service import build_chat_system_prompt

    prompt = build_chat_system_prompt()
    assert "Personalised plan" not in prompt
    assert "Never reply in Banglish" in prompt

    prompt = build_chat_system_prompt(
        coach_context="Study coach: today's focus is Optics."
    )
    assert "Personalised plan: Study coach: today's focus is Optics." in prompt
    assert "Never reply in Banglish" in prompt, "coach context must not displace policy"


@pytest.mark.asyncio
async def test_chat_generate_hands_the_coach_line_to_the_provider(
    client, fake_db, fake_auth
):
    from unittest.mock import AsyncMock, MagicMock, patch

    from app.services import ai_service as ai_service_module

    uid = "coach-chat-generate"
    seed_profile(fake_db, uid)
    _seed_quiz(fake_db, uid, "q1", 40, {"Optics": 40})
    _seed_mistake(fake_db, uid, "m1", "Optics", occurrences=3)
    _seed_exam(fake_db, uid, "s1", in_days=4)

    settings = MagicMock()
    settings.groq_api_key = "g-key"
    settings.gemini_api_key = ""
    settings.openrouter_api_key = ""

    with patch(
        "app.services.ai_service.get_settings", return_value=settings
    ), patch("app.services.ai_service._consume_quota"), patch(
        "app.services.ai_service._groq_chat",
        new_callable=AsyncMock,
        return_value="আগে substitution method দেখি, তারপর practice দিই।",
    ) as mock_chat:
        result = await ai_service_module.chat_generate(
            uid, [{"role": "user", "content": "explain integration"}]
        )

    assert mock_chat.await_count == 1
    _, system_prompt = mock_chat.await_args.args
    assert "Personalised plan:" in system_prompt
    assert "Study coach:" in system_prompt
    assert "Optics" in system_prompt
    assert result["reply"].startswith("আগে")
