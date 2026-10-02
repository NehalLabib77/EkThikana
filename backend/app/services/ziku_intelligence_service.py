"""Phase 8 - Ziku Personal Intelligence Layer.

Ziku stops being five screens a student has to remember to open and becomes
one **Personal Academic Operating System**: it remembers the whole journey,
briefs the morning and the evening, says who the student is as a learner,
picks the next best action out of everything the app knows, and keeps a
scoreboard of real learning achievements.

Like Phase 4's coach, this module is an **aggregator**. It reads five
systems - Mistake Memory, the Real Exam Simulator, the Ziku Focus Engine,
the Learning Community and the Study Coach - and writes only its own
caches:

==================================== ===================================
``learning_journeys/{dayKey}``       timeline + improvement trends
``ziku_briefs/{dayKey}``             morning block + the AI reflection
``learning_personalities/{docId}``   the learning personality
``next_best_actions/{dayKey}``       the recommendation
``learning_achievements/{docId}``    "earned" stamps (never progress)
==================================== ===================================

Design rules (the same ones the coach follows):

* **Offline first.** Every block is a rule over data the app already has.
  The single AI spend is one evening reflection line per student per day,
  best effort, with a rule-based fallback - so the brief never blanks out
  when the key is missing.
* **Cache before compute.** The journey, the personality, the morning block
  and the recommendation are built once a day; the evening block is rebuilt
  on read because it reports *today*.
* **Never raise into a card.** Every reader is wrapped: a broken system
  degrades one line of the payload, it does not take the layer down.
* **Nothing depends on query order.** Rows are streamed and sorted in
  Python, so the tests' in-memory Firestore and the real one agree.
"""

from __future__ import annotations

import logging
from collections import defaultdict
from datetime import date, datetime, timedelta, timezone
from typing import Any

from app.services import academic_health_service as health
from app.services import exam_pro_service
from app.services import focus_service
from app.services import mistake_memory_service as mistakes
from app.services import study_coach_service as coach

logger = logging.getLogger("gochano.ziku_intel")

JOURNEY_COLLECTION = "learning_journeys"
BRIEF_COLLECTION = "ziku_briefs"
PERSONALITY_COLLECTION = "learning_personalities"
ACTION_COLLECTION = "next_best_actions"
ACHIEVEMENTS_COLLECTION = "learning_achievements"
CURRENT = "current"

#: Everything the timeline remembers. Older rows still count towards the
#: totals, they just fall out of the event list.
TIMELINE_DAYS = 90
MAX_TIMELINE_EVENTS = 80
MAX_TRENDS = 8
MAX_ALTERNATIVES = 4
MAX_TOPIC_LIST = 5

#: The bars the layer calls "good", mirroring the quiz mastery bar the rest
#: of the app uses (``weak_topic_service.DEFAULT_WEAK_THRESHOLD`` = 60,
#: strong topics start at 70 in the coach profile).
PASS_MARK = 70
NEUTRAL_MARK = 50

#: The evening brief only becomes interesting after this hour (UTC, matching
#: the coach's greeting buckets so the two never disagree about what time it
#: is - the client may still ask for a block explicitly).
EVENING_HOUR = 18

PHASES = ("auto", "morning", "evening")

ACHIEVEMENT_CATEGORIES = ("mcq", "consistency", "improvement", "contribution")

#: Every achievement in the system. ``target: 0`` means "at most zero"
#: (the bar only fills while the count is 0).
ACHIEVEMENTS: tuple[dict[str, Any], ...] = (
    # --- MCQ milestones ---------------------------------------------------
    {
        "id": "mcq_first",
        "category": "mcq",
        "metric": "quizzes",
        "target": 1,
        "title": "First Step",
        "description": "Log your first quiz and the scoreboard starts.",
    },
    {
        "id": "mcq_10",
        "category": "mcq",
        "metric": "quizzes",
        "target": 10,
        "title": "Ten Down",
        "description": "Ten quizzes recorded.",
    },
    {
        "id": "mcq_50",
        "category": "mcq",
        "metric": "quizzes",
        "target": 50,
        "title": "Fifty Club",
        "description": "Fifty quizzes recorded.",
    },
    {
        "id": "mcq_sharpshooter",
        "category": "mcq",
        "metric": "quizAverage",
        "target": 80,
        "title": "Sharpshooter",
        "description": "Hold an 80% quiz average across ten quizzes or more.",
    },
    # --- Consistency ------------------------------------------------------
    {
        "id": "streak_3",
        "category": "consistency",
        "metric": "streak",
        "target": 3,
        "title": "Three Straight",
        "description": "Three days of deep work in a row.",
    },
    {
        "id": "streak_7",
        "category": "consistency",
        "metric": "streak",
        "target": 7,
        "title": "Full Week",
        "description": "Seven days of deep work in a row.",
    },
    {
        "id": "streak_30",
        "category": "consistency",
        "metric": "streak",
        "target": 30,
        "title": "Unbreakable Month",
        "description": "Thirty days of deep work in a row.",
    },
    {
        "id": "focus_25",
        "category": "consistency",
        "metric": "focusSessions",
        "target": 25,
        "title": "Deep Work Regular",
        "description": "Finish 25 focus sessions.",
    },
    # --- Improvement ------------------------------------------------------
    {
        "id": "health_up_5",
        "category": "improvement",
        "metric": "healthDelta",
        "target": 5,
        "title": "Getting Healthier",
        "description": "Academic Health up 5 points or more.",
    },
    {
        "id": "health_80",
        "category": "improvement",
        "metric": "healthScore",
        "target": 80,
        "title": "In The Green",
        "description": "Academic Health reaches 80.",
    },
    {
        "id": "exam_up_10",
        "category": "improvement",
        "metric": "examImprovement",
        "target": 10,
        "title": "Better Every Paper",
        "description": "Beat your previous exam result by 10 points.",
    },
    {
        "id": "revision_clear",
        "category": "improvement",
        "metric": "revisionDue",
        "target": 0,
        "title": "Revision Zero",
        "description": "Clear the revision queue after recording mistakes.",
    },
    # --- Contribution -----------------------------------------------------
    {
        "id": "first_post",
        "category": "contribution",
        "metric": "communityPosts",
        "target": 1,
        "title": "Asked For The Class",
        "description": "Post your first question or notes in the community.",
    },
    {
        "id": "first_answer",
        "category": "contribution",
        "metric": "acceptedAnswers",
        "target": 1,
        "title": "Answered And Accepted",
        "description": "Have an answer accepted by the asker.",
    },
    {
        "id": "points_50",
        "category": "contribution",
        "metric": "points",
        "target": 50,
        "title": "Helpful Classmate",
        "description": "Earn 50 Learning Points.",
    },
    {
        "id": "points_250",
        "category": "contribution",
        "metric": "points",
        "target": 250,
        "title": "Community Pillar",
        "description": "Earn 250 Learning Points.",
    },
)

#: Learning style candidates, scored on evidence and picked by weight.
STYLE_LABELS = {
    "deep_worker": "The Steady Finisher",
    "practice_first": "The Practiser",
    "revision_led": "The Comeback Kid",
    "social_learner": "The Explainer",
    "exam_first": "The Clock Runner",
}


# ---------------------------------------------------------------------------
# seams + small helpers
# ---------------------------------------------------------------------------


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _day_key(moment: datetime | date) -> str:
    if isinstance(moment, datetime):
        moment = moment.astimezone(timezone.utc).date() if moment.tzinfo else moment.date()
    return moment.isoformat()


def _iso(moment: datetime) -> str:
    return moment.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def _text(value: Any, default: str = "") -> str:
    if isinstance(value, str):
        return value.strip()
    if value is None:
        return default
    return str(value).strip()


def _int(value: Any) -> int | None:
    if isinstance(value, bool) or value is None:
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return int(round(value))
    try:
        return int(str(value).strip())
    except (TypeError, ValueError):
        return None


def _as_int(value: Any, default: int = 0) -> int:
    parsed = _int(value)
    return default if parsed is None else parsed


def _float(value: Any) -> float | None:
    if isinstance(value, bool) or value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    try:
        return float(str(value).strip())
    except (TypeError, ValueError):
        return None


