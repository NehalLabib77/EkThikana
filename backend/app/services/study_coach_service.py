"""Phase 4 — the Study Coach: Ziku's proactive intelligence layer.

This module is deliberately an **aggregator**, not another analytics engine.
Everything it reports already exists somewhere else:

* **Academic Health** (``academic_health_service``) - the 0-100 score, the four
  metrics (Exam readiness is read straight out of them), the merged weak-area
  list, the focus/quiz/mistake/task signals. Always read with
  ``persist=False``: opening the coach must never double as a scoring run and
  write a ``health_history`` snapshot.
* **Mistake Memory** (``mistake_memory_service``) - repeated mistakes, the
  spaced-repetition queue and the priority topics Exam Rescue already uses.
* **Quiz mastery** (``weak_topic_service``) - strong/weak topic averages.
* **Exam Rescue** - the nearest active plan, already projected into
  ``signals["exam"]`` by Academic Health.
* **Real Exam Simulator** - ``signals["practiceExams"]``.

Nothing here recomputes a score, re-derives mastery or writes to any collection
another service owns. The only writes are this service's own three caches:

=============================== ===========================================
``learning_profiles``           one ``current`` doc per student, per day
``daily_coach_recommendations`` one doc per day (the mission)
``weekly_reports``              one doc per ISO week (the narrative)
=============================== ===========================================

Design rules:

* **Offline first.** The profile, the weakness tiers and the daily mission are
  pure rules over existing data - they work with no AI key and cost no quota.
  AI is used exactly once per student per week, for the weekly narrative, and
  falls back to a rule-based sentence when it fails.
* **Cache before compute.** Chat asks for context on every message, so
  :func:`chat_context` reads today's cache first and only builds when the day
  rolled over.
* **Never raise into a chat message.** Every read is wrapped: a broken reader
  degrades the advice, it does not take the assistant down.
"""

from __future__ import annotations

import logging
from datetime import date, datetime, timedelta, timezone
from typing import Any

from app.core.firebase import get_firestore
from app.services import academic_health_service as health
from app.services import mistake_memory_service as mistakes
from app.services import weak_topic_service

logger = logging.getLogger("gochano.study_coach")

PROFILE_COLLECTION = "learning_profiles"
DAILY_COLLECTION = "daily_coach_recommendations"
WEEKLY_COLLECTION = "weekly_reports"
CURRENT_PROFILE = "current"

# The window every "this week" number is measured over (Academic Health uses
# the same 7 days, so the coach and the score always agree).
WINDOW_DAYS = 7
# A topic becomes High priority only when it hurts *and* the exam is close.
EXAM_SOON_DAYS = 14
# Rescue tasks join the mission only in the last week before the exam.
RESCUE_SOON_DAYS = 7
# Mirrors weak_topic_service.DEFAULT_WEAK_THRESHOLD.
QUIZ_WEAK_THRESHOLD = 60
STRONG_TOPIC_FLOOR = 70

MAX_TOPICS = 6
MAX_MISSION_ITEMS = 4
MAX_REASONS = 3

GREETING_EN = {"morning": "Good Morning", "afternoon": "Good Afternoon", "evening": "Good Evening"}


# ---------------------------------------------------------------------------
# seams + small helpers
# ---------------------------------------------------------------------------


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _day_key(moment: datetime | date) -> str:
    if isinstance(moment, datetime):
        return moment.date().isoformat()
    return moment.isoformat()


def _week_key(moment: datetime | date) -> str:
    day = moment.date() if isinstance(moment, datetime) else moment
    iso = day.isocalendar()
    return f"{iso.year}-W{iso.week:02d}"


def _int(value: Any) -> int | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return int(round(value))
    if isinstance(value, str):
        try:
            return int(float(value.strip()))
        except (ValueError, AttributeError):
            return None
    return None


def _as_int(value: Any, default: int = 0) -> int:
    parsed = _int(value)
    return default if parsed is None else parsed


def _percent(value: Any) -> float | None:
    """One-decimal percentage (focus consistency and friends)."""
    if value is None or isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        return round(float(value), 1)
    if isinstance(value, str):
        try:
            return round(float(value.strip()), 1)
        except (ValueError, AttributeError):
            return None
    return None


def _text(value: Any, default: str = "") -> str:
    if value is None:
        return default
    return str(value).strip() or default


