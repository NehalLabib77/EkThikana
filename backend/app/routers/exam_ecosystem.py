"""Phase 15 — Exam Ecosystem API Router.

Mounted at: /api/exam-ecosystem

All routes require authenticated student.
UID is ALWAYS taken from the Firebase token — never from client body.

Endpoints:
  POST   /api/exam-ecosystem/papers/analyze
  GET    /api/exam-ecosystem/papers
  GET    /api/exam-ecosystem/papers/{paper_id}
  GET    /api/exam-ecosystem/insights
  DELETE /api/exam-ecosystem/papers/{paper_id}

  POST   /api/exam-ecosystem/priority/recalculate
  GET    /api/exam-ecosystem/priorities

  POST   /api/exam-ecosystem/plans
  GET    /api/exam-ecosystem/plans/active
  GET    /api/exam-ecosystem/plans/{plan_id}/today
  POST   /api/exam-ecosystem/plans/{plan_id}/recalculate

  POST   /api/exam-ecosystem/practice/start

  GET    /api/exam-ecosystem/readiness
  GET    /api/exam-ecosystem/readiness/history

  GET    /api/exam-ecosystem/coaching/daily

  GET    /api/exam-ecosystem/dashboard
"""

from __future__ import annotations

import logging
from typing import Any

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, Field

from app.core.auth import CurrentUser, require_student

logger = logging.getLogger("gochano.exam_ecosystem")

router = APIRouter(prefix="/exam-ecosystem", tags=["exam-ecosystem"])


# ---------------------------------------------------------------------------
# Request / Response models
# ---------------------------------------------------------------------------

class AnalyzePaperRequest(BaseModel):
    material_id: str
    exam_name: str | None = None
    board: str | None = None
    subject: str | None = None
    year: int | None = None
    session: str | None = None
    paper_code: str | None = None
    force: bool = False


class CreatePlanRequest(BaseModel):
    exam_name: str = Field(..., min_length=1, max_length=200)
    exam_date: str = Field(..., description="YYYY-MM-DD")
    subjects: list[str] = Field(default_factory=list)
    daily_minutes: int | None = Field(default=None, ge=30, le=600)
    selected_materials: list[str] = Field(default_factory=list)
    force_new: bool = False


class StartPracticeRequest(BaseModel):
    mode: str = Field(..., description=(
        "quick_quiz | topic_drill | weak_topic_drill | "
        "mistake_revision | chapter_test | mixed_priority | full_mock"
    ))
    topic: str | None = None
    chapter: str | None = None
    subject: str | None = None
    material_ids: list[str] = Field(default_factory=list)
    question_count: int | None = Field(default=None, ge=1, le=50)
    exam_id: str | None = None


# ---------------------------------------------------------------------------
# Past Paper routes
# ---------------------------------------------------------------------------

@router.post("/papers/analyze")
async def analyze_past_paper(
    req: AnalyzePaperRequest,
    user: CurrentUser = Depends(require_student),
) -> dict[str, Any]:
    """
    Analyze a Workspace material as a historical exam paper.
    Reuses Phase 14 chunks — no separate document ingestion.
    Idempotent: returns cache unless force=True.
    """
    from app.services.past_paper_service import analyze_past_paper as _analyze
    from app.services.analytics_service import record_event
    result = await _analyze(
        uid=user.uid,
        material_id=req.material_id,
        user=user,
        exam_name=req.exam_name,
        board=req.board,
        subject=req.subject,
        year=req.year,
        session=req.session,
        paper_code=req.paper_code,
        force=req.force,
    )
    try:
        record_event(user.uid, "past_paper_analyzed", {
            "materialId": req.material_id,
            "questionCount": result.get("questionCount", 0),
        })
    except Exception:
        pass
    return result


@router.get("/papers")
def list_past_papers(
    limit: int = Query(default=50, ge=1, le=200),
    user: CurrentUser = Depends(require_student),
) -> dict[str, Any]:
    """List all past papers analyzed by this student."""
    from app.services.past_paper_service import list_past_papers as _list
    return {"papers": _list(user.uid, limit=limit)}


@router.get("/papers/{paper_id}")
def get_past_paper(
    paper_id: str,
    user: CurrentUser = Depends(require_student),
) -> dict[str, Any]:
    """Get a single past paper record."""
    from app.services.past_paper_service import get_past_paper as _get
    return _get(user.uid, paper_id)


@router.delete("/papers/{paper_id}")
def delete_past_paper(
    paper_id: str,
    user: CurrentUser = Depends(require_student),
) -> dict[str, Any]:
    """
    Remove a past paper analysis.
    Does NOT delete the original Workspace material.
    """
    from app.services.past_paper_service import delete_past_paper as _del
    _del(user.uid, paper_id)
    return {"deleted": True, "paperId": paper_id}


