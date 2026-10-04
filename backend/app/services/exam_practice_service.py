"""Phase 15.4 — Smart Practice Engine.

Orchestration service: selects WHAT to practice.
Existing Quiz engine and Exam Simulator decide HOW to generate and grade.

Modes:
  quick_quiz        — short quiz on highest-priority topic
  topic_drill       — focused drill on specified topic
  weak_topic_drill  — automatic selection of weakest topic
  mistake_revision  — launches canonical mistake review
  chapter_test      — quiz on a chapter/subject
  mixed_priority    — mixed questions from CRITICAL+HIGH topics
  full_mock         — full exam simulation (reuses Exam Simulator)

All quiz and mock results continue flowing through canonical:
  - quiz_results collection (Learning Memory)
  - mistakes collection (Mistake Memory)
  - analytics_service

No second quiz/exam system is created here.
"""

from __future__ import annotations

import logging
import uuid
from datetime import datetime, timezone
from typing import Any

from fastapi import HTTPException

from app.core.firebase import get_firestore

logger = logging.getLogger("gochano.practice")

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

VALID_MODES = frozenset([
    "quick_quiz",
    "topic_drill",
    "weak_topic_drill",
    "mistake_revision",
    "chapter_test",
    "mixed_priority",
    "full_mock",
])

# Default question counts per mode
MODE_QUESTION_COUNTS = {
    "quick_quiz": 5,
    "topic_drill": 10,
    "weak_topic_drill": 8,
    "mistake_revision": 5,
    "chapter_test": 15,
    "mixed_priority": 10,
    "full_mock": 30,
}


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _nowiso() -> str:
    return _now().isoformat()


def _db():
    db = get_firestore()
    if db is None:
        raise HTTPException(status_code=503, detail="Database unavailable")
    return db


try:
    from app.services.mistake_memory_service import get_review_queue
except ImportError:
    get_review_queue = None


# ---------------------------------------------------------------------------
# Topic selection logic
# ---------------------------------------------------------------------------

def _select_topic_for_mode(
    uid: str,
    mode: str,
    topic: str | None = None,
    chapter: str | None = None,
    subject: str | None = None,
) -> dict[str, Any]:
    """
    Determine the target topic/chapter/subject for a practice session.
    Selection priority:
      1. CRITICAL topics
      2. Repeated mistakes
      3. Low mastery
      4. Revision due
      5. Historically frequent
    Returns selection metadata dict.
    """
    selection: dict[str, Any] = {
        "topic": topic,
        "chapter": chapter,
        "subject": subject,
        "selectionReason": "user_specified",
        "selectedAt": _nowiso(),
    }

    if topic:
        return selection

    # Auto-select based on mode
    if mode == "mistake_revision":
        # Use canonical review queue
        try:
            queue = get_review_queue(uid, due_only=True)
            if queue:
                top = queue[0]
                selection["topic"] = top.get("topic")
                selection["subject"] = top.get("subject")
                selection["selectionReason"] = "due_mistake_review"
        except Exception:
            pass
        return selection

    if mode in ("quick_quiz", "weak_topic_drill", "mixed_priority"):
        # Use priority engine
        try:
            from app.services.exam_priority_service import get_priority_topics
            priorities = get_priority_topics(uid, limit=10)
            if priorities:
                # Avoid same topic as last practice session
                last_topic = _last_practiced_topic(uid)
                for p in priorities:
                    if p.get("topic") != last_topic:
                        selection["topic"] = p["topic"]
                        selection["selectionReason"] = (
                            f"priority_{p.get('priority', 'high')}_auto_selected"
                        )
                        break
        except Exception:
            pass
        return selection

    if mode == "full_mock":
        selection["selectionReason"] = "full_exam_simulation"
        return selection

    return selection


def _last_practiced_topic(uid: str) -> str | None:
    """Return topic of last practice session to avoid repetition."""
    db = _db()
    try:
        docs = (
            db.collection("users").document(uid)
            .collection("practice_sessions")
            .order_by("startedAt", direction="DESCENDING")
            .limit(1)
            .stream()
        )
        for doc in docs:
            return (doc.to_dict() or {}).get("topic")
    except Exception:
        pass
    return None


