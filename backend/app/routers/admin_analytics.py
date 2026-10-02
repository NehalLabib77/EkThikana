"""Protected deterministic platform analytics for administrators."""

from fastapi import APIRouter, Depends, Query

from app.core.auth import CurrentUser, require_admin
from app.services import admin_analytics_service as analytics

router = APIRouter()


@router.get("/overview")
def overview(
    days: int = Query(default=30, ge=7, le=90),
    user: CurrentUser = Depends(require_admin),
):
    return analytics.overview(days)


@router.get("/subjects")
def subjects(
    days: int = Query(default=30, ge=7, le=90),
    user: CurrentUser = Depends(require_admin),
):
    return analytics.subject_demand(days)


@router.get("/topics")
def topics(
    days: int = Query(default=30, ge=7, le=90),
    user: CurrentUser = Depends(require_admin),
):
    return analytics.topic_difficulty(days)


@router.get("/features")
def features(
    days: int = Query(default=30, ge=7, le=90),
    user: CurrentUser = Depends(require_admin),
):
    return analytics.feature_usage(days)