@router.get("/insights")
def get_historical_insights(
    user: CurrentUser = Depends(require_student),
) -> dict[str, Any]:
    """
    Historical exam insights aggregated across all past papers.
    Uses cached topic stats — no AI call.
    Labels describe historical data only, not predictions.
    """
    from app.services.past_paper_service import get_historical_insights as _insights
    from app.services.analytics_service import record_event
    result = _insights(user.uid)
    try:
        record_event(user.uid, "exam_priority_viewed", {
            "topicCount": len(result.get("topicStats", [])),
        })
    except Exception:
        pass
    return result


# ---------------------------------------------------------------------------
# Priority Engine routes
# ---------------------------------------------------------------------------

@router.post("/priority/recalculate")
def recalculate_priority(
    user: CurrentUser = Depends(require_student),
) -> dict[str, Any]:
    """
    Recalculate priority scores for all known topics.
    Deterministic formula — AI does not select scores.
    """
    from app.services.exam_priority_service import recalculate_priorities
    topics = recalculate_priorities(user.uid)
    return {
        "topicsScored": len(topics),
        "priorities": topics[:20],  # return top 20 in response
    }


@router.get("/priorities")
def get_priorities(
    priority: str | None = Query(default=None,
                                  description="Filter: critical|high|medium|low"),
    limit: int = Query(default=20, ge=1, le=100),
    user: CurrentUser = Depends(require_student),
) -> dict[str, Any]:
    """Return persisted priority topics. Reads cache — no recalculation."""
    from app.services.exam_priority_service import get_priority_topics
    topics = get_priority_topics(user.uid, limit=limit, priority_filter=priority)
    return {"priorities": topics}


# ---------------------------------------------------------------------------
# Exam Plan routes
# ---------------------------------------------------------------------------

@router.post("/plans")
def create_plan(
    req: CreatePlanRequest,
    user: CurrentUser = Depends(require_student),
) -> dict[str, Any]:
    """
    Create a personalized exam study plan.
    Supports 3/7/14/30/45-day durations automatically.
    Idempotent: returns existing active plan for same exam unless force_new.
    """
    from app.services.exam_plan_service import create_exam_plan
    from app.services.analytics_service import record_event
    result = create_exam_plan(
        user.uid,
        exam_name=req.exam_name,
        exam_date_str=req.exam_date,
        subjects=req.subjects,
        daily_minutes=req.daily_minutes,
        selected_materials=req.selected_materials,
        force_new=req.force_new,
    )
    try:
        record_event(user.uid, "exam_plan_created", {
            "durationDays": result.get("durationDays"),
            "examName": req.exam_name,
        })
    except Exception:
        pass
    return result


@router.get("/plans/active")
def get_active_plan(
    user: CurrentUser = Depends(require_student),
) -> dict[str, Any]:
    """Return the current active exam plan (expires plan if exam date passed)."""
    from app.services.exam_plan_service import get_active_plan as _get
    plan = _get(user.uid)
    return {"plan": plan}


@router.get("/plans/{plan_id}/today")
def get_plan_today(
    plan_id: str,
    user: CurrentUser = Depends(require_student),
) -> dict[str, Any]:
    """Return today's study blocks for a plan."""
    from app.services.exam_plan_service import get_plan_today as _today
    items = _today(user.uid, plan_id)
    return {"today": items}


@router.post("/plans/{plan_id}/recalculate")
def recalculate_plan(
    plan_id: str,
    user: CurrentUser = Depends(require_student),
) -> dict[str, Any]:
    """Recalculate an existing plan without losing completed work."""
    from app.services.exam_plan_service import recalculate_plan as _recalc
    from app.services.analytics_service import record_event
    result = _recalc(user.uid, plan_id)
    try:
        record_event(user.uid, "exam_plan_recalculated", {"planId": plan_id})
    except Exception:
        pass
    return result


# ---------------------------------------------------------------------------
# Smart Practice routes
# ---------------------------------------------------------------------------

@router.post("/practice/start")
def start_practice(
    req: StartPracticeRequest,
    user: CurrentUser = Depends(require_student),
) -> dict[str, Any]:
    """
    Start a practice session. Selects WHAT to practice.
    Existing Quiz/Exam engines handle HOW to generate and grade.
    """
    from app.services.exam_practice_service import start_practice as _start
    from app.services.analytics_service import record_event
    result = _start(
        user.uid,
        mode=req.mode,
        topic=req.topic,
        chapter=req.chapter,
        subject=req.subject,
        material_ids=req.material_ids,
        question_count=req.question_count,
        exam_id=req.exam_id,
    )
    try:
        record_event(user.uid, "smart_practice_started", {
            "mode": req.mode,
            "topic": result.get("topic"),
        })
    except Exception:
        pass
    return result


