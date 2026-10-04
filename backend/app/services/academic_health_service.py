"""Phase 2 — Academic Health Score + Focus intelligence signals.

A single 0-100 answer to "how are my studies going?", computed only from
evidence the app already records: quiz results, recorded mistakes, focus
sessions, tasks and the active Exam Rescue plan. Nothing here asks the
student to self-report.

Design rules:

* **Modular metrics.** Every metric declares its own weight in
  :data:`METRIC_WEIGHTS` and reports ``None`` when the student has not
  produced that signal yet. Weights of missing metrics are renormalised
  across the ones that do have data, so a brand-new account never reads as
  a failing student — it reads as an account with too little evidence.
* **No AI in the score.** The score must be reproducible and explainable;
  the AI recommendation engine is wired on top of it in the router instead
  of inside the arithmetic.
* **One write per read.** ``get_academic_health`` persists a daily snapshot
  under ``users/{uid}/health_history/{day}`` so the trend and the history
  chart have something to compare against.
"""

from __future__ import annotations

import logging
from collections import defaultdict
from datetime import date, datetime, timedelta, timezone
from typing import Any

from app.core.firebase import get_firestore
from app.services import ai_service, mistake_memory_service
from app.services.weak_topic_service import DEFAULT_WEAK_THRESHOLD

logger = logging.getLogger("gochano.ai_study")

HISTORY_COLLECTION = "health_history"

# Rolling windows. ``WINDOW_DAYS`` is what the score looks at; the focus
# rows are fetched over a longer span so "study days this week" can be
# computed without a composite index.
WINDOW_DAYS = 7
FOCUS_WINDOW_DAYS = 14

MAX_QUIZZES = 100
MAX_FOCUS_ROWS = 500
MAX_TASKS = 400

# Mirrors ``part3._FOCUS_MAX_SECONDS``: above this a duration is corrupt.
FOCUS_MAX_SECONDS = 24 * 60 * 60

# Phase 5 - mirrors ``focus_service.PLAN_TARGET_MINUTES``: the block length a
# healthy focus session averages (the depth part of the focus metric).
PLAN_TARGET_MINUTES = 25

# A change smaller than this many points is noise, not a trend.
TREND_THRESHOLD = 2

# Phase 5 - five metrics. Weights are renormalised over whatever is
# available, so adding ``focusConsistency`` changes nothing for a student
# who has no focus sessions yet.
METRIC_WEIGHTS: dict[str, float] = {
    "consistency": 0.22,
    "understanding": 0.26,
    "revision": 0.22,
    "examReadiness": 0.18,
    "focusConsistency": 0.12,
}

METRIC_LABELS: dict[str, str] = {
    "consistency": "Consistency",
    "understanding": "Understanding",
    "revision": "Revision",
    "examReadiness": "Exam readiness",
    "focusConsistency": "Focus consistency",
}

METRIC_ORDER: tuple[str, ...] = (
    "consistency",
    "understanding",
    "revision",
    "examReadiness",
    "focusConsistency",
)

# (minimum score, grade key, headline)
_GRADE_BANDS: tuple[tuple[int, str, str], ...] = (
    (85, "excellent", "Excellent — you're on top of your studies."),
    (70, "good", "Good — steady and in control."),
    (55, "fair", "Fair — a few gaps worth closing."),
    (0, "needs_attention", "Needs attention — start with one small win today."),
)

_NO_DATA_GRADE = "no_data"
_NO_DATA_HEADLINE = (
    "Not enough data yet — take a quiz or start a study session."
)


# ---------------------------------------------------------------------------
# small coercion helpers (Firestore hands back str / int / float / Timestamp)
# ---------------------------------------------------------------------------


def _to_int(raw: Any) -> int | None:
    if isinstance(raw, bool):
        return None
    if isinstance(raw, int):
        return raw
    if isinstance(raw, float):
        return int(raw)
    if isinstance(raw, str):
        try:
            return int(float(raw.strip()))
        except ValueError:
            return None
    return None


def _to_float(raw: Any) -> float | None:
    if isinstance(raw, bool):
        return None
    if isinstance(raw, (int, float)):
        return float(raw)
    if isinstance(raw, str):
        try:
            return float(raw.strip())
        except ValueError:
            return None
    return None


def _to_date(raw: Any) -> date | None:
    if raw is None:
        return None
    if isinstance(raw, datetime):
        return raw.date()
    if isinstance(raw, date):
        return raw
    if isinstance(raw, str):
        text = raw.strip()
        if not text:
            return None
        try:
            return datetime.fromisoformat(text.replace("Z", "+00:00")).date()
        except ValueError:
            return None
    for attr in ("to_datetime", "toDate"):
        converter = getattr(raw, attr, None)
        if callable(converter):
            try:
                value = converter()
            except Exception:  # pragma: no cover - defensive
                return None
            if isinstance(value, datetime):
                return value.date()
    seconds = getattr(raw, "seconds", None)
    if isinstance(seconds, (int, float)) and not isinstance(seconds, bool):
        return datetime.fromtimestamp(seconds, tz=timezone.utc).date()
    return None