def _percent(value: Any) -> float | None:
    raw = _float(value)
    return None if raw is None else round(raw, 1)


def _avg(values: list[float]) -> float | None:
    return round(sum(values) / len(values), 1) if values else None


def _firestore():
    try:
        from app.core.firebase import get_firestore

        return get_firestore()
    except Exception as exc:  # pragma: no cover - defensive
        logger.debug("ziku intel: firestore unavailable (%s)", exc)
        return None


def _read_doc(uid: str, collection: str, doc_id: str) -> dict[str, Any] | None:
    """One cached document under ``users/{uid}/{collection}/{doc_id}``."""
    try:
        db = _firestore()
        if db is None:
            return None
        snap = (
            db.collection("users")
            .document(uid)
            .collection(collection)
            .document(doc_id)
            .get()
        )
        if snap is None or not snap.exists:
            return None
        return snap.to_dict() or None
    except Exception as exc:  # pragma: no cover - defensive
        logger.debug("ziku intel: cache read failed (%s)", exc)
        return None


def _write_doc(uid: str, collection: str, doc_id: str, payload: dict[str, Any]) -> None:
    try:
        db = _firestore()
        if db is None:
            return
        db.collection("users").document(uid).collection(collection).document(doc_id).set(
            payload, merge=True
        )
    except Exception as exc:  # pragma: no cover - defensive
        logger.debug("ziku intel: cache write failed (%s)", exc)


def _read_rows(uid: str, collection: str) -> list[tuple[str, dict[str, Any]]]:
    """Every document of ``users/{uid}/{collection}``, unsorted and unwrapped.

    Sorted in Python on purpose: an ``order_by`` on a field that some rows
    lack is both a real index requirement and a crash waiting to happen in
    the test double.
    """
    try:
        db = _firestore()
        if db is None:
            return []
        out: list[tuple[str, dict[str, Any]]] = []
        for snap in db.collection("users").document(uid).collection(collection).stream():
            out.append((snap.id, snap.to_dict() or {}))
        return out
    except Exception as exc:  # pragma: no cover - defensive
        logger.debug("ziku intel: %s unreadable (%s)", collection, exc)
        return []


def _day_of(value: Any) -> date | None:
    """The calendar day behind a timestamp field of any shape the app writes.

    Handles ``datetime``, ``date``, ISO strings (``2026-10-02`` or a full
    ``...T12:00:00Z``), a Firestore ``Timestamp`` (``.seconds`` or
    ``.datetime()``) and ``None``.
    """
    if value is None:
        return None
    if isinstance(value, datetime):
        return value.astimezone(timezone.utc).date() if value.tzinfo else value.date()
    if isinstance(value, date):
        return value
    if isinstance(value, str):
        raw = value.strip()
        if not raw:
            return None
        try:
            if "T" in raw:
                return datetime.fromisoformat(raw.replace("Z", "+00:00")).date()
            return date.fromisoformat(raw[:10])
        except ValueError:
            return None
    datetime_attr = getattr(value, "datetime", None)
    if callable(datetime_attr):
        try:
            return datetime_attr().date()
        except Exception:  # pragma: no cover - defensive
            return None
    seconds = getattr(value, "seconds", None)
    if isinstance(seconds, (int, float)):
        try:
            return datetime.fromtimestamp(seconds, tz=timezone.utc).date()
        except (OverflowError, OSError, ValueError):  # pragma: no cover - defensive
            return None
    return None


def _window_start(today: date) -> date:
    return today - timedelta(days=TIMELINE_DAYS - 1)


def _tone_for_score(pct: float | None) -> str:
    if pct is None:
        return "neutral"
    if pct >= PASS_MARK:
        return "positive"
    if pct >= NEUTRAL_MARK:
        return "neutral"
    return "negative"


# ---------------------------------------------------------------------------
# 1. academic memory timeline
# ---------------------------------------------------------------------------


def _trend(
    key: str,
    label: str,
    unit: str,
    first: float | None,
    last: float | None,
    *,
    higher_is_better: bool = True,
) -> dict[str, Any] | None:
    """One improvement trend: two window halves and whether it got better.

    ``None`` only when there is no data at all - a single-sided window still
    reports so the UI can say "not enough history" instead of hiding the row.
    """
    if first is None and last is None:
        return None
    if first is None or last is None:
        return {
            "key": key,
            "label": label,
            "unit": unit,
            "first": first,
            "last": last,
            "delta": None,
            "direction": "baseline",
            "improving": None,
            "higherIsBetter": higher_is_better,
        }
    delta = round(last - first, 1)
    direction = "up" if delta > 0 else ("down" if delta < 0 else "flat")
    improving = None if delta == 0 else (delta > 0) == higher_is_better
    return {
        "key": key,
        "label": label,
        "unit": unit,
        "first": first,
        "last": last,
        "delta": delta,
        "direction": direction,
        "improving": improving,
        "higherIsBetter": higher_is_better,
    }


def _avg_split(
    values: list[tuple[date, float]], cutoff: date
) -> tuple[float | None, float | None]:
    """Average of a (day, value) series before and after ``cutoff``."""
    return _avg([v for d, v in values if d < cutoff]), _avg(
        [v for d, v in values if d >= cutoff]
    )


def _sum_split(
    values: list[tuple[date, float]], cutoff: date
) -> tuple[float | None, float | None]:
    """Total of a (day, value) series per half - equal-length halves."""
    early = [v for d, v in values if d < cutoff]
    late = [v for d, v in values if d >= cutoff]
    if not early and not late:
        return None, None
    return round(sum(early), 1), round(sum(late), 1)


def _rate_split(
    days: set[date], start: date, cutoff: date, today: date
) -> tuple[float | None, float | None]:
    """Share of each half's days that carry an event (0..100)."""
    if not days:
        return None, None
    early_span = max(1, (cutoff - start).days)
    late_span = max(1, (today - cutoff).days + 1)
    early = sum(1 for d in days if start <= d < cutoff)
    late = sum(1 for d in days if cutoff <= d <= today)
    return round(100.0 * early / early_span, 1), round(100.0 * late / late_span, 1)


def _community_activity(
    uid: str,
) -> tuple[list[tuple[date, str]], dict[str, Any]]:
    """The student's own community rows plus their Learning Points.

    Single-field equality queries only - no cross-student read, no index
    requirement - merged and classified here rather than by the store.
    """
    rows: list[tuple[date, str]] = []
    reputation: dict[str, Any] = {}
    db = _firestore()
    if db is None:
        return rows, reputation
    try:
        from app.services.community_service import CHALLENGES, POSTS, REPUTATION

        snap = db.collection(REPUTATION).document(uid).get()
        if snap is not None and snap.exists:
            reputation = snap.to_dict() or {}

        for field, name, kind in (
            ("authorId", POSTS, "post"),
            ("challengerId", CHALLENGES, "challenge"),
            ("opponentId", CHALLENGES, "challenge"),
        ):
            try:
                stream = db.collection(name).where(field, "==", uid).stream()
            except Exception as exc:  # pragma: no cover - defensive
                logger.debug("ziku intel: %s unreadable (%s)", name, exc)
                continue
            for item in stream:
                data = item.to_dict() or {}
                stamp = data.get("createdAtIso") or data.get("createdAt")
                day = _day_of(stamp)
                if day is None:
                    continue
                rows.append((day, kind))
    except Exception as exc:  # pragma: no cover - defensive
        logger.debug("ziku intel: community activity unavailable (%s)", exc)
    return rows, reputation


def _profile(uid: str, *, force: bool = False) -> dict[str, Any]:
    """The Phase 4 profile, wrapped so a failure still yields an empty dict."""
    try:
        return coach.build_learning_profile(uid, force=force)
    except Exception as exc:  # pragma: no cover - defensive
        logger.debug("ziku intel: learning profile unavailable (%s)", exc)
        return {}