def _read_doc(uid: str, collection: str, doc_id: str) -> dict[str, Any] | None:
    """Best-effort read of one coach cache document (``None`` when absent)."""
    db = get_firestore()
    if db is None:
        return None
    try:
        snap = (
            db.collection("users")
            .document(uid)
            .collection(collection)
            .document(doc_id)
            .get()
        )
    except Exception as exc:  # pragma: no cover - defensive
        logger.debug("study coach: %s/%s unreadable (%s)", collection, doc_id, exc)
        return None
    if not getattr(snap, "exists", False):
        return None
    data = snap.to_dict() or {}
    return data or None


def _write_doc(uid: str, collection: str, doc_id: str, payload: dict[str, Any]) -> None:
    """Persist a coach cache document; a failed write never fails the answer."""
    db = get_firestore()
    if db is None:
        return
    try:
        (
            db.collection("users")
            .document(uid)
            .collection(collection)
            .document(doc_id)
            .set(payload)
        )
    except Exception as exc:  # pragma: no cover - defensive
        logger.warning("study coach: could not persist %s (%s)", collection, exc)


def _display_name(uid: str) -> str:
    db = get_firestore()
    if db is None:
        return ""
    try:
        snap = db.collection("users").document(uid).get()
        data = snap.to_dict() or {}
    except Exception as exc:  # pragma: no cover - defensive
        logger.debug("study coach: display name unavailable (%s)", exc)
        return ""
    return _text(data.get("displayName") or data.get("name"))


# ---------------------------------------------------------------------------
# reads of the systems this layer consumes
# ---------------------------------------------------------------------------


def _read_health(uid: str) -> dict[str, Any]:
    """Academic Health, read-only. Never persists a snapshot (``persist=False``)."""
    try:
        return health.get_academic_health(uid, persist=False)
    except Exception as exc:
        logger.debug("study coach: academic health unavailable (%s)", exc)
        return {}


def _read_brain(uid: str) -> dict[str, Any]:
    try:
        return mistakes.get_learning_brain(uid)
    except Exception as exc:
        logger.debug("study coach: learning brain unavailable (%s)", exc)
        return {}


def _read_summary(uid: str) -> dict[str, Any]:
    try:
        return weak_topic_service.get_learning_summary(uid)
    except Exception as exc:
        logger.debug("study coach: learning summary unavailable (%s)", exc)
        return {}


def _public_exam(exam: Any) -> dict[str, Any] | None:
    """The nearest active Exam Rescue plan, already normalised by Phase 2/3."""
    if not isinstance(exam, dict) or exam.get("exists") is False:
        return None
    title = _text(exam.get("title") or exam.get("examTitle"))
    days = _int(exam.get("daysRemaining"))
    if days is None or days < 0:
        return None
    return {
        "title": title,
        "examDate": _text(exam.get("examDate")),
        "daysRemaining": days,
        "dailyTargetMinutes": _as_int(exam.get("dailyTargetMinutes")),
        "sessionId": _text(exam.get("sessionId")),
    }


def _weak_topics(profile_health: dict[str, Any], brain: dict[str, Any]) -> list[dict[str, Any]]:
    """Weak topics as Academic Health ranks them, Learning Brain as the fallback.

    ``weakAreas`` already merges quiz mastery with recorded mistakes, so the
    coach must not rebuild that list - it only trims it to the fields the
    profile shows.
    """
    out: list[dict[str, Any]] = []
    for area in profile_health.get("weakAreas") or []:
        if not isinstance(area, dict):
            continue
        topic = _text(area.get("topic"))
        if not topic:
            continue
        out.append(
            {
                "topic": topic,
                "quizAverage": _int(area.get("quizAverage")),
                "mistakes": _as_int(area.get("mistakes")),
                # Total misses across repeats - "you got this wrong 6 times"
                # reads truer than "you have 1 wrong question on file".
                "occurrences": _as_int(area.get("occurrences")),
                "repeated": _as_int(area.get("repeated")),
                "due": _as_int(area.get("due")),
                "priority": _text(area.get("priority"), "medium"),
                "action": _text(area.get("action")),
            }
        )
        if len(out) >= MAX_TOPICS:
            return out

    # No health data yet (or the merge came back empty): the Learning Brain's
    # mistake-aware list is the same idea from the mistake side.
    for entry in brain.get("weakTopics") or []:
        if not isinstance(entry, dict):
            continue
        topic = _text(entry.get("topic"))
        if not topic:
            continue
        out.append(
            {
                "topic": topic,
                "quizAverage": _int(entry.get("averageScore")),
                "mistakes": _as_int(entry.get("mistakes")),
                "occurrences": _as_int(entry.get("mistakes")),
                "repeated": 0,
                "due": 0,
                "priority": "medium",
                "action": _text(entry.get("recommendation")),
            }
        )
        if len(out) >= MAX_TOPICS:
            break
    return out