def _coerce_seconds(raw: Any) -> int:
    """Same policy as ``part3._coerce_focus_seconds``: corrupt → 0, never clamp up."""
    value = _to_int(raw)
    if value is None or value < 0 or value > FOCUS_MAX_SECONDS:
        return 0
    return value


def _day_key(value: datetime | date) -> str:
    if isinstance(value, datetime):
        return value.date().isoformat()
    return value.isoformat()


def _clamp(value: float, low: float = 0.0, high: float = 100.0) -> float:
    return max(low, min(high, value))


def _empty_signals(today: date) -> dict[str, Any]:
    return {
        "dayKey": _day_key(today),
        "windowDays": WINDOW_DAYS,
        "quizzes": {
            "total": 0,
            "recentAverage": 0,
            "recentCount": 0,
            "topicAverages": {},
            "topicAttempts": {},
            "strongTopics": 0,
            "weakTopics": 0,
            "strongTopicShare": 0.0,
        },
        "study": {
            "hasData": False,
            "studyDays": 0,
            "weekSeconds": 0,
            "weekMinutes": 0,
            "todaySeconds": 0,
            "todayMinutes": 0,
            "todaySessions": 0,
            "todayPlannedMinutes": 0,
            "interruptionsToday": 0,
            "averageFocusScore": None,
            "focusScoreCount": 0,
            "bySubjectMinutes": {},
            # Phase 5 - Focus Engine signals (see ``_collect_focus``).
            "weekSessions": 0,
            "averageSessionMinutes": None,
            "focusConsistencyPct": None,
            "dailyMinutes": {},
        },
        "mistakes": {
            "total": 0,
            "occurrences": 0,
            "repeated": 0,
            "due": 0,
            "analyzed": 0,
            "topics": [],
        },
        "tasks": {
            "open": 0,
            "completed": 0,
            "overdue": 0,
            "dueSoon": 0,
            "rescueTotal": 0,
            "rescueDone": 0,
        },
        "exam": None,
        # Phase 3 — practice exams from the Real Exam Simulator. Empty until
        # a student submits one, so every pre-Phase-3 expectation is unchanged.
        "practiceExams": {
            "count7": 0,
            "avgAccuracy": 0,
            "total": 0,
            "weakTopics": [],
        },
        "ai": {"mistakeAnalyses": 0, "chatMessages": 0},
    }


# ---------------------------------------------------------------------------
# signal collection
# ---------------------------------------------------------------------------


def _collect_quizzes(db, uid: str, signals: dict[str, Any]) -> None:
    collection = db.collection("users").document(uid).collection("quiz_results")
    try:
        rows = list(
            collection.order_by("createdAt", direction="DESCENDING")
            .limit(MAX_QUIZZES)
            .stream()
        )
    except Exception as exc:  # pragma: no cover - missing createdAt / no index
        logger.debug("academic health: quiz ordering unavailable (%s)", exc)
        rows = list(collection.limit(MAX_QUIZZES).stream())
    scores: list[int] = []
    topic_scores: dict[str, list[int]] = defaultdict(list)
    topic_attempts: dict[str, int] = defaultdict(int)

    for snap in rows:
        data = snap.to_dict() or {}
        score = _to_int(data.get("score"))
        if score is None:
            continue
        scores.append(score)
        raw_topics = data.get("topicScores") or {}
        if isinstance(raw_topics, dict):
            for topic, value in raw_topics.items():
                name = str(topic or "").strip()
                topic_value = _to_int(value)
                if name and topic_value is not None:
                    topic_scores[name].append(topic_value)
                    topic_attempts[name] += 1

    topic_averages = {
        name: int(sum(values) / len(values))
        for name, values in topic_scores.items()
        if values
    }
    recent = scores[:20]
    strong = [name for name, avg in topic_averages.items() if avg >= 70]
    weak = [name for name, avg in topic_averages.items() if avg < DEFAULT_WEAK_THRESHOLD]

    signals["quizzes"] = {
        "total": len(scores),
        "recentAverage": int(sum(recent) / len(recent)) if recent else 0,
        "recentCount": len(recent),
        "topicAverages": topic_averages,
        "topicAttempts": dict(topic_attempts),
        "strongTopics": len(strong),
        "weakTopics": len(weak),
        "strongTopicShare": (len(strong) / len(topic_averages)) if topic_averages else 0.0,
    }


MAX_EXAM_RESULTS = 100


