"""Phase 5 — Ziku Focus Engine API (``/api/focus/*``).

Thin HTTP surface over :mod:`app.services.focus_service`. It deliberately
carries no focus logic of its own: start / complete go through the one
session state machine that ``/api/study/focus/*`` (``routers/part3.py``)
also uses, so there is exactly one tracking system for deep work and every
consumer — Home card, Ziku Coach, Academic Health — reads the same numbers.

Endpoints
    POST  /api/focus/start     begin a session (same lifecycle as part3)
    POST  /api/focus/complete  finish a session (idempotent), with the fresh
                               today snapshot for the completion card
    GET   /api/focus/today     minutes vs goal, rolling Focus Score, weekly
                               consistency, live sessions, smart nudge
    GET   /api/focus/history   session list + per-day buckets + score

Every route is student-only (``require_student``), and the prefix is
asserted by ``tests/test_role_gate_coverage.py``.
"""
from __future__ import annotations

from fastapi import APIRouter, Depends, Query

from app.core.auth import CurrentUser, require_student
from app.core.firebase import get_firestore
from app.schemas import FocusCompleteRequest, FocusStartRequest
from app.services import focus_service

router = APIRouter()


@router.post("/start")
def start_focus(
    body: FocusStartRequest,
    user: CurrentUser = Depends(require_student),
):
    """Begin a focus session and return its id (``focus_<ms>``)."""
    return focus_service.start_session(
        get_firestore(),
        user.uid,
        label=body.label,
        planned_minutes=body.planned_minutes,
        note=body.note,
        subject=body.subject,
        topic=body.topic,
    )


@router.post("/complete")
def complete_focus(
    body: FocusCompleteRequest,
    user: CurrentUser = Depends(require_student),
):
    """Finish a session.

    Idempotent (completing twice returns the original completion payload)
    and returns ``today`` — the same snapshot ``GET /today`` serves — so the
    completion card can show the rolling Focus Score and the nudge without a
    second round trip.
    """
    db = get_firestore()
    result = focus_service.apply_action(
        db,
        user.uid,
        body.focus_id,
        action="complete",
        subject=body.subject,
        topic=body.topic,
    )
    return {**result, "today": focus_service.engine_today(db, user.uid)}


@router.get("/today")
def focus_today(user: CurrentUser = Depends(require_student)):
    """Today's minutes vs goal, the rolling Focus Score, weekly consistency,
    live session ids and the smart nudge."""
    return focus_service.engine_today(get_firestore(), user.uid)


@router.get("/history")
def focus_history(
    days: int = Query(default=30, ge=1, le=365),
    user: CurrentUser = Depends(require_student),
):
    """Focus history for the last ``days`` days (sessions + daily buckets)."""
    return focus_service.history(get_firestore(), user.uid, days)