# ---------------------------------------------------------------------------
# 1. student learning profile
# ---------------------------------------------------------------------------


def build_learning_profile(uid: str, *, force: bool = False) -> dict[str, Any]:
    """Who this student is as a learner, refreshed once per day.

    Cached at ``users/{uid}/learning_profiles/current``; ``force`` rebuilds it
    (used after a quiz or an exam, and by ``POST /api/coach/recalculate``).
    """
    now = _now()
    day_key = _day_key(now)

    if not force:
        cached = _read_doc(uid, PROFILE_COLLECTION, CURRENT_PROFILE)
        if cached and _text(cached.get("dayKey")) == day_key:
            return {**cached, "cached": True}

    health_payload = _read_health(uid)
    brain = _read_brain(uid)
    summary = _read_summary(uid)

    signals = health_payload.get("signals") or {}
    study = signals.get("study") or {}
    quizzes = signals.get("quizzes") or {}

    exam_readiness: int | None = None
    for metric in health_payload.get("metrics") or []:
        if isinstance(metric, dict) and metric.get("key") == "examReadiness":
            exam_readiness = _int(metric.get("score"))
            break

    week_minutes = _as_int(study.get("weekMinutes"))
    study_days = _as_int(study.get("studyDays"))
    # Minutes of deep work per study day - the number the profile reports as
    # average focus time. Falls back to a 7-day average so the field is never
    # silently wrong for a student who only studied yesterday.
    if study_days > 0:
        average_focus = int(round(week_minutes / study_days))
    else:
        average_focus = int(round(week_minutes / WINDOW_DAYS))

    strong_topics: list[dict[str, Any]] = []
    for entry in summary.get("strong_topics") or []:
        if not isinstance(entry, dict):
            continue
        topic = _text(entry.get("topic"))
        if not topic:
            continue
        strong_topics.append(
            {
                "topic": topic,
                "averageScore": _int(entry.get("average_score")),
                "attempts": _as_int(entry.get("attempts")),
            }
        )
        if len(strong_topics) >= MAX_TOPICS:
            break

    profile: dict[str, Any] = {
        "student": _display_name(uid),
        "dayKey": day_key,
        "hasData": bool(health_payload.get("hasData")),
        "healthScore": _as_int(health_payload.get("score")),
        "healthGrade": _text(health_payload.get("grade")),
        "healthHeadline": _text(health_payload.get("headline")),
        "trend": health_payload.get("trend"),
        "weakTopics": _weak_topics(health_payload, brain),
        "strongTopics": strong_topics,
        "repeatedMistakes": _as_int(brain.get("repeatedCount")),
        "revisionDue": _as_int(brain.get("revisionDueCount")),
        "totalMistakes": _as_int(brain.get("totalMistakes")),
        "quizAverage": _as_int(quizzes.get("recentAverage")),
        "averageFocusTime": average_focus,
        "studyPattern": {
            "weekMinutes": week_minutes,
            "studyDays": study_days,
            "todayMinutes": _as_int(study.get("todayMinutes")),
            "averageFocusScore": _int(study.get("averageFocusScore")),
            "bySubjectMinutes": study.get("bySubjectMinutes") or {},
            # Phase 5 - Ziku Focus Engine signals (Academic Health collects
            # them from the same focus_sessions rows): share of the last 7
            # days with a finished session, average session depth, and the
            # 7-day minute trend ({"2026-10-01": 45, ...}).
            "focusConsistency": _percent(study.get("focusConsistencyPct")),
            "averageSessionMinutes": _int(study.get("averageSessionMinutes")),
            "focusTrend7": study.get("dailyMinutes") or {},
        },
        "examReadiness": exam_readiness,
        "upcomingExam": _public_exam(signals.get("exam")),
        "practiceExams": signals.get("practiceExams"),
        "generatedAt": now,
    }

    _write_doc(uid, PROFILE_COLLECTION, CURRENT_PROFILE, profile)
    return {**profile, "cached": False}


# ---------------------------------------------------------------------------
# 2. weakness analysis
# ---------------------------------------------------------------------------