def _collect_exams(db, uid: str, today: date, signals: dict[str, Any]) -> None:
    """Phase 3 — practice exams submitted through the Real Exam Simulator.

    Read-only like every other collector: the exam itself writes the result,
    and the score just learns from it. Exam readiness gets a bounded boost
    from recent, accurate practice, and the weak-topic chain picks the result
    up through ``quiz_results`` / ``mistakes`` instead of from here.
    """
    collection = db.collection("users").document(uid).collection("exam_results")
    try:
        rows = list(collection.limit(MAX_EXAM_RESULTS).stream())
    except Exception as exc:  # pragma: no cover - missing collection
        logger.debug("academic health: exam results unavailable (%s)", exc)
        rows = []

    cutoff = (today - timedelta(days=WINDOW_DAYS - 1)).isoformat()
    recent: list[dict[str, Any]] = []
    weak: list[str] = []
    for snap in rows:
        data = snap.to_dict() or {}
        if str(data.get("dayKey") or "") >= cutoff:
            recent.append(data)
        for topic in data.get("weakTopics") or []:
            name = str(topic or "").strip()
            if name and name not in weak:
                weak.append(name)

    accuracies: list[float] = []
    for data in recent:
        try:
            accuracies.append(float(data.get("accuracy") or 0))
        except (TypeError, ValueError):
            continue

    signals["practiceExams"] = {
        "count7": len(recent),
        "avgAccuracy": int(sum(accuracies) / len(accuracies)) if accuracies else 0,
        "total": len(rows),
        "weakTopics": weak[:8],
    }


def _collect_focus(db, uid: str, today: date, signals: dict[str, Any]) -> None:
    window = {_day_key(today - timedelta(days=i)) for i in range(WINDOW_DAYS)}
    focus_window = {_day_key(today - timedelta(days=i)) for i in range(FOCUS_WINDOW_DAYS)}
    today_key = _day_key(today)

    rows = (
        db.collection("users")
        .document(uid)
        .collection("focus_sessions")
        .limit(MAX_FOCUS_ROWS)
        .stream()
    )

    study: dict[str, Any] = signals["study"]
    study_days: set[str] = set()
    week_seconds = 0
    week_sessions = 0
    day_seconds: dict[str, int] = defaultdict(int)
    today_seconds = 0
    today_sessions = 0
    today_planned = 0
    interruptions_today = 0
    focus_scores: list[int] = []
    by_subject: dict[str, int] = defaultdict(int)
    any_terminal = False

    for snap in rows:
        data = snap.to_dict() or {}
        if data.get("status") not in ("completed", "cancelled"):
            continue
        any_terminal = True
        day = str(data.get("dayKey") or "")
        if not day:
            continue
        seconds = _coerce_seconds(data.get("accumulatedSeconds"))
        if day in focus_window:
            if day in window:
                study_days.add(day)
                week_seconds += seconds
                week_sessions += 1
                day_seconds[day] += seconds // 60
                score = _to_int(data.get("focusScore"))
                if score is not None:
                    focus_scores.append(_clamp(float(score)))
            subject = str(data.get("subject") or "").strip()
            if subject:
                by_subject[subject] += seconds // 60
        if day == today_key:
            today_seconds += seconds
            today_sessions += 1
            today_planned += max(0, _to_int(data.get("plannedMinutes")) or 0)
            interruptions_today += max(0, _to_int(data.get("interruptions")) or 0)

    signals["study"] = {
        "hasData": any_terminal,
        "studyDays": len(study_days),
        "weekSeconds": week_seconds,
        "weekMinutes": week_seconds // 60,
        "todaySeconds": today_seconds,
        "todayMinutes": today_seconds // 60,
        "todaySessions": today_sessions,
        "todayPlannedMinutes": today_planned,
        "interruptionsToday": interruptions_today,
        "averageFocusScore": (
            int(sum(focus_scores) / len(focus_scores)) if focus_scores else None
        ),
        "focusScoreCount": len(focus_scores),
        "bySubjectMinutes": dict(by_subject),
        # Phase 5 - Focus Engine signals. ``dailyMinutes`` is the 7-day trend
        # the Ziku Coach profile reports; the others feed the
        # ``focusConsistency`` metric and the coach's study pattern.
        "weekSessions": week_sessions,
        "averageSessionMinutes": (
            int(round(week_seconds / week_sessions / 60)) if week_sessions else None
        ),
        "focusConsistencyPct": round(100.0 * len(study_days) / WINDOW_DAYS, 1),
        "dailyMinutes": {
            day: day_seconds[day] for day in sorted(day_seconds)
        },
    }


