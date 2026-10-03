"""Phase 12.2.3 — Consolidated student dashboard bootstrap service.

Aggregates:
- Profile
- Academic Health
- Study Coach (daily brief / mission)
- Focus Engine (today's stats & score)
- AI Usage
- Content Recommendations
- Active Exam Rescue

Executes aggregations concurrently via asyncio.to_thread and guarantees
isolated section failure handling so a failure in any one section does not
fail the overall bootstrap response.
"""
from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timezone
from typing import Any

from app.core.auth import CurrentUser
from app.core.firebase import get_firestore
from app.services import (
    academic_health_service,
    ai_service,
    content_recommendation_service,
    focus_service,
    study_coach_service,
)

logger = logging.getLogger(__name__)


def _get_profile(user: CurrentUser) -> dict[str, Any]:
    return {
        "uid": user.uid,
        "displayName": user.display_name or "",
        "role": user.role or "student",
        "email": user.email,
    }


def _get_academic_health(uid: str) -> dict[str, Any]:
    try:
        health = academic_health_service.get_academic_health(uid)
        return {
            "available": True,
            **health,
        }
    except Exception as exc:
        logger.warning("dashboard bootstrap: academic health failed (%s)", exc)
        return {
            "available": False,
            "score": None,
            "hasData": False,
            "headline": "No health data available",
        }


def _get_coach(uid: str) -> dict[str, Any]:
    try:
        coach = study_coach_service.daily_recommendation(uid)
        return {
            "available": True,
            **coach,
        }
    except Exception as exc:
        logger.warning("dashboard bootstrap: coach failed (%s)", exc)
        return {
            "available": False,
            "headline": "Coach currently unavailable",
            "mission": [],
        }


def _get_focus(uid: str) -> dict[str, Any]:
    try:
        db = get_firestore()
        focus = focus_service.engine_today(db, uid)
        return {
            "available": True,
            **focus,
        }
    except Exception as exc:
        logger.warning("dashboard bootstrap: focus failed (%s)", exc)
        return {
            "available": False,
            "minutesDone": 0,
            "goalMinutes": 60,
            "focusScore": 0,
        }


def _get_ai_usage(uid: str) -> dict[str, Any]:
    try:
        usage = ai_service.get_ai_usage(uid)
        return {
            "available": True,
            **usage,
        }
    except Exception as exc:
        logger.warning("dashboard bootstrap: ai usage failed (%s)", exc)
        return {
            "available": False,
        }


def _get_recommendations(uid: str) -> dict[str, Any]:
    try:
        recs = content_recommendation_service.get_recommendations(uid)
        return {
            "available": True,
            **recs,
        }
    except Exception as exc:
        logger.warning("dashboard bootstrap: recommendations failed (%s)", exc)
        return {
            "available": False,
            "items": [],
        }


def _get_exam_rescue(uid: str) -> dict[str, Any]:
    try:
        db = get_firestore()
        if db is None:
            return {"available": False}
        rows = (
            db.collection("users")
            .document(uid)
            .collection("exam_rescue")
            .where("status", "==", "active")
            .limit(1)
            .stream()
        )
        exam_doc = None
        for snap in rows:
            data = snap.to_dict() or {}
            data["sessionId"] = str(data.get("sessionId") or snap.id or "")
            exam_doc = data
            break
        if exam_doc:
            return {"available": True, **exam_doc}
        return {"available": False}
    except Exception as exc:
        logger.warning("dashboard bootstrap: exam rescue failed (%s)", exc)
        return {"available": False}


async def get_dashboard_bootstrap(user: CurrentUser) -> dict[str, Any]:
    """Fetch all dashboard data concurrently with isolated section error handling."""
    uid = user.uid

    profile_data = _get_profile(user)

    # Run independent aggregations concurrently on threads
    results = await asyncio.gather(
        asyncio.to_thread(_get_academic_health, uid),
        asyncio.to_thread(_get_coach, uid),
        asyncio.to_thread(_get_focus, uid),
        asyncio.to_thread(_get_ai_usage, uid),
        asyncio.to_thread(_get_recommendations, uid),
        asyncio.to_thread(_get_exam_rescue, uid),
        return_exceptions=True,
    )

    academic_health_res = (
        results[0]
        if not isinstance(results[0], Exception)
        else {"available": False, "score": None, "hasData": False}
    )
    coach_res = (
        results[1]
        if not isinstance(results[1], Exception)
        else {"available": False, "mission": []}
    )
    focus_res = (
        results[2]
        if not isinstance(results[2], Exception)
        else {"available": False, "minutesDone": 0, "goalMinutes": 60, "focusScore": 0}
    )
    ai_usage_res = (
        results[3]
        if not isinstance(results[3], Exception)
        else {"available": False}
    )
    recommendation_res = (
        results[4]
        if not isinstance(results[4], Exception)
        else {"available": False, "items": []}
    )
    exam_rescue_res = (
        results[5]
        if not isinstance(results[5], Exception)
        else {"available": False}
    )

    return {
        "profile": profile_data,
        "academicHealth": academic_health_res,
        "coach": coach_res,
        "focus": focus_res,
        "aiUsage": ai_usage_res,
        "recommendation": recommendation_res,
        "examRescue": exam_rescue_res,
        "generatedAt": datetime.now(timezone.utc).isoformat(),
    }