def weakness_analysis(
    uid: str, *, profile: dict[str, Any] | None = None
) -> dict[str, Any]:
    """Rank weak topics into High / Medium / Low urgency.

    The tiers are the Phase 4 spec, expressed as one readable rule:

    * **high** - a repeated mistake *or* an overdue revision **and** an exam
      inside :data:`EXAM_SOON_DAYS`. (Repeated mistakes + upcoming exam.)
    * **medium** - a repeated/overdue gap without a near exam, or a quiz
      average below :data:`QUIZ_WEAK_THRESHOLD`.
    * **low** - an old gap that is no longer repeating and no longer scoring
      badly: worth keeping on the list, not worth today.

    A topic the quiz engine calls strong never outranks a live gap, so strong
    topics are filtered out first.
    """
    if profile is None:
        profile = build_learning_profile(uid)

    exam = profile.get("upcomingExam") or {}
    exam_days = _int(exam.get("daysRemaining"))
    strong = {t["topic"].lower() for t in profile.get("strongTopics") or []}

    rank = {"high": 0, "medium": 1, "low": 2}
    items: list[dict[str, Any]] = []

    for topic_entry in profile.get("weakTopics") or []:
        if not isinstance(topic_entry, dict):
            continue
        topic = _text(topic_entry.get("topic"))
        if not topic or topic.lower() in strong:
            continue

        repeated = _as_int(topic_entry.get("repeated"))
        due = _as_int(topic_entry.get("due"))
        mistakes_count = _as_int(topic_entry.get("mistakes"))
        occurrences = _as_int(topic_entry.get("occurrences"))
        quiz_average = _int(topic_entry.get("quizAverage"))

        urgent = repeated > 0 or due > 0
        exam_soon = exam_days is not None and exam_days <= EXAM_SOON_DAYS
        low_score = quiz_average is not None and quiz_average < QUIZ_WEAK_THRESHOLD

        reasons: list[str] = []
        # Ordered by how much the advice depends on it: the exam countdown
        # decides the tier, then the evidence, then the score.
        if exam_soon and exam_days is not None:
            reasons.append(f"exam in {exam_days} day(s)")
        if repeated:
            reasons.append(f"{repeated} repeated mistake(s)")
        if due:
            reasons.append(f"{due} revision(s) overdue")
        recorded = occurrences or mistakes_count
        if recorded:
            reasons.append(f"{recorded} mistake(s) recorded")
        if low_score and quiz_average is not None:
            reasons.append(f"quiz average {quiz_average}%")

        if urgent and exam_soon:
            priority = "high"
        elif urgent or low_score:
            priority = "medium"
        else:
            priority = "low"
            if not reasons:
                reasons.append("old mistakes, currently improving")

        items.append(
            {
                "topic": topic,
                "priority": priority,
                "reasons": reasons[:MAX_REASONS],
                "mistakes": mistakes_count,
                "occurrences": occurrences,
                "repeated": repeated,
                "due": due,
                "quizAverage": quiz_average,
                "daysToExam": exam_days,
                "action": _text(topic_entry.get("action")),
            }
        )

    items.sort(key=lambda item: (rank.get(item["priority"], 3), item["topic"].lower()))

    return {
        "priorities": items,
        "high": sum(1 for i in items if i["priority"] == "high"),
        "medium": sum(1 for i in items if i["priority"] == "medium"),
        "low": sum(1 for i in items if i["priority"] == "low"),
        "examDaysRemaining": exam_days,
        "generatedAt": _now(),
    }


# ---------------------------------------------------------------------------
# 3. daily recommendation
# ---------------------------------------------------------------------------


def _greeting(moment: datetime) -> tuple[str, str]:
    """(key, english) greeting for the hour the brief is read (UTC)."""
    hour = moment.hour
    if hour < 12:
        key = "morning"
    elif hour < 18:
        key = "afternoon"
    else:
        key = "evening"
    return key, GREETING_EN[key]


def _mission_item(
    key: str,
    action: str,
    title: str,
    detail: str,
    minutes: int,
    **extra: Any,
) -> dict[str, Any]:
    item = {
        "key": key,
        "action": action,
        "title": title,
        "detail": detail,
        "minutes": minutes,
    }
    item.update(extra)
    return item


