"""Phase 15.5 — Ziku Exam Coach context extension.

Extends existing Ziku context with exam-specific awareness.
Does NOT create a second assistant or duplicate memory.

Context payload injected into existing Ziku tutor/coach prompts:
  - exam metadata (date, days remaining)
  - readiness overview
  - top priority topics
  - recent mistakes
  - due revisions
  - recent practice summary
  - today's plan blocks

Safety rules:
  - Never say "guaranteed", "will appear", "A+" etc.
  - Raw past-paper text NOT injected (bounded context).
  - Max top topics: 5 per coaching context.
  - Max recent mistakes: 5.
"""

from __future__ import annotations

import logging
from datetime import date, datetime, timedelta, timezone
from typing import Any

from app.core.firebase import get_firestore

logger = logging.getLogger("gochano.ziku_exam")

# Bounded context limits
MAX_PRIORITY_TOPICS = 5
MAX_RECENT_MISTAKES = 5
MAX_REVISIONS_DUE   = 5
MAX_TODAY_BLOCKS    = 4

# Coaching language templates (safe, no guarantees)
_COACHING_TEMPLATES = {
    "critical_topic": (
        "Based on historical exam data, {topic} is frequently tested "
        "and your current mastery is {mastery:.0f}%. "
        "Recommended: dedicate {minutes} minutes to review and practice."
    ),
    "mistake_alert": (
        "You have repeated a mistake on {topic} {count} time(s). "
        "Reviewing this now will help consolidate understanding."
    ),
    "revision_due": (
        "Your spaced-repetition queue shows {count} overdue item(s). "
        "Clearing these will improve long-term retention."
    ),
    "readiness_positive": (
        "Your readiness improved from {prev:.0f} to {current:.0f} — "
        "keep up the consistent practice."
    ),
    "days_warning": (
        "{days} day(s) until {exam}. "
        "Focus on high-priority topics for the most effective use of time."
    ),
}

# Forbidden phrases (enforced in output validation)
_FORBIDDEN_PHRASES = [
    "guaranteed to pass",
    "will get A",
    "this question will appear",
    "this topic is guaranteed",
    "100% chance",
    "90% chance",
    "certain to",
    "definitely appear",
]


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _today() -> date:
    return _now().date()


def _parse_date(value: Any) -> date | None:
    if isinstance(value, date):
        return value
    if isinstance(value, str):
        try:
            return date.fromisoformat(value[:10])
        except ValueError:
            return None
    return None


def _db():
    return get_firestore()


# ---------------------------------------------------------------------------
# Context builders
# ---------------------------------------------------------------------------

def _get_active_exam(uid: str) -> dict[str, Any] | None:
    """Load the student's active exam configuration."""
    try:
        from app.services.exam_plan_service import get_active_plan
        plan = get_active_plan(uid)
        if not plan:
            return None
        exam_date = _parse_date(plan.get("examDate", ""))
        if not exam_date:
            return None
        days_remaining = (exam_date - _today()).days
        if days_remaining < 0:
            return None
        return {
            "examName": plan.get("examName", "Upcoming Exam"),
            "examDate": plan.get("examDate"),
            "daysRemaining": days_remaining,
            "subjects": plan.get("subjects", []),
        }
    except Exception:
        return None


def _get_readiness_summary(uid: str) -> dict[str, Any]:
    """Get a bounded readiness summary for coaching context."""
    try:
        from app.services.exam_readiness_service import calculate_readiness
        r = calculate_readiness(uid)
        return {
            "overall": r.get("overallReadiness"),
            "label": r.get("label"),
            "trend": r.get("trend"),
        }
    except Exception:
        return {}


