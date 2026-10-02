"""Phase 10.5 - long-term learning memory.

This is a derived memory layer, not a second AI system. It joins the existing
Mistake Memory, Academic Health, Adaptive Learning, focus, exam and generated
content records into one explainable student profile.
"""

from __future__ import annotations

import logging
from collections import defaultdict
from datetime import date, datetime, timedelta, timezone
from typing import Any

from app.core.firebase import get_firestore
from app.services import academic_health_service as health
from app.services import mistake_memory_service as mistakes
from app.services import ziku_adaptive_service as adaptive

logger = logging.getLogger("gochano.learning_memory")

MEMORY_COLLECTION = "learning_memory"
EFFECTIVENESS_COLLECTION = "content_effectiveness"
MAX_ROWS = 300


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _to_datetime(value: Any) -> datetime | None:
    if isinstance(value, datetime):
        return value if value.tzinfo else value.replace(tzinfo=timezone.utc)
    if isinstance(value, date):
        return datetime.combine(value, datetime.min.time(), tzinfo=timezone.utc)
    if isinstance(value, str) and value.strip():
        try:
            parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
            return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)
        except ValueError:
            return None
    for method in ("to_datetime", "toDate"):
        converter = getattr(value, method, None)
        if callable(converter):
            try:
                parsed = converter()
            except Exception:
                return None
            if isinstance(parsed, datetime):
                return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)
    return None


def _number(value: Any, default: float = 0.0) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def _read(collection: str, *, uid: str | None = None) -> list[tuple[str, dict[str, Any]]]:
    db = get_firestore()
    if db is None:
        return []
    try:
        ref = db.collection(collection)
        if uid is not None:
            ref = ref.where("studentId", "==", uid)
        return [(snap.id, snap.to_dict() or {}) for snap in ref.limit(MAX_ROWS).stream()]
    except Exception as exc:  # pragma: no cover
        logger.debug("learning memory read failed for %s: %s", collection, exc)
        return []


def _user_read(uid: str, collection: str) -> list[tuple[str, dict[str, Any]]]:
    db = get_firestore()
    if db is None:
        return []
    try:
        ref = db.collection("users").document(uid).collection(collection)
        return [(snap.id, snap.to_dict() or {}) for snap in ref.limit(MAX_ROWS).stream()]
    except Exception as exc:  # pragma: no cover
        logger.debug("learning memory user read failed for %s: %s", collection, exc)
        return []


def _average(values: list[float]) -> float | None:
    return round(sum(values) / len(values), 1) if values else None


def _quiz_topic_history(uid: str) -> dict[str, list[tuple[datetime, float]]]:
    history: dict[str, list[tuple[datetime, float]]] = defaultdict(list)
    for _, data in _user_read(uid, "quiz_results"):
        stamp = _to_datetime(data.get("createdAt") or data.get("dayKey")) or _now()
        topic_scores = data.get("topicScores") or {}
        if isinstance(topic_scores, dict):
            for topic, score in topic_scores.items():
                if str(topic).strip():
                    history[str(topic).strip()].append((stamp, _number(score)))
    for values in history.values():
        values.sort(key=lambda item: item[0])
    return history


def _content_rows(uid: str) -> list[tuple[str, dict[str, Any]]]:
    return _read("ai_content", uid=uid)


def _community_signals() -> list[dict[str, Any]]:
    """Return aggregate public discussion signals only, never private bodies."""
    db = get_firestore()
    if db is None:
        return []
    counts: dict[tuple[str, str], int] = defaultdict(int)
    try:
        for snap in db.collection("community_posts").limit(MAX_ROWS).stream():
            data = snap.to_dict() or {}
            if str(data.get("groupId") or "").strip():
                continue
            subject = str(data.get("subject") or "General").strip()
            topic = str(data.get("chapter") or data.get("concept") or "General").strip()
            counts[(subject, topic)] += 1
    except Exception as exc:  # pragma: no cover
        logger.debug("community memory read failed: %s", exc)
    return [
        {"subject": subject, "topic": topic, "discussionCount": count}
        for (subject, topic), count in sorted(counts.items(), key=lambda item: -item[1])[:30]
    ]


