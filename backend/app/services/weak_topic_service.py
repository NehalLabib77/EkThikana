"""Phase 3C-2 — Weak Topic Detection Service.

Aggregates quiz_results topicScores to identify topics where the student
needs improvement. Pure data aggregation — no AI calls.
"""
from __future__ import annotations

import logging
from collections import defaultdict
from typing import Any

from app.core.firebase import get_firestore

logger = logging.getLogger("gochano.ai_study")

# Default threshold: topics below this average score are flagged as weak.
DEFAULT_WEAK_THRESHOLD = 60

# Minimum attempts before a topic is considered for weak detection.
# Prevents flagging a topic from a single bad quiz.
MIN_ATTEMPTS = 1


def _canonical_mastery(uid: str) -> dict[str, dict[str, Any]]:
    """One canonical read per call, keyed by topic.

    The adapter imports lazily so the module graph stays acyclic:
    ``learning_memory_service`` already depends on Mistake Memory, which
    depends on this module.
    """
    try:
        from app.services import learning_memory_service as memory

        return {
            str(record.get("topic") or ""): record
            for record in memory.get_all_topics_mastery(uid)
        }
    except Exception as exc:  # pragma: no cover - defensive
        logger.debug("weak topic adapter: canonical mastery unavailable: %s", exc)
        return {}


def get_weak_topics(
    uid: str,
    threshold: int = DEFAULT_WEAK_THRESHOLD,
    min_attempts: int = MIN_ATTEMPTS,
) -> list[dict[str, Any]]:
    """Analyze quiz history and return topics below the mastery threshold.

    Compatibility adapter: the legacy 0-100 contract (``topic``,
    ``average_score``, ``attempts``, ``recommendation`` and the 0-100
    ``threshold``) is preserved exactly, while ``mastery`` / ``confidence`` /
    ``signals`` are delegated to the canonical
    :func:`learning_memory_service.get_all_topics_mastery` so the numbers a
    legacy consumer reads are the same numbers every other consumer reads.

    Args:
        uid: Firebase Auth UID of the student.
        threshold: Average score below which a topic is considered weak (0-100).
        min_attempts: Minimum number of quiz attempts before flagging.

    Returns:
        List of weak topic dicts, sorted by average score ascending (weakest first).
        Each dict contains: topic, average_score, attempts, recommendation.
    """
    db = get_firestore()
    if db is None:
        logger.warning("Firestore unavailable, cannot compute weak topics")
        return []

    canonical = _canonical_mastery(uid)

    # Fetch all quiz results for the user
    docs = (
        db.collection("users")
        .document(uid)
        .collection("quiz_results")
        .order_by("createdAt", direction="DESCENDING")
        .limit(100)
        .stream()
    )

    # Aggregate topic scores across all quizzes
    # topic -> {total_score: int, count: int}
    topic_data: dict[str, dict[str, int]] = defaultdict(
        lambda: {"total_score": 0, "count": 0}
    )

    for snap in docs:
        data = snap.to_dict() or {}
        topic_scores = data.get("topicScores") or {}

        for topic, score in topic_scores.items():
            topic = topic.strip()
            if not topic:
                continue
            # Normalize score to 0-100 range
            if isinstance(score, (int, float)):
                topic_data[topic]["total_score"] += int(score)
                topic_data[topic]["count"] += 1

    # Find weak topics
    weak_topics = []
    for topic, agg in topic_data.items():
        attempts = agg["count"]
        if attempts < min_attempts:
            continue
        avg_score = agg["total_score"] // attempts
        if avg_score < threshold:
            recommendation = _generate_recommendation(topic, avg_score, attempts)
            record = canonical.get(topic)
            if record is not None:
                mastery = float(record["mastery"])
                confidence = float(record["confidence"])
                signals = dict(record["signals"])
            else:
                mastery = round(max(0.0, min(1.0, avg_score / 100.0)), 2)
                confidence = round(min(1.0, max(0.0, attempts / 5.0)), 2)
                signals = {
                    "quizAccuracy": float(avg_score),
                    "quizAttempts": attempts,
                }
            weak_topics.append({
                "topic": topic,
                "average_score": avg_score,
                "attempts": attempts,
                "recommendation": recommendation,
                "mastery": mastery,
                "confidence": confidence,
                "signals": signals,
            })

    # Sort by average score ascending (weakest first)
    weak_topics.sort(key=lambda x: x["average_score"])

    logger.info(
        "Weak topic analysis: uid=%s total_topics=%d weak_topics=%d threshold=%d",
        uid, len(topic_data), len(weak_topics), threshold,
    )

    return weak_topics


def get_learning_summary(uid: str) -> dict[str, Any]:
    """Get a summary of the user's learning performance across all quizzes.

    Returns:
        Dict with total_quizzes, average_score, total_topics,
        strong_topics, weak_topics, recent_trend.
    """
    db = get_firestore()
    if db is None:
        return {
            "total_quizzes": 0,
            "average_score": 0,
            "total_topics": 0,
            "strong_topics": [],
            "weak_topics": [],
        }

    docs = (
        db.collection("users")
        .document(uid)
        .collection("quiz_results")
        .order_by("createdAt", direction="DESCENDING")
        .limit(100)
        .stream()
    )

    total_quizzes = 0
    total_score = 0
    topic_data: dict[str, dict[str, int]] = defaultdict(
        lambda: {"total_score": 0, "count": 0}
    )

    for snap in docs:
        data = snap.to_dict() or {}
        score = data.get("score", 0)
        total_quizzes += 1
        total_score += score

        topic_scores = data.get("topicScores") or {}
        for topic, ts in topic_scores.items():
            topic = topic.strip()
            if not topic:
                continue
            if isinstance(ts, (int, float)):
                topic_data[topic]["total_score"] += int(ts)
                topic_data[topic]["count"] += 1

    avg_score = total_score // total_quizzes if total_quizzes > 0 else 0

    strong_topics = []
    weak_topics = []
    for topic, agg in topic_data.items():
        if agg["count"] < 1:
            continue
        topic_avg = agg["total_score"] // agg["count"]
        entry = {
            "topic": topic,
            "average_score": topic_avg,
            "attempts": agg["count"],
        }
        if topic_avg >= 70:
            strong_topics.append(entry)
        elif topic_avg < DEFAULT_WEAK_THRESHOLD:
            weak_topics.append(entry)

    strong_topics.sort(key=lambda x: x["average_score"], reverse=True)
    weak_topics.sort(key=lambda x: x["average_score"])

    return {
        "total_quizzes": total_quizzes,
        "average_score": avg_score,
        "total_topics": len(topic_data),
        "strong_topics": strong_topics[:10],
        "weak_topics": weak_topics[:10],
    }


def _generate_recommendation(topic: str, avg_score: int, attempts: int) -> str:
    """Generate a simple text recommendation based on performance."""
    topic_lower = topic.lower()

    if avg_score < 30:
        base = f"Focus on understanding the fundamentals of '{topic}'. "
        if attempts <= 1:
            return base + "Try reading your notes or textbook on this topic first."
        return base + "Review your notes and practice more questions on this topic."

    if avg_score < 50:
        base = f"You're getting started with '{topic}'. "
        return base + "Review the key concepts and take another practice quiz."

    # 50-59 range
    base = f"You're close to mastering '{topic}'. "
    return base + "Review the specific areas you missed and try one more quiz."
