"""Phase 10.6 - deterministic admin analytics over canonical events."""

from __future__ import annotations

from collections import defaultdict
from datetime import datetime, timedelta, timezone
from typing import Any

from app.core import firebase
from app.services.analytics_service import EVENTS_COLLECTION

MIN_TOPIC_SAMPLE = 3


def _date(value: Any) -> datetime:
    if isinstance(value, datetime):
        return value if value.tzinfo else value.replace(tzinfo=timezone.utc)
    if isinstance(value, str):
        try:
            parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
            return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)
        except ValueError:
            pass
    return datetime.min.replace(tzinfo=timezone.utc)


def _number(value: Any, default: float = 0.0) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def read_events(days: int = 30) -> list[dict[str, Any]]:
    cutoff = datetime.now(timezone.utc) - timedelta(days=max(1, min(days, 365)))
    db = firebase.get_firestore()
    if db is None:
        return []
    try:
        rows = [snap.to_dict() or {} for snap in db.collection(EVENTS_COLLECTION).limit(5000).stream()]
    except Exception:
        return []
    return [row for row in rows if _date(row.get("timestamp")) >= cutoff]


def subject_demand(days: int = 30) -> dict[str, Any]:
    counts: dict[str, int] = defaultdict(int)
    for event in read_events(days):
        subject = str(event.get("subject") or "General")
        counts[subject] += 1
    items = [{"subject": subject, "eventCount": count} for subject, count in counts.items()]
    items.sort(key=lambda item: (-item["eventCount"], item["subject"]))
    return {"days": days, "subjects": items}


def topic_difficulty(days: int = 30) -> dict[str, Any]:
    buckets: dict[str, dict[str, float]] = defaultdict(lambda: {"quizSamples": 0, "wrong": 0, "questions": 0, "repeatedMistakes": 0, "lowAccuracy": 0, "unsuccessfulRevisions": 0})
    for event in read_events(days):
        topic = str(event.get("topic") or event.get("chapter") or "").strip()
        if not topic:
            continue
        bucket = buckets[topic]
        if event.get("eventName") == "quiz_completed":
            total = _number(event.get("total"))
            score = _number(event.get("score"))
            if total > 0:
                bucket["quizSamples"] += 1
                bucket["questions"] += total
                bucket["wrong"] += max(0, total - score)
                if score / total < 0.6:
                    bucket["lowAccuracy"] += 1
        bucket["repeatedMistakes"] += _number(event.get("mistake_count"))
        if event.get("eventName") == "revision_completed" and event.get("source") == "unsuccessful":
            bucket["unsuccessfulRevisions"] += 1
    ranked = []
    for topic, bucket in buckets.items():
        samples = int(bucket["quizSamples"])
        if samples < MIN_TOPIC_SAMPLE:
            continue
        wrong_rate = bucket["wrong"] / max(1, bucket["questions"])
        repeat_rate = min(1.0, bucket["repeatedMistakes"] / max(1, samples * 3))
        low_rate = bucket["lowAccuracy"] / samples
        revision_rate = min(1.0, bucket["unsuccessfulRevisions"] / samples)
        score = round(100 * (0.45 * wrong_rate + 0.30 * repeat_rate + 0.20 * low_rate + 0.05 * revision_rate), 1)
        ranked.append({
            "topic": topic,
            "difficultyScore": score,
            "interpretation": "Observed platform struggle, not an objective property of the topic.",
            "supportingMetrics": {
                "quizSamples": samples,
                "wrongAnswerRate": round(wrong_rate, 3),
                "repeatedMistakes": int(bucket["repeatedMistakes"]),
                "lowAccuracyQuizCount": int(bucket["lowAccuracy"]),
                "unsuccessfulRevisions": int(bucket["unsuccessfulRevisions"]),
            },
        })
    ranked.sort(key=lambda item: (-item["difficultyScore"], item["topic"]))
    return {"days": days, "minimumSample": MIN_TOPIC_SAMPLE, "topics": ranked}


def feature_usage(days: int = 30) -> dict[str, Any]:
    counts: dict[str, int] = defaultdict(int)
    for event in read_events(days):
        counts[str(event.get("eventName") or "unknown")] += 1
    return {"days": days, "features": [{"eventName": name, "count": count} for name, count in sorted(counts.items())]}


def overview(days: int = 30) -> dict[str, Any]:
    events = read_events(days)
    users = {str(event.get("userId")) for event in events if event.get("userId")}
    ai_events = {"ai_chat_used", "ai_teacher_used", "content_generated", "study_pack_created"}
    return {
        "days": days,
        "activeStudents": len(users),
        "aiRequests": sum(1 for event in events if event.get("eventName") in ai_events),
        "quizAttempts": sum(1 for event in events if event.get("eventName") == "quiz_completed"),
        "examAttempts": sum(1 for event in events if event.get("eventName") in {"exam_started", "exam_completed"}),
        "eventCount": len(events),
    }
