"""Phase 2 — Academic Health endpoints.

Three reads, all student-only:

* ``GET /api/ai/academic-health`` — the 0-100 score, metric breakdown,
  weak areas and the rule-based recommendations, plus today's snapshot.
* ``GET /api/ai/academic-health/history`` — daily snapshots for the trend.
* ``GET /api/ai/academic-health/recommendations`` — health rules merged
  with Ziku's AI-authored list (the existing daily-cached recommender).

The score itself never calls the AI: it has to be reproducible, explainable
and cheap enough for the Home card to refresh on every open.
"""

from __future__ import annotations

from datetime import date, datetime

from fastapi import APIRouter, Depends, HTTPException, Query

from app.core.auth import CurrentUser, require_student
from app.services import academic_health_service as health

router = APIRouter()


def _parse_exam_date(raw: str | None) -> date | None:
    if not raw:
        return None
    try:
        return datetime.strptime(raw.strip()[:10], "%Y-%m-%d").date()
    except ValueError:
        raise HTTPException(
            status_code=400,
            detail="exam_date must be YYYY-MM-DD",
        ) from None


@router.get("/academic-health")
def academic_health(
    examDate: str | None = Query(
        default=None,
        description="Optional target exam date (YYYY-MM-DD) to score against.",
    ),
    exam_date: str | None = Query(
        default=None,
        description="snake_case spelling of examDate.",
    ),
    user: CurrentUser = Depends(require_student),
):
    """Current Academic Health score with metrics, weak areas and advice."""
    raw = examDate or exam_date
    return health.get_academic_health(user.uid, exam_date=_parse_exam_date(raw))


@router.get("/academic-health/history")
def academic_health_history(
    days: int = Query(default=30, ge=1, le=365),
    user: CurrentUser = Depends(require_student),
):
    """Daily score snapshots, oldest first."""
    return health.get_history(user.uid, days=days)


@router.get("/academic-health/recommendations")
async def academic_health_recommendations(
    user: CurrentUser = Depends(require_student),
):
    """Health-rule advice merged with Ziku's AI recommendations."""
    return await health.get_recommendations(user.uid)
