"""Phase 15.2 — Exam Priority Engine.

Deterministic, explainable priority scoring that combines historical exam
importance with the student's actual learning state.

Formula (documented, not AI-chosen):
  priorityScore =
      0.30 * historicalFrequency +
      0.25 * masteryGap +
      0.20 * mistakePressure +
      0.15 * revisionUrgency +
      0.10 * recentPerformanceGap

Every component is normalized 0–100. AI may explain the score but NEVER
selects the numeric value.

Priority labels:
  85–100 → CRITICAL
  70–84  → HIGH
  45–69  → MEDIUM
  0–44   → LOW
"""

from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone
from typing import Any

from app.core.firebase import get_firestore

logger = logging.getLogger("gochano.exam_priority")

# ---------------------------------------------------------------------------
# Formula weights (sum to 1.0)
# ---------------------------------------------------------------------------

W_HISTORICAL   = 0.30
W_MASTERY_GAP  = 0.25
W_MISTAKE      = 0.20
W_REVISION     = 0.15
W_RECENT_PERF  = 0.10

# Thresholds
MASTERY_TARGET = 0.80       # 80 % mastery = full competence
OVERDUE_DAYS_CAP = 30       # beyond 30 days overdue → max urgency


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _nowiso() -> str:
    return _now().isoformat()


def _db():
    return get_firestore()


def _clamp(value: float) -> float:
    return max(0.0, min(100.0, float(value)))


# ---------------------------------------------------------------------------
# Priority label
# ---------------------------------------------------------------------------

def _priority_label(score: float) -> str:
    if score >= 85:
        return "critical"
    if score >= 70:
        return "high"
    if score >= 45:
        return "medium"
    return "low"


# ---------------------------------------------------------------------------
# Component calculators (all return float 0–100)
# ---------------------------------------------------------------------------

def _calc_historical_frequency(topic_stats: dict[str, Any]) -> float:
    """Historical frequency score straight from past-paper analysis."""
    return _clamp(float(topic_stats.get("historicalFrequencyScore") or 0))


def _calc_mastery_gap(mastery_record: dict[str, Any]) -> float:
    """
    Gap from target mastery (80%). If mastery=40%, gap=40/80=50 → 50 score.
    Perfect mastery → 0 gap score (no priority boost from this component).
    Missing data → neutral 50 (documented fallback, not perfect 0).
    """
    if not mastery_record:
        return 50.0  # neutral — missing data documented
    # Use explicit None check so 0.0 mastery is not treated as missing
    raw_mastery = mastery_record.get("masteryScore")
    if raw_mastery is None:
        raw_mastery = mastery_record.get("mastery")
    if raw_mastery is None:
        return 50.0  # neutral — no mastery data
    mastery = float(raw_mastery)
    gap = max(0.0, MASTERY_TARGET - mastery)
    # Normalize gap (0–0.8 range) to 0–100
    return _clamp((gap / MASTERY_TARGET) * 100)


def _calc_mistake_pressure(mistake_stats: dict[str, Any]) -> float:
    """
    Mistake pressure based on repeat mistakes and unreviewed count.
    repeat_count → exponential pressure; unreviewed → linear boost.
    Missing data → 0 (safer: don't penalize absence of mistakes).
    """
    if not mistake_stats:
        return 0.0
    repeat_count = int(mistake_stats.get("repeatCount") or 0)
    unreviewed = int(mistake_stats.get("unreviewed") or 0)
    recent_mistakes = int(mistake_stats.get("recentMistakes") or 0)

    # Exponential pressure from repeats (caps at ~100)
    repeat_pressure = min(100.0, repeat_count * 25.0)
    # Linear unreviewed boost
    unreviewed_boost = min(40.0, unreviewed * 10.0)
    # Recent mistakes boost
    recent_boost = min(30.0, recent_mistakes * 10.0)

    return _clamp(0.50 * repeat_pressure + 0.30 * unreviewed_boost + 0.20 * recent_boost)


def _calc_revision_urgency(revision_record: dict[str, Any]) -> float:
    """
    Spaced-repetition urgency from revision queue.
    overdue_days > 0 → escalating urgency.
    Missing data → 0 (no revision → no urgency from this component).
    """
    if not revision_record:
        return 0.0
    next_review_str = revision_record.get("nextReviewDate") or revision_record.get("dueDate")
    if not next_review_str:
        return 0.0
    try:
        if isinstance(next_review_str, str):
            next_review = datetime.fromisoformat(
                next_review_str.replace("Z", "+00:00")
            )
        elif hasattr(next_review_str, "to_datetime"):
            next_review = next_review_str.to_datetime()
        else:
            return 0.0
        if next_review.tzinfo is None:
            next_review = next_review.replace(tzinfo=timezone.utc)
        overdue_days = (_now() - next_review).days
        if overdue_days <= 0:
            return 0.0  # not yet due
        # Normalize: each overdue day adds urgency; cap at OVERDUE_DAYS_CAP
        return _clamp((overdue_days / OVERDUE_DAYS_CAP) * 100)
    except Exception:
        return 0.0


