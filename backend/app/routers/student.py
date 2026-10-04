"""Phase 12.2.3 — Student dashboard router.

Endpoints:
    GET /api/student/dashboard-bootstrap
        Single consolidated endpoint aggregating all home/study dashboard signals:
        Profile, Academic Health, Study Coach, Focus Engine, AI Usage,
        Recommendations, and Exam Rescue.
"""
from __future__ import annotations

from fastapi import APIRouter, Depends

from app.core.auth import CurrentUser, require_student
from app.services import dashboard_bootstrap_service

router = APIRouter()


@router.get("/dashboard-bootstrap")
async def dashboard_bootstrap(
    user: CurrentUser = Depends(require_student),
):
    """Return consolidated student dashboard bootstrap payload.

    Derived exclusively from the authenticated user token (user.uid).
    Does not allow querying other users.
    """
    return await dashboard_bootstrap_service.get_dashboard_bootstrap(user)