def _collect_mistakes(uid: str, signals: dict[str, Any]) -> None:
    try:
        analytics = mistake_memory_service.get_analytics(uid)
    except Exception as exc:  # pragma: no cover - defensive
        logger.warning("academic health: mistake analytics unavailable (%s)", exc)
        return

    topics = analytics.get("topics") or []
    signals["mistakes"] = {
        "total": int(analytics.get("totalMistakes") or 0),
        "occurrences": sum(int(t.get("occurrences") or 0) for t in topics),
        "repeated": sum(int(t.get("repeated") or 0) for t in topics),
        "due": sum(int(t.get("due") or 0) for t in topics),
        "analyzed": sum(int(t.get("analyzed") or 0) for t in topics),
        "topics": [
            {
                "topic": str(t.get("name") or "General"),
                "mistakes": int(t.get("mistakes") or 0),
                "occurrences": int(t.get("occurrences") or 0),
                "repeated": int(t.get("repeated") or 0),
                "due": int(t.get("due") or 0),
                "analyzed": int(t.get("analyzed") or 0),
            }
            for t in topics
        ],
    }


def _collect_tasks(
    db, uid: str, today: date, signals: dict[str, Any], rescue_session_id: str | None
) -> None:
    """Count open / overdue / due-soon tasks, plus Exam Rescue plan progress."""
    rows = list(
        db.collection("tasks").where("ownerId", "==", uid).limit(MAX_TASKS).stream()
    )
    soon = today + timedelta(days=7)

    open_count = 0
    completed = 0
    overdue = 0
    due_soon = 0
    rescue_total = 0
    rescue_done = 0

    for snap in rows:
        data = snap.to_dict() or {}
        done = data.get("done") is True or data.get("completedAt") is not None
        if done:
            completed += 1
        else:
            open_count += 1
            due = _to_date(data.get("dueAt") or data.get("dueDate"))
            if due is not None:
                if due < today:
                    overdue += 1
                elif due <= soon:
                    due_soon += 1
        if str(data.get("source") or "") == "exam_rescue":
            if rescue_session_id and str(data.get("rescueSessionId") or "") != rescue_session_id:
                continue
            rescue_total += 1
            if done:
                rescue_done += 1

    signals["tasks"] = {
        "open": open_count,
        "completed": completed,
        "overdue": overdue,
        "dueSoon": due_soon,
        "rescueTotal": rescue_total,
        "rescueDone": rescue_done,
    }


def _collect_exam(
    db, uid: str, today: date, exam_date: date | None
) -> dict[str, Any] | None:
    """Nearest active Exam Rescue exam (or an explicit override date)."""
    exam_day: date | None = None
    data: dict[str, Any] = {}

    rows = db.collection("users").document(uid).collection("exam_rescue").stream()
    eligible: list[tuple[date, dict[str, Any]]] = []
    for snap in rows:
        row = snap.to_dict() or {}
        if str(row.get("status") or "") != "active":
            continue
        row_day = _to_date(row.get("examDate"))
        if row_day is None:
            continue
        row["sessionId"] = str(row.get("sessionId") or snap.id or "")
        eligible.append((row_day, row))
    eligible.sort(key=lambda item: item[0])

    if eligible:
        exam_day, data = eligible[0]
    if exam_date is not None:
        exam_day = exam_date
    if exam_day is None:
        return None

    days_remaining = (exam_day - today).days
    if days_remaining < 0:
        return None

    return {
        "exists": True,
        "title": str(data.get("examTitle") or ""),
        "examDate": _day_key(exam_day),
        "daysRemaining": days_remaining,
        "dailyTargetMinutes": _to_int(data.get("dailyTargetMinutes")) or 0,
        "sessionId": str(data.get("sessionId") or ""),
    }


def _collect_ai_usage(uid: str, signals: dict[str, Any]) -> None:
    try:
        summary = ai_service.get_ai_activity_summary(uid)
    except Exception as exc:  # pragma: no cover - defensive
        logger.debug("academic health: AI usage summary unavailable (%s)", exc)
        return
    signals["ai"] = {
        "mistakeAnalyses": int(summary.get("mistake_analyses") or 0),
        "chatMessages": int(summary.get("ai_chat_messages") or 0),
        "studyRecommendations": int(summary.get("study_recommendations") or 0),
    }


def collect_signals(uid: str, exam_date: date | None = None) -> dict[str, Any]:
    """Gather every raw signal the score is built from.

    Pure read: no writes, no AI calls, no quota. Individual sources fail
    soft — one broken collection degrades that signal to "unavailable"
    rather than taking the whole screen down.
    """
    today = datetime.now(timezone.utc).date()
    signals = _empty_signals(today)
    db = get_firestore()
    if db is None:
        logger.warning("academic health: Firestore unavailable for uid=%s", uid)
        return signals

    _collect_quizzes(db, uid, signals)
    _collect_focus(db, uid, today, signals)
    _collect_mistakes(uid, signals)
    _collect_exams(db, uid, today, signals)

    signals["exam"] = _collect_exam(db, uid, today, exam_date)
    rescue_session_id = (signals["exam"] or {}).get("sessionId") or None
    _collect_tasks(db, uid, today, signals, rescue_session_id)

    _collect_ai_usage(uid, signals)
    return signals


# ---------------------------------------------------------------------------
# metric maths
# ---------------------------------------------------------------------------