def _get_priority_topics_context(uid: str) -> list[dict[str, Any]]:
    """Top priority topics for coaching (bounded, no raw question text)."""
    try:
        from app.services.exam_priority_service import get_priority_topics
        topics = get_priority_topics(uid, limit=MAX_PRIORITY_TOPICS)
        return [
            {
                "topic": t.get("topic"),
                "priority": t.get("priority"),
                "priorityScore": t.get("priorityScore"),
                "historicalFrequency": (
                    t.get("components", {}).get("historicalFrequency")
                ),
                "masteryGap": t.get("components", {}).get("masteryGap"),
            }
            for t in topics
        ]
    except Exception:
        return []


def _get_recent_mistakes_context(uid: str) -> list[dict[str, Any]]:
    """Recent mistakes for coaching (bounded, no answer text)."""
    db = _db()
    if db is None:
        return []
    try:
        cutoff = (_now() - timedelta(days=14)).isoformat()
        docs = (
            db.collection("users").document(uid)
            .collection("mistakes")
            .where("createdAt", ">=", cutoff)
            .order_by("createdAt", direction="DESCENDING")
            .limit(MAX_RECENT_MISTAKES)
            .stream()
        )
        return [
            {
                "topic": (d.to_dict() or {}).get("topic"),
                "occurrences": (d.to_dict() or {}).get("occurrences", 1),
                "subject": (d.to_dict() or {}).get("subject"),
            }
            for d in docs
        ]
    except Exception:
        return []


def _get_due_revisions_context(uid: str) -> list[dict[str, Any]]:
    """Overdue revision items for coaching (bounded)."""
    db = _db()
    if db is None:
        return []
    try:
        today_str = _today().isoformat()
        docs = (
            db.collection("users").document(uid)
            .collection("mistakes")
            .where("nextReviewDate", "<=", today_str)
            .limit(MAX_REVISIONS_DUE)
            .stream()
        )
        return [
            {
                "topic": (d.to_dict() or {}).get("topic"),
                "dueDate": str((d.to_dict() or {}).get("nextReviewDate", ""))[:10],
            }
            for d in docs
        ]
    except Exception:
        return []


def _get_today_plan_context(uid: str) -> list[dict[str, Any]]:
    """Today's plan blocks for coaching (bounded)."""
    try:
        from app.services.exam_plan_service import get_active_plan, get_plan_today
        plan = get_active_plan(uid)
        if not plan:
            return []
        plan_id = plan.get("planId")
        if not plan_id:
            return []
        items = get_plan_today(uid, plan_id)
        return [
            {
                "blockType": item.get("blockType"),
                "topic": item.get("topic"),
                "durationMinutes": item.get("durationMinutes"),
                "status": item.get("status"),
                "phase": item.get("phase"),
            }
            for item in items[:MAX_TODAY_BLOCKS]
        ]
    except Exception:
        return []


def _get_recent_practice_summary(uid: str) -> dict[str, Any]:
    """Summary of last 3 practice sessions."""
    db = _db()
    if db is None:
        return {}
    try:
        docs = (
            db.collection("users").document(uid)
            .collection("practice_sessions")
            .where("status", "==", "completed")
            .order_by("startedAt", direction="DESCENDING")
            .limit(3)
            .stream()
        )
        sessions = []
        for d in docs:
            data = d.to_dict() or {}
            sessions.append({
                "mode": data.get("mode"),
                "topic": data.get("topic"),
                "startedAt": str(data.get("startedAt", ""))[:10],
            })
        return {"recentSessions": sessions, "count": len(sessions)}
    except Exception:
        return {}


# ---------------------------------------------------------------------------
# Coaching text generation
# ---------------------------------------------------------------------------

def _validate_coaching_output(text: str) -> str:
    """Remove any forbidden guarantee-language from coaching output."""
    if not text:
        return text
    lower = text.lower()
    for phrase in _FORBIDDEN_PHRASES:
        if phrase in lower:
            logger.warning("Coaching output contained forbidden phrase: '%s'", phrase)
            # Replace conservatively
            text = text.replace(phrase, "[removed: unsuitable phrasing]")
    return text


