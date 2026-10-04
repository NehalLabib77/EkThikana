"""Phase 10.5 - explainable learning recommendations and reminders."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from app.core.firebase import get_firestore
from app.services import learning_memory_service as memory
from app.services import mistake_memory_service as mistakes
from app.services import ziku_adaptive_service as adaptive

RECOMMENDATIONS_COLLECTION = "learning_recommendations"


def _save(uid: str, payload: dict[str, Any]) -> None:
    db = get_firestore()
    if db is None:
        return
    try:
        db.collection(RECOMMENDATIONS_COLLECTION).document(uid).set(payload)
    except Exception:
        return


def get_recommendations(uid: str) -> dict[str, Any]:
    graph = memory.build_memory(uid, persist=True)
    queue = adaptive.get_revision_queue(uid).get("items") or []
    items: list[dict[str, Any]] = []
    for item in queue[:3]:
        topic = str(item.get("topic") or "General")
        if item.get("reviewOverdue"):
            items.append({"title": f"Review {topic} flashcards", "type": "flashcards", "topic": topic, "priority": 100, "reason": "Review is due after the spaced-repetition interval."})
        elif item.get("accuracy") is not None and item["accuracy"] < 60:
            items.append({"title": f"Practice a {topic} quiz", "type": "quiz", "topic": topic, "priority": 90, "reason": "Recent accuracy is low."})
        else:
            items.append({"title": f"Read your {topic} explanation", "type": "explanation", "topic": topic, "priority": 80, "reason": "Repeated mistakes show a concept gap."})
    for item in graph.get("improvement", [])[:3]:
        if item.get("delta", 0) >= 15:
            items.append({"title": f"Keep building {item['topic']}", "type": "revision_sheet", "topic": item["topic"], "priority": 60, "reason": f"You improved by {int(item['delta'])}% after practice."})
    if not items:
        items.append({"title": "Take a short practice quiz", "type": "quiz", "topic": "General", "priority": 20, "reason": "A quiz gives Ziku evidence for your next recommendation."})
    items.sort(key=lambda item: (-item["priority"], item["title"]))
    payload = {"studentId": uid, "items": items[:5], "notifications": _notifications(graph, queue), "generatedAt": datetime.now(timezone.utc)}
    _save(uid, payload)
    return payload


def _notifications(graph: dict[str, Any], queue: list[dict[str, Any]]) -> list[dict[str, Any]]:
    notices = []
    for item in queue:
        if item.get("reviewOverdue"):
            notices.append({"message": f"Your {item['topic']} revision is due today.", "priority": 90, "topic": item["topic"]})
    for item in graph.get("improvement", []):
        if item.get("delta", 0) >= 20:
            notices.append({"message": f"You improved {item['topic']} by {int(item['delta'])}%.", "priority": 70, "topic": item["topic"]})
    return sorted(notices, key=lambda item: -item["priority"])[:3]