def _metric_consistency(signals: dict[str, Any]) -> tuple[float | None, str]:
    study = signals["study"]
    if not study["hasData"]:
        return None, "No finished study sessions yet"
    days = study["studyDays"]
    today_minutes = study["todayMinutes"]
    score = 70.0 * min(days / 5, 1.0) + 30.0 * min(today_minutes / 60, 1.0)
    detail = f"{days}/{WINDOW_DAYS} study days this week · {today_minutes} min today"
    return score, detail


def _metric_understanding(signals: dict[str, Any]) -> tuple[float | None, str]:
    quizzes = signals["quizzes"]
    if quizzes["total"] == 0:
        return None, "No quizzes taken yet"
    recent = float(quizzes["recentAverage"])
    strong_share = float(quizzes["strongTopicShare"])
    score = 0.7 * recent + 0.3 * (strong_share * 100.0)
    detail = (
        f"Last {quizzes['recentCount']} quizzes average {quizzes['recentAverage']}% · "
        f"{quizzes['strongTopics']} strong topic(s)"
    )
    return score, detail


def _metric_revision(signals: dict[str, Any]) -> tuple[float | None, str]:
    mistakes = signals["mistakes"]
    total = mistakes["total"]
    if total == 0:
        return None, "No recorded mistakes yet"
    due_penalty = min(mistakes["due"] * 8, 50)
    repeat_penalty = min(mistakes["repeated"] * 6, 30)
    base = max(0.0, 100.0 - due_penalty - repeat_penalty)
    analysed_ratio = mistakes["analyzed"] / total
    score = base * (0.7 + 0.3 * analysed_ratio)
    detail = (
        f"{mistakes['due']} due for revision · "
        f"{mistakes['repeated']} repeated · {mistakes['analyzed']} analysed"
    )
    return score, detail


def _metric_exam_readiness(signals: dict[str, Any]) -> tuple[float | None, str]:
    tasks = signals["tasks"]
    study = signals["study"]
    exam = signals["exam"]
    practice = signals.get("practiceExams") or {}
    practice_count = int(practice.get("count7") or 0)
    has_plan = bool(exam and exam.get("exists"))

    if (
        not has_plan
        and tasks["open"] == 0
        and not study["hasData"]
        and practice_count == 0
    ):
        return None, "No open tasks or study plan yet"

    penalty = min(tasks["overdue"] * 12, 36) + min(tasks["dueSoon"] * 4, 20)
    momentum = 15.0 * min(study["todayMinutes"] / 60, 1.0)
    # Phase 3 — a mock exam is the most direct readiness evidence there is,
    # but only recent and accurate ones count: bounded so five bad attempts
    # cannot out-perform a finished rescue plan.
    practice_boost = (
        min(practice_count * 5, 15) * (int(practice.get("avgAccuracy") or 0) / 100)
        if practice_count
        else 0.0
    )
    practice_note = (
        f" · {practice_count} practice exam(s)"
        f" ({practice.get('avgAccuracy') or 0}% avg)"
        if practice_count
        else ""
    )

    if has_plan:
        completion = tasks["rescueTotal"] and tasks["rescueDone"] / tasks["rescueTotal"] or 0.0
        score = (
            0.5 * (100.0 - penalty)
            + 0.5 * (completion * 100.0)
            + momentum
            + practice_boost
        )
        detail = (
            f"{exam['title'] or 'Exam'} in {exam['daysRemaining']} day(s) · "
            f"{tasks['rescueDone']}/{tasks['rescueTotal']} plan tasks done · "
            f"{tasks['overdue']} overdue"
        )
    else:
        score = 85.0 - penalty + momentum + practice_boost
        detail = f"{tasks['overdue']} overdue · {tasks['dueSoon']} due this week"

    return _clamp(score), detail + practice_note


def _metric_focus_consistency(signals: dict[str, Any]) -> tuple[float | None, str]:
    """Phase 5 — deep-work regularity, session depth and session quality.

    Three parts, all read from the same ``focus_sessions`` rows the Ziku
    Focus Engine tracks:

    * regularity (35%) — share of the 7-day window with a finished session,
    * depth (40%) — average finished session against the 25-minute block
      target, capped at the target (a two-hour block is not a fault),
    * quality (25%) — the per-session Focus Score computed at completion.

    Reports ``None`` (and is renormalised away) until one session exists.
    """
    study = signals["study"]
    if not study["hasData"]:
        return None, "No finished study sessions yet"

    regularity = float(study.get("focusConsistencyPct") or 0.0) / 100.0
    average_session = float(study.get("averageSessionMinutes") or 0)
    depth = min(average_session / PLAN_TARGET_MINUTES, 1.0)
    quality = float(study.get("averageFocusScore") or 0) / 100.0

    score = _clamp(100.0 * (0.35 * regularity + 0.40 * depth + 0.25 * quality))
    quality_text = study.get("averageFocusScore")
    detail = (
        f"{study['studyDays']}/{WINDOW_DAYS} study days this week - "
        f"{average_session:g} min per session - "
        f"session quality {quality_text if quality_text is not None else 'n/a'}"
    )
    return score, detail