def _build_daily_coaching(context: dict[str, Any]) -> dict[str, Any]:
    """
    Generate coaching output from context (deterministic structure).
    AI may be used to enrich explanation text but NOT to select priorities.
    """
    exam = context.get("exam") or {}
    readiness = context.get("readiness") or {}
    priority_topics = context.get("priorityTopics") or []
    recent_mistakes = context.get("recentMistakes") or []
    due_revisions = context.get("dueRevisions") or []
    today_plan = context.get("todayPlan") or []

    coaching_items = []

    # 1. Top priority topic recommendation
    if priority_topics:
        top = priority_topics[0]
        coaching_items.append({
            "type": "study_recommendation",
            "topic": top.get("topic"),
            "action": "Review and practice",
            "durationMinutes": 25,
            "reason": (
                f"Historically frequent in past papers + "
                f"mastery gap detected"
            ),
            "priority": top.get("priority"),
        })

    # 2. Mistake revision if repeat mistakes exist
    repeat_mistakes = [m for m in recent_mistakes if m.get("occurrences", 1) > 1]
    if repeat_mistakes:
        coaching_items.append({
            "type": "mistake_revision",
            "topic": repeat_mistakes[0].get("topic"),
            "action": f"Review {len(repeat_mistakes)} repeated mistake(s)",
            "durationMinutes": 15,
            "reason": "Based on your recent mistake history",
            "priority": "high",
        })

    # 3. Revision due
    if due_revisions:
        coaching_items.append({
            "type": "revision_due",
            "topic": due_revisions[0].get("topic"),
            "action": f"Clear {len(due_revisions)} overdue revision(s)",
            "durationMinutes": 10,
            "reason": "Spaced repetition schedule",
            "priority": "medium",
        })

    # Readiness message (no guarantees)
    days_remaining = (exam or {}).get("daysRemaining")
    exam_name = (exam or {}).get("examName", "your exam")

    if days_remaining is not None and days_remaining <= 14:
        urgency_note = (
            f"{days_remaining} day(s) until {exam_name}. "
            "Focusing on high-priority topics is recommended."
        )
    elif days_remaining is not None:
        urgency_note = (
            f"{days_remaining} day(s) until {exam_name}. "
            "Stay consistent with your study plan."
        )
    else:
        urgency_note = "Set an exam date to get a personalized countdown."

    overall_readiness = (readiness or {}).get("overall")
    readiness_message = (
        f"Your current readiness is {overall_readiness:.0f}% ({readiness.get('label', '')})."
        if overall_readiness is not None
        else "Add quiz and practice data to calculate your readiness."
    )

    return {
        "coachingItems": coaching_items,
        "urgencyNote": urgency_note,
        "readinessMessage": readiness_message,
        "examCountdown": days_remaining,
        "examName": exam_name,
        "todayPlan": today_plan,
        "generatedAt": _now().isoformat(),
    }


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def build_exam_coach_context(uid: str) -> dict[str, Any]:
    """
    Build the full exam coaching context for Ziku.
    Returns a bounded, structured payload — does NOT include raw question text.
    """
    return {
        "exam": _get_active_exam(uid),
        "readiness": _get_readiness_summary(uid),
        "priorityTopics": _get_priority_topics_context(uid),
        "recentMistakes": _get_recent_mistakes_context(uid),
        "dueRevisions": _get_due_revisions_context(uid),
        "recentPractice": _get_recent_practice_summary(uid),
        "todayPlan": _get_today_plan_context(uid),
    }


def get_daily_coaching(uid: str) -> dict[str, Any]:
    """
    Generate today's coaching recommendations for the student.
    Deterministic structure; Ziku AI enriches language but NOT the selection.
    Output validated for forbidden guarantee-language.
    """
    context = build_exam_coach_context(uid)
    coaching = _build_daily_coaching(context)

    # Validate all string fields for forbidden language
    for item in coaching.get("coachingItems") or []:
        if "reason" in item:
            item["reason"] = _validate_coaching_output(item["reason"])

    return {
        "context": context,
        "coaching": coaching,
    }
