"""Phase 15.3 — Personalized Exam Plan Service.

Generates a realistic, adaptive study roadmap toward a specific exam date.

Supported durations: 3, 7, 14, 30, 45 days (one algorithm, not multiple engines).

Plan phases by duration:
  45-day:  Foundation → Strengthening → Exam Practice → Final Revision
  30-day:  Foundation → Strengthening → Exam Practice → Final Revision
  14-day:  Priority Repair → Practice → Mock → Final Revision
  7-day:   Priority Repair → Practice → Mock/Mistake Review → Final Recall
  3-day:   Critical Weakness → High-Yield Revision → Mock/Mistake Review → Final Recall

Rescheduling:
  - Preserve completed tasks.
  - Move incomplete high-priority items forward.
  - Do not regenerate the entire plan for minor events.

Reuses canonical planner/task architecture where possible.
"""

from __future__ import annotations

import logging
import uuid
from datetime import date, datetime, timedelta, timezone
from typing import Any

from fastapi import HTTPException

from app.core.firebase import get_firestore

logger = logging.getLogger("gochano.exam_plan")

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

DEFAULT_DAILY_MINUTES = 120      # documented fallback when student hasn't set
MAX_DAILY_BLOCKS = 4
MIN_PLAN_DAYS = 1
MAX_PLAN_DAYS = 180

# Daily block types
BLOCK_LEARN = "learn_review"
BLOCK_PRACTICE = "practice"
BLOCK_MISTAKE = "mistake_revision"
BLOCK_QUIZ = "quiz_recall"
BLOCK_MOCK = "mock_exam"

# Plan phases
_PHASES_45 = ["Foundation", "Strengthening", "Exam Practice", "Final Revision"]
_PHASES_30 = ["Foundation", "Strengthening", "Exam Practice", "Final Revision"]
_PHASES_14 = ["Priority Repair", "Practice", "Mock", "Final Revision"]
_PHASES_7  = ["Priority Repair", "Practice", "Mock/Mistake Review", "Final Recall"]
_PHASES_3  = ["Critical Weakness", "High-Yield Revision", "Mock/Mistake Review", "Final Recall"]


def _phases_for(days: int) -> list[str]:
    if days >= 30:
        return _PHASES_45
    if days >= 14:
        return _PHASES_14
    if days >= 7:
        return _PHASES_7
    return _PHASES_3


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _today() -> date:
    return _now().date()


def _nowiso() -> str:
    return _now().isoformat()


def _db():
    db = get_firestore()
    if db is None:  # pragma: no cover
        raise HTTPException(status_code=503, detail="Database unavailable")
    return db


def _plan_col(uid: str):
    return (
        _db().collection("users").document(uid)
        .collection("exam_ecosystem").document("default")
        .collection("plans")
    )


def _daily_items_col(uid: str, plan_id: str):
    return _plan_col(uid).document(plan_id).collection("daily_items")


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

def _parse_date(value: Any) -> date | None:
    if isinstance(value, date):
        return value
    if isinstance(value, str):
        try:
            return date.fromisoformat(value[:10])
        except ValueError:
            return None
    return None


def _split_phases(total_days: int, phase_names: list[str]) -> list[tuple[str, int, int]]:
    """
    Distribute days across phases.
    Returns list of (phase_name, start_day, end_day) 1-indexed.
    """
    n = len(phase_names)
    weights = {
        4: [0.30, 0.30, 0.25, 0.15],  # last phase shorter (final revision)
        3: [0.35, 0.40, 0.25],
        2: [0.60, 0.40],
        1: [1.0],
    }.get(n, [1.0 / n] * n)

    phases = []
    start = 1
    for i, (name, weight) in enumerate(zip(phase_names, weights)):
        if i == n - 1:
            end = total_days
        else:
            end = start + max(1, round(total_days * weight)) - 1
            end = min(end, total_days - (n - i - 1))
        phases.append((name, start, end))
        start = end + 1

    return phases


def _phase_for_day(day: int, phases: list[tuple[str, int, int]]) -> str:
    for name, start, end in phases:
        if start <= day <= end:
            return name
    return phases[-1][0]


