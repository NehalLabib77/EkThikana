# Phase 1 — AI Mistake Memory endpoints.
#
# Storage, review scheduling and the Ziku analysis all live in
# ``app.services.mistake_memory_service``; this router is the thin,
# require_student-gated surface the Flutter "My Learning Brain" section talks
# to. Analysis is triggered from the client (quiz result screen and the
# brain's "Analyse now" button) rather than a background task, so a student
# always sees the same state the server has — a plan is either analysed or
# still listed as pending.

from fastapi import APIRouter, Depends, HTTPException, Query

from app.core.auth import CurrentUser, require_student
from app.services import mistake_memory_service as mistakes

router = APIRouter()

_STATUS_VALUES = ("all", "due", "repeated", "pending")


@router.get("/mistakes")
def list_mistakes(
    status: str = Query(default="all", description="all | due | repeated | pending"),
    limit: int = Query(default=50, ge=1, le=200),
    user: CurrentUser = Depends(require_student),
):
    """The student's recorded mistakes, most repeated / most recent first."""
    if status not in _STATUS_VALUES:
        raise HTTPException(
            status_code=400,
            detail=f"status must be one of: {', '.join(_STATUS_VALUES)}",
        )
    items = mistakes.list_mistakes(user.uid, status=status, limit=limit)
    return {"mistakes": items, "count": len(items)}


@router.get("/mistakes/brain")
def learning_brain(user: CurrentUser = Depends(require_student)):
    """My Learning Brain: totals, weak topics, repeats, revision queue."""
    return mistakes.get_learning_brain(user.uid)


@router.post("/mistakes/analyze")
async def analyze_mistakes(
    limit: int = Query(default=5, ge=1, le=mistakes.MAX_ANALYSIS_BATCH),
    user: CurrentUser = Depends(require_student),
):
    """Ask Ziku to analyse the not-yet-analysed mistakes in one request.

    Quota/provider failures surface as HTTP errors so the screen can say
    "analysis unavailable" instead of silently showing nothing.
    """
    return await mistakes.analyze_pending(user.uid, limit=limit)


@router.post("/mistakes/{mistake_id}/review")
def review_mistake(
    mistake_id: str,
    user: CurrentUser = Depends(require_student),
):
    """Mark one mistake revised: advances its spaced-repetition ladder."""
    updated = mistakes.mark_reviewed(user.uid, mistake_id)
    if updated is None:
        raise HTTPException(status_code=404, detail="Mistake not found")
    return updated
