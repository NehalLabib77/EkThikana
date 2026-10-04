"""Phase 4 — Study Coach endpoints (student-only).

Four reads that turn the existing student data into proactive advice:

* ``GET  /api/coach/profile``         the learning profile (cached per day)
* ``GET  /api/coach/daily``           today's AI study brief and mission
* ``GET  /api/coach/weekly-report``   the 7-day summary with one AI paragraph
* ``POST /api/coach/recalculate``     force-rebuild profile + mission

Everything here is student-only: a learning profile is built from quiz scores,
recorded mistakes and exam attempts, so no ``general`` role may read one. The
gate lives in ``require_student`` and is pinned by
``tests/test_role_gate_coverage.py``.

``force`` on the GETs is what the "Refresh" affordance uses; the mission and
profile are otherwise cached for the day (and the report for the week) so the
Home card can poll without spending anything.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, Query

from app.core.auth import CurrentUser, require_student
from app.services import study_coach_service as coach

router = APIRouter()


@router.get("/profile")
def coach_profile(
    force: bool = Query(
        default=False,
        description="Rebuild the profile instead of serving today's cache.",
    ),
    user: CurrentUser = Depends(require_student),
):
    """The student's learning profile: weak/strong topics, focus habits, readiness."""
    return coach.build_learning_profile(user.uid, force=force)


@router.get("/daily")
def coach_daily(
    force: bool = Query(
        default=False,
        description="Rebuild today's brief instead of serving the cache.",
    ),
    user: CurrentUser = Depends(require_student),
):
    """Today's study mission - priority topic, reason and up to 4 steps."""
    return coach.daily_recommendation(user.uid, force=force)


@router.get("/weekly-report")
async def coach_weekly_report(
    force: bool = Query(
        default=False,
        description="Rebuild this week's report (retries the AI narrative).",
    ),
    user: CurrentUser = Depends(require_student),
):
    """Seven-day summary: study time, score movement, weak area, next step."""
    return await coach.weekly_report(user.uid, force=force)


@router.post("/recalculate")
def coach_recalculate(user: CurrentUser = Depends(require_student)):
    """Rebuild the profile and today's mission from the latest student data."""
    return coach.recalculate(user.uid)