def _effectiveness_for(uid: str, content_id: str, content: dict[str, Any], history: dict[str, list[tuple[datetime, float]]]) -> dict[str, Any]:
    topic = str(content.get("topic") or "General").strip() or "General"
    created = _to_datetime(content.get("createdAt")) or _now()
    scores = history.get(topic, [])
    before_values = [score for stamp, score in scores if stamp <= created]
    after_values = [score for stamp, score in scores if stamp > created]
    before = _average(before_values)
    after = _average(after_values[-10:])
    if before is None and scores:
        before = scores[0][1]
    improvement = round(after - before, 1) if after is not None and before is not None else None
    new_mistakes = 0
    for mistake in mistakes.get_review_queue(uid, limit=MAX_ROWS):
        if str(mistake.get("topic") or "").strip().casefold() != topic.casefold():
            continue
        seen = _to_datetime(mistake.get("lastSeenAt") or mistake.get("createdAt"))
        if seen is not None and seen > created:
            new_mistakes += int(mistake.get("occurrences") or 1)
    if improvement is not None and improvement >= 10:
        outcome = "helped"
    elif improvement is not None and improvement <= -10:
        outcome = "needs_review"
    elif after is not None:
        outcome = "stable"
    else:
        outcome = "awaiting_evidence"
    return {
        "contentId": content_id,
        "type": content.get("type", "unknown"),
        "topic": topic,
        "createdAt": created,
        "beforeAccuracy": before,
        "afterAccuracy": after,
        "improvement": improvement,
        "newMistakes": new_mistakes,
        "reviewResult": content.get("reviewStatus", "new"),
        "outcome": outcome,
        "evidence": "later_quiz" if after is not None else "awaiting_quiz",
    }


def get_content_effectiveness(uid: str, *, persist: bool = True) -> dict[str, Any]:
    history = _quiz_topic_history(uid)
    items = [_effectiveness_for(uid, doc_id, data, history) for doc_id, data in _content_rows(uid)]
    items.sort(key=lambda item: item["createdAt"], reverse=True)
    type_scores: dict[str, list[float]] = defaultdict(list)
    for item in items:
        if item["improvement"] is not None:
            type_scores[str(item["type"])].append(item["improvement"])
    best_type = max(type_scores, key=lambda kind: _average(type_scores[kind]) or 0, default=None)
    payload = {
        "studentId": uid,
        "items": items[:50],
        "bestContentType": best_type,
        "typeEffectiveness": {kind: _average(values) for kind, values in type_scores.items()},
        "generatedAt": _now(),
    }
    if persist:
        db = get_firestore()
        if db is not None:
            for item in items[:50]:
                try:
                    db.collection(EFFECTIVENESS_COLLECTION).document(item["contentId"]).set(
                        {**item, "studentId": uid, "updatedAt": _now()}
                    )
                except Exception as exc:  # pragma: no cover
                    logger.debug("effectiveness cache write failed: %s", exc)
    return payload


def _study_pattern(uid: str) -> str:
    hours: list[int] = []
    for _, data in _user_read(uid, "focus_sessions"):
        stamp = _to_datetime(data.get("startedAtIso") or data.get("startedAt") or data.get("createdAt"))
        if stamp is not None:
            hours.append(stamp.hour)
    if not hours:
        return "not enough focus data"
    average = sum(hours) / len(hours)
    if average < 12:
        return "morning"
    if average < 18:
        return "afternoon"
    return "evening"


def _profile(uid: str, graph: dict[str, Any], effectiveness: dict[str, Any]) -> dict[str, Any]:
    subject_scores: dict[str, list[float]] = defaultdict(list)
    for _, data in _user_read(uid, "quiz_results"):
        subject = str(data.get("subjectId") or data.get("subject") or "General").strip()
        subject_scores[subject].append(_number(data.get("score")))
    strongest = max(subject_scores, key=lambda key: _average(subject_scores[key]) or 0, default=None)
    topic_history = _quiz_topic_history(uid)
    first_last: list[float] = []
    for values in topic_history.values():
        if len(values) >= 2:
            first_last.append(values[-1][1] - values[0][1])
    improvement = _average(first_last)
    return {
        "studentId": uid,
        "strongestSubject": strongest,
        "weakestTopics": [item["topic"] for item in graph.get("topics", [])[:5]],
        "preferredLearningStyle": "examples + practice" if (effectiveness.get("bestContentType") in {"flashcards", "study_pack"}) else "guided explanation",
        "bestContentType": effectiveness.get("bestContentType"),
        "studyTimePattern": _study_pattern(uid),
        "improvementRate": improvement,
    }