_METRIC_FUNCS = {
    "consistency": _metric_consistency,
    "understanding": _metric_understanding,
    "revision": _metric_revision,
    "examReadiness": _metric_exam_readiness,
    "focusConsistency": _metric_focus_consistency,
}


def _compute_metrics(signals: dict[str, Any]) -> tuple[list[dict[str, Any]], int, str]:
    metrics: list[dict[str, Any]] = []
    available_weight = 0.0
    weighted = 0.0

    for key in METRIC_ORDER:
        func = _METRIC_FUNCS[key]
        try:
            score, detail = func(signals)
        except Exception as exc:  # pragma: no cover - defensive
            logger.warning("academic health: metric %s failed (%s)", key, exc)
            score, detail = None, "Signal unavailable"
        available = score is not None
        if available:
            value = round(float(_clamp(score)), 1)
            weight = METRIC_WEIGHTS[key]
            available_weight += weight
            weighted += weight * value
        else:
            value = None
        metrics.append(
            {
                "key": key,
                "label": METRIC_LABELS[key],
                "weight": METRIC_WEIGHTS[key],
                "score": value,
                "available": available,
                "detail": detail,
            }
        )

    if available_weight <= 0:
        return metrics, 0, _NO_DATA_GRADE

    total = int(round(weighted / available_weight))
    return metrics, int(_clamp(float(total))), _grade_for(total)[1]


def _grade_for(score: int) -> tuple[int, str, str]:
    for floor, key, headline in _GRADE_BANDS:
        if score >= floor:
            return score, key, headline
    return score, _GRADE_BANDS[-1][1], _GRADE_BANDS[-1][2]  # pragma: no cover


# ---------------------------------------------------------------------------
# weak areas + recommendations (rule based, no AI)
# ---------------------------------------------------------------------------


def build_weak_areas(signals: dict[str, Any], limit: int = 5) -> list[dict[str, Any]]:
    """Merge quiz mastery and recorded mistakes into one priority list."""
    topic_averages: dict[str, int] = signals["quizzes"]["topicAverages"]
    attempts: dict[str, int] = signals["quizzes"]["topicAttempts"]
    mistake_topics = {t["topic"]: t for t in signals["mistakes"]["topics"]}

    names = set(topic_averages) | set(mistake_topics)
    areas: list[dict[str, Any]] = []
    for name in names:
        quiz_average = topic_averages.get(name)
        mistake = mistake_topics.get(name, {})
        repeated = int(mistake.get("repeated") or 0)
        due = int(mistake.get("due") or 0)
        mistake_count = int(mistake.get("mistakes") or 0)

        high = due > 0 or repeated > 0 or (quiz_average is not None and quiz_average < 50)
        if due:
            action = f"{due} mistake(s) due — revise before the next {name} quiz."
        elif repeated:
            action = f"{repeated} repeat miss(es) in {name} — redo them without notes."
        elif quiz_average is not None:
            action = f"Averaging {quiz_average}% in {name} — re-read the rules, then quiz again."
        else:
            action = f"Log a few {name} mistakes so Ziku can build a revision plan."

        areas.append(
            {
                "topic": name,
                "quizAverage": quiz_average,
                "attempts": int(attempts.get(name, 0)),
                "mistakes": mistake_count,
                "occurrences": int(mistake.get("occurrences") or 0),
                "repeated": repeated,
                "due": due,
                "priority": "high" if high else "medium",
                "action": action,
            }
        )

    def _sort_key(area: dict[str, Any]) -> tuple:
        average = area["quizAverage"]
        return (
            0 if area["priority"] == "high" else 1,
            average if average is not None else 101,
            -area["mistakes"],
            area["topic"].lower(),
        )

    areas.sort(key=_sort_key)
    return areas[: max(1, limit)]


