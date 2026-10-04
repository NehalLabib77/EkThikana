"""Phase 5 — Ziku Focus Engine.

Single source of truth for focus sessions, deep-work totals and the Focus
Score. There is exactly **one** tracking system here:

* collection ``users/{uid}/focus_sessions`` (pre-existing, Phase 2),
* one state machine (start / pause / resume / complete / cancel /
  interruption) with the idempotency and corruption policies that
  ``tests/test_part3.py`` pins,
* one set of aggregations, shared by every surface that reports focus
  minutes (Home card, Ziku Coach, Academic Health, Study stats).

``routers/part3.py`` keeps its historical URLs (``/api/study/focus/*``) and
now delegates into this module, so Phase 5 adds the ``/api/focus/*`` engine
endpoints without forking the lifecycle logic. Anything that needs focus
data must call in here rather than reading the collection directly.
"""
from __future__ import annotations

import logging
import re
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from typing import Any

from firebase_admin import firestore
from fastapi import HTTPException

logger = logging.getLogger("gochano.focus")

# Collection / document identity -------------------------------------------
FOCUS_COLLECTION = "focus_sessions"
FOCUS_ID_RE = re.compile(r"^[A-Za-z0-9_\-]{1,80}$")

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
# to 0 in :func:`coerce_focus_seconds` — never clamped to the ceiling.
FOCUS_MAX_SECONDS = 24 * 60 * 60  # 86_400 s = 24h (validation only)

# Phase 5 — Focus Score (5.3) and smart behaviour (5.8) constants.
SCORE_WINDOW_DAYS = 7
PLAN_TARGET_MINUTES = 25  # one "block" for the duration part of the score
DEFAULT_GOAL_MINUTES = 60  # daily deep-work goal when no exam plan says more
STREAK_NUDGE_DAYS = 3
ADJUST_AFTER_MINUTES = 45

SCORE_BANDS: tuple[tuple[int, str, str], ...] = (
    # (minimum score, band key, headline)
    (90, "excellent", "Deep focus streak"),
    (60, "developing", "Solid rhythm"),
    (0, "needs_structure", "Needs structure"),
)