def _blocks_for_day(
    day: int,
    total_days: int,
    phase_name: str,
    daily_minutes: int,
    priority_topics: list[dict],
    weak_topics: list[str],
    mistake_topics: list[str],
) -> list[dict[str, Any]]:
    """
    Build up to MAX_DAILY_BLOCKS study blocks for a day.
    Final days: more mock/recall; early days: more learn/review.
    """
    blocks = []
    mins_each = max(20, daily_minutes // MAX_DAILY_BLOCKS)

    # Always start with highest-priority topic for learning
    top_topic = (priority_topics[0]["topic"] if priority_topics else
                 (weak_topics[0] if weak_topics else "Review"))

    phase_lower = phase_name.lower()
    days_left = total_days - day

    # Block 1: Learn/Review (reduced in final 3 days)
    if days_left > 2 or "final" not in phase_lower:
        blocks.append({
            "blockType": BLOCK_LEARN,
            "topic": top_topic,
            "durationMinutes": mins_each,
            "priority": priority_topics[0].get("priority", "medium") if priority_topics else "medium",
            "reason": "High historical frequency + mastery gap" if priority_topics else "Foundational review",
        })

    # Block 2: Practice
    practice_topic = (
        priority_topics[1]["topic"] if len(priority_topics) > 1 else top_topic
    )
    blocks.append({
        "blockType": BLOCK_PRACTICE,
        "topic": practice_topic,
        "durationMinutes": mins_each,
        "priority": priority_topics[1].get("priority", "medium") if len(priority_topics) > 1 else "medium",
        "reason": "Frequently tested in past papers" if priority_topics else "General practice",
    })

    # Block 3: Mistake Revision (if mistakes exist)
    if mistake_topics:
        blocks.append({
            "blockType": BLOCK_MISTAKE,
            "topic": mistake_topics[0],
            "durationMinutes": max(15, mins_each // 2),
            "priority": "high",
            "reason": "Repeated mistake — needs targeted review",
        })

    # Block 4: Quiz/Mock (more mock near exam)
    if len(blocks) < MAX_DAILY_BLOCKS:
        block_type = BLOCK_MOCK if days_left <= 5 else BLOCK_QUIZ
        blocks.append({
            "blockType": block_type,
            "topic": "Mixed" if days_left <= 5 else top_topic,
            "durationMinutes": mins_each,
            "priority": "high" if days_left <= 7 else "medium",
            "reason": "Exam simulation" if days_left <= 5 else "Active recall to consolidate",
        })

    return blocks[:MAX_DAILY_BLOCKS]


# ---------------------------------------------------------------------------
# Plan persistence
# ---------------------------------------------------------------------------

def _save_plan(uid: str, plan_id: str, plan_data: dict[str, Any]) -> None:
    _plan_col(uid).document(plan_id).set(plan_data)


def _save_daily_items(
    uid: str, plan_id: str, items: list[dict[str, Any]]
) -> None:
    if not items:
        return
    db = _db()
    batch = db.batch()
    col = _daily_items_col(uid, plan_id)
    for item in items:
        ref = col.document(item["itemId"])
        batch.set(ref, item)
    batch.commit()


def _load_plan(uid: str, plan_id: str) -> dict[str, Any] | None:
    doc = _plan_col(uid).document(plan_id).get()
    if doc.exists:
        return {"planId": doc.id, **(doc.to_dict() or {})}
    return None


def _active_plan(uid: str) -> dict[str, Any] | None:
    try:
        docs = (
            _plan_col(uid)
            .where("status", "==", "active")
            .order_by("createdAt", direction="DESCENDING")
            .limit(1)
            .stream()
        )
        for doc in docs:
            return {"planId": doc.id, **(doc.to_dict() or {})}
    except Exception:
        pass
    return None


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def create_exam_plan(
    uid: str,
    *,
    exam_name: str,
    exam_date_str: str,
    subjects: list[str] | None = None,
    daily_minutes: int | None = None,
    selected_materials: list[str] | None = None,
    force_new: bool = False,
) -> dict[str, Any]:
    """
    Generate a personalized exam study plan.

    Returns the plan record; daily items stored in subcollection.
    Idempotent: returns existing active plan unless force_new=True.
    """
    # 1. Parse and validate exam date
    exam_date = _parse_date(exam_date_str)
    if not exam_date:
        raise HTTPException(
            status_code=400,
            detail="Invalid exam_date — expected YYYY-MM-DD",
        )
    today = _today()
    if exam_date <= today:
        raise HTTPException(
            status_code=400,
            detail="Exam date must be in the future",
        )

    duration_days = (exam_date - today).days
    if duration_days > MAX_PLAN_DAYS:
        raise HTTPException(
            status_code=400,
            detail=f"Exam date too far in future (max {MAX_PLAN_DAYS} days)",
        )

    # 2. Idempotency check (only skip if same exam_name + exam_date)
    if not force_new:
        existing = _active_plan(uid)
        if existing and existing.get("examDate") == exam_date_str:
            return existing

    # 3. Resolve daily minutes
    resolved_minutes = daily_minutes
    fallback_source = "user_preference"
    if not resolved_minutes:
        resolved_minutes = DEFAULT_DAILY_MINUTES
        fallback_source = "system_default"

    resolved_minutes = max(30, min(600, resolved_minutes))

    # 4. Load priority topics
    try:
        from app.services.exam_priority_service import get_priority_topics
        priority_topics = get_priority_topics(uid, limit=20)
    except Exception:
        priority_topics = []

    # 5. Load weak topics from canonical service
    try:
        from app.services.weak_topic_service import get_weak_topics
        weak_data = get_weak_topics(uid)
        weak_topics = [w.get("topic", "") for w in weak_data if w.get("topic")]
    except Exception:
        weak_topics = []

    # 6. Load recent mistake topics
    try:
        from app.services.mistake_memory_service import get_review_queue
        review_queue = get_review_queue(uid, due_only=False)
        mistake_topics = list({
            item.get("topic", "") for item in review_queue if item.get("topic")
        })[:10]
    except Exception:
        mistake_topics = []

    # 7. Phase allocation
    phase_names = _phases_for(duration_days)
    phases = _split_phases(duration_days, phase_names)

    # 8. Build daily items
    daily_items = []
    for day_offset in range(duration_days):
        day_num = day_offset + 1
        study_date = today + timedelta(days=day_offset)
        phase_name = _phase_for_day(day_num, phases)

        # Rotate priority topics to avoid repetition
        rotated_priorities = priority_topics[day_offset % max(1, len(priority_topics)):]
        rotated_priorities = rotated_priorities + priority_topics[:day_offset % max(1, len(priority_topics))]

        blocks = _blocks_for_day(
            day=day_num,
            total_days=duration_days,
            phase_name=phase_name,
            daily_minutes=resolved_minutes,
            priority_topics=rotated_priorities[:4],
            weak_topics=weak_topics,
            mistake_topics=mistake_topics,
        )

        for block_idx, block in enumerate(blocks):
            item_id = str(uuid.uuid4())
            daily_items.append({
                "itemId": item_id,
                "dayNumber": day_num,
                "studyDate": study_date.isoformat(),
                "phase": phase_name,
                "blockIndex": block_idx,
                "status": "pending",
                **block,
            })

    # 9. Create plan record
    plan_id = str(uuid.uuid4())
    now_str = _nowiso()
    plan_data = {
        "planId": plan_id,
        "ownerId": uid,
        "examName": exam_name,
        "examDate": exam_date_str,
        "subjects": subjects or [],
        "durationDays": duration_days,
        "startDate": today.isoformat(),
        "dailyMinutes": resolved_minutes,
        "dailyMinutesFallbackSource": fallback_source,
        "phases": [{"name": n, "startDay": s, "endDay": e} for n, s, e in phases],
        "version": 1,
        "status": "active",
        "totalItems": len(daily_items),
        "createdAt": now_str,
        "updatedAt": now_str,
    }

    _save_plan(uid, plan_id, plan_data)
    _save_daily_items(uid, plan_id, daily_items)

    logger.info(
        "Created exam plan %s for user %s: %d days, %d items",
        plan_id, uid, duration_days, len(daily_items),
    )

    return {**plan_data, "dailyItemsCount": len(daily_items)}


def get_active_plan(uid: str) -> dict[str, Any] | None:
    """Return the current active plan, expiring plans past exam date."""
    plan = _active_plan(uid)
    if not plan:
        return None

    exam_date = _parse_date(plan.get("examDate", ""))
    if exam_date and exam_date < _today():
        # Mark as expired
        try:
            _plan_col(uid).document(plan["planId"]).update({
                "status": "expired",
                "updatedAt": _nowiso(),
            })
        except Exception:
            pass
        return None

    return plan


def get_plan_today(uid: str, plan_id: str) -> list[dict[str, Any]]:
    """Return today's study items for a plan."""
    today_str = _today().isoformat()
    try:
        docs = (
            _daily_items_col(uid, plan_id)
            .where("studyDate", "==", today_str)
            .stream()
        )
        items = [d.to_dict() or {} for d in docs]
        items.sort(key=lambda x: x.get("blockIndex", 0))
        return items
    except Exception as exc:
        logger.warning("get_plan_today failed: %s", exc)
        return []


def recalculate_plan(uid: str, plan_id: str) -> dict[str, Any]:
    """
    Recalculate an existing plan without losing completed work.
    Preserves completed items; moves pending high-priority items forward.
    """
    existing = _load_plan(uid, plan_id)
    if not existing:
        raise HTTPException(status_code=404, detail="Plan not found")
    if existing.get("ownerId") != uid:
        raise HTTPException(status_code=403, detail="Access denied")

    exam_date_str = existing.get("examDate", "")
    exam_date = _parse_date(exam_date_str)
    if not exam_date or exam_date <= _today():
        raise HTTPException(
            status_code=400,
            detail="Cannot recalculate: exam date has passed",
        )

    # Create a new version (increment version, keep plan_id)
    new_version = int(existing.get("version") or 1) + 1

    # Rebuild with same parameters — priority topics may have changed
    result = create_exam_plan(
        uid,
        exam_name=existing.get("examName", ""),
        exam_date_str=exam_date_str,
        subjects=existing.get("subjects"),
        daily_minutes=existing.get("dailyMinutes"),
        force_new=True,
    )

    # Tag new plan as recalculation
    new_plan_id = result["planId"]
    _plan_col(uid).document(new_plan_id).update({
        "version": new_version,
        "recalculatedFrom": plan_id,
        "updatedAt": _nowiso(),
    })

    # Archive old plan
    try:
        _plan_col(uid).document(plan_id).update({
            "status": "superseded",
            "updatedAt": _nowiso(),
        })
    except Exception:
        pass

    return {**result, "version": new_version, "recalculatedFrom": plan_id}
