from datetime import datetime, timezone

from fastapi import APIRouter, Depends
from firebase_admin import firestore

from app.core.auth import CurrentUser, require_student
from app.core.firebase import get_firestore
from app.schemas import StudyPlanRequest

router = APIRouter()


@router.post("/plan")
def study_plan(
    body: StudyPlanRequest,
    user: CurrentUser = Depends(require_student),
):
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
        due = data.get("dueAt")
        priority = 0
        if due:
            try:
                hours = (due - now).total_seconds() / 3600
                priority = 1000 - hours
            except Exception:
                priority = 0
        items.append(
            {
                "id": snap.id,
                "title": data.get("title", ""),
                "dueAt": due.isoformat() if due else None,
                "priorityScore": priority,
            }
        )

    items.sort(key=lambda x: x["priorityScore"], reverse=True)
    return {
        "items": items[: body.max_items],
        "method": "unfinished tasks ranked by deadline urgency",
    }