def daily_recommendation(uid: str, *, force: bool = False) -> dict[str, Any]:
    """Today's study mission - rule based, offline safe, cached for the day.

    The mission is at most :data:`MAX_MISSION_ITEMS` steps: review the top
    gap, drill it, put a focus block on it, and - only in the last week before
    an exam - follow the Exam Rescue plan that already owns the calendar.
    """
    now = _now()
    day_key = _day_key(now)

    if not force:
        cached = _read_doc(uid, DAILY_COLLECTION, day_key)
        if cached:
            return {**cached, "cached": True}

    profile = build_learning_profile(uid, force=force)
    analysis = weakness_analysis(uid, profile=profile)
    priorities = analysis["priorities"]
    exam = profile.get("upcomingExam")
    exam_days = _int((exam or {}).get("daysRemaining"))
    pattern = profile.get("studyPattern") or {}

    mission: list[dict[str, Any]] = []
    priority_payload: dict[str, Any] | None = None

    if priorities:
        top = priorities[0]
        topic = top["topic"]
        misses = _as_int(top.get("occurrences")) or _as_int(top.get("mistakes"))
        why = (
            f"{topic} is your weakest topic based on recent mistakes."
            if misses
            else (
                f"{topic} needs attention - your quiz average there is "
                f"{top.get('quizAverage')}%."
                if top.get("quizAverage") is not None
                else f"{topic} needs a review before your next quiz."
            )
        )
        priority_payload = {
            "topic": topic,
            "priority": top["priority"],
            "why": why,
            "reasons": top["reasons"],
            "mistakes": top["mistakes"],
            "occurrences": top.get("occurrences", 0),
            "repeated": top["repeated"],
            "due": top["due"],
            "quizAverage": top["quizAverage"],
        }

        if exam and _text(exam.get("sessionId")) and (
            exam_days is not None and exam_days <= RESCUE_SOON_DAYS
        ):
            mission.append(
                _mission_item(
                    "rescue",
                    "rescue",
                    "Follow today's Exam Rescue plan",
                    f"{_text(exam.get('title')) or 'Your exam'} is "
                    f"{exam_days} day(s) away - stick to the rescue schedule.",
                    _as_int(exam.get("dailyTargetMinutes"), 30) or 30,
                    target=topic,
                    priority=top["priority"],
                )
            )

        count = 20 if (exam_days is not None and exam_days <= RESCUE_SOON_DAYS) else 15
        mission.append(
            _mission_item(
                "review",
                "review",
                f"Review {topic}",
                top.get("action") or "Re-read the concept you missed, then redo the question.",
                20,
                target=topic,
                priority=top["priority"],
            )
        )
        mission.append(
            _mission_item(
                "quiz",
                "quiz",
                f"Solve {count} MCQ on {topic}",
                "One short set is enough - accuracy matters more than volume today.",
                25,
                count=count,
                target=topic,
                priority=top["priority"],
            )
        )
    else:
        priority_payload = None

    mission.append(
        _mission_item(
            "focus",
            "focus",
            "Complete a 25 minute focus session",
            "No interruptions - one block, one subject.",
            25,
        )
    )
    mission = mission[:MAX_MISSION_ITEMS]

    if not priority_payload:
        why = (
            "No urgent gaps today - keep the streak going with a focus session."
            if profile.get("hasData")
            else "Take one quiz today so the coach can see where you stand."
        )

    greeting_key, greeting_text = _greeting(now)
    payload: dict[str, Any] = {
        "dayKey": day_key,
        "greetingKey": greeting_key,
        "greeting": greeting_text,
        "healthScore": _as_int(profile.get("healthScore")),
        "hasData": bool(profile.get("hasData")),
        "priority": priority_payload,
        "why": priority_payload["why"] if priority_payload else why,
        "mission": mission,
        "missionCount": len(mission),
        "exam": (
            {
                "title": exam.get("title"),
                "examDate": exam.get("examDate"),
                "daysRemaining": exam_days,
            }
            if exam
            else None
        ),
        "generatedAt": now,
        # Phase 5 - focus state, so the dashboard and Ziku's chat context can
        # talk about deep work without a second profile read.
        "focus": {
            "consistency": _percent(pattern.get("focusConsistency")),
            "averageSessionMinutes": _int(pattern.get("averageSessionMinutes")),
            "todayMinutes": _as_int(pattern.get("todayMinutes")),
            "weekMinutes": _as_int(pattern.get("weekMinutes")),
        },
    }

    _write_doc(uid, DAILY_COLLECTION, day_key, payload)
    return {**payload, "cached": False}


# ---------------------------------------------------------------------------
# 4. weekly academic report
# ---------------------------------------------------------------------------