def _build_timeline(
    uid: str, start: date, today: date
) -> tuple[list[dict[str, Any]], dict[str, Any], list[dict[str, Any]], dict[str, Any]]:
    """Read every stream once and return ``(events, stats, weakTopics, raw)``.

    ``raw`` carries the per-day series the trend builder needs, so nothing is
    read twice.
    """
    events: list[dict[str, Any]] = []
    raw: dict[str, list[tuple[date, float]]] = defaultdict(list)
    stats: dict[str, Any] = {
        "daysActive": 0,
        "quizzes": 0,
        "exams": 0,
        "mistakes": 0,
        "studyMinutes": 0,
        "focusSessions": 0,
        "communityPosts": 0,
        "communityChallenges": 0,
        "communityPoints": 0,
        "focusStreak": 0,
    }

    # --- exams ------------------------------------------------------------
    exam_pcts: list[tuple[date, float]] = []
    exam_days: set[date] = set()
    try:
        exam_history = exam_pro_service.history(uid, limit=50)
    except Exception as exc:  # pragma: no cover - defensive
        logger.debug("ziku intel: exam history unavailable (%s)", exc)
        exam_history = {}
    for item in exam_history.get("exams") or []:
        if not isinstance(item, dict):
            continue
        day = _day_of(item.get("createdAt")) or _day_of(item.get("dayKey"))
        if day is None or day < start or day > today:
            continue
        pct = _float(item.get("percentage"))
        exam_days.add(day)
        if pct is not None:
            exam_pcts.append((day, pct))
        subject = _text(item.get("subject"))
        events.append(
            {
                "dayKey": _day_key(day),
                "kind": "exam",
                "title": _text(item.get("title")) or "Practice paper",
                "detail": f"{subject} - {item.get('correctCount', 0)} correct"
                if subject
                else "Practice paper",
                "value": pct,
                "unit": "percent",
                "tone": _tone_for_score(pct),
            }
        )
        stats["exams"] += 1

    # --- quiz scores ------------------------------------------------------
    quiz_pcts: list[tuple[date, float]] = []
    quizzes_by_day: dict[date, list[int]] = defaultdict(list)
    for _, data in _read_rows(uid, "quiz_results"):
        score = _int(data.get("score"))
        if score is None:
            continue
        day = _day_of(data.get("createdAt")) or _day_of(data.get("dayKey"))
        if day is None or day < start or day > today:
            continue
        quizzes_by_day[day].append(score)
        quiz_pcts.append((day, float(score)))
        stats["quizzes"] += 1
    for day, scores in quizzes_by_day.items():
        average = round(sum(scores) / len(scores), 1)
        events.append(
            {
                "dayKey": _day_key(day),
                "kind": "quiz",
                "title": "Quiz",
                "detail": (
                    f"{len(scores)} attempt(s), average {average}%"
                    if len(scores) > 1
                    else f"Score {average}%"
                ),
                "value": average,
                "unit": "percent",
                "count": len(scores),
                "tone": _tone_for_score(average),
            }
        )

    # --- mistakes ---------------------------------------------------------
    mistake_days: set[date] = set()
    mistakes_by_day: dict[date, list[str]] = defaultdict(list)
    try:
        mistake_rows = mistakes.list_mistakes(uid, limit=200)
    except Exception as exc:  # pragma: no cover - defensive
        logger.debug("ziku intel: mistakes unavailable (%s)", exc)
        mistake_rows = []
    for item in mistake_rows:
        day = _day_of(item.get("firstSeenAt")) or _day_of(item.get("lastSeenAt"))
        if day is None or day < start or day > today:
            continue
        mistake_days.add(day)
        mistakes_by_day[day].append(_text(item.get("topic")) or "General")
        stats["mistakes"] += 1
    raw["mistakeDays"] = [
        (day, float(len(topics))) for day, topics in sorted(mistakes_by_day.items())
    ]
    for day, topics in mistakes_by_day.items():
        top = max(set(topics), key=topics.count)
        events.append(
            {
                "dayKey": _day_key(day),
                "kind": "mistake",
                "title": "Mistake recorded",
                "detail": f"{len(topics)} new - most in {top}",
                "value": len(topics),
                "unit": "count",
                "count": len(topics),
                "tone": "negative",
            }
        )

    # --- study hours + focus sessions (the same rows, two readings) ------
    focus_by_day: dict[str, dict[str, Any]] = {}
    active_days: set[date] = set()
    db = _firestore()
    try:
        focus_rows = focus_service.read_rows(db, uid) if db is not None else []
    except Exception as exc:  # pragma: no cover - defensive
        logger.debug("ziku intel: focus rows unavailable (%s)", exc)
        focus_rows = []
    for row in focus_rows:
        if row.get("status") not in ("completed", "cancelled"):
            continue
        day_text = focus_service.row_day(row)
        day = _day_of(day_text)
        if day is None or day < start or day > today:
            continue
        minutes = focus_service.coerce_focus_seconds(row.get("accumulatedSeconds", 0)) // 60
        bucket = focus_by_day.setdefault(day_text, {"minutes": 0, "sessions": 0, "scores": []})
        bucket["minutes"] += minutes
        bucket["sessions"] += 1
        score = _int(row.get("focusScore"))
        if score is not None:
            bucket["scores"].append(score)
        if minutes > 0:
            active_days.add(day)
        raw["studyMinutes"].append((day, float(minutes)))
        stats["studyMinutes"] += minutes
        stats["focusSessions"] += 1
    for day_text, bucket in focus_by_day.items():
        day = _day_of(day_text)
        if day is None:
            continue
        average_score = _avg([float(s) for s in bucket["scores"]])
        events.append(
            {
                "dayKey": day_text,
                "kind": "focus",
                "title": "Focus block",
                "detail": f"{bucket['minutes']} min across {bucket['sessions']} session(s)"
                + (f", focus score {average_score}" if average_score is not None else ""),
                "value": bucket["minutes"],
                "unit": "minutes",
                "count": bucket["sessions"],
                "tone": "positive" if bucket["minutes"] >= 25 else "neutral",
            }
        )
    # ``calc_streak`` walks day keys (strings), not ``date`` objects.
    stats["focusStreak"] = focus_service.calc_streak({_day_key(d) for d in active_days})
    stats["daysActive"] = len(
        active_days | set(quizzes_by_day) | exam_days | set(mistakes_by_day)
    )

    # --- community activity ----------------------------------------------
    community_rows, reputation = _community_activity(uid)
    community_by_day: dict[date, int] = defaultdict(int)
    for day, kind in community_rows:
        if day < start or day > today:
            continue
        community_by_day[day] += 1
        if kind == "post":
            stats["communityPosts"] += 1
        else:
            stats["communityChallenges"] += 1
    for day, count in community_by_day.items():
        raw["communityActivity"].append((day, float(count)))
        events.append(
            {
                "dayKey": _day_key(day),
                "kind": "community",
                "title": "Community activity",
                "detail": f"{count} post(s) or challenge(s)",
                "value": count,
                "unit": "count",
                "count": count,
                "tone": "positive",
            }
        )
    stats["communityPoints"] = _as_int(reputation.get("points"))

    # --- weak topics (a snapshot, not an event per day) -------------------
    weak_topics: list[dict[str, Any]] = []
    profile = _profile(uid)
    for entry in (profile.get("weakTopics") or [])[:MAX_TOPIC_LIST]:
        if not isinstance(entry, dict):
            continue
        topic = _text(entry.get("topic"))
        if not topic:
            continue
        weak_topics.append(
            {
                "topic": topic,
                "mistakes": _as_int(entry.get("mistakes")),
                "repeated": _as_int(entry.get("repeated")),
                "due": _as_int(entry.get("due")),
                "quizAverage": _int(entry.get("quizAverage")),
            }
        )
    if weak_topics:
        events.append(
            {
                "dayKey": _day_key(today),
                "kind": "weakTopic",
                "title": "Weak topics refreshed",
                "detail": ", ".join(t["topic"] for t in weak_topics[:3]),
                "value": len(weak_topics),
                "unit": "count",
                "count": len(weak_topics),
                "tone": "neutral",
            }
        )

    # --- Academic Health snapshots close the loop -------------------------
    try:
        for point in health.get_history(uid, days=TIMELINE_DAYS).get("history") or []:
            day = _day_of(point.get("dayKey"))
            score = _int(point.get("score"))
            if day is None or score is None or day < start or day > today:
                continue
            raw["healthScore"].append((day, float(score)))
    except Exception as exc:  # pragma: no cover - defensive
        logger.debug("ziku intel: health history unavailable (%s)", exc)

    raw["quizzes"] = quiz_pcts
    raw["exams"] = exam_pcts
    raw["activeDays"] = [(d, 1.0) for d in sorted(active_days)]
    return events, stats, weak_topics, raw


