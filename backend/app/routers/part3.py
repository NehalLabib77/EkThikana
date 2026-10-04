"""PART 3 — Monthly Available Money + Focus sessions + Study stats.

These features are scoped to the FINAL-scope student user. Rules are enforced
in firestore.rules as well; this router is the privileged-read/write surface.

Idempotency contract:
- Complete-a-focus-session is idempotent: completedAtIso set once; subsequent
  marks are no-ops (returns the original completion timestamp).
- Task completion computes a deterministic id from (uid, taskId) and merges
  completed=true exactly once; re-complete is a no-op (no double increment).
"""
from __future__ import annotations

import logging
import re
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from typing import Any

from fastapi import APIRouter, Depends, HTTPException
from firebase_admin import firestore

from app.core.auth import CurrentUser, require_student
from app.core.firebase import get_firestore
from app.schemas import (
    FocusPatchRequest,
    FocusStartRequest,
    MonthlyBudgetRequest,
    OfflineRegisterRequest,
)
from app.services import focus_service

logger = logging.getLogger("gochano.part3")

router = APIRouter()

# Focus-domain helpers and the session state machine live in
# ``app.services.focus_service`` (Phase 5 — Ziku Focus Engine) so the legacy
# ``/api/study/focus/*`` routes and the new ``/api/focus/*`` engine routes
# share exactly one implementation. The private aliases preserve this
# module's historic names — ``tests/test_part3.py`` imports
# ``_fold_running_interval`` from here — without keeping a second copy of
# the policy code.
from app.services.focus_service import (
    FOCUS_ID_RE as _FOCUS_ID_RE,
    FOCUS_MAX_SECONDS as _FOCUS_MAX_SECONDS,
    as_int as _as_int,
    calc_streak as _calc_streak,
    coerce_focus_seconds as _coerce_focus_seconds,
    day_key as _day_key,
    focus_ref as _focus_ref,
    fold_running_interval as _fold_running_interval,
    parse_iso as _parse_iso,
    session_score as _focus_score,
)


def _month_key(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).strftime("%Y-%m")


# ============================================================
# OFFLINE MATERIALS
# ============================================================
@router.post("/offline/register")
def register_offline(
    body: OfflineRegisterRequest,
    user: CurrentUser = Depends(require_student),
):
    db = get_firestore()
    ref = (
        db.collection("users")
        .document(user.uid)
        .collection("offline_materials")
        .document(body.material_id)
    )
    ref.set(
        {
            "materialId": body.material_id,
            "title": body.title,
            "size": body.size,
            "localPath": body.local_path,
            "fileType": body.file_type,
            "originalFilename": body.original_filename,
            "downloadedAt": firestore.SERVER_TIMESTAMP,
            "downloadedAtIso": datetime.now(timezone.utc).isoformat(),
        },
        merge=True,
    )
    return {
        "registered": True,
        "materialId": body.material_id,
        "localPath": body.local_path,
    }


@router.get("/offline/list")
def list_offline(
    user: CurrentUser = Depends(require_student),
):
    rows = (
        get_firestore()
        .collection("users")
        .document(user.uid)
        .collection("offline_materials")
        .stream()
    )
    out = []
    for r in rows:
        d = r.to_dict() or {}
        out.append(
            {
                "materialId": d.get("materialId", r.id),
                "title": d.get("title", ""),
                "size": int(d.get("size", 0)),
                "localPath": d.get("localPath", ""),
                "fileType": d.get("fileType", ""),
                "originalFilename": d.get("originalFilename", ""),
                "downloadedAtIso": d.get("downloadedAtIso"),
            }
        )
    return {"items": out}


@router.delete("/offline/remove/{material_id}")
def remove_offline(
    material_id: str,
    user: CurrentUser = Depends(require_student),
):
    ref = (
        get_firestore()
        .collection("users")
        .document(user.uid)
        .collection("offline_materials")
        .document(material_id)
    )
    snap = ref.get()
    if not snap.exists:
        raise HTTPException(status_code=404, detail="Offline copy not found")
    ref.delete()
    return {"removed": True, "materialId": material_id}


