from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException

from app.core.auth import CurrentUser, require_student
from app.core.firebase import get_firestore
from app.schemas import StudyPlanRequest

router = APIRouter()


def _as_utc(value):
    if value is None:
        return None
    if isinstance(value, datetime):
        if value.tzinfo is None:
            return value.replace(tzinfo=timezone.utc)
        return value.astimezone(timezone.utc)
    # Firestore Timestamp-like values normally expose to_datetime().
    converter = getattr(value, "to_datetime", None)
    if callable(converter):
        converted = converter()
        if converted.tzinfo is None:
            converted = converted.replace(tzinfo=timezone.utc)
        return converted.astimezone(timezone.utc)
    return None


@router.post("/plan")
def study_plan(
    body: StudyPlanRequest,
    user: CurrentUser = Depends(require_student),
):
    try:
        docs = (
            get_firestore()
            .collection("tasks")
            .where("ownerId", "==", user.uid)
            .limit(100)
            .stream()
        )

        items = []
        now = datetime.now(timezone.utc)
        for snap in docs:
            data = snap.to_dict() or {}
            if data.get("done") is True:
                continue
            due = _as_utc(data.get("dueAt"))
            if due is None:
                priority = -1_000_000
            else:
                hours = (due - now).total_seconds() / 3600
                # Overdue tasks remain highest priority; future tasks decrease
                # smoothly with time. This is deterministic planning only.
                priority = 1_000_000 - hours

            items.append(
                {
                    "id": snap.id,
                    "title": str(data.get("title", "")),
                    "dueAt": due.isoformat() if due else None,
                    "subjectId": data.get("subjectId"),
                    "semesterId": data.get("semesterId"),
                    "priorityScore": priority,
                }
            )

        items.sort(key=lambda x: x["priorityScore"], reverse=True)
        return {
            "items": items[: body.max_items],
            "method": "unfinished tasks ranked by deadline urgency",
        }
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=f"Could not build the study plan ({type(exc).__name__}). Check Render logs.",
        ) from exc