def build_recommendations(
    signals: dict[str, Any], weak_areas: list[dict[str, Any]], limit: int = 5
) -> list[dict[str, Any]]:
    """Deterministic, always-available advice — the AI layer sits on top."""
    recs: list[dict[str, Any]] = []
    seen: set[str] = set()

    def add(title: str, reason: str, priority: str) -> None:
        key = title.strip().lower()
        if key in seen or len(recs) >= limit:
            return
        seen.add(key)
        recs.append(
            {
                "title": title,
                "reason": reason,
                "priority": priority,
                "source": "health",
            }
        )

    exam = signals["exam"]
    tasks = signals["tasks"]
    study = signals["study"]
    mistakes = signals["mistakes"]

    if exam and exam.get("exists") and exam["daysRemaining"] <= 7:
        add(
            f"Follow your {exam['title'] or 'exam'} plan",
            f"{exam['daysRemaining']} day(s) left and {tasks['rescueDone']}/"
            f"{tasks['rescueTotal']} plan tasks are done.",
            "high",
        )

    if weak_areas:
        top = weak_areas[0]
        add(f"Revise {top['topic']}", top["action"], "high")

    if mistakes["due"]:
        add(
            f"{mistakes['due']} mistake(s) ready for revision",
            "Your spaced-repetition queue is waiting — one pass takes 10 minutes.",
            "high",
        )

    if tasks["overdue"]:
        add(
            f"Clear {tasks['overdue']} overdue task(s)",
            "Overdue work is the fastest way to lose readiness points.",
            "high",
        )

    if study["hasData"] and study["studyDays"] < 3:
        add(
            f"Study on {3 - study['studyDays']} more day(s) this week",
            f"You've studied {study['studyDays']}/{WINDOW_DAYS} days — "
            "three is the habit floor.",
            "medium",
        )

    if study["todayMinutes"] < 30:
        add(
            "Start one 25-minute deep-work session",
            f"You've put in {study['todayMinutes']} min today. A single session "
            "moves consistency and exam readiness together.",
            "medium",
        )

    if tasks["dueSoon"] and len(recs) < limit:
        add(
            f"{tasks['dueSoon']} task(s) due this week",
            "Schedule them before the week gets away from you.",
            "low",
        )

    if not recs:
        add(
            "Keep the rhythm going",
            "Nothing urgent — take a quiz so your Understanding score has data.",
            "low",
        )

    return recs


# ---------------------------------------------------------------------------
# history / trend
# ---------------------------------------------------------------------------


def _history_ref(db, uid: str, day_key: str):
    return (
        db.collection("users")
        .document(uid)
        .collection(HISTORY_COLLECTION)
        .document(day_key)
    )


def _previous_score(db, uid: str, today: date) -> int | None:
    try:
        snap = _history_ref(db, uid, _day_key(today - timedelta(days=1))).get()
    except Exception as exc:  # pragma: no cover - defensive
        logger.debug("academic health: previous snapshot unreadable (%s)", exc)
        return None
    if snap is None or not snap.exists:
        return None
    return _to_int((snap.to_dict() or {}).get("score"))


def _save_snapshot(
    db, uid: str, today: date, score: int, grade: str, metrics: list[dict[str, Any]]
) -> None:
    payload = {
        "dayKey": _day_key(today),
        "score": score,
        "grade": grade,
        "metrics": {m["key"]: m["score"] for m in metrics},
        "savedAt": datetime.now(timezone.utc),
    }
    try:
        _history_ref(db, uid, payload["dayKey"]).set(payload)
    except Exception as exc:  # pragma: no cover - defensive
        logger.warning("academic health: snapshot not saved (%s)", exc)


def get_history(uid: str, days: int = 30) -> dict[str, Any]:
    """Daily score snapshots, oldest first, for the trend chart."""
    days = max(1, min(days, 365))
    today = datetime.now(timezone.utc).date()
    cutoff = today - timedelta(days=days - 1)

    db = get_firestore()
    entries: list[dict[str, Any]] = []
    if db is not None:
        try:
            rows = (
                db.collection("users")
                .document(uid)
                .collection(HISTORY_COLLECTION)
                .stream()
            )
            for snap in rows:
                data = snap.to_dict() or {}
                day_key = str(data.get("dayKey") or snap.id or "")
                try:
                    parsed = date.fromisoformat(day_key)
                except ValueError:
                    continue
                if parsed < cutoff:
                    continue
                entries.append(
                    {
                        "dayKey": day_key,
                        "score": _to_int(data.get("score")),
                        "grade": data.get("grade"),
                        "metrics": data.get("metrics") or {},
                    }
                )
        except Exception as exc:  # pragma: no cover - defensive
            logger.warning("academic health: history unreadable (%s)", exc)

    entries.sort(key=lambda e: e["dayKey"])
    return {
        "days": days,
        "history": entries,
        "count": len(entries),
    }


# ---------------------------------------------------------------------------
# public API
# ---------------------------------------------------------------------------