# ============================================================
# MONTHLY AVAILABLE MONEY
# ============================================================
@router.post("/budget/monthly")
def set_monthly_available(
    body: MonthlyBudgetRequest,
    user: CurrentUser = Depends(require_student),
):
    ref = (
        get_firestore()
        .collection("users")
        .document(user.uid)
        .collection("monthly_budget")
        .document(body.month_key)
    )
    ref.set(
        {
            "monthKey": body.month_key,
            "availableAmount": float(body.available_amount),
            "currency": "BDT",
            "updatedAt": firestore.SERVER_TIMESTAMP,
            "updatedAtIso": datetime.now(timezone.utc).isoformat(),
        },
        merge=True,
    )
    return {"monthKey": body.month_key, "availableAmount": float(body.available_amount)}


@router.get("/budget/monthly")
def get_monthly_available(
    month_key: str,
    user: CurrentUser = Depends(require_student),
):
    if not re.fullmatch(r"\d{4}-\d{2}", month_key or ""):
        raise HTTPException(status_code=400, detail="month_key must be YYYY-MM")
    snap = (
        get_firestore()
        .collection("users")
        .document(user.uid)
        .collection("monthly_budget")
        .document(month_key)
        .get()
    )
    available = float((snap.to_dict() or {}).get("availableAmount", 0.0)) if snap.exists else 0.0
    return {"monthKey": month_key, "availableAmount": available}


@router.get("/budget/remaining")
def get_remaining(
    month_key: str,
    user: CurrentUser = Depends(require_student),
):
    """actualConfirmedSpending aggregates ONLY rows whose sourceRecordId
    exists in the corresponding source collection (Daily expense,
    Bazar purchased, Medicine Taken, Confirmed Commute fare).
    Estimated commute, pending/skipped/missed medicine, unpurchased bazar
    NEVER contribute.
    """
    if not re.fullmatch(r"\d{4}-\d{2}", month_key or ""):
        raise HTTPException(status_code=400, detail="month_key must be YYYY-MM")

    db = get_firestore()
    budget_snap = (
        db.collection("users")
        .document(user.uid)
        .collection("monthly_budget")
        .document(month_key)
        .get()
    )
    available = float((budget_snap.to_dict() or {}).get("availableAmount", 0.0)) if budget_snap.exists else 0.0

    # Select the month by the ledger's own partition key.
    #
    # This previously ran a range filter on ``createdAtIso``. No Gochano
    # client has ever written that field — ``FinancialService`` stamps
    # ``date`` / ``dateKey`` / ``monthKey`` and a ``createdAt`` Timestamp — and
    # a Firestore range filter on an absent field matches nothing. The query
    # therefore returned zero rows for every user, ``total_confirmed`` was
    # always 0.0, and ``remaining`` always came back equal to the full monthly
    # budget no matter how much the student had actually spent.
    #
    # ``monthKey`` is the field the client actually partitions on, it is an
    # equality filter (no composite index beyond ownerId+monthKey), and it
    # fixes historical rows too — which re-stamping new writes client-side
    # would not have done. Endpoint path, request and response schema are
    # unchanged.
    #
    # ``status`` is still filtered in Python: rows written before the client
    # started stamping it are treated as confirmed, which matches how they
    # were created (Gochano only mirrors a ledger row once the underlying
    # daily expense / purchase / taken dose / actual fare is real).
    # Two equality filters need a composite index on
    # (ownerId, monthKey). It is declared in firestore.indexes.json, but a
    # project where that was never deployed answers with FAILED_PRECONDITION
    # -- and the screen then showed "Not set" whether the student had set an
    # amount or not, which reads exactly like saving being broken.
    #
    # So the indexed query is tried first and a single-field query is the
    # fallback, with the month filtered in Python. One student's ledger is a
    # few hundred rows at most, so the fallback is cheap; it just should not
    # be the normal path, which is why the index is still declared.
    try:
        all_rows = list(
            db.collection("financial_transactions")
            .where("ownerId", "==", user.uid)
            .where("monthKey", "==", month_key)
            .stream()
        )
    except Exception as exc:
        logger.warning(
            "budget/remaining composite query unavailable (%s); "
            "falling back to an owner-only query. Deploy firestore.indexes.json "
            "to restore the indexed path.",
            type(exc).__name__,
        )
        all_rows = [
            snap
            for snap in db.collection("financial_transactions")
            .where("ownerId", "==", user.uid)
            .stream()
            if (snap.to_dict() or {}).get("monthKey") == month_key
        ]

    confirmed_by_source: dict[str, float] = defaultdict(float)
    total_confirmed = 0.0
    total_estimated = 0.0
    for s in all_rows:
        d = s.to_dict() or {}
        amt = float(d.get("amount") or 0.0)
        status = (d.get("status") or "confirmed").lower()
        src = (d.get("source") or "other").lower()
        if status == "confirmed":
            confirmed_by_source[src] += amt
            total_confirmed += amt
        elif status == "estimated":
            total_estimated += amt

    remaining = round(available - total_confirmed, 2)
    return {
        "monthKey": month_key,
        "available": available,
        "confirmedSpending": round(total_confirmed, 2),
        "estimatedSpending": round(total_estimated, 2),
        "remaining": remaining,
        "bySource": {k: round(v, 2) for k, v in confirmed_by_source.items()},
    }


