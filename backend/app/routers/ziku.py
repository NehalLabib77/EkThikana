"""Phase 8 — Ziku Personal Intelligence endpoints (student-only).

Five reads that turn the student's own history into a Personal Academic
Operating System instead of a chatbot:

* ``GET /api/ziku/journey``             the Academic Memory Timeline (90 days,
  seven streams, improvement trends) - "Your Learning Journey"
* ``GET /api/ziku/brief``               the AI daily brief: morning headings
  (health, priority, why, mission) and the evening recap (progress, mistakes
  today, tomorrow's recommendation) with one AI reflection line
* ``GET /api/ziku/profile``             the Student Learning Profile: preferred
  study time, learning style, strong/weak subjects
* ``GET /api/ziku/next-best-action``    the Smart Recommendation Engine: five
  systems (Mistake Memory, Exam Simulator, Focus Engine, Community Insights,
  Study Coach) ranked into one next action plus its alternatives
* ``GET /api/ziku/achievements``        the Achievement System scoreboard

Every handler is student-only: a journey, a brief and a scoreboard are built
from quiz scores, recorded mistakes, focus sessions and exam attempts, so no
``general`` role may read one. The gate lives in ``require_student`` and is
pinned by ``tests/test_role_gate_coverage.py``.

``force`` is what the "Refresh" affordance uses; the journey, the morning
brief, the personality and the recommendation are otherwise cached for the
day. The evening half of the brief and the achievement bars are rebuilt on
read because they report *today*.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query

from app.core.auth import CurrentUser, require_student
from app.services import ziku_intelligence_service as intel

router = APIRouter()


def _phase_or_400(phase: str) -> str:
    if phase not in intel.PHASES:
        raise HTTPException(
            status_code=400,
            detail=f"phase must be one of {list(intel.PHASES)}",
        )
    return phase


@router.get("/journey")
def ziku_journey(
    force: bool = Query(
        default=False,
        description="Rebuild the timeline instead of serving today's cache.",
    ),
    user: CurrentUser = Depends(require_student),
):
    """Your Learning Journey - 90 days of exams, quizzes, mistakes, focus and
    community activity collapsed into one timeline with improvement trends."""
    return intel.build_journey(user.uid, force=force)


@router.get("/brief")
async def ziku_brief(
    phase: str = Query(
        default="auto",
        description="auto | morning | evening - which half the client asked for.",
    ),
    force: bool = Query(
        default=False,
        description="Rebuild the morning block instead of serving the cache.",
    ),
    user: CurrentUser = Depends(require_student),
):
    """The daily brief: academic health, today's priority and why plus the
    study mission in the morning; progress, mistakes and tomorrow's plan in
    the evening. Both halves always come back."""
    return await intel.daily_brief(
        user.uid, phase=_phase_or_400(phase), force=force
    )


@router.get("/profile")
def ziku_profile(
    force: bool = Query(
        default=False,
        description="Rebuild the learning personality instead of the cache.",
    ),
    user: CurrentUser = Depends(require_student),
):
    """The Student Learning Profile - preferred study time, learning style and
    strong/weak subjects (or topics when a quiz records no subject)."""
    return intel.learning_personality(user.uid, force=force)


@router.get("/next-best-action")
def ziku_next_best_action(
    force: bool = Query(
        default=False,
        description="Re-rank the recommendation instead of serving the cache.",
    ),
    user: CurrentUser = Depends(require_student),
):
    """The one thing to do next - five systems ranked, winner plus alternatives
    so the card can explain *why*, not just *what*."""
    return intel.next_best_action(user.uid, force=force)


@router.get("/achievements")
def ziku_achievements(
    force: bool = Query(
        default=False,
        description="Ignore cached earned stamps and re-grade every bar.",
    ),
    user: CurrentUser = Depends(require_student),
):
    """The scoreboard - MCQ milestones, consistency, improvement and
    contribution. Earned stamps are write-once: a metric that later regresses
    never un-earns an achievement."""
    return intel.achievements(user.uid, force=force)
