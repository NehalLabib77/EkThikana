"""Phase 9 - Ziku Adaptive Learning Engine.

Mistake Memory owns mistakes and review dates; Academic Health owns quiz and
exam signals. This module ranks those existing signals and stores only its
derived, read-only caches.
"""

from __future__ import annotations

import logging
from collections import defaultdict
from datetime import date, datetime, timezone
from typing import Any

from app.core.firebase import get_firestore
from app.services import academic_health_service as health
from app.services import ai_service
from app.services import mistake_memory_service as mistakes

logger = logging.getLogger("gochano.adaptive")
REVISION_COLLECTION = "adaptive_revision"
CURRICULUM_COLLECTION = "adaptive_curriculum"
TEXTBOOK_COLLECTION = "adaptive_textbooks"
PATH_COLLECTION = "adaptive_learning_paths"
MAX_ITEMS = 12


def _day_key() -> str:
    return datetime.now(timezone.utc).date().isoformat()


def _number(value: Any, default: float = 0.0) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def _read_cache(uid: str, collection: str, doc_id: str) -> dict[str, Any] | None:
    db = get_firestore()
    if db is None:
        return None
    try:
        snap = db.collection("users").document(uid).collection(collection).document(doc_id).get()
        return snap.to_dict() if snap.exists else None
    except Exception as exc:  # pragma: no cover
        logger.debug("adaptive cache read failed: %s", exc)
        return None


def _write_cache(uid: str, collection: str, doc_id: str, payload: dict[str, Any]) -> None:
    db = get_firestore()
    if db is None:
        return
    try:
        db.collection("users").document(uid).collection(collection).document(doc_id).set(
            {**payload, "ownerId": uid, "dayKey": _day_key(), "updatedAt": datetime.now(timezone.utc)}
        )
    except Exception as exc:  # pragma: no cover
        logger.debug("adaptive cache write failed: %s", exc)


def _health_signals(uid: str) -> dict[str, Any]:
    try:
        return health.collect_signals(uid)
    except Exception as exc:  # pragma: no cover
        logger.debug("adaptive health signals unavailable: %s", exc)
        return {"quizzes": {}, "exam": None}


def _topic_scores(uid: str) -> dict[str, float]:
    quizzes = _health_signals(uid).get("quizzes") or {}
    return {str(topic): _number(score) for topic, score in (quizzes.get("topicAverages") or {}).items()}


def _exam_days(uid: str) -> int | None:
    raw = (_health_signals(uid).get("exam") or {}).get("examDate")
    if not raw:
        return None
    try:
        return max(0, (date.fromisoformat(str(raw)[:10]) - datetime.now(timezone.utc).date()).days)
    except ValueError:
        return None


def _revision_items(uid: str) -> list[dict[str, Any]]:
    rows = mistakes.get_review_queue(uid, limit=MAX_ITEMS * 4)
    averages = _topic_scores(uid)
    exam_days = _exam_days(uid)
    by_topic: dict[str, dict[str, Any]] = {}
    for item in rows:
        topic = str(item.get("topic") or "General").strip() or "General"
        entry = by_topic.setdefault(topic, {"topic": topic, "mistakes": 0, "occurrences": 0, "reviewOverdue": False})
        entry["mistakes"] += 1
        entry["occurrences"] += int(_number(item.get("occurrences"), 1))
        entry["reviewOverdue"] |= bool(item.get("nextReviewDate") and str(item["nextReviewDate"]) <= _day_key())

    ranked = []
    for topic, entry in by_topic.items():
        accuracy = averages.get(topic)
        score = min(10, entry["occurrences"] / 2)
        score += 3 if entry["reviewOverdue"] else 0
        score += 3 if exam_days is not None and exam_days <= 7 else (1 if exam_days is not None and exam_days <= 14 else 0)
        score += 2 if accuracy is not None and accuracy < 60 else (1 if accuracy is not None and accuracy < 75 else 0)
        reasons = [f"{entry['occurrences']} mistake(s)"]
        if exam_days is not None and exam_days <= 14:
            reasons.append(f"Exam in {exam_days} day(s)")
        if entry["reviewOverdue"]:
            reasons.append("Review overdue")
        if accuracy is not None and accuracy < 75:
            reasons.append(f"Low accuracy ({int(accuracy)}%)")
        ranked.append({"topic": topic, "priorityScore": round(score, 2), "mistakes": entry["mistakes"], "occurrences": entry["occurrences"], "accuracy": int(accuracy) if accuracy is not None else None, "reviewOverdue": entry["reviewOverdue"], "reason": reasons})
    ranked.sort(key=lambda item: (-item["priorityScore"], item["topic"].lower()))
    for index, item in enumerate(ranked[:MAX_ITEMS], 1):
        item["priority"] = index
    return ranked[:MAX_ITEMS]


def get_revision_queue(uid: str) -> dict[str, Any]:
    day = _day_key()
    cached = _read_cache(uid, REVISION_COLLECTION, day)
    if cached:
        return cached
    items = _revision_items(uid)
    payload = {"dayKey": day, "title": "Today's Revision Queue", "items": items, "count": len(items)}
    _write_cache(uid, REVISION_COLLECTION, day, payload)
    return payload