def _metric_deltas(entries: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """First-vs-last movement per Academic Health metric over the window."""
    scored: dict[str, list[int]] = {}
    labels: dict[str, str] = {}
    for entry in entries:
        metrics = entry.get("metrics") or {}
        if not isinstance(metrics, dict):
            continue
        for key, value in metrics.items():
            parsed = _int(value)
            if parsed is None:
                continue
            scored.setdefault(key, []).append(parsed)
            labels[key] = key

    out: list[dict[str, Any]] = []
    for key, values in scored.items():
        if len(values) < 2:
            continue
        delta = values[-1] - values[0]
        if delta == 0:
            continue
        out.append(
            {
                "key": key,
                "label": health.METRIC_LABELS.get(key, labels[key]),
                "delta": delta,
                "first": values[0],
                "last": values[-1],
            }
        )
    out.sort(key=lambda item: -abs(item["delta"]))
    return out


def _weekly_facts(uid: str) -> dict[str, Any]:
    profile = build_learning_profile(uid)
    try:
        history = health.get_history(uid, days=WINDOW_DAYS)
    except Exception as exc:  # pragma: no cover - defensive
        logger.debug("study coach: health history unavailable (%s)", exc)
        history = {}

    points = [
        p
        for p in (history.get("history") or [])
        if isinstance(p, dict) and _int(p.get("score")) is not None
    ]
    scores = [_as_int(p.get("score")) for p in points]

    previous_score: int | None = scores[-2] if len(scores) >= 2 else None
    current_score = scores[-1] if scores else (
        _as_int(profile.get("healthScore")) if profile.get("hasData") else None
    )
    score_delta: int | None = (
        current_score - previous_score
        if current_score is not None and previous_score is not None
        else None
    )

    weak_topics = profile.get("weakTopics") or []
    strong_topics = profile.get("strongTopics") or []
    weak_topic = weak_topics[0] if weak_topics else None
    strong_topic = strong_topics[0] if strong_topics else None

    by_subject: dict[str, int] = {}
    pattern = profile.get("studyPattern") or {}
    for subject, minutes in (pattern.get("bySubjectMinutes") or {}).items():
        name = _text(subject)
        if name:
            by_subject[name] = _as_int(minutes)

    if weak_topic:
        weak_area = _text(weak_topic.get("topic"))
        weak_reason = (
            f"{_as_int(weak_topic.get('mistakes'))} mistake(s) recorded"
            if _as_int(weak_topic.get("mistakes"))
            else (
                f"quiz average {_as_int(weak_topic.get('quizAverage'))}%"
                if weak_topic.get("quizAverage") is not None
                else "below the mastery bar"
            )
        )
    elif by_subject:
        weak_area = min(by_subject, key=lambda k: by_subject[k])
        weak_reason = "least focused subject this week"
    else:
        weak_area = ""
        weak_reason = ""

    recommendation = (
        f"Spend the next 3 days revising {weak_area}."
        if weak_area
        else "Log a quiz or a mistake so next week's report has something to measure."
    )

    return {
        "profile": profile,
        "score": current_score,
        "previousScore": previous_score,
        "scoreDelta": score_delta,
        "improvement": _metric_deltas(history.get("history") or []),
        "weakArea": weak_area,
        "weakReason": weak_reason,
        "strongArea": _text(strong_topic.get("topic")) if strong_topic else "",
        "studyMinutes": _as_int(pattern.get("weekMinutes")),
        "studyDays": _as_int(pattern.get("studyDays")),
        "focusScore": _int(pattern.get("averageFocusScore")),
        # Phase 5 - focus engine signals for the narrative and the coach chat.
        "focusConsistency": _percent(pattern.get("focusConsistency")),
        "averageSessionMinutes": _int(pattern.get("averageSessionMinutes")),
        "focusTrend7": pattern.get("focusTrend7") or {},
        "mistakes": _as_int(profile.get("totalMistakes")),
        "repeatedMistakes": _as_int(profile.get("repeatedMistakes")),
        "revisionDue": _as_int(profile.get("revisionDue")),
        "quizAverage": _as_int(profile.get("quizAverage")),
        "practiceExams": profile.get("practiceExams") or {},
        "recommendation": recommendation,
    }


def _fallback_narrative(facts: dict[str, Any]) -> str:
    hours = int(round(_as_int(facts["studyMinutes"]) / 60))
    parts = [f"You studied {hours}h this week."]
    if facts["score"] is not None:
        if facts["scoreDelta"] is not None:
            direction = "up" if facts["scoreDelta"] >= 0 else "down"
            parts.append(
                f"Academic Health {direction} {abs(facts['scoreDelta'])} point(s) "
                f"to {facts['score']}."
            )
        else:
            parts.append(f"Academic Health is at {facts['score']}.")
    consistency = facts.get("focusConsistency")
    if consistency is not None:
        line = f"Focus consistency {consistency}% of the last 7 days"
        average = facts.get("averageSessionMinutes")
        if average:
            line += f", {average} min per session"
        parts.append(line + ".")
    if facts["strongArea"]:
        parts.append(f"Strongest area: {facts['strongArea']}.")
    if facts["weakArea"]:
        parts.append(f"Weak area: {facts['weakArea']}.")
    parts.append(facts["recommendation"])
    return " ".join(parts)


async def _ai_narrative(uid: str, facts: dict[str, Any]) -> str | None:
    """One short AI paragraph per student per week; ``None`` when unavailable."""
    try:
        from app.services.ai_service import AiFeature, generate
    except Exception as exc:  # pragma: no cover - defensive
        logger.debug("study coach: ai_service unavailable (%s)", exc)
        return None

    # Phase 5 - only name focus numbers the student actually produced.
    focus_line = ""
    consistency = facts.get("focusConsistency")
    if consistency is not None:
        focus_line = (
            f"- Focus: {consistency}% consistency over the last 7 days, "
            f"{facts.get('averageSessionMinutes') or 0} min per session\n"
        )

    prompt = (
        "Write a 2-3 sentence weekly study report for a university student. "
        "Warm, specific, no headings, no lists, no invented facts. "
        "Use only these numbers.\n"
        f"- Study time: {facts['studyMinutes']} minutes over "
        f"{facts['studyDays']} day(s)\n"
        f"{focus_line}"
        f"- Academic Health: {facts['score']} "
        f"(previous {facts['previousScore']}, delta {facts['scoreDelta']})\n"
        f"- Metric movement: {facts['improvement']}\n"
        f"- Quiz average: {facts['quizAverage']}\n"
        f"- Recorded mistakes: {facts['mistakes']} "
        f"(repeated {facts['repeatedMistakes']}, due {facts['revisionDue']})\n"
        f"- Strongest topic: {facts['strongArea'] or 'unknown'}\n"
        f"- Weakest topic: {facts['weakArea'] or 'unknown'} "
        f"({facts['weakReason']})\n"
        f"- Recommendation to repeat: {facts['recommendation']}"
    )

    try:
        text = await generate(uid, prompt, feature=AiFeature.CHAT)
    except Exception as exc:
        logger.info("study coach: weekly narrative unavailable (%s)", exc)
        return None
    cleaned = _text(text)
    return cleaned or None


async def weekly_report(uid: str, *, force: bool = False) -> dict[str, Any]:
    """Seven-day summary: time, movement, weak area, one recommendation.

    Cached per ISO week at ``users/{uid}/weekly_reports/{weekKey}``. The AI
    paragraph is the only quota spend in this module and is attempted once per
    week; a failed call caches the rule-based narrative instead of retrying on
    every open (``force=True`` retries).
    """
    now = _now()
    week_key = _week_key(now)

    if not force:
        cached = _read_doc(uid, WEEKLY_COLLECTION, week_key)
        if cached:
            return {**cached, "cached": True}

    facts = _weekly_facts(uid)
    narrative = await _ai_narrative(uid, facts)
    ai_generated = bool(narrative)
    if not narrative:
        narrative = _fallback_narrative(facts)

    payload: dict[str, Any] = {
        "weekKey": week_key,
        "weekStart": _day_key(now.date() - timedelta(days=now.date().weekday())),
        "studyMinutes": facts["studyMinutes"],
        "studyDays": facts["studyDays"],
        "score": facts["score"],
        "previousScore": facts["previousScore"],
        "scoreDelta": facts["scoreDelta"],
        "improvement": facts["improvement"],
        "strongArea": facts["strongArea"],
        "weakArea": facts["weakArea"],
        "weakReason": facts["weakReason"],
        "focusScore": facts["focusScore"],
        # Phase 5 - focus engine signals on the weekly report payload.
        "focusConsistency": facts.get("focusConsistency"),
        "averageSessionMinutes": facts.get("averageSessionMinutes"),
        "focusTrend7": facts.get("focusTrend7") or {},
        "quizAverage": facts["quizAverage"],
        "mistakes": facts["mistakes"],
        "repeatedMistakes": facts["repeatedMistakes"],
        "revisionDue": facts["revisionDue"],
        "practiceExams": facts["practiceExams"],
        "recommendation": facts["recommendation"],
        "narrative": narrative,
        "aiGenerated": ai_generated,
        "cached": False,
        "generatedAt": now,
    }

    _write_doc(uid, WEEKLY_COLLECTION, week_key, payload)
    return payload


# ---------------------------------------------------------------------------
# 5. recalculate + Ziku chat context
# ---------------------------------------------------------------------------


def recalculate(uid: str) -> dict[str, Any]:
    """Force-rebuild today's analysis (called after a quiz, exam or rescue edit)."""
    profile = build_learning_profile(uid, force=True)
    daily = daily_recommendation(uid, force=True)
    return {
        "profile": profile,
        "daily": daily,
        "recalculatedAt": _now(),
    }


def chat_context(uid: str) -> str | None:
    """One sentence of coaching state for Ziku's system prompt.

    Cache-first: chat runs on every message, so this reads today's brief when
    it exists and only builds (and then caches) after the day rolls over.
    Read-only and defensive - a failure returns ``None`` and the assistant
    simply answers without coach context.
    """
    try:
        day_key = _day_key(_now())
        brief = _read_doc(uid, DAILY_COLLECTION, day_key)
        if brief is None:
            brief = daily_recommendation(uid)
        if not brief:
            return None
        # A student with no signal at all gets no line: "mission has 1 step"
        # without a reason to believe it would be noise in every message.
        if not brief.get("hasData") and not isinstance(brief.get("priority"), dict):
            return None

        parts: list[str] = []
        score = _int(brief.get("healthScore"))
        if brief.get("hasData") and score is not None:
            parts.append(f"Academic Health {score}/100")

        # Phase 5 - how this week's deep work looks (only when the student
        # has actually logged a session).
        focus = brief.get("focus")
        if isinstance(focus, dict):
            consistency = focus.get("consistency")
            if consistency is not None:
                line = f"focus consistency {consistency}% of the last 7 days"
                average = focus.get("averageSessionMinutes")
                if average:
                    line += f", {average} min per session"
                parts.append(line)

        priority = brief.get("priority")
        if isinstance(priority, dict) and _text(priority.get("topic")):
            topic = priority["topic"]
            bits: list[str] = []
            repeated = _int(priority.get("repeated")) or 0
            misses = (
                _int(priority.get("occurrences"))
                or _int(priority.get("mistakes"))
                or 0
            )
            if misses:
                bits.append(
                    f"{misses} mistake(s)" + (f", {repeated} repeated" if repeated else "")
                )
            quiz_average = _int(priority.get("quizAverage"))
            if quiz_average is not None:
                bits.append(f"quiz average {quiz_average}%")
            suffix = f" ({', '.join(bits)})" if bits else ""
            parts.append(f"today's focus is {topic}{suffix}")

        exam = brief.get("exam")
        if isinstance(exam, dict) and _int(exam.get("daysRemaining")) is not None:
            title = _text(exam.get("title")) or "upcoming exam"
            parts.append(f"{title} in {exam['daysRemaining']} day(s)")

        # Phase 7 - one sentence about the student's study group, straight
        # out of the Learning Community. Read-only and defensive: no group
        # with a hot topic simply adds nothing.
        try:
            from app.services.community_service import group_trend_line

            trend = group_trend_line(uid)
        except Exception as exc:  # pragma: no cover - defensive
            logger.debug("community trend unavailable in coach (%s)", exc)
            trend = None
        if trend:
            parts.append(trend)

        # Phase 8 - the Personal OS layer: one cache-only line about today's
        # next best action and anything just earned. Read-only and defensive:
        # a student with nothing cached simply adds nothing, and the line is
        # inserted before the mission clause so the prompt still ends on
        # "mission has N step(s)."
        try:
            from app.services import ziku_intelligence_service as ziku_intel

            intel_line = ziku_intel.chat_line(uid)
        except Exception as exc:  # pragma: no cover - defensive
            logger.debug("ziku intelligence unavailable in coach (%s)", exc)
            intel_line = None
        if intel_line:
            parts.append(intel_line)

        steps = brief.get("missionCount") or len(brief.get("mission") or [])
        if steps:
            parts.append(f"mission has {steps} step(s)")

        if not parts:
            return None
        return "Study coach: " + "; ".join(parts) + "."
    except Exception as exc:  # pragma: no cover - defensive
        logger.debug("study coach: chat context unavailable (%s)", exc)
        return None