def _calc_recent_performance_gap(performance_record: dict[str, Any]) -> float:
    """
    Gap between recent quiz/test scores and target.
    Missing data → neutral 50 (documented).
    """
    if not performance_record:
        return 50.0  # neutral
    avg_score = float(performance_record.get("averageScore") or
                      performance_record.get("recentScore") or 0)
    # avg_score expected 0–100
    target = 75.0  # documented performance target
    gap = max(0.0, target - avg_score)
    return _clamp((gap / target) * 100)


# ---------------------------------------------------------------------------
# Data collection helpers
# ---------------------------------------------------------------------------

def _get_topic_stats(uid: str, topic: str) -> dict[str, Any]:
    db = _db()
    if db is None:
        return {}
    try:
        import hashlib
        topic_key = hashlib.sha256(topic.encode()).hexdigest()[:20]
        doc = (
            db.collection("users").document(uid)
            .collection("exam_ecosystem").document("default")
            .collection("topic_stats").document(topic_key)
            .get()
        )
        return doc.to_dict() or {} if doc.exists else {}
    except Exception:
        return {}


def _get_mastery_record(uid: str, topic: str) -> dict[str, Any]:
    """Pull mastery from canonical Learning Memory."""
    try:
        from app.services.learning_memory_service import get_topic_mastery
        result = get_topic_mastery(uid, topic)
        return result or {}
    except Exception:
        return {}


def _get_mistake_stats(uid: str, topic: str) -> dict[str, Any]:
    """Aggregate mistake stats for a topic from canonical Mistake Memory."""
    db = _db()
    if db is None:
        return {}
    try:
        docs = (
            db.collection("users").document(uid).collection("mistakes")
            .where("topic", "==", topic)
            .limit(100)
            .stream()
        )
        repeat_count = 0
        unreviewed = 0
        recent_mistakes = 0
        cutoff = _now() - timedelta(days=14)
        for doc in docs:
            data = doc.to_dict() or {}
            occ = int(data.get("occurrences") or 1)
            if occ > 1:
                repeat_count += occ - 1
            if data.get("analysisStatus") != "analyzed":
                unreviewed += 1
            # recent mistakes (last 14 days)
            last_seen = data.get("lastSeenAt") or data.get("createdAt")
            if last_seen:
                try:
                    if isinstance(last_seen, str):
                        dt = datetime.fromisoformat(last_seen.replace("Z", "+00:00"))
                    elif hasattr(last_seen, "to_datetime"):
                        dt = last_seen.to_datetime()
                    else:
                        dt = None
                    if dt and dt.tzinfo is None:
                        dt = dt.replace(tzinfo=timezone.utc)
                    if dt and dt >= cutoff:
                        recent_mistakes += 1
                except Exception:
                    pass
        return {
            "repeatCount": repeat_count,
            "unreviewed": unreviewed,
            "recentMistakes": recent_mistakes,
        }
    except Exception as exc:
        logger.debug("Mistake stats error for %s/%s: %s", uid, topic, exc)
        return {}


def _get_revision_record(uid: str, topic: str) -> dict[str, Any]:
    """Find the most overdue revision entry for this topic."""
    db = _db()
    if db is None:
        return {}
    try:
        docs = (
            db.collection("users").document(uid).collection("mistakes")
            .where("topic", "==", topic)
            .order_by("nextReviewDate")
            .limit(5)
            .stream()
        )
        earliest = None
        for doc in docs:
            data = doc.to_dict() or {}
            nrd = data.get("nextReviewDate")
            if nrd and (earliest is None or nrd < earliest):
                earliest = nrd
        if earliest:
            return {"nextReviewDate": earliest}
        return {}
    except Exception:
        return {}


def _get_performance_record(uid: str, topic: str) -> dict[str, Any]:
    """Get recent quiz performance for this topic from quiz_results."""
    db = _db()
    if db is None:
        return {}
    try:
        docs = (
            db.collection("users").document(uid).collection("quiz_results")
            .where("topic", "==", topic)
            .order_by("createdAt", direction="DESCENDING")
            .limit(5)
            .stream()
        )
        scores = []
        for doc in docs:
            data = doc.to_dict() or {}
            score = data.get("score") or data.get("percentage")
            if score is not None:
                scores.append(float(score))
        if scores:
            return {"averageScore": sum(scores) / len(scores)}
        return {}
    except Exception:
        return {}


# ---------------------------------------------------------------------------
# Core scoring function
# ---------------------------------------------------------------------------