# ---------------------------------------------------------------------------
# Readiness routes
# ---------------------------------------------------------------------------

@router.get("/readiness")
def get_readiness(
    user: CurrentUser = Depends(require_student),
) -> dict[str, Any]:
    """
    Calculate current exam readiness.
    Deterministic formula — AI does NOT select the numeric score.
    Readiness labels describe study preparation, not exam outcome guarantees.
    """
    from app.services.exam_readiness_service import (
        calculate_readiness,
        save_readiness_snapshot,
    )
    from app.services.analytics_service import record_event
    result = calculate_readiness(user.uid)
    try:
        record_event(user.uid, "exam_readiness_viewed", {
            "readiness": result.get("overallReadiness"),
            "label": result.get("label"),
        })
    except Exception:
        pass
    return result


@router.get("/readiness/history")
def get_readiness_history(
    days: int = Query(default=30, ge=7, le=90),
    user: CurrentUser = Depends(require_student),
) -> dict[str, Any]:
    """Return readiness snapshots for trend visualization."""
    from app.services.exam_readiness_service import get_readiness_history as _hist
    snapshots = _hist(user.uid, days=days)
    return {"history": snapshots, "days": days}


# ---------------------------------------------------------------------------
# Coaching route
# ---------------------------------------------------------------------------

@router.get("/coaching/daily")
def get_daily_coaching(
    user: CurrentUser = Depends(require_student),
) -> dict[str, Any]:
    """
    Get today's Ziku Exam Coach recommendations.
    Extends existing Ziku context — not a second assistant.
    Output validated: no guaranteed-exam-prediction language.
    """
    from app.services.ziku_exam_coach_service import get_daily_coaching as _coach
    from app.services.analytics_service import record_event
    result = _coach(user.uid)
    try:
        record_event(user.uid, "ziku_exam_action_started", {
            "type": "daily_coaching",
        })
    except Exception:
        pass
    return result


# ---------------------------------------------------------------------------
# Dashboard bootstrap
# ---------------------------------------------------------------------------

@router.get("/dashboard")
def get_exam_dashboard(
    user: CurrentUser = Depends(require_student),
) -> dict[str, Any]:
    """
    Single-request Exam Ecosystem bootstrap.
    Reduces mobile network calls by aggregating:
      - active exam
      - days remaining
      - overall readiness
      - top 5 priority topics
      - today's plan
      - latest coaching
    """
    from app.services.analytics_service import record_event

    # Active exam / plan
    try:
        from app.services.exam_plan_service import get_active_plan
        plan = get_active_plan(user.uid)
    except Exception:
        plan = None

    # Readiness
    try:
        from app.services.exam_readiness_service import calculate_readiness
        readiness = calculate_readiness(user.uid)
    except Exception:
        readiness = {}

    # Top priorities
    try:
        from app.services.exam_priority_service import get_priority_topics
        priorities = get_priority_topics(user.uid, limit=5)
    except Exception:
        priorities = []

    # Today's plan
    today_plan = []
    if plan:
        try:
            from app.services.exam_plan_service import get_plan_today
            today_plan = get_plan_today(user.uid, plan["planId"])
        except Exception:
            pass

    # Coaching summary
    try:
        from app.services.ziku_exam_coach_service import get_daily_coaching
        coaching = get_daily_coaching(user.uid)
    except Exception:
        coaching = {}

    # Historical insights summary
    try:
        from app.services.past_paper_service import get_historical_insights
        insights = get_historical_insights(user.uid)
        papers_analyzed = insights.get("papersAnalyzed", 0)
    except Exception:
        papers_analyzed = 0

    try:
        record_event(user.uid, "exam_ecosystem_opened", {})
    except Exception:
        pass

    return {
        "activePlan": plan,
        "daysRemaining": (
            plan.get("daysRemaining") if plan else None
        ),
        "examName": plan.get("examName") if plan else None,
        "overallReadiness": readiness.get("overallReadiness"),
        "readinessLabel": readiness.get("label"),
        "readinessTrend": readiness.get("trend"),
        "topPriorityTopics": priorities,
        "todayPlan": today_plan,
        "coaching": coaching.get("coaching"),
        "papersAnalyzed": papers_analyzed,
        "recommendedAction": readiness.get("recommendedNextAction"),
    }