def build_journey(uid: str, *, force: bool = False) -> dict[str, Any]:
    """The Academic Memory Timeline - "Your Learning Journey".

    Seven streams (exams, quiz scores, mistakes, weak topics, study hours,
    focus sessions, community activity) collapsed into one dated timeline
    plus the improvement trends computed from the two window halves.
    """
    today = _now().date()
    day_key = _day_key(today)

    if not force:
        cached = _read_doc(uid, JOURNEY_COLLECTION, day_key)
        if cached:
            return {**cached, "cached": True}

    start = _window_start(today)
    cutoff = today - timedelta(days=TIMELINE_DAYS // 2)
    events, stats, weak_topics, raw = _build_timeline(uid, start, today)

    events.sort(key=lambda e: (e.get("dayKey", ""), e.get("kind", "")), reverse=True)
    timeline = events[:MAX_TIMELINE_EVENTS]

    trends: list[dict[str, Any]] = []
    for candidate in (
        _trend("healthScore", "Academic Health", "points", *_avg_split(raw["healthScore"], cutoff)),
        _trend("quizAverage", "Quiz average", "percent", *_avg_split(raw["quizzes"], cutoff)),
        _trend("examAverage", "Exam average", "percent", *_avg_split(raw["exams"], cutoff)),
        _trend(
            "studyHours",
            "Study hours",
            "hours",
            *_sum_split([(d, m / 60.0) for d, m in raw["studyMinutes"]], cutoff),
        ),
        _trend(
            "mistakes",
            "New mistakes",
            "count",
            *_sum_split(raw["mistakeDays"], cutoff),
            higher_is_better=False,
        ),
        _trend(
            "focusConsistency",
            "Days with focus",
            "percent",
            *_rate_split(_days(raw["activeDays"]), start, cutoff, today),
        ),
        _trend(
            "communityActivity",
            "Community activity",
            "count",
            *_sum_split(raw["communityActivity"], cutoff),
        ),
    ):
        if candidate is not None:
            trends.append(candidate)
    trends = trends[:MAX_TRENDS]

    improving = sum(1 for t in trends if t.get("improving"))
    declining = sum(1 for t in trends if t.get("improving") is False)

    if not stats["quizzes"] and not stats["exams"] and not stats["mistakes"]:
        headline = "Not enough yet - log one quiz or one focus block and your journey starts."
    else:
        headline = (
            f"{stats['daysActive']} active day(s), {stats['quizzes']} quiz(zes), "
            f"{stats['exams']} practice paper(s) and "
            f"{round(stats['studyMinutes'] / 60.0, 1)} study hour(s) in the last "
            f"{TIMELINE_DAYS} days."
        )
        if improving and not declining:
            headline += f" {improving} trend(s) moving up."
        elif improving and declining:
            headline += f" {improving} up, {declining} down."
        elif declining:
            headline += f" {declining} trend(s) to watch."

    payload: dict[str, Any] = {
        "student": profile_name(uid),
        "dayKey": day_key,
        "title": "Your Learning Journey",
        "headline": headline,
        "hasData": bool(
            stats["quizzes"] or stats["exams"] or stats["focusSessions"] or stats["mistakes"]
        ),
        "spanDays": TIMELINE_DAYS,
        "windowStart": _day_key(start),
        "windowEnd": _day_key(today),
        "stats": stats,
        "streams": {
            "exams": stats["exams"],
            "quizScores": stats["quizzes"],
            "mistakes": stats["mistakes"],
            "weakTopics": len(weak_topics),
            "studyHours": round(stats["studyMinutes"] / 60.0, 1),
            "focusSessions": stats["focusSessions"],
            "communityActivity": len(raw["communityActivity"]),
        },
        "timeline": timeline,
        "timelineCount": len(events),
        "trends": trends,
        "weakTopics": weak_topics,
        "improving": improving,
        "declining": declining,
        "generatedAt": _now(),
    }

    _write_doc(uid, JOURNEY_COLLECTION, day_key, payload)
    return {**payload, "cached": False}


def profile_name(uid: str) -> str:
    """The student's display name, best effort (never raises)."""
    try:
        from app.core.firebase import get_firestore

        db = get_firestore()
        if db is None:
            return ""
        snap = db.collection("users").document(uid).get()
        data = snap.to_dict() if snap is not None and snap.exists else None
        return _text((data or {}).get("displayName"))
    except Exception:  # pragma: no cover - defensive
        return ""


def _days(pairs: list[tuple[date, float]]) -> set[date]:
    return {d for d, _ in pairs}


# ---------------------------------------------------------------------------
# 2. AI daily brief upgrade (morning + evening)
# ---------------------------------------------------------------------------


def _resolve_phase(phase: str) -> str:
    if phase in ("morning", "evening"):
        return phase
    return "evening" if _now().hour >= EVENING_HOUR else "morning"


def _morning_block(uid: str, *, force: bool) -> dict[str, Any]:
    """The morning half: health, priority, why, mission - one mapping pass.

    Everything here already exists in the Phase 4 brief; this only re-frames
    it under the four headings the spec asks for, so the coach and the OS can
    never disagree about what today's priority is.
    """
    brief = coach.daily_recommendation(uid, force=force)
    profile = _profile(uid, force=force)
    return {
        "greeting": brief.get("greeting"),
        "greetingKey": brief.get("greetingKey"),
        "academicHealth": {
            "score": brief.get("healthScore"),
            "hasData": brief.get("hasData"),
            "grade": profile.get("healthGrade"),
            "headline": profile.get("healthHeadline"),
            "trend": profile.get("trend"),
            "examReadiness": profile.get("examReadiness"),
        },
        "priority": brief.get("priority"),
        "why": brief.get("why"),
        "mission": brief.get("mission") or [],
        "missionCount": brief.get("missionCount") or len(brief.get("mission") or []),
        "exam": brief.get("exam"),
        "focus": brief.get("focus"),
        "generatedAt": brief.get("generatedAt"),
    }


def _today_mistakes(uid: str, today: date) -> list[dict[str, Any]]:
    """Mistakes first recorded today, newest encounter first."""
    out: list[dict[str, Any]] = []
    try:
        for item in mistakes.list_mistakes(uid, limit=200):
            day = _day_of(item.get("firstSeenAt")) or _day_of(item.get("lastSeenAt"))
            if day != today:
                continue
            out.append(
                {
                    "topic": _text(item.get("topic")) or "General",
                    "subjectId": _text(item.get("subjectId")),
                    "occurrences": _as_int(item.get("occurrences"), 1),
                }
            )
    except Exception as exc:  # pragma: no cover - defensive
        logger.debug("ziku intel: today's mistakes unavailable (%s)", exc)
    return out


def _today_counts(uid: str, today: date) -> dict[str, int]:
    """Quizzes, practice papers and focus sessions produced today."""
    quizzes = sum(
        1
        for _, data in _read_rows(uid, "quiz_results")
        if (_day_of(data.get("createdAt")) or _day_of(data.get("dayKey"))) == today
    )

    exams = 0
    try:
        for item in exam_pro_service.history(uid, limit=50).get("exams") or []:
            day = _day_of(item.get("createdAt")) or _day_of(item.get("dayKey"))
            if day == today:
                exams += 1
    except Exception:  # pragma: no cover - defensive
        exams = 0

    sessions = 0
    db = _firestore()
    try:
        rows = focus_service.read_rows(db, uid) if db is not None else []
        for row in rows:
            if row.get("status") not in ("completed", "cancelled"):
                continue
            if focus_service.row_day(row) == _day_key(today):
                sessions += 1
    except Exception:  # pragma: no cover - defensive
        sessions = 0

    return {"quizzes": quizzes, "exams": exams, "focusSessions": sessions}


def _evening_block(uid: str, today: date) -> dict[str, Any]:
    """The evening half: progress, today's mistakes, tomorrow's recommendation.

    Rebuilt on every read because it reports *today* - and cheap: the mission
    comes from Phase 4's cache and the rest are single-pass reads.
    """
    brief = coach.daily_recommendation(uid)
    profile = _profile(uid)
    pattern = profile.get("studyPattern") or {}
    focus = brief.get("focus") or {}
    counts = _today_counts(uid, today)

    study_minutes = _as_int(focus.get("todayMinutes")) or _as_int(pattern.get("todayMinutes"))
    today_mistakes = _today_mistakes(uid, today)

    topics: dict[str, int] = defaultdict(int)
    for item in today_mistakes:
        topics[item["topic"]] += 1

    mission_count = brief.get("missionCount") or len(brief.get("mission") or [])
    score = _int(brief.get("healthScore"))

    parts: list[str] = []
    if study_minutes:
        parts.append(f"{study_minutes} min of deep work")
    if counts["focusSessions"]:
        parts.append(f"{counts['focusSessions']} focus session(s)")
    if counts["quizzes"]:
        parts.append(f"{counts['quizzes']} quiz(zes)")
    if counts["exams"]:
        parts.append(f"{counts['exams']} practice paper(s)")
    if today_mistakes:
        parts.append(f"{len(today_mistakes)} new mistake(s)")
    summary = (
        "Today: " + ", ".join(parts) + "."
        if parts
        else "Nothing logged today - tomorrow is a clean start."
    )

    # Tomorrow's recommendation: the top weakness, else keep the streak alive.
    try:
        analysis = coach.weakness_analysis(uid, profile=profile)
        priorities = analysis.get("priorities") or []
    except Exception:  # pragma: no cover - defensive
        priorities = []
    if priorities:
        top = priorities[0]
        topic = _text(top.get("topic"))
        reasons = ", ".join(top.get("reasons") or []) or "needs attention"
        tomorrow = {
            "topic": topic,
            "title": f"Start tomorrow with {topic}",
            "why": f"{topic}: {reasons}.",
            "minutes": 40,
            "action": _text(top.get("action")) or "Review the concept, then drill it.",
            "priority": top.get("priority"),
            "destination": "quiz",
        }
    else:
        tomorrow = {
            "topic": "",
            "title": "Keep the streak going",
            "why": (
                "No urgent gaps - one focus block keeps the routine intact."
                if brief.get("hasData")
                else "Log one quiz so tomorrow's brief has something to measure."
            ),
            "minutes": 25,
            "action": "Complete a 25 minute focus session.",
            "priority": "low",
            "destination": "focus",
        }

    return {
        "summary": summary,
        "progress": {
            "studyMinutes": study_minutes,
            "focusSessions": counts["focusSessions"],
            "quizzes": counts["quizzes"],
            "exams": counts["exams"],
            "mistakes": len(today_mistakes),
            "missionSteps": mission_count,
            "healthScore": score,
        },
        "mistakesToday": [
            {"topic": topic, "count": count}
            for topic, count in sorted(topics.items(), key=lambda kv: (-kv[1], kv[0]))
        ],
        "mistakesTodayCount": len(today_mistakes),
        "mistakesTotal": _as_int(profile.get("totalMistakes")),
        "tomorrow": tomorrow,
    }


def _fallback_reflection(facts: dict[str, Any]) -> str:
    parts: list[str] = []
    if facts.get("studyMinutes"):
        parts.append(f"You put in {facts['studyMinutes']} min of deep work.")
    if facts.get("quizzes"):
        parts.append(f"{facts['quizzes']} quiz(zes) logged.")
    if facts.get("mistakes"):
        parts.append(f"{facts['mistakes']} new mistake(s) to revisit.")
    if facts.get("healthScore") is not None:
        parts.append(f"Academic Health is {facts['healthScore']}/100.")
    if not parts:
        parts.append("A quiet day - tomorrow's plan is already set.")
    tomorrow = facts.get("tomorrowTopic") or ""
    if tomorrow:
        parts.append(f"Pick up with {tomorrow} tomorrow.")
    return " ".join(parts)


async def _ai_reflection(uid: str, facts: dict[str, Any]) -> str | None:
    """One short AI line for the evening brief; ``None`` when unavailable."""
    try:
        from app.services.ai_service import AiFeature, generate
    except Exception as exc:  # pragma: no cover - defensive
        logger.debug("ziku intel: ai_service unavailable (%s)", exc)
        return None

    prompt = (
        "Write one warm 1-2 sentence evening reflection for a university "
        "student. No headings, no lists, no invented facts, no emoji.\n"
        f"- Deep work today: {facts.get('studyMinutes', 0)} minutes\n"
        f"- Focus sessions: {facts.get('focusSessions', 0)}\n"
        f"- Quizzes: {facts.get('quizzes', 0)}\n"
        f"- Practice papers: {facts.get('exams', 0)}\n"
        f"- New mistakes: {facts.get('mistakes', 0)}\n"
        f"- Academic Health: {facts.get('healthScore')}\n"
        f"- Tomorrow's focus: {facts.get('tomorrowTopic') or 'a light review'}"
    )
    try:
        text = await generate(uid, prompt, feature=AiFeature.CHAT)
    except Exception as exc:
        logger.info("ziku intel: evening reflection unavailable (%s)", exc)
        return None
    return _text(text) or None


async def daily_brief(
    uid: str, *, phase: str = "auto", force: bool = False
) -> dict[str, Any]:
    """The upgraded daily brief - morning headings *and* an evening recap.

    The morning half and the AI reflection are cached for the day; the
    evening half is rebuilt on every read because it reports today's
    progress. ``phase`` is only what the client asked to be told about -
    both halves always come back so a screen can switch without a second
    round trip.
    """
    if phase not in PHASES:
        raise ValueError(f"phase must be one of {list(PHASES)}")

    now = _now()
    today = now.date()
    day_key = _day_key(today)
    resolved = _resolve_phase(phase)

    cached = _read_doc(uid, BRIEF_COLLECTION, day_key) or {}
    changed = False

    if force or not cached.get("morning"):
        cached["dayKey"] = day_key
        cached["morning"] = _morning_block(uid, force=force)
        changed = True

    evening = _evening_block(uid, today)

    reflection = "" if force else _text(cached.get("reflection"))
    ai_generated = False if force else bool(cached.get("reflectionAi"))
    if not reflection:
        facts = {**evening["progress"], "tomorrowTopic": evening["tomorrow"]["topic"]}
        generated = await _ai_reflection(uid, facts)
        ai_generated = bool(generated)
        reflection = _text(generated) or _fallback_reflection(facts)
        cached["reflection"] = reflection
        cached["reflectionAi"] = ai_generated
        changed = True

    evening["reflection"] = reflection
    evening["reflectionAi"] = ai_generated

    if changed:
        cached["dayKey"] = day_key
        cached["generatedAt"] = _iso(now)
        _write_doc(uid, BRIEF_COLLECTION, day_key, cached)

    return {
        "dayKey": day_key,
        "phase": resolved,
        "requestedPhase": phase,
        "morning": cached.get("morning") or {},
        "evening": evening,
        "generatedAt": now,
        "cached": bool(cached.get("morning")) and not changed,
    }


# ---------------------------------------------------------------------------
# 3. student learning profile (personality)
# ---------------------------------------------------------------------------

#: Session-start buckets, matching the coach's greeting hours.
_TIME_BUCKETS: tuple[tuple[str, str, int, int], ...] = (
    ("morning", "Morning", 5, 12),
    ("afternoon", "Afternoon", 12, 17),
    ("evening", "Evening", 17, 24),
    ("night", "Late night", 0, 5),
)


def _preferred_study_time(uid: str) -> dict[str, Any]:
    """When this student actually works, from the hours of their sessions."""
    counts: dict[str, int] = {key: 0 for key, _, _, _ in _TIME_BUCKETS}
    labelled: dict[str, str] = {key: label for key, label, _, _ in _TIME_BUCKETS}
    total = 0
    try:
        db = _firestore()
        rows = focus_service.read_rows(db, uid) if db is not None else []
        for row in rows:
            if row.get("status") not in ("completed", "cancelled"):
                continue
            started = focus_service.parse_iso(row.get("startedAtIso"))
            if started is None:
                continue
            hour = started.hour
            total += 1
            for key, _, lo, hi in _TIME_BUCKETS:
                if lo <= hour < hi:
                    counts[key] += 1
                    break
    except Exception as exc:  # pragma: no cover - defensive
        logger.debug("ziku intel: study time unavailable (%s)", exc)

    if not total:
        return {
            "key": "unknown",
            "label": "Not enough sessions yet",
            "sharePct": 0,
            "sessions": 0,
            "breakdown": counts,
            "evidence": "Finish a few focus sessions and your working hours appear here.",
        }

    key = max(counts, key=lambda k: counts[k])
    share = round(100.0 * counts[key] / total, 1)
    label = labelled[key]
    return {
        "key": key,
        "label": label,
        "sharePct": share,
        "sessions": total,
        "breakdown": counts,
        "evidence": f"{share}% of your finished sessions start in the {label.lower()}.",
    }


def _subject_split(uid: str) -> tuple[list[dict[str, Any]], list[dict[str, Any]], str]:
    """Strong / weak subjects (or topics when a quiz records no subject)."""
    totals: dict[str, dict[str, Any]] = defaultdict(lambda: {"score": 0, "count": 0})
    kind = "subject"
    for _, data in _read_rows(uid, "quiz_results"):
        score = _int(data.get("score"))
        if score is None:
            continue
        subject = _text(data.get("subjectId")) or _text(data.get("subject"))
        topic_scores = data.get("topicScores") or {}
        if subject:
            totals[subject]["score"] += score
            totals[subject]["count"] += 1
            continue
        kind = "topic"
        if isinstance(topic_scores, dict) and topic_scores:
            for topic, value in topic_scores.items():
                name = _text(topic)
                parsed = _int(value)
                if not name or parsed is None:
                    continue
                totals[name]["score"] += parsed
                totals[name]["count"] += 1
        else:
            totals["General"]["score"] += score
            totals["General"]["count"] += 1

    rows = [
        {
            "name": name,
            "average": round(bucket["score"] / bucket["count"], 1),
            "attempts": bucket["count"],
        }
        for name, bucket in totals.items()
        if bucket["count"]
    ]
    rows.sort(key=lambda r: (-r["average"], r["name"]))
    strong = [r for r in rows if r["average"] >= PASS_MARK][:MAX_TOPIC_LIST]
    weak = [r for r in rows if r["average"] < PASS_MARK]
    weak.sort(key=lambda r: (r["average"], r["name"]))
    return strong, weak[:MAX_TOPIC_LIST], kind


def _learning_style(
    *,
    quizzes: int,
    consistency: float | None,
    average_session: int | None,
    repeated: int,
    due: int,
    community_posts: int,
    practice_exams: int,
) -> dict[str, Any]:
    """Score five candidate styles on evidence and keep the heaviest one."""
    candidates: list[tuple[str, str, str, float]] = []

    deep = 0.0
    if consistency is not None and consistency >= 60:
        deep += 2
    if average_session and average_session >= 25:
        deep += 2
    if quizzes >= 10:
        deep += 1
    candidates.append(
        (
            "deep_worker",
            "Deep work blocks",
            "You finish long, uninterrupted sessions - protect that habit.",
            deep,
        )
    )
    candidates.append(
        (
            "practice_first",
            "Practice first",
            "You learn by answering: short sets beat long reads for you.",
            float(min(quizzes, 40)) / 8.0,
        )
    )
    candidates.append(
        (
            "revision_led",
            "Revision led",
            "You come back to what you missed - schedule the review instead of chasing it.",
            float(repeated * 2 + due),
        )
    )
    candidates.append(
        (
            "social_learner",
            "Learning out loud",
            "Explaining in the group is where your understanding sticks.",
            float(min(community_posts, 10)),
        )
    )
    candidates.append(
        (
            "exam_first",
            "Exam first",
            "You think under a clock - past papers are your best teacher.",
            float(min(practice_exams, 10)),
        )
    )

    key, label, why, weight = max(candidates, key=lambda c: c[3])
    return {"key": key, "label": label, "why": why, "score": round(weight, 1)}


def _quiz_count(uid: str) -> int:
    return sum(
        1 for _, data in _read_rows(uid, "quiz_results") if _int(data.get("score")) is not None
    )


def _focus_streak(uid: str) -> int:
    try:
        db = _firestore()
        if db is None:
            return 0
        active = {
            focus_service.row_day(row)
            for row in focus_service.read_rows(db, uid)
            if row.get("status") in ("completed", "cancelled")
            and focus_service.coerce_focus_seconds(row.get("accumulatedSeconds", 0)) > 0
        }
        return focus_service.calc_streak(active)
    except Exception:  # pragma: no cover - defensive
        return 0


def _community_totals(uid: str) -> tuple[int, int, int]:
    """``(points, accepted answers, posts)`` - one place, three numbers."""
    points = accepted = posts = 0
    try:
        from app.services.community_service import POSTS, REPUTATION

        db = _firestore()
        if db is None:
            return points, accepted, posts
        snap = db.collection(REPUTATION).document(uid).get()
        if snap is not None and snap.exists:
            data = snap.to_dict() or {}
            points = _as_int(data.get("points"))
            accepted = _as_int((data.get("breakdown") or {}).get("answer_accepted"))
        posts = sum(1 for _ in db.collection(POSTS).where("authorId", "==", uid).stream())
    except Exception as exc:  # pragma: no cover - defensive
        logger.debug("ziku intel: community totals unavailable (%s)", exc)
    return points, accepted, posts


def learning_personality(uid: str, *, force: bool = False) -> dict[str, Any]:
    """The Student Learning Profile: preferred time, style, strong/weak sides."""
    today = _now().date()
    day_key = _day_key(today)

    if not force:
        cached = _read_doc(uid, PERSONALITY_COLLECTION, CURRENT)
        if cached and _text(cached.get("dayKey")) == day_key:
            return {**cached, "cached": True}

    profile = _profile(uid, force=force)
    pattern = profile.get("studyPattern") or {}
    preferred = _preferred_study_time(uid)
    strong, weak, split_kind = _subject_split(uid)

    try:
        brain = mistakes.get_learning_brain(uid)
    except Exception as exc:  # pragma: no cover - defensive
        logger.debug("ziku intel: learning brain unavailable (%s)", exc)
        brain = {}

    points, _accepted, posts = _community_totals(uid)
    practice_exams = _as_int((profile.get("practiceExams") or {}).get("count"))
    consistency = _percent(pattern.get("focusConsistency"))
    average_session = _int(pattern.get("averageSessionMinutes"))
    repeated = _as_int(profile.get("repeatedMistakes")) or _as_int(brain.get("repeatedCount"))
    due = _as_int(profile.get("revisionDue")) or _as_int(brain.get("revisionDueCount"))
    quizzes = _quiz_count(uid)

    style = _learning_style(
        quizzes=quizzes,
        consistency=consistency,
        average_session=average_session,
        repeated=repeated,
        due=due,
        community_posts=posts,
        practice_exams=practice_exams,
    )
    label = STYLE_LABELS.get(style["key"], "The Balanced Learner")

    strengths: list[str] = []
    watchouts: list[str] = []
    if strong:
        strengths.append(f"Strongest in {strong[0]['name']} ({strong[0]['average']}%)")
    if consistency is not None and consistency >= 60:
        strengths.append(f"Focus consistency {consistency}% of the last 7 days")
    if points:
        strengths.append(f"{points} Learning Points earned helping others")
    if weak:
        watchouts.append(f"Weakest in {weak[0]['name']} ({weak[0]['average']}%)")
    if repeated:
        watchouts.append(f"{repeated} repeated mistake(s) waiting for a review")
    if due:
        watchouts.append(f"{due} revision(s) overdue")
    if not strengths:
        strengths.append("Take one quiz - the profile fills itself in from there")

    payload: dict[str, Any] = {
        "student": profile.get("student") or profile_name(uid),
        "dayKey": day_key,
        "hasData": bool(profile.get("hasData")),
        "title": "Student Learning Profile",
        "label": label,
        "personality": {
            "label": label,
            "preferredStudyTime": preferred,
            "learningStyle": style,
            "strongSubjects": strong,
            "weakSubjects": weak,
            "subjectKind": split_kind,
            "strengths": strengths[:3],
            "watchouts": watchouts[:3],
        },
        "evidence": {
            "quizzes": quizzes,
            "quizAverage": _int(profile.get("quizAverage")),
            "focusMinutes": _as_int(pattern.get("weekMinutes")),
            "focusConsistency": consistency,
            "averageSessionMinutes": average_session,
            "focusStreak": _focus_streak(uid),
            "mistakes": _as_int(profile.get("totalMistakes")),
            "repeatedMistakes": repeated,
            "revisionDue": due,
            "practiceExams": practice_exams,
            "communityPosts": posts,
            "communityPoints": points,
        },
        "healthScore": _as_int(profile.get("healthScore")),
        "weakTopics": profile.get("weakTopics") or [],
        "strongTopics": profile.get("strongTopics") or [],
        "generatedAt": _now(),
    }

    _write_doc(uid, PERSONALITY_COLLECTION, CURRENT, payload)
    return {**payload, "cached": False}


# ---------------------------------------------------------------------------
# 4. smart recommendation engine
# ---------------------------------------------------------------------------


def _candidate(
    key: str,
    source: str,
    title: str,
    detail: str,
    minutes: int,
    score: float,
    destination: str,
    *,
    target: str = "",
    evidence: dict[str, Any] | None = None,
) -> dict[str, Any]:
    return {
        "key": key,
        "source": source,
        "title": title,
        "detail": detail,
        "minutes": minutes,
        "score": round(score, 1),
        "destination": destination,
        "target": target,
        "evidence": evidence or {},
    }


def _coach_candidate(profile: dict[str, Any], analysis: dict[str, Any]) -> dict[str, Any]:
    priorities = analysis.get("priorities") or []
    exam_days = _int(analysis.get("examDaysRemaining"))
    if not priorities:
        return _candidate(
            "coach_baseline",
            "Study Coach",
            "Take one quiz so the coach can see where you stand",
            "No urgent gap is on record yet.",
            20,
            15,
            "quiz",
        )
    top = priorities[0]
    topic = _text(top.get("topic"))
    tier = _text(top.get("priority")) or "medium"
    score = {"high": 100.0, "medium": 60.0, "low": 25.0}.get(tier, 40.0)
    if exam_days is not None and exam_days <= 7:
        score += 15
    reasons = ", ".join(top.get("reasons") or []) or "needs attention"
    return _candidate(
        "coach_review",
        "Study Coach",
        f"Review {topic}",
        f"{topic}: {reasons}.",
        25,
        score,
        "review",
        target=topic,
        evidence={"priority": tier, "reasons": top.get("reasons") or []},
    )


def _mistake_candidate(profile: dict[str, Any]) -> dict[str, Any]:
    due = _as_int(profile.get("revisionDue"))
    repeated = _as_int(profile.get("repeatedMistakes"))
    if not due and not repeated:
        return _candidate(
            "mistakes_clear",
            "Mistake Memory",
            "Your revision queue is clear",
            "Nothing is overdue and nothing is repeating.",
            5,
            5,
            "review",
            evidence={"due": 0, "repeated": 0},
        )
    bits = []
    if due:
        bits.append(f"{due} revision(s) overdue")
    if repeated:
        bits.append(f"{repeated} repeated mistake(s)")
    return _candidate(
        "mistakes_review",
        "Mistake Memory",
        "Clear the revision queue",
        "; ".join(bits) + " - one pass clears them all.",
        20,
        min(110.0, due * 8 + repeated * 6),
        "review",
        evidence={"due": due, "repeated": repeated},
    )


def _exam_candidate(profile: dict[str, Any]) -> dict[str, Any]:
    exam = profile.get("upcomingExam") or {}
    days = _int(exam.get("daysRemaining"))
    readiness = _int(profile.get("examReadiness"))
    practice = profile.get("practiceExams") or {}
    average = _float(practice.get("averagePercentage"))

    if days is None:
        if _as_int(practice.get("count")):
            return _candidate(
                "exam_practice",
                "Exam Simulator",
                "Sit a short practice paper",
                "Your last papers average "
                f"{average if average is not None else '-'}% - keep the habit warm.",
                30,
                35,
                "exam",
                evidence={"practiceCount": practice.get("count"), "average": average},
            )
        return _candidate(
            "exam_first",
            "Exam Simulator",
            "Build your first practice paper",
            "One paper gives the simulator (and you) a baseline.",
            30,
            30,
            "exam",
            evidence={"practiceCount": 0},
        )

    score = 95.0 if days <= 3 else (80.0 if days <= 7 else 55.0)
    title = _text(exam.get("title")) or "your exam"
    return _candidate(
        "exam_rescue",
        "Exam Simulator",
        f"Prepare for {title}",
        f"{title} is in {days} day(s)"
        + (f" - readiness {readiness}/100" if readiness is not None else "")
        + ".",
        45,
        score,
        "rescue",
        evidence={"daysRemaining": days, "examReadiness": readiness},
    )


def _focus_candidate(uid: str, profile: dict[str, Any]) -> dict[str, Any]:
    pattern = profile.get("studyPattern") or {}
    today_minutes = _as_int(pattern.get("todayMinutes"))
    streak = _focus_streak(uid)

    goal = 60
    try:
        db = _firestore()
        if db is not None:
            goal = focus_service.goal_minutes(db, uid) or goal
    except Exception:  # pragma: no cover - defensive
        goal = 60

    remaining = max(0, goal - today_minutes)
    if remaining <= 0:
        return _candidate(
            "focus_done",
            "Ziku Focus Engine",
            "Today's focus goal is met",
            f"{today_minutes} of {goal} minutes already banked.",
            0,
            8,
            "focus",
            evidence={"todayMinutes": today_minutes, "goal": goal, "streak": streak},
        )
    score = 45.0 + (15.0 if today_minutes == 0 and streak >= 3 else 0.0)
    return _candidate(
        "focus_block",
        "Ziku Focus Engine",
        f"Bank {remaining} more focus minutes",
        f"{today_minutes}/{goal} minutes today"
        + (f", {streak} day streak at risk" if streak else "")
        + ".",
        max(15, min(remaining, 45)),
        score,
        "focus",
        evidence={"todayMinutes": today_minutes, "goal": goal, "streak": streak},
    )


def _community_candidate(uid: str) -> dict[str, Any]:
    """Community insights: the group's hot chapter, or the invitation to one."""
    try:
        from app.services.community_service import GROUPS, group_insights_data

        db = _firestore()
        if db is None:
            raise RuntimeError("no firestore")
        group_id = ""
        for snap in db.collection(GROUPS).where("memberIds", "array_contains", uid).stream():
            group_id = snap.id
            break
        if not group_id:
            return _candidate(
                "community_join",
                "Learning Community",
                "Join a study group",
                "Group insight, hot chapters and peer answers all start here.",
                10,
                20,
                "community",
                evidence={"groups": 0},
            )
        insights = group_insights_data(group_id)
        hot = insights.get("hotChapters") or []
        if hot:
            chapter = _text(hot[0].get("chapter")) or "a new chapter"
            subject = _text(hot[0].get("subject"))
            return _candidate(
                "community_hot",
                "Learning Community",
                f"Your group is drilling {chapter}",
                f"{chapter} ({subject}) is the hottest chapter in your group."
                if subject
                else f"{chapter} is the hottest chapter in your group.",
                20,
                45,
                "community",
                target=chapter,
                evidence={
                    "groupHotChapter": chapter,
                    "questionCount": insights.get("questionCount"),
                },
            )
        return _candidate(
            "community_ask",
            "Learning Community",
            "Ask one question in your group",
            "Your group is quiet - a question gives everyone something to work on.",
            10,
            30,
            "community",
            evidence={"groupHotChapter": ""},
        )
    except Exception as exc:  # pragma: no cover - defensive
        logger.debug("ziku intel: community candidate unavailable (%s)", exc)
        return _candidate(
            "community_unavailable",
            "Learning Community",
            "Check your study group",
            "Group insight is unavailable right now.",
            5,
            5,
            "community",
        )


def next_best_action(uid: str, *, force: bool = False) -> dict[str, Any]:
    """The one thing to do next - five systems, one ranked answer.

    Every system offers a candidate; the highest score wins and the rest come
    back as alternatives so the UI can show *why* this one, not just *what*.
    """
    today = _now().date()
    day_key = _day_key(today)

    if not force:
        cached = _read_doc(uid, ACTION_COLLECTION, day_key)
        if cached:
            return {**cached, "cached": True}

    profile = _profile(uid, force=force)
    try:
        analysis = coach.weakness_analysis(uid, profile=profile)
    except Exception as exc:  # pragma: no cover - defensive
        logger.debug("ziku intel: weakness analysis unavailable (%s)", exc)
        analysis = {"priorities": [], "examDaysRemaining": None}

    candidates = [
        _coach_candidate(profile, analysis),
        _mistake_candidate(profile),
        _exam_candidate(profile),
        _focus_candidate(uid, profile),
        _community_candidate(uid),
    ]
    candidates.sort(key=lambda c: -c["score"])
    best = candidates[0]

    points, _accepted, _posts = _community_totals(uid)
    payload: dict[str, Any] = {
        "dayKey": day_key,
        "action": best,
        "alternatives": candidates[1 : 1 + MAX_ALTERNATIVES],
        "why": f"{best['source']}: {best['detail']}",
        "sources": {
            "coach": {
                "priority": ((analysis.get("priorities") or [{}])[0]).get("topic", ""),
                "priorityCount": len(analysis.get("priorities") or []),
                "examDaysRemaining": analysis.get("examDaysRemaining"),
            },
            "mistakes": {
                "due": _as_int(profile.get("revisionDue")),
                "repeated": _as_int(profile.get("repeatedMistakes")),
                "total": _as_int(profile.get("totalMistakes")),
            },
            "exams": profile.get("practiceExams") or {},
            "focus": {
                "todayMinutes": _as_int(
                    (profile.get("studyPattern") or {}).get("todayMinutes")
                ),
                "streak": _focus_streak(uid),
            },
            "community": {"points": points},
        },
        "generatedAt": _now(),
    }

    _write_doc(uid, ACTION_COLLECTION, day_key, payload)
    return {**payload, "cached": False}


def chat_line(uid: str) -> str | None:
    """One cached line for Ziku's system prompt - never a rebuild.

    Chat runs on every message, so this only reads what a dashboard open has
    already written. Nothing earned, nothing cached, means no line.
    """
    day_key = _day_key(_now().date())
    parts: list[str] = []

    action = _read_doc(uid, ACTION_COLLECTION, day_key)
    if isinstance(action, dict):
        title = _text((action.get("action") or {}).get("title"))
        if title:
            parts.append(f"next best action: {title}")

    earned = (_read_doc(uid, ACHIEVEMENTS_COLLECTION, CURRENT) or {}).get("earned") or {}
    unlocked_today = sum(1 for stamp in earned.values() if _day_of(stamp) == _now().date())
    if unlocked_today:
        parts.append(f"{unlocked_today} achievement(s) unlocked today")

    if not parts:
        return None
    return "Personal OS: " + "; ".join(parts)


# ---------------------------------------------------------------------------
# 5. achievement system
# ---------------------------------------------------------------------------


def _focus_session_count(uid: str) -> int:
    try:
        db = _firestore()
        if db is None:
            return 0
        return sum(
            1
            for row in focus_service.read_rows(db, uid)
            if row.get("status") in ("completed", "cancelled")
        )
    except Exception:  # pragma: no cover - defensive
        return 0


def _metrics(uid: str) -> dict[str, float | int]:
    """Every number an achievement grades against - read once, all of them."""
    profile = _profile(uid)

    quizzes = _quiz_count(uid)
    quiz_average = _int(profile.get("quizAverage")) or 0

    exam_improvement = 0.0
    try:
        exam_improvement = _float(
            exam_pro_service.history(uid, limit=20).get("improvement")
        ) or 0.0
    except Exception:  # pragma: no cover - defensive
        exam_improvement = 0.0

    trend = profile.get("trend") if isinstance(profile.get("trend"), dict) else {}
    health_delta = max(0, _int(trend.get("delta")) or 0)

    health_score = _as_int(profile.get("healthScore"))
    if not health_score:
        try:
            rows = health.get_history(uid, days=TIMELINE_DAYS).get("history") or []
            scores = [s for s in (_int(p.get("score")) for p in rows if isinstance(p, dict)) if s is not None]
            health_score = scores[-1] if scores else 0
        except Exception:  # pragma: no cover - defensive
            health_score = 0

    points, accepted, posts = _community_totals(uid)

    return {
        # ``quizAverage`` only counts once ten quizzes exist, so Sharpshooter
        # cannot be won on a single lucky set.
        "quizzes": quizzes,
        "quizAverage": quiz_average if quizzes >= 10 else 0,
        "streak": _focus_streak(uid),
        "focusSessions": _focus_session_count(uid),
        "healthDelta": health_delta,
        "healthScore": health_score,
        "examImprovement": exam_improvement,
        "revisionDue": _as_int(profile.get("revisionDue")),
        "communityPosts": posts,
        "acceptedAnswers": accepted,
        "points": points,
    }


def _progress(current: float | int, target: float | int) -> float:
    """0..1 progress. ``target == 0`` is an "at most zero" bar."""
    if target == 0:
        return 1.0 if current <= 0 else 0.0
    if target <= 0:
        return 0.0
    return max(0.0, min(1.0, round(float(current) / float(target), 4)))


def achievements(uid: str, *, force: bool = False) -> dict[str, Any]:
    """The scoreboard: 16 achievements across the four asked-for kinds.

    Progress is computed every read; an "earned" stamp is written **only**
    when a bar first fills, so a metric that later regresses (a streak that
    breaks) does not un-earn anything.
    """
    metrics = _metrics(uid)
    earned: dict[str, Any] = {}
    if not force:
        cached = _read_doc(uid, ACHIEVEMENTS_COLLECTION, CURRENT) or {}
        earned = dict(cached.get("earned") or {})

    now_iso = _iso(_now())
    changed = False
    rows: list[dict[str, Any]] = []
    for spec in ACHIEVEMENTS:
        current = metrics.get(spec["metric"], 0)
        progress = _progress(current, spec["target"])
        if progress >= 1.0 and spec["id"] not in earned:
            earned[spec["id"]] = now_iso
            changed = True
        rows.append(
            {
                "id": spec["id"],
                "category": spec["category"],
                "metric": spec["metric"],
                "title": spec["title"],
                "description": spec["description"],
                "current": current,
                "target": spec["target"],
                "progress": progress,
                "earned": spec["id"] in earned,
                "earnedAt": earned.get(spec["id"]),
            }
        )

    if changed:
        _write_doc(
            uid,
            ACHIEVEMENTS_COLLECTION,
            CURRENT,
            {"earned": earned, "updatedAt": now_iso},
        )

    by_category = {
        category: sum(1 for r in rows if r["category"] == category and r["earned"])
        for category in ACHIEVEMENT_CATEGORIES
    }
    totals = {
        category: sum(1 for r in rows if r["category"] == category)
        for category in ACHIEVEMENT_CATEGORIES
    }
    locked = sorted((r for r in rows if not r["earned"]), key=lambda r: -r["progress"])

    return {
        "dayKey": _day_key(_now().date()),
        "hasData": any(
            metrics.get(key)
            for key in ("quizzes", "focusSessions", "communityPosts", "points")
        ),
        "counts": {
            "earned": sum(1 for r in rows if r["earned"]),
            "locked": len(locked),
            "total": len(rows),
            "earnedByCategory": by_category,
            "totalByCategory": totals,
        },
        "categories": [
            {"key": category, "earned": by_category[category], "total": totals[category]}
            for category in ACHIEVEMENT_CATEGORIES
        ],
        "achievements": rows,
        "next": locked[0] if locked else None,
        "metrics": metrics,
        "earnedAt": earned,
        "generatedAt": _now(),
    }