def get_curriculum(uid: str) -> dict[str, Any]:
    day = _day_key()
    cached = _read_cache(uid, CURRICULUM_COLLECTION, day)
    if cached:
        return cached
    plan = []
    for item in get_revision_queue(uid)["items"][:6]:
        accuracy = item.get("accuracy")
        concept = 20 if accuracy is None or accuracy < 60 else 10
        practice = 40 if accuracy is None or accuracy < 75 else 25
        revision = 15 if item.get("reviewOverdue") else 10
        plan.append({"topic": item["topic"], "conceptReviewMinutes": concept, "practiceMinutes": practice, "revisionMinutes": revision, "totalMinutes": concept + practice + revision, "reason": f"You solved questions with {int(accuracy)}% accuracy." if accuracy is not None else "Recorded mistakes show this needs attention."})
    payload = {"dayKey": day, "title": "Today's Adaptive Plan", "items": plan, "count": len(plan)}
    _write_cache(uid, CURRICULUM_COLLECTION, day, payload)
    return payload


def _deterministic_textbook(uid: str) -> dict[str, Any]:
    grouped: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for item in mistakes.get_review_queue(uid, limit=MAX_ITEMS):
        grouped[str(item.get("topic") or "General")].append(item)
    chapters = []
    for topic, topic_items in list(grouped.items())[:8]:
        errors = []
        for item in topic_items[:4]:
            analysis = item.get("analysis") or {}
            errors.append(str(analysis.get("conceptGap") or analysis.get("mistakeReason") or "Review the concept and check each step carefully."))
        chapters.append({"chapter": topic, "yourMistakes": errors, "correction": "Start with the definition, work through one guided example, then verify the final step.", "practice": [f"Explain {topic} in your own words.", f"Solve a new {topic} example and show every step."]})
    return {"title": "My AI Textbook", "chapters": chapters, "source": "deterministic"}


async def get_textbook(uid: str) -> dict[str, Any]:
    cached = _read_cache(uid, TEXTBOOK_COLLECTION, "current")
    if cached:
        return cached
    payload = _deterministic_textbook(uid)
    try:
        if payload["chapters"]:
            topics = ", ".join(chapter["chapter"] for chapter in payload["chapters"][:5])
            generated = await ai_service.generate(uid, f"Create concise correction notes and two practice prompts for these student weak topics. Use only the supplied topics and mistakes. Topics: {topics}\n{payload['chapters']}", feature=getattr(ai_service.AiFeature, "ADAPTIVE_TEXTBOOK", ai_service.AiFeature.NOTE))
            if generated.strip():
                payload["aiExplanation"] = generated.strip()
                payload["source"] = "ai"
    except Exception as exc:  # pragma: no cover
        logger.info("adaptive textbook AI fallback: %s", exc)
    _write_cache(uid, TEXTBOOK_COLLECTION, "current", payload)
    return payload


def get_difficulty(uid: str) -> dict[str, Any]:
    cached = _read_cache(uid, PATH_COLLECTION, "difficulty")
    if cached:
        return cached
    db = get_firestore()
    buckets: dict[str, list[float]] = defaultdict(list)
    if db is not None:
        try:
            for snap in db.collection("users").document(uid).collection("quiz_results").limit(100).stream():
                scores = (snap.to_dict() or {}).get("difficultyScores") or {}
                if isinstance(scores, dict):
                    for level, score in scores.items():
                        buckets[str(level).lower()].append(_number(score))
        except Exception as exc:  # pragma: no cover
            logger.debug("difficulty data unavailable: %s", exc)
    accuracy = {level: round(sum(values) / len(values)) if values else None for level, values in buckets.items()}
    easy, medium, hard = accuracy.get("easy"), accuracy.get("medium"), accuracy.get("hard")
    if hard is not None and hard < 60 and (medium is None or medium >= 70):
        recommendation, action = "Practice more medium questions before hard problems.", "maintain_level"
    elif easy is not None and easy < 70:
        recommendation, action = "Review basics before increasing difficulty.", "review_basics"
    elif medium is not None and medium >= 75 and (hard is None or hard >= 60):
        recommendation, action = "Increase difficulty gradually.", "increase_difficulty"
    else:
        recommendation, action = "Maintain your current level and collect more evidence.", "maintain_level"
    payload = {"accuracy": accuracy, "recommendation": recommendation, "action": action}
    _write_cache(uid, PATH_COLLECTION, "difficulty", payload)
    return payload


def get_learning_path(uid: str) -> dict[str, Any]:
    cached = _read_cache(uid, PATH_COLLECTION, "current")
    if cached:
        return cached
    steps = []
    for item in get_revision_queue(uid)["items"][:6]:
        if item.get("accuracy") is not None and item["accuracy"] < 50:
            steps.append({"topic": f"Basic {item['topic']}", "reason": "Prerequisite missing", "kind": "prerequisite"})
        steps.append({"topic": item["topic"], "reason": "Repeated mistakes or weak accuracy", "kind": "weakness"})
    payload = {"title": "Recommended Learning Path", "items": steps[:MAX_ITEMS], "count": len(steps[:MAX_ITEMS])}
    _write_cache(uid, PATH_COLLECTION, "current", payload)
    return payload


def chat_context(uid: str) -> str | None:
    try:
        items = get_revision_queue(uid).get("items") or []
        if not items:
            return None
        top = items[0]
        return f"Adaptive focus: {top['topic']} has {top.get('occurrences', 1)} recorded mistake(s); start with its concept review before harder practice."
    except Exception as exc:  # pragma: no cover
        logger.debug("adaptive chat context unavailable: %s", exc)
        return None