# ============================================================
# FOCUS / STUDY PRODUCTIVITY
#
# The session state machine, the corruption policies and the focus
# aggregations live in ``app.services.focus_service`` (Phase 5 — Ziku Focus
# Engine). These routes keep their historical URLs and response shapes and
# only adapt the request/response, so the Phase 5 ``/api/focus/*`` engine
# routes and every already-shipped client share exactly one implementation.
# ============================================================
@router.post("/study/focus/start")
def focus_start(
    body: FocusStartRequest,
    user: CurrentUser = Depends(require_student),
):
    return focus_service.start_session(
        get_firestore(),
        user.uid,
        label=body.label,
        planned_minutes=body.planned_minutes,
        note=body.note,
        subject=body.subject,
        topic=body.topic,
    )


@router.patch("/study/focus/{focus_id}")
def focus_patch(
    focus_id: str,
    body: FocusPatchRequest,
    user: CurrentUser = Depends(require_student),
):
    return focus_service.apply_action(
        get_firestore(),
        user.uid,
        focus_id,
        action=body.action,
        subject=body.subject,
        topic=body.topic,
        interruptions=body.interruptions,
    )


@router.get("/study/focus/list")
def focus_list(
    days: int = 30,
    user: CurrentUser = Depends(require_student),
):
    return focus_service.list_sessions(get_firestore(), user.uid, days)


@router.get("/study/focus/today")
def focus_today(user: CurrentUser = Depends(require_student)):
    """Today's deep-work total plus the Focus Score the Home card shows.

    Finished sessions use the same counting policy as ``study_stats``
    (completed + cancelled, corrupt durations collapsed to 0). A session
    that is still running or paused is reported separately as live progress
    so the card can show a timer that is actually ticking without inflating
    the finished total.
    """
    return focus_service.today_summary(get_firestore(), user.uid)


@router.get("/study/stats")
def study_stats(
    user: CurrentUser = Depends(require_student),
):
    db = get_firestore()
    rows = list(
        db.collection("users")
        .document(user.uid)
        .collection("focus_sessions")
        .stream()
    )
    daily_seconds = defaultdict(int)
    monthly_seconds = defaultdict(int)
    study_days: set[str] = set()
    for r in rows:
        d = r.to_dict() or {}
        status = d.get("status")
        # Include completed and cancelled/stopped sessions — both are
        # terminal states with legitimate accumulatedSeconds. Exclude
        # running/paused (still in progress) and corrupt durations.
        if status not in ("completed", "cancelled"):
            continue
        day = d.get("dayKey")
        secs = _coerce_focus_seconds(d.get("accumulatedSeconds", 0))
        if day:
            daily_seconds[day] += secs
            study_days.add(day)
            month = day[:7]
            monthly_seconds[month] += secs

    streak = _calc_streak(study_days)

    task_rows = list(
        db.collection("tasks")
        .where("ownerId", "==", user.uid)
        .stream()
    )
    completed_count = 0
    total_count = 0
    for t in task_rows:
        td = t.to_dict() or {}
        total_count += 1
        if td.get("done") is True or td.get("completedAt") is not None:
            completed_count += 1

    today = _day_key(datetime.now(timezone.utc))
    this_month = _month_key(datetime.now(timezone.utc))
    return {
        "todaySeconds": daily_seconds.get(today, 0),
        "todayMinutes": daily_seconds.get(today, 0) // 60,
        "monthSeconds": monthly_seconds.get(this_month, 0),
        "monthMinutes": monthly_seconds.get(this_month, 0) // 60,
        "streakDays": streak,
        "completedTaskCount": completed_count,
        "totalTaskCount": total_count,
        "dailySeconds": [{"day": k, "seconds": v} for k, v in sorted(daily_seconds.items())],
    }