def score_topic(
    uid: str,
    topic: str,
    *,
    topic_stats: dict[str, Any] | None = None,
    mastery_record: dict[str, Any] | None = None,
    mistake_stats: dict[str, Any] | None = None,
    revision_record: dict[str, Any] | None = None,
    performance_record: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """
    Calculate the deterministic priority score for a topic.

    All numeric components are computed here; AI does NOT select numbers.
    Callers may pass pre-fetched data to avoid N+1 database reads.
    """
    ts = topic_stats if topic_stats is not None else _get_topic_stats(uid, topic)
    mr = mastery_record if mastery_record is not None else _get_mastery_record(uid, topic)
    ms = mistake_stats if mistake_stats is not None else _get_mistake_stats(uid, topic)
    rr = revision_record if revision_record is not None else _get_revision_record(uid, topic)
    pr = performance_record if performance_record is not None else _get_performance_record(uid, topic)

    hist_freq     = _calc_historical_frequency(ts)
    mastery_gap   = _calc_mastery_gap(mr)
    mistake_press = _calc_mistake_pressure(ms)
    rev_urgency   = _calc_revision_urgency(rr)
    recent_gap    = _calc_recent_performance_gap(pr)

    priority_score = _clamp(
        W_HISTORICAL  * hist_freq    +
        W_MASTERY_GAP * mastery_gap  +
        W_MISTAKE     * mistake_press +
        W_REVISION    * rev_urgency  +
        W_RECENT_PERF * recent_gap
    )
    priority_score = round(priority_score, 1)
    label = _priority_label(priority_score)

    return {
        "topic": topic,
        "priorityScore": priority_score,
        "priority": label,
        "components": {
            "historicalFrequency": round(hist_freq, 1),
            "masteryGap": round(mastery_gap, 1),
            "mistakePressure": round(mistake_press, 1),
            "revisionUrgency": round(rev_urgency, 1),
            "recentPerformanceGap": round(recent_gap, 1),
        },
        "weights": {
            "historicalFrequency": W_HISTORICAL,
            "masteryGap": W_MASTERY_GAP,
            "mistakePressure": W_MISTAKE,
            "revisionUrgency": W_REVISION,
            "recentPerformanceGap": W_RECENT_PERF,
        },
        "calculatedAt": _nowiso(),
    }


# ---------------------------------------------------------------------------
# Batch recalculation
# ---------------------------------------------------------------------------

def _all_topics_for_user(uid: str) -> list[str]:
    """Collect all known topics from past papers + learning memory."""
    topics: set[str] = set()

    # From past paper topic stats
    db = _db()
    if db is not None:
        try:
            docs = (
                db.collection("users").document(uid)
                .collection("exam_ecosystem").document("default")
                .collection("topic_stats")
                .limit(200)
                .stream()
            )
            for doc in docs:
                data = doc.to_dict() or {}
                t = data.get("topic")
                if t:
                    topics.add(t)
        except Exception:
            pass

    # From learning memory (mastery topics)
    try:
        from app.services.learning_memory_service import get_all_topics_mastery
        mastery_data = get_all_topics_mastery(uid)
        if isinstance(mastery_data, list):
            for item in mastery_data:
                t = item.get("topic")
                if t:
                    topics.add(t)
        elif isinstance(mastery_data, dict):
            topics.update(mastery_data.keys())
    except Exception:
        pass

    return sorted(topics)


def _persist_priority(uid: str, scored_topic: dict[str, Any]) -> None:
    db = _db()
    if db is None:
        return
    try:
        import hashlib
        key = hashlib.sha256(
            scored_topic["topic"].encode()
        ).hexdigest()[:20]
        db.collection("users").document(uid) \
            .collection("exam_ecosystem").document("default") \
            .collection("priority_topics").document(key).set(scored_topic)
    except Exception as exc:
        logger.warning("Failed to persist priority for %s: %s",
                       scored_topic.get("topic"), exc)


def recalculate_priorities(uid: str) -> list[dict[str, Any]]:
    """
    Recalculate priority scores for all known topics for a user.
    Returns sorted list (CRITICAL first).
    """
    topics = _all_topics_for_user(uid)
    if not topics:
        return []

    scored = []
    for topic in topics:
        result = score_topic(uid, topic)
        _persist_priority(uid, result)
        scored.append(result)

    scored.sort(key=lambda x: x["priorityScore"], reverse=True)
    logger.info("Recalculated priorities for %s: %d topics", uid, len(scored))
    return scored


def get_priority_topics(
    uid: str,
    *,
    limit: int = 20,
    priority_filter: str | None = None,
) -> list[dict[str, Any]]:
    """
    Return persisted priority topics for the UI.
    Reads from Firestore — no recalculation triggered.
    """
    db = _db()
    if db is None:
        return []
    try:
        col = (
            db.collection("users").document(uid)
            .collection("exam_ecosystem").document("default")
            .collection("priority_topics")
        )
        query = col.order_by("priorityScore", direction="DESCENDING")
        if priority_filter:
            query = col.where("priority", "==", priority_filter.lower())
        docs = query.limit(limit).stream()
        return [d.to_dict() or {} for d in docs]
    except Exception as exc:
        logger.warning("get_priority_topics failed: %s", exc)
        return []
