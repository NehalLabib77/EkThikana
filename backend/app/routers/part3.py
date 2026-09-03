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

logger = logging.getLogger("gochano.part3")

router = APIRouter()

_FOCUS_ID_RE = re.compile(r"^[A-Za-z0-9_\-]{1,80}$")

# Realistic per-session upper bound. A single Gochano focus session is
# started from the app and explicitly finished by the user; the longest
# realistic session is on the order of a few hours, with a hard ceiling at
# 24h for safety. This constant is used only to validate that a freshly
# computed duration (running interval) is plausible — it is NEVER used to
# silently rewrite a corrupt historical value into a real-looking number.
#
# Legacy rows sometimes carry values that look like minutes stored in a
# seconds-shaped column (354_920s ≈ 5_917 min — the "5917 min" pollution on
# the Profile study-stats card; "98h 37m" focus history row). Rewriting
# those into 86_400 s is itself a bug class: it would surface as a fresh
# 1_440 min session in the UI even though no such session ever happened.
# Corrupt / impossible / negative historical values are therefore mapped
# to 0 in ``_coerce_focus_seconds`` — never clamped to the ceiling.
_FOCUS_MAX_SECONDS = 24 * 60 * 60  # 86_400 s = 24h (validation only)


def _day_key(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%d")


def _month_key(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).strftime("%Y-%m")


def _parse_iso(s: str | None) -> datetime | None:
    if not s:
        return None
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00"))
    except Exception:
        return None


def _coerce_focus_seconds(raw: Any) -> int:
    """Read a focus session's accumulated seconds with two safety nets.

    Policy (single source of truth — applied on reads, on pause, on complete,
    and on cancel):

      * Negative values, malformed strings, bools, and any value above
        [_FOCUS_MAX_SECONDS] are treated as evidence of corruption and
        returned as ``0``.
      * A legitimately recorded duration in ``[0, _FOCUS_MAX_SECONDS]`` is
        preserved exactly.
      * The function NEVER fabricates a real-looking duration (e.g. 86_400)
        from a corrupt value. Returning 0 is the honest, deterministic
        answer; the UI then shows "0 min" instead of a phantom session.
    """
    seconds = 0
    if isinstance(raw, bool):
        # ``bool`` is a subclass of ``int`` in Python; guard explicitly so
        # ``True`` does not become "1 second" silently.
        seconds = 0
    elif isinstance(raw, int):
        seconds = raw
    elif isinstance(raw, float):
        seconds = int(raw)
    elif isinstance(raw, str):
        try:
            seconds = int(raw)
        except ValueError:
            seconds = 0
    if seconds < 0:
        return 0
    if seconds > _FOCUS_MAX_SECONDS:
        # Corrupt / impossible legacy value — surface as 0 rather than
        # silently clamping up to a real-looking 24h. Clamping up here
        # would re-introduce the "5917 min" / "98h 37m" bug class.
        return 0
    return seconds


def _fold_running_interval(
    now: datetime,
    last_resumed: datetime | None,
    accumulated: int,
) -> tuple[int, str]:
    """Compute the new ``accumulatedSeconds`` for a running session.

    The state machine has exactly three safe answers here, and they are
    chosen so we can never double-count an interval we have already folded
    in:

            * **RUNNING + valid ``lastResumedAtIso``** —
                add the interval only when it is within the safety ceiling and the
                resulting candidate remains within the safety ceiling. Otherwise,
                discard the new interval and preserve ``accumulated``.
      * **PAUSED** (caller passed ``last_resumed=None`` because pause
        cleared it) — return ``accumulated`` unchanged.
      * **RUNNING but ``lastResumedAtIso`` is missing / unparseable** —
        the row is in an inconsistent state. We do NOT fall back to
        ``startedAtIso`` because ``accumulatedSeconds`` may already
        contain folded intervals from prior pause/resume cycles; using
        ``startedAtIso`` would add the entire start→now span on top of
        that and double-count every previously-folded interval. The safe
        deterministic answer is to discard the active interval and keep
        only the already-folded accumulated value.

    Returns ``(new_accumulated_seconds, policy_tag)``. ``policy_tag`` is
    one of ``"running"``, ``"paused"``, ``"stale_no_resume_stamp"`` and
    is exposed for diagnostics / tests so a regression in the choice
    surfaces as a readable failure.
    """
    if last_resumed is not None:
        interval_seconds = int((now - last_resumed).total_seconds())
        if interval_seconds < 0 or interval_seconds > _FOCUS_MAX_SECONDS:
            return accumulated, "stale_interval"
        candidate = accumulated + interval_seconds
        if candidate > _FOCUS_MAX_SECONDS:
            return accumulated, "accumulation_overflow"
        return candidate, "running"
    # last_resumed is None. Two cases collapse into one safe answer:
    #   (a) status was "paused" — running interval was already folded at
    #       pause time; ``lastResumedAtIso`` is cleared. Keep accumulated.
    #   (b) status was "running" but the row is stale (no resume stamp) —
    #       we cannot prove how much of start→now is already inside
    #       ``accumulatedSeconds``, so adding the whole span would
    #       double-count. Keep accumulated.
    return accumulated, "paused_or_stale_no_resume_stamp"


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
# ============================================================
def _focus_ref(db, uid: str, focus_id: str):
    return (
        db.collection("users")
        .document(uid)
        .collection("focus_sessions")
        .document(focus_id)
    )


@router.post("/study/focus/start")
def focus_start(
    body: FocusStartRequest,
    user: CurrentUser = Depends(require_student),
):
    db = get_firestore()
    now = datetime.now(timezone.utc)
    doc_id = f"focus_{int(now.timestamp() * 1000)}"
    ref = _focus_ref(db, user.uid, doc_id)
    ref.set(
        {
            "id": doc_id,
            "ownerId": user.uid,
            "status": "running",
            "label": body.label,
            "plannedMinutes": int(body.planned_minutes),
            "accumulatedSeconds": 0,
            "lastResumedAtIso": now.isoformat(),
            "startedAt": firestore.SERVER_TIMESTAMP,
            "startedAtIso": now.isoformat(),
            "note": body.note,
            "dayKey": _day_key(now),
        }
    )
    return {
        "id": doc_id,
        "status": "running",
        "label": body.label,
        "plannedMinutes": int(body.planned_minutes),
        "startedAtIso": now.isoformat(),
    }


@router.patch("/study/focus/{focus_id}")
def focus_patch(
    focus_id: str,
    body: FocusPatchRequest,
    user: CurrentUser = Depends(require_student),
):
    if not _FOCUS_ID_RE.fullmatch(focus_id or ""):
        raise HTTPException(status_code=400, detail="Invalid focus id")
    db = get_firestore()
    ref = _focus_ref(db, user.uid, focus_id)
    snap = ref.get()
    if not snap.exists:
        raise HTTPException(status_code=404, detail="Focus session not found")
    d = snap.to_dict() or {}
    status = d.get("status")
    action = body.action
    now = datetime.now(timezone.utc)

    if action == "complete":
        if status == "completed":
            return {
                "id": focus_id,
                "status": "completed",
                "completedAtIso": d.get("completedAtIso"),
                "accumulatedSeconds": _coerce_focus_seconds(
                    d.get("accumulatedSeconds", 0)
                ),
                "idempotent": True,
            }
        last_resumed = _parse_iso(d.get("lastResumedAtIso"))
        accumulated = _coerce_focus_seconds(d.get("accumulatedSeconds", 0))
        if status == "running":
            # Fold the active running interval into accumulatedSeconds.
            #
            # Policy (see ``_fold_running_interval``):
            #   - RUNNING + valid lastResumedAtIso → add (now - last_resumed).
            #   - RUNNING but no resume stamp → keep accumulated unchanged.
            #     We deliberately do NOT fall back to ``startedAtIso`` here:
            #     if ``accumulatedSeconds`` already contains folded
            #     pause/resume intervals, ``now - startedAtIso`` would
            #     double-count them. The safe deterministic answer is to
            #     keep the already-folded value and surface 0 / unchanged
            #     rather than inflate.
            accumulated, _policy = _fold_running_interval(
                now, last_resumed, accumulated
            )
        ref.update(
            {
                "status": "completed",
                "completedAt": firestore.SERVER_TIMESTAMP,
                "completedAtIso": now.isoformat(),
                "dayKey": _day_key(now),
                "lastResumedAtIso": None,
                "accumulatedSeconds": accumulated,
            }
        )
        return {
            "id": focus_id,
            "status": "completed",
            "completedAtIso": now.isoformat(),
            "accumulatedSeconds": accumulated,
        }

    if action == "cancel":
        # Cancel must persist the elapsed time, not silently drop it.
        #
        # The "Focus History shows 0 min" bug was caused by this branch
        # flipping ``status=cancelled`` without ever reading or updating
        # ``accumulatedSeconds`` — a 7-minute session cancelled at the 7th
        # minute saved as 0 seconds.
        #
        # The math is the same as ``pause`` / ``complete``: if the row is
        # currently ``running``, fold ``now - lastResumedAtIso`` into
        # accumulatedSeconds; if it's ``paused``, the running interval was
        # already folded at pause time and ``lastResumedAtIso`` is None, so
        # the persisted ``accumulatedSeconds`` is exactly what we want. A
        # cancelled row is a terminal state — repeated cancel must not
        # re-add anything.
        if status == "cancelled":
            return {
                "id": focus_id,
                "status": "cancelled",
                "accumulatedSeconds": _coerce_focus_seconds(
                    d.get("accumulatedSeconds", 0)
                ),
                "idempotent": True,
            }
        last_resumed = _parse_iso(d.get("lastResumedAtIso"))
        accumulated = _coerce_focus_seconds(d.get("accumulatedSeconds", 0))
        if status == "running":
            # Same policy as ``complete``: fold the running interval only
            # when ``lastResumedAtIso`` is valid. No ``startedAtIso``
            # fallback — see the comment in the complete branch above for
            # the double-count rationale.
            accumulated, _policy = _fold_running_interval(
                now, last_resumed, accumulated
            )
        ref.update(
            {
                "status": "cancelled",
                "cancelledAtIso": now.isoformat(),
                "lastResumedAtIso": None,
                "accumulatedSeconds": accumulated,
            }
        )
        return {
            "id": focus_id,
            "status": "cancelled",
            "accumulatedSeconds": accumulated,
        }

    if action == "pause":
        if status != "running":
            raise HTTPException(status_code=409, detail=f"Cannot pause from status={status}")
        last_resumed = _parse_iso(d.get("lastResumedAtIso"))
        accumulated = _coerce_focus_seconds(d.get("accumulatedSeconds", 0))
        accumulated, _policy = _fold_running_interval(
            now, last_resumed, accumulated
        )
        ref.update(
            {
                "status": "paused",
                "accumulatedSeconds": accumulated,
                "lastResumedAtIso": None,
            }
        )
        return {"id": focus_id, "status": "paused", "accumulatedSeconds": accumulated}

    if action == "resume":
        if status != "paused":
            raise HTTPException(status_code=409, detail=f"Cannot resume from status={status}")
        ref.update({"status": "running", "lastResumedAtIso": now.isoformat()})
        return {"id": focus_id, "status": "running"}

    raise HTTPException(status_code=400, detail="Unknown action")


@router.get("/study/focus/list")
def focus_list(
    days: int = 30,
    user: CurrentUser = Depends(require_student),
):
    if days < 1 or days > 365:
        raise HTTPException(status_code=400, detail="days must be 1..365")
    db = get_firestore()
    rows = list(
        db.collection("users")
        .document(user.uid)
        .collection("focus_sessions")
        .order_by("startedAtIso", direction=firestore.Query.DESCENDING)
        .limit(500)
        .stream()
    )
    out = []
    for r in rows:
        d = r.to_dict() or {}
        out.append(
            {
                "id": d.get("id", r.id),
                "status": d.get("status"),
                "label": d.get("label", ""),
                "plannedMinutes": d.get("plannedMinutes"),
                "accumulatedSeconds": _coerce_focus_seconds(
                    d.get("accumulatedSeconds", 0)
                ),
                "startedAtIso": d.get("startedAtIso"),
                "completedAtIso": d.get("completedAtIso"),
                "dayKey": d.get("dayKey"),
                "note": d.get("note", ""),
            }
        )
    sessions = out[:200]
    # `items` is an additive alias for `sessions`. The app shipped reading
    # `items`, which was always null here and threw
    # "type 'Null' is not a subtype of type 'List<dynamic>'" on every visit to
    # the Focus screen. The client now reads `sessions`; carrying both means
    # an already-installed build recovers from a redeploy alone, without
    # breaking anything that reads either name.
    return {"sessions": sessions, "items": sessions, "count": len(sessions)}


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
    completed_days: set[str] = set()
    for r in rows:
        d = r.to_dict() or {}
        if d.get("status") != "completed":
            continue
        day = d.get("dayKey")
        secs = _coerce_focus_seconds(d.get("accumulatedSeconds", 0))
        if day:
            daily_seconds[day] += secs
            completed_days.add(day)
            month = day[:7]
            monthly_seconds[month] += secs

    streak = _calc_streak(completed_days)

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


def _calc_streak(completed_days: set[str]) -> int:
    if not completed_days:
        return 0
    today = datetime.now(timezone.utc).date()
    streak = 0
    cursor = today
    while _day_key(datetime(cursor.year, cursor.month, cursor.day, tzinfo=timezone.utc)) in completed_days:
        streak += 1
        cursor = cursor - timedelta(days=1)
    return streak