# ---------------------------------------------------------------------------
# Practice session record
# ---------------------------------------------------------------------------

def _practice_col(uid: str):
    return (
        _db().collection("users").document(uid)
        .collection("practice_sessions")
    )


def _save_session(uid: str, session: dict[str, Any]) -> None:
    try:
        _practice_col(uid).document(session["sessionId"]).set(session)
    except Exception as exc:
        logger.warning("Failed to save practice session: %s", exc)


def _complete_session_record(
    uid: str, session_id: str, outcome: dict[str, Any]
) -> None:
    try:
        _practice_col(uid).document(session_id).update({
            "status": "completed",
            "completedAt": _nowiso(),
            "outcome": outcome,
        })
    except Exception as exc:
        logger.warning("Failed to complete practice session %s: %s", session_id, exc)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def start_practice(
    uid: str,
    *,
    mode: str,
    topic: str | None = None,
    chapter: str | None = None,
    subject: str | None = None,
    material_ids: list[str] | None = None,
    question_count: int | None = None,
    exam_id: str | None = None,
) -> dict[str, Any]:
    """
    Orchestrate the start of a practice session.

    Returns a session record with:
      - sessionId (for tracking)
      - mode
      - selection metadata (topic, reason)
      - quiz_config or mock_config for the client to pass to existing engines
      - instructions for how to submit results (reuse canonical endpoint)

    The actual question generation and grading remains in the existing
    Quiz / Exam Simulator engines. This service only selects and routes.
    """
    if mode not in VALID_MODES:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid mode '{mode}'. Valid: {sorted(VALID_MODES)}",
        )

    q_count = question_count or MODE_QUESTION_COUNTS.get(mode, 10)
    q_count = max(1, min(50, q_count))

    # Determine target topic
    selection = _select_topic_for_mode(uid, mode, topic, chapter, subject)

    session_id = str(uuid.uuid4())
    now_str = _nowiso()

    session: dict[str, Any] = {
        "sessionId": session_id,
        "ownerId": uid,
        "mode": mode,
        "topic": selection.get("topic"),
        "chapter": selection.get("chapter"),
        "subject": selection.get("subject"),
        "selectionReason": selection.get("selectionReason"),
        "questionCount": q_count,
        "materialIds": material_ids or [],
        "examId": exam_id,
        "status": "started",
        "startedAt": now_str,
        "completedAt": None,
        "outcome": None,
    }

    # Build engine config based on mode
    if mode == "full_mock":
        # Client should use existing Exam Simulator
        session["engineType"] = "exam_simulator"
        session["engineConfig"] = {
            "mode": "timed",
            "questionCount": q_count,
            "subject": selection.get("subject"),
            "instruction": "Use existing /api/exams endpoint to start exam",
        }
    elif mode == "mistake_revision":
        # Client should use existing Mistake Revision flow
        session["engineType"] = "mistake_review"
        session["engineConfig"] = {
            "mode": "mistake_revision",
            "topic": selection.get("topic"),
            "instruction": "Use existing /api/mistakes/review-queue endpoint",
        }
    else:
        # Standard quiz via existing quiz engine
        session["engineType"] = "quiz"
        session["engineConfig"] = {
            "mode": mode,
            "topic": selection.get("topic"),
            "chapter": selection.get("chapter"),
            "subject": selection.get("subject"),
            "questionCount": q_count,
            "materialIds": material_ids or [],
            "instruction": "Use existing /api/ai-study/quiz/generate endpoint",
        }

    _save_session(uid, session)
    logger.info(
        "Practice session started: %s mode=%s topic=%s",
        session_id, mode, selection.get("topic"),
    )
    return session


def get_practice_history(uid: str, *, limit: int = 20) -> list[dict[str, Any]]:
    """Return recent practice sessions for a user."""
    try:
        docs = (
            _practice_col(uid)
            .order_by("startedAt", direction="DESCENDING")
            .limit(limit)
            .stream()
        )
        return [d.to_dict() or {} for d in docs]
    except Exception as exc:
        logger.warning("get_practice_history failed: %s", exc)
        return []