def build_memory(uid: str, *, persist: bool = True) -> dict[str, Any]:
    mistakes_rows = mistakes.get_review_queue(uid, limit=MAX_ROWS)
    history = _quiz_topic_history(uid)
    topics: dict[str, dict[str, Any]] = {}
    for topic, values in history.items():
        topics[topic] = {
            "topic": topic,
            "accuracy": _average([score for _, score in values]),
            "beforeAccuracy": values[0][1] if values else None,
            "improvement": round(values[-1][1] - values[0][1], 1) if len(values) > 1 else 0,
            "attempts": len(values),
            "concepts": [],
            "mistakes": 0,
            "revisions": 0,
        }
    for item in mistakes_rows:
        topic = str(item.get("topic") or "General").strip() or "General"
        entry = topics.setdefault(topic, {"topic": topic, "accuracy": None, "beforeAccuracy": None, "improvement": 0, "attempts": 0, "concepts": [], "mistakes": 0, "revisions": 0})
        analysis = item.get("analysis") or {}
        concept = str(analysis.get("conceptGap") or topic).strip()
        if concept and concept not in entry["concepts"]:
            entry["concepts"].append(concept)
        entry["mistakes"] += int(item.get("occurrences") or 1)
        entry["revisions"] += int(item.get("reviewCount") or 0)
    ordered_topics = sorted(topics.values(), key=lambda item: (item.get("accuracy") is not None, item.get("accuracy") or 0, -item["mistakes"]))
    effectiveness = get_content_effectiveness(uid, persist=persist)
    community_signals = _community_signals()
    graph = {
        "studentId": uid,
        "topics": ordered_topics[:50],
        "generatedContent": [_effectiveness_for(uid, doc_id, data, history) for doc_id, data in _content_rows(uid)][:50],
        "communityDiscussions": community_signals,
        "revisionHistory": [{"topic": item["topic"], "revisions": item["revisions"]} for item in ordered_topics if item["revisions"]],
        "improvement": [{"topic": item["topic"], "before": item["beforeAccuracy"], "now": item["accuracy"], "delta": item["improvement"]} for item in ordered_topics if item["accuracy"] is not None],
        "profile": _profile(uid, {"topics": ordered_topics}, effectiveness),
        "updatedAt": _now(),
    }
    if persist:
        db = get_firestore()
        if db is not None:
            try:
                db.collection(MEMORY_COLLECTION).document(uid).set(graph)
            except Exception as exc:  # pragma: no cover
                logger.debug("learning memory cache write failed: %s", exc)
    return graph


def get_progress(uid: str) -> dict[str, Any]:
    memory = build_memory(uid, persist=True)
    return {
        "studentId": uid,
        "improvement": memory.get("improvement", [])[:20],
        "topics": memory.get("topics", [])[:20],
        "profile": memory.get("profile", {}),
        "generatedAt": memory.get("updatedAt"),
    }


def chat_context(uid: str) -> str | None:
    try:
        memory = build_memory(uid, persist=False)
        topics = memory.get("topics") or []
        if not topics:
            return None
        top = topics[0]
        improvement = top.get("improvement") or 0
        progress = f" Improvement since first quiz: {int(improvement)}%." if improvement else ""
        public_discussions = memory.get("communityDiscussions") or []
        community_line = ""
        for discussion in public_discussions:
            if str(discussion.get("topic") or "").casefold() == str(top["topic"]).casefold():
                community_line = f" Many students are also discussing {top['topic']} in the community."
                break
        return f"Learning memory: the student has a recurring gap in {top['topic']} with {top.get('mistakes', 0)} mistake(s).{progress}{community_line}"
    except Exception as exc:  # pragma: no cover
        logger.debug("learning memory chat context unavailable: %s", exc)
        return None