def get_academic_health(
    uid: str, exam_date: date | None = None, *, persist: bool = True
) -> dict[str, Any]:
    """The full Academic Health payload Profile and Home render.

    ``persist=False`` skips today's snapshot write — used when the score is
    only being read to give Ziku context, where a chat message must not
    double as a scoring run.
    """
    now = datetime.now(timezone.utc)
    today = now.date()
    signals = collect_signals(uid, exam_date=exam_date)

    metrics, score, grade = _compute_metrics(signals)
    available = [m for m in metrics if m["available"]]
    headline = _grade_for(score)[2] if available else _NO_DATA_HEADLINE

    db = get_firestore()
    previous = _previous_score(db, uid, today) if db is not None else None
    if previous is None:
        trend = {"direction": "new", "delta": None, "previousScore": None}
    else:
        delta = score - previous
        direction = "up" if delta >= TREND_THRESHOLD else (
            "down" if delta <= -TREND_THRESHOLD else "stable"
        )
        trend = {"direction": direction, "delta": delta, "previousScore": previous}

    weak_areas = build_weak_areas(signals)
    recommendations = build_recommendations(signals, weak_areas)

    exam = signals.get("exam")
    payload: dict[str, Any] = {
        "score": score,
        "grade": grade,
        "headline": headline,
        "hasData": bool(available),
        "generatedAt": now,
        "dayKey": signals["dayKey"],
        "trend": trend,
        "metrics": metrics,
        "signals": {
            "quizzes": {
                k: v
                for k, v in signals["quizzes"].items()
                if k not in ("topicAverages", "topicAttempts")
            },
            "study": signals["study"],
            "mistakes": {
                k: v for k, v in signals["mistakes"].items() if k != "topics"
            },
            "tasks": signals["tasks"],
            "exam": exam,
            # Phase 3 — practice exams from the Real Exam Simulator.
            "practiceExams": signals.get("practiceExams"),
            "ai": signals["ai"],
        },
        "weakAreas": weak_areas,
        "recommendations": recommendations,
        "coverage": [m["key"] for m in available],
        "missing": [m["key"] for m in metrics if not m["available"]],
    }

    if db is not None and persist:
        _save_snapshot(db, uid, today, score, grade, metrics)

    return payload


async def get_recommendations(uid: str) -> dict[str, Any]:
    """Health rules first, then Ziku's AI-authored list, de-duplicated."""
    signals = collect_signals(uid)
    weak_areas = build_weak_areas(signals)
    health_items = build_recommendations(signals, weak_areas, limit=3)

    ai_items: list[dict[str, Any]] = []
    ai_cached = False
    try:
        from app.services.ai_recommendation_service import (
            generate_study_recommendation,
        )

        result = await generate_study_recommendation(uid)
        ai_cached = bool(result.get("cached"))
        for item in result.get("recommendations") or []:
            if not isinstance(item, dict):
                continue
            title = str(item.get("title") or "").strip()
            if not title:
                continue
            ai_items.append(
                {
                    "title": title[:100],
                    "reason": str(item.get("reason") or "")[:200],
                    "priority": str(item.get("priority") or "medium"),
                    "source": "ai",
                }
            )
    except Exception as exc:  # pragma: no cover - defensive
        logger.warning("academic health: AI recommendations unavailable (%s)", exc)

    merged: list[dict[str, Any]] = list(health_items)
    seen = {item["title"].strip().lower() for item in merged}
    for item in ai_items:
        key = item["title"].strip().lower()
        if key in seen or len(merged) >= 6:
            continue
        seen.add(key)
        merged.append(item)

    return {
        "recommendations": merged,
        "count": len(merged),
        "healthCount": len(health_items),
        "aiCount": len(ai_items),
        "aiCached": ai_cached,
        "generatedAt": datetime.now(timezone.utc),
    }


# ---------------------------------------------------------------------------
# Ziku context
# ---------------------------------------------------------------------------


def chat_context_line(uid: str) -> str | None:
    """One sentence of academic state, handed to Ziku's system prompt.

    Deliberately cheap and read-only: no snapshot write, no AI call. Returns
    ``None`` when there is nothing to say (no signal yet) or the read fails —
    a chat message must never fail because scoring did.
    """
    try:
        payload = get_academic_health(uid, persist=False)
    except Exception as exc:  # pragma: no cover - defensive
        logger.debug("academic health: chat context unavailable (%s)", exc)
        return None

    if not payload.get("hasData"):
        return None

    signals = payload.get("signals") or {}
    parts: list[str] = [f"score {_to_int(payload.get('score')) or 0}/100"]

    weak_areas = payload.get("weakAreas") or []
    if weak_areas:
        top = weak_areas[0]
        topic = str(top.get("topic") or "").strip()
        quiz_average = _to_int(top.get("quizAverage"))
        if topic:
            parts.append(
                f"weakest topic {topic} ({quiz_average}%)"
                if quiz_average is not None
                else f"weakest topic {topic}"
            )

    mistakes = signals.get("mistakes") or {}
    due = _to_int(mistakes.get("due")) or 0
    if due > 0:
        parts.append(f"{due} mistake(s) due for revision")

    study = signals.get("study") or {}
    today_minutes = _to_int(study.get("todayMinutes")) or 0
    parts.append(f"{today_minutes} min of deep work today")

    exam = signals.get("exam")
    if isinstance(exam, dict) and exam.get("exists"):
        days_remaining = _to_int(exam.get("daysRemaining"))
        if days_remaining is not None:
            title = str(exam.get("title") or "exam").strip() or "exam"
            parts.append(f"{title} in {days_remaining} day(s)")

    return "Current academic health: " + ", ".join(parts) + "."
