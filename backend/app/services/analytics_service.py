"""Phase 10.6 - canonical, privacy-preserving analytics events."""

from __future__ import annotations

import logging
from datetime import date, datetime, timezone
from typing import Any
from uuid import uuid4

from app.core import firebase

logger = logging.getLogger("gochano.analytics")

EVENTS_COLLECTION = "analytics_events"
EVENT_NAMES = {
    "ai_chat_used",
    "ai_teacher_used",
    "content_generated",
    "study_pack_created",
    "quiz_completed",
    "flashcard_reviewed",
    "revision_completed",
    "mistake_corrected",
    "exam_started",
    "exam_completed",
    "focus_session_completed",
    "community_question_posted",
    "community_answer_given",
    "study_group_joined",
    "group_quiz_created",
    "challenge_completed",
    "tutor_session_started",
    "tutor_session_completed",
    "tutor_hint_used",
    "tutor_mode_changed",
    # Phase 14: Document Intelligence events
    "document_processed",
    "document_process_failed",
    "document_tutor_started",
    "document_quiz_generated",
    "document_exam_generated",
    "document_artifact_generated",
    # Phase 15: Exam Ecosystem events
    "past_paper_analyzed",
    "exam_priority_viewed",
    "exam_plan_created",
    "exam_plan_recalculated",
    "smart_practice_started",
    "exam_readiness_viewed",
    "ziku_exam_action_started",
    "exam_ecosystem_opened",
}
_STRING_FIELDS = {
    "subject",
    "topic",
    "chapter",
    "feature",
    "content_type",
    "source",
    "exam_type",
    "mode",
    "mastery_band",
    "mime_type",   # Phase 14
    # Phase 15 dimensions
    "exam_name",
    "examName",
    "plan_id",
    "planId",
    "material_id",
    "materialId",
    "label",
    "type",
    "difficulty",
}
_NUMBER_FIELDS = {
    "score",
    "total",
    "mistake_count",
    "duration_seconds",
    "hints_used",
    "page_count",
    "chunk_count",  # Phase 14
    # Phase 15 metrics
    "question_count",
    "questionCount",
    "topic_count",
    "topicCount",
    "duration_days",
    "durationDays",
    "readiness",
}


def _string(value: Any, limit: int = 160) -> str:
    return str(value or "").strip()[:limit]


def normalize_metadata(metadata: dict[str, Any] | None) -> dict[str, Any]:
    """Keep only aggregate educational dimensions; discard raw content."""
    raw = metadata if isinstance(metadata, dict) else {}
    normalized: dict[str, Any] = {}
    for field in _STRING_FIELDS:
        value = _string(raw.get(field))
        if value:
            normalized[field] = value
    for field in _NUMBER_FIELDS:
        value = raw.get(field)
        if isinstance(value, bool):
            continue
        try:
            number = float(value)
        except (TypeError, ValueError):
            continue
        normalized[field] = int(number) if number.is_integer() else round(number, 2)
    event_date = _string(raw.get("event_date"), 10)
    if event_date:
        try:
            date.fromisoformat(event_date)
        except ValueError:
            event_date = ""
    if not event_date:
        event_date = datetime.now(timezone.utc).date().isoformat()
    normalized["event_date"] = event_date
    return normalized


def track_event(user_id: str, event_name: str, metadata: dict[str, Any] | None = None) -> str | None:
    """Write one backend-only normalized event and never raw student content."""
    if not user_id or event_name not in EVENT_NAMES:
        logger.warning("Ignored invalid analytics event: %s", event_name)
        return None
    event_id = f"event_{uuid4().hex}"
    timestamp = datetime.now(timezone.utc)
    payload = {
        "eventId": event_id,
        "userId": user_id,
        "eventName": event_name,
        "timestamp": timestamp,
        **normalize_metadata(metadata),
    }
    db = firebase.get_firestore()
    if db is None:
        return event_id
    try:
        db.collection(EVENTS_COLLECTION).document(event_id).set(payload)
    except Exception:  # analytics must never break the product event
        logger.exception("Could not write analytics event %s", event_name)
    return event_id


# Canonical alias for callers using record_event
record_event = track_event