# ---------------------------------------------------------------------------
# State-machine helpers (single source of truth — moved from routers/part3.py)
# ---------------------------------------------------------------------------
def day_key(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%d")


def parse_iso(s: str | None) -> datetime | None:
    if not s:
        return None
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00"))
    except Exception:
        return None


def coerce_focus_seconds(raw: Any) -> int:
    """Read a focus session's accumulated seconds with two safety nets.

    Policy (single source of truth — applied on reads, on pause, on complete,
    and on cancel):

      * Negative values, malformed strings, bools, and any value above
        [:data:`FOCUS_MAX_SECONDS`] are treated as evidence of corruption and
        returned as ``0``.
      * A legitimately recorded duration in ``[0, FOCUS_MAX_SECONDS]`` is
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
    if seconds > FOCUS_MAX_SECONDS:
        # Corrupt / impossible legacy value — surface as 0 rather than
        # silently clamping up to a real-looking 24h. Clamping up here
        # would re-introduce the "5917 min" / "98h 37m" bug class.
        return 0
    return seconds


def fold_running_interval(
    now: datetime,
    last_resumed: datetime | None,
    accumulated: int,
) -> tuple[int, str]:
    """Compute the new ``accumulatedSeconds`` for a running session.

    The state machine has exactly three safe answers here, and they are
    chosen so we can never double-count an interval we have already folded
    in:

      * **RUNNING + valid ``lastResumedAtIso``** — add the interval only when
        it is within the safety ceiling and the resulting candidate remains
        within the safety ceiling. Otherwise, discard the new interval and
        preserve ``accumulated``.
      * **PAUSED** (caller passed ``last_resumed=None`` because pause
        cleared it) — return ``accumulated`` unchanged.
      * **RUNNING but ``lastResumedAtIso`` is missing / unparseable** — the
        row is in an inconsistent state. We do NOT fall back to
        ``startedAtIso`` because ``accumulatedSeconds`` may already contain
        folded intervals from prior pause/resume cycles; using
        ``startedAtIso`` would add the entire start→now span on top of that
        and double-count every previously-folded interval. The safe
        deterministic answer is to discard the active interval and keep only
        the already-folded accumulated value.

    Returns ``(new_accumulated_seconds, policy_tag)``. ``policy_tag`` is one
    of ``"running"``, ``"paused_or_stale_no_resume_stamp"``,
    ``"stale_interval"`` and ``"accumulation_overflow"`` and is exposed for
    diagnostics / tests so a regression in the choice surfaces as a readable
    failure.
    """
    if last_resumed is not None:
        interval_seconds = int((now - last_resumed).total_seconds())
        if interval_seconds < 0 or interval_seconds > FOCUS_MAX_SECONDS:
            return accumulated, "stale_interval"
        candidate = accumulated + interval_seconds
        if candidate > FOCUS_MAX_SECONDS:
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


def as_int(raw: Any, default: int = 0) -> int:
    if isinstance(raw, bool):
        return default
    if isinstance(raw, int):
        return raw
    if isinstance(raw, float):
        return int(raw)
    if isinstance(raw, str):
        try:
            return int(float(raw))
        except ValueError:
            return default
    return default


def focus_ref(db, uid: str, focus_id: str):
    return (
        db.collection("users")
        .document(uid)
        .collection(FOCUS_COLLECTION)
        .document(focus_id)
    )


def session_score(
    accumulated_seconds: int, planned_minutes: int, interruptions: int
) -> int:
    """Quality score (0-100) for a finished session.

    Completion is capped at 100 — running past the plan is not a fault —
    and every interruption costs 5 points, floored at 0. A session with no
    plan scores purely on "did you actually sit down", i.e. 100.
    """
    planned = max(0, int(planned_minutes or 0))
    actual_minutes = max(0, accumulated_seconds) / 60.0
    completion = 1.0 if planned <= 0 else min(actual_minutes / planned, 1.0)
    score = round(completion * 100 - max(0, int(interruptions or 0)) * 5)
    return int(max(0, min(100, score)))


def calc_streak(completed_days: set[str]) -> int:
    if not completed_days:
        return 0
    today = datetime.now(timezone.utc).date()
    streak = 0
    cursor = today
    while day_key(
        datetime(cursor.year, cursor.month, cursor.day, tzinfo=timezone.utc)
    ) in completed_days:
        streak += 1
        cursor = cursor - timedelta(days=1)
    return streak


# ---------------------------------------------------------------------------
# Reads
# ---------------------------------------------------------------------------
def read_rows(db, uid: str) -> list[dict[str, Any]]:
    """Every focus session row for a student, with the document id filled in
    when the row predates the ``id`` field."""
    rows = (
        db.collection("users")
        .document(uid)
        .collection(FOCUS_COLLECTION)
        .stream()
    )
    out: list[dict[str, Any]] = []
    for snap in rows:
        d = snap.to_dict() or {}
        if not d.get("id"):
            d["id"] = snap.id
        out.append(d)
    return out


def row_day(row: dict[str, Any]) -> str:
    """The UTC day a session belongs to (``dayKey`` first — the field every
    aggregator groups by — then ``startedAtIso`` for legacy rows)."""
    day = str(row.get("dayKey") or "")
    if day:
        return day
    started = parse_iso(row.get("startedAtIso"))
    return day_key(started) if started else ""


def serialize_session(d: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": d.get("id", ""),
        "status": d.get("status"),
        "label": d.get("label", ""),
        "plannedMinutes": d.get("plannedMinutes"),
        "accumulatedSeconds": coerce_focus_seconds(d.get("accumulatedSeconds", 0)),
        "startedAtIso": d.get("startedAtIso"),
        "completedAtIso": d.get("completedAtIso"),
        "dayKey": d.get("dayKey"),
        "note": d.get("note", ""),
        # Phase 2 — additive keys, older clients ignore them.
        "subject": d.get("subject", ""),
        "topic": d.get("topic", ""),
        "focusScore": d.get("focusScore"),
        "interruptions": max(0, as_int(d.get("interruptions"), 0)),
    }


def list_sessions(db, uid: str, days: int = 30) -> dict[str, Any]:
    if days < 1 or days > 365:
        raise HTTPException(status_code=400, detail="days must be 1..365")
    rows = (
        db.collection("users")
        .document(uid)
        .collection(FOCUS_COLLECTION)
        .order_by("startedAtIso", direction=firestore.Query.DESCENDING)
        .limit(500)
        .stream()
    )
    out = []
    for snap in rows:
        d = snap.to_dict() or {}
        out.append(serialize_session({**d, "id": d.get("id", snap.id)}))
    sessions = out[:200]
    # `items` is an additive alias for `sessions`. The app shipped reading
    # `items`, which was always null here and threw
    # "type 'Null' is not a subtype of type 'List<dynamic>'" on every visit to
    # the Focus screen. The client now reads `sessions`; carrying both means
    # an already-installed build recovers from a redeploy alone, without
    # breaking anything that reads either name.
    return {"sessions": sessions, "items": sessions, "count": len(sessions)}


def today_summary(db, uid: str) -> dict[str, Any]:
    """Today's deep-work total plus the Focus Score the Home card shows.

    Finished sessions use the same counting policy as ``study_stats``
    (completed + cancelled, corrupt durations collapsed to 0). A session
    that is still running or paused is reported separately as live progress
    so the card can show a timer that is actually ticking without inflating
    the finished total.
    """
    return summary_from_rows(read_rows(db, uid), datetime.now(timezone.utc))


def summary_from_rows(
    rows: list[dict[str, Any]], now: datetime
) -> dict[str, Any]:
    """:func:`today_summary` for rows the caller already loaded (so the
    engine endpoints scan the collection once, not twice)."""
    today = day_key(now)

    seconds = 0
    sessions = 0
    interruptions = 0
    planned = 0
    scores: list[int] = []
    by_subject: dict[str, int] = defaultdict(int)
    active_seconds = 0
    active_sessions = 0

    for d in rows:
        if d.get("dayKey") != today:
            continue
        status = d.get("status")
        accumulated = coerce_focus_seconds(d.get("accumulatedSeconds", 0))

        if status in ("completed", "cancelled"):
            seconds += accumulated
            sessions += 1
            planned += max(0, as_int(d.get("plannedMinutes"), 0))
            interruptions += max(0, as_int(d.get("interruptions"), 0))
            raw_score = d.get("focusScore")
            if isinstance(raw_score, (int, float)) and not isinstance(raw_score, bool):
                scores.append(int(max(0, min(100, raw_score))))
            subject = str(d.get("subject") or "").strip()
            if subject:
                by_subject[subject] += accumulated // 60
        elif status in ("running", "paused"):
            active_sessions += 1
            folded, _policy = fold_running_interval(
                now, parse_iso(d.get("lastResumedAtIso")), accumulated
            )
            active_seconds += folded

    return {
        "dayKey": today,
        "seconds": seconds,
        "minutes": seconds // 60,
        "plannedMinutes": planned,
        "sessions": sessions,
        "interruptions": interruptions,
        "focusScore": int(round(sum(scores) / len(scores))) if scores else None,
        "scoredSessions": len(scores),
        "bySubjectMinutes": dict(by_subject),
        "activeSessions": active_sessions,
        "activeSeconds": active_seconds,
        "activeMinutes": active_seconds // 60,
    }


# ---------------------------------------------------------------------------
# Lifecycle (single implementation; routers/part3.py and routers/focus.py
# both call these so the state machine is never forked)
# ---------------------------------------------------------------------------
def start_session(
    db,
    uid: str,
    *,
    label: str = "",
    planned_minutes: int = 25,
    note: str = "",
    subject: str = "",
    topic: str = "",
) -> dict[str, Any]:
    now = datetime.now(timezone.utc)
    doc_id = f"focus_{int(now.timestamp() * 1000)}"
    ref = focus_ref(db, uid, doc_id)
    ref.set(
        {
            "id": doc_id,
            "ownerId": uid,
            "status": "running",
            "label": label,
            "plannedMinutes": int(planned_minutes),
            "accumulatedSeconds": 0,
            "lastResumedAtIso": now.isoformat(),
            "startedAt": firestore.SERVER_TIMESTAMP,
            "startedAtIso": now.isoformat(),
            "note": note,
            "dayKey": day_key(now),
            # Phase 2 — smart focus session metadata.
            "subject": subject.strip(),
            "topic": topic.strip(),
            "interruptions": 0,
        }
    )
    return {
        "id": doc_id,
        "status": "running",
        "label": label,
        "plannedMinutes": int(planned_minutes),
        "startedAtIso": now.isoformat(),
        "subject": subject.strip(),
        "topic": topic.strip(),
    }


def apply_action(
    db,
    uid: str,
    focus_id: str,
    *,
    action: str,
    subject: str | None = None,
    topic: str | None = None,
    interruptions: int | None = None,
) -> dict[str, Any]:
    """The focus session state machine: pause / resume / complete / cancel /
    interruption, with the idempotency and no-double-count policies that
    ``tests/test_part3.py`` pins."""
    if not FOCUS_ID_RE.fullmatch(focus_id or ""):
        raise HTTPException(status_code=400, detail="Invalid focus id")
    ref = focus_ref(db, uid, focus_id)
    snap = ref.get()
    if not snap.exists:
        raise HTTPException(status_code=404, detail="Focus session not found")
    d = snap.to_dict() or {}
    status = d.get("status")
    now = datetime.now(timezone.utc)

    if action == "complete":
        if status == "completed":
            return {
                "id": focus_id,
                "status": "completed",
                "completedAtIso": d.get("completedAtIso"),
                "accumulatedSeconds": coerce_focus_seconds(
                    d.get("accumulatedSeconds", 0)
                ),
                "focusScore": d.get("focusScore"),
                "idempotent": True,
            }
        last_resumed = parse_iso(d.get("lastResumedAtIso"))
        accumulated = coerce_focus_seconds(d.get("accumulatedSeconds", 0))
        if status == "running":
            # Fold the active running interval into accumulatedSeconds.
            #
            # Policy (see ``fold_running_interval``):
            #   - RUNNING + valid lastResumedAtIso → add (now - last_resumed).
            #   - RUNNING but no resume stamp → keep accumulated unchanged.
            #     We deliberately do NOT fall back to ``startedAtIso`` here:
            #     if ``accumulatedSeconds`` already contains folded
            #     pause/resume intervals, ``now - startedAtIso`` would
            #     double-count them. The safe deterministic answer is to
            #     keep the already-folded value and surface 0 / unchanged
            #     rather than inflate.
            accumulated, _policy = fold_running_interval(
                now, last_resumed, accumulated
            )
        interruptions = max(0, as_int(d.get("interruptions"), 0))
        score = session_score(
            accumulated, as_int(d.get("plannedMinutes"), 25), interruptions
        )
        update: dict[str, Any] = {
            "status": "completed",
            "completedAt": firestore.SERVER_TIMESTAMP,
            "completedAtIso": now.isoformat(),
            "dayKey": day_key(now),
            "lastResumedAtIso": None,
            "accumulatedSeconds": accumulated,
            "interruptions": interruptions,
            "focusScore": score,
        }
        # Optional re-tagging: finish a session under the subject it really
        # covered (the start call may have been made from a generic timer).
        if subject is not None:
            update["subject"] = subject.strip()
        if topic is not None:
            update["topic"] = topic.strip()
        ref.update(update)
        from app.services.analytics_service import track_event

        track_event(
            uid,
            "focus_session_completed",
            {
                "subject": subject if subject is not None else d.get("subject"),
                "topic": topic if topic is not None else d.get("topic"),
                "duration_seconds": accumulated,
                "score": score,
                "source": "focus",
            },
        )
        return {
            "id": focus_id,
            "status": "completed",
            "completedAtIso": now.isoformat(),
            "accumulatedSeconds": accumulated,
            "focusScore": score,
            "interruptions": interruptions,
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
                "accumulatedSeconds": coerce_focus_seconds(
                    d.get("accumulatedSeconds", 0)
                ),
                "idempotent": True,
            }
        last_resumed = parse_iso(d.get("lastResumedAtIso"))
        accumulated = coerce_focus_seconds(d.get("accumulatedSeconds", 0))
        if status == "running":
            # Same policy as ``complete``: fold the running interval only
            # when ``lastResumedAtIso`` is valid. No ``startedAtIso``
            # fallback — see the comment in the complete branch above for
            # the double-count rationale.
            accumulated, _policy = fold_running_interval(
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
            raise HTTPException(
                status_code=409, detail=f"Cannot pause from status={status}"
            )
        last_resumed = parse_iso(d.get("lastResumedAtIso"))
        accumulated = coerce_focus_seconds(d.get("accumulatedSeconds", 0))
        accumulated, _policy = fold_running_interval(
            now, last_resumed, accumulated
        )
        ref.update(
            {
                "status": "paused",
                "accumulatedSeconds": accumulated,
                "lastResumedAtIso": None,
            }
        )
        return {
            "id": focus_id,
            "status": "paused",
            "accumulatedSeconds": accumulated,
        }

    if action == "resume":
        if status != "paused":
            raise HTTPException(
                status_code=409, detail=f"Cannot resume from status={status}"
            )
        ref.update({"status": "running", "lastResumedAtIso": now.isoformat()})
        return {"id": focus_id, "status": "running"}

    if action == "interruption":
        # Phase 2 — count a distraction while the timer is live. The focus
        # score computed at complete time deducts 5 points per interruption.
        if status not in ("running", "paused"):
            raise HTTPException(
                status_code=409,
                detail=f"Cannot record an interruption from status={status}",
            )
        current = max(0, as_int(d.get("interruptions"), 0))
        value = current + 1 if interruptions is None else max(0, int(interruptions))
        update: dict[str, Any] = {"interruptions": value}
        if subject is not None:
            update["subject"] = subject.strip()
        if topic is not None:
            update["topic"] = topic.strip()
        ref.update(update)
        return {"id": focus_id, "status": status, "interruptions": value}

    raise HTTPException(status_code=400, detail="Unknown action")


# ---------------------------------------------------------------------------
# Phase 5 — aggregations, Focus Score (5.3), smart behaviour (5.8)
# ---------------------------------------------------------------------------
def goal_minutes(db, uid: str) -> int:
    """Daily deep-work goal: the active Exam Rescue plan's target, else 60.

    Reads the plan that already exists (``users/{uid}/exam_rescue``) instead
    of introducing a second goal store.
    """
    rows = (
        db.collection("users")
        .document(uid)
        .collection("exam_rescue")
        .stream()
    )
    best: int | None = None
    for snap in rows:
        row = snap.to_dict() or {}
        if str(row.get("status") or "") != "active":
            continue
        target = as_int(row.get("dailyTargetMinutes"))
        if target > 0 and (best is None or target > best):
            best = target
    return best or DEFAULT_GOAL_MINUTES


def weekly_consistency(
    rows: list[dict[str, Any]], today: datetime
) -> dict[str, Any]:
    """Minutes per day for the last 7 days plus the consistency headline.

    ``consistencyPct`` is the share of window days with at least one finished
    session; ``streakDays`` walks back from today (same policy as
    ``/api/study/stats``).
    """
    keys = [day_key(today - timedelta(days=i)) for i in range(SCORE_WINDOW_DAYS - 1, -1, -1)]
    minutes_by_day: dict[str, int] = {k: 0 for k in keys}
    active: set[str] = set()

    for row in rows:
        if row.get("status") not in ("completed", "cancelled"):
            continue
        day = row_day(row)
        if day not in minutes_by_day:
            continue
        seconds = coerce_focus_seconds(row.get("accumulatedSeconds", 0))
        minutes_by_day[day] += seconds // 60
        if seconds > 0:
            active.add(day)

    total = sum(minutes_by_day.values())
    return {
        "windowDays": SCORE_WINDOW_DAYS,
        "days": [{"day": k, "minutes": minutes_by_day[k]} for k in keys],
        "activeDays": len(active),
        "minutes": total,
        "consistencyPct": round(100.0 * len(active) / SCORE_WINDOW_DAYS, 1),
        "streakDays": calc_streak(active),
    }


def compute_focus_score(
    rows: list[dict[str, Any]], today: datetime
) -> dict[str, Any] | None:
    """Phase 5.3 — the rolling Focus Score (0-100) with its bands.

    Three weighted parts over the last 7 days:

    * **completion** (40%) — finished sessions that completed vs cancelled.
      Leaving early is not a crime, but never finishing is a pattern.
    * **consistency** (35%) — share of window days with a finished session.
    * **duration** (25%) — average finished session against the 25-minute
      block target, capped at the target (longer is not penalised).

    Bands (``SCORE_BANDS``): 90-100 excellent, 60-89 developing
    (the 60-80 core the brief names), below 60 needs structure.
    Returns ``None`` when there is no finished session in the window — the
    score must never invent data.
    """
    keys = {day_key(today - timedelta(days=i)) for i in range(SCORE_WINDOW_DAYS)}
    completed = 0
    cancelled = 0
    total_seconds = 0
    active: set[str] = set()

    for row in rows:
        status = row.get("status")
        if status not in ("completed", "cancelled"):
            continue
        day = row_day(row)
        if day not in keys:
            continue
        seconds = coerce_focus_seconds(row.get("accumulatedSeconds", 0))
        total_seconds += seconds
        active.add(day)
        if status == "completed":
            completed += 1
        else:
            cancelled += 1

    started = completed + cancelled
    if started == 0:
        return None

    completion = completed / started
    consistency = len(active) / SCORE_WINDOW_DAYS
    average_minutes = (total_seconds / started) / 60.0
    duration = min(average_minutes / PLAN_TARGET_MINUTES, 1.0)

    value = int(
        round(100 * (0.40 * completion + 0.35 * consistency + 0.25 * duration))
    )
    value = max(0, min(100, value))
    band = "needs_structure"
    label = SCORE_BANDS[-1][2]
    for minimum, key, headline in SCORE_BANDS:
        if value >= minimum:
            band = key
            label = headline
            break

    return {
        "value": value,
        "band": band,
        "label": label,
        "windowDays": SCORE_WINDOW_DAYS,
        "sessions": started,
        "activeDays": len(active),
        "parts": {
            "completion": round(completion * 100, 1),
            "consistency": round(consistency * 100, 1),
            "duration": round(duration * 100, 1),
        },
    }


def smart_nudge(
    *,
    today_minutes: int,
    goal: int,
    active_minutes: int,
    streak_days: int,
) -> dict[str, str]:
    """Phase 5.8 — what the Ziku Focus screen tells you *before* you start.

    Order matters: a session that is already running long is an "adjust"
    (break now), then "skip" (target already met), then "streak" (momentum
    worth protecting), else a plain "start" invitation. Each kind carries
    its own copy so the client never has to invent policy text.
    """
    if active_minutes >= ADJUST_AFTER_MINUTES:
        kind = "adjust"
        message = (
            f"{active_minutes} minutes on the clock — stand up, drink water, "
            "eyes off the screen for 5 minutes, then resume."
        )
    elif today_minutes >= goal and goal > 0:
        kind = "skip"
        message = (
            f"Already {today_minutes}/{goal} min today — Ziku suggests a "
            "break instead of another block."
        )
    elif streak_days >= STREAK_NUDGE_DAYS:
        kind = "streak"
        message = (
            f"{streak_days}-day focus streak — keep the chain alive with one "
            "short block."
        )
    else:
        kind = "start"
        message = (
            f"Start a {goal or DEFAULT_GOAL_MINUTES} minute block — one "
            "subject, phone away."
        )
    return {"kind": kind, "message": message}


def engine_today(db, uid: str) -> dict[str, Any]:
    """:func:`today_summary` plus the Phase 5 additions: goal, rolling score,
    weekly consistency, live session ids and the smart nudge."""
    rows = read_rows(db, uid)
    now = datetime.now(timezone.utc)
    summary = summary_from_rows(rows, now)
    goal = goal_minutes(db, uid)
    weekly = weekly_consistency(rows, now)
    score = compute_focus_score(rows, now)

    active_ids = [
        str(row.get("id") or "")
        for row in rows
        if row.get("dayKey") == summary["dayKey"]
        and row.get("status") in ("running", "paused")
    ]

    summary.update(
        {
            "goalMinutes": goal,
            "score": score,
            "weekly": weekly,
            "streakDays": weekly["streakDays"],
            "activeSessionIds": active_ids,
            "nudge": smart_nudge(
                today_minutes=summary["minutes"],
                goal=goal,
                active_minutes=summary["activeMinutes"],
                streak_days=weekly["streakDays"],
            ),
        }
    )
    return summary


def history(db, uid: str, days: int = 30) -> dict[str, Any]:
    """Focus history for the last ``days`` days: the session list the app
    already shows, plus per-day buckets, weekly consistency and the rolling
    Focus Score."""
    if days < 1 or days > 365:
        raise HTTPException(status_code=400, detail="days must be 1..365")
    now = datetime.now(timezone.utc)
    rows = read_rows(db, uid)

    window = {day_key(now - timedelta(days=i)) for i in range(days)}
    in_window = [row for row in rows if row_day(row) in window]

    minutes_by_day: dict[str, int] = defaultdict(int)
    sessions_by_day: dict[str, int] = defaultdict(int)
    for row in in_window:
        if row.get("status") not in ("completed", "cancelled"):
            continue
        day = row_day(row)
        minutes_by_day[day] += coerce_focus_seconds(row.get("accumulatedSeconds", 0)) // 60
        sessions_by_day[day] += 1

    ordered_days = sorted(
        ({"day": day, "minutes": minutes_by_day[day], "sessions": sessions_by_day[day]}
         for day in set(minutes_by_day) | set(sessions_by_day)),
        key=lambda item: item["day"],
    )

    sessions = [serialize_session(row) for row in in_window]
    sessions.sort(
        key=lambda item: str(item.get("startedAtIso") or ""), reverse=True
    )
    sessions = sessions[:200]

    return {
        "sessions": sessions,
        "items": sessions,
        "count": len(sessions),
        "dayKey": day_key(now),
        "days": ordered_days,
        "weekly": weekly_consistency(rows, now),
        "score": compute_focus_score(rows, now),
        "goalMinutes": goal_minutes(db, uid),
    }
