# Phase 7 — Ziku Moderator + group quizzes (spec §7.1 / §7.2).
#
# Mounted on the existing ``/api/groups`` prefix because a moderator and a
# group quiz are group-domain features: same membership gate, same
# ``groups`` documents, no parallel "community groups" system. Every route
# is member-only (the service checks ``memberIds``), and quiz attempts are
# graded server-side like the exam hall — the answer key stays in
# ``groups/{id}/quizzes/{qid}`` where Firestore rules deny client reads.

from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Depends, HTTPException

from app.core.auth import CurrentUser, require_student
from app.schemas import _CamelModel
from app.services import community_service as community
from app.services.community_service import CommunityError

router = APIRouter()


class ZikuAskRequest(_CamelModel):
    question: str = ""


class ZikuModerateRequest(_CamelModel):
    claim_a: str = ""
    claim_b: str = ""
    context: str = ""


class ZikuQuizRequest(_CamelModel):
    topic: str = ""
    question_count: int = 5


class QuizAttemptRequest(_CamelModel):
    answers: list[Any] = []
    duration_seconds: int = 0


def _raise(exc: CommunityError) -> None:
    raise HTTPException(status_code=exc.status, detail=exc.detail)


@router.post("/{group_id}/ziku/ask")
async def ziku_ask(
    group_id: str,
    body: ZikuAskRequest,
    user: CurrentUser = Depends(require_student),
):
    """Member-only doubt answering with group context (chat + question bank)."""
    try:
        return await community.ziku_ask(user.uid, group_id, body.question)
    except CommunityError as exc:
        _raise(exc)


@router.post("/{group_id}/ziku/moderate")
async def ziku_moderate(
    group_id: str,
    body: ZikuModerateRequest,
    user: CurrentUser = Depends(require_student),
):
    """Spec 7.2 — "Let's analyze both solutions..." disagreement analysis."""
    try:
        return await community.ziku_moderate(
            user.uid,
            group_id,
            body.claim_a,
            body.claim_b,
            body.context,
        )
    except CommunityError as exc:
        _raise(exc)


@router.post("/{group_id}/ziku/topics")
async def ziku_topics(
    group_id: str,
    user: CurrentUser = Depends(require_student),
):
    """Suggested discussion topics — AI with a rule-based fallback."""
    try:
        return await community.ziku_topics(user.uid, group_id)
    except CommunityError as exc:
        _raise(exc)


@router.post("/{group_id}/ziku/quiz")
async def ziku_quiz(
    group_id: str,
    body: ZikuQuizRequest | None = None,
    user: CurrentUser = Depends(require_student),
):
    """Generate and save a group quiz through the existing QUIZ quota.

    The source blends the group's weak topics, the caller's Mistake
    Memory priorities and recent group questions (spec integration).
    """
    try:
        options = body or ZikuQuizRequest()
        return await community.group_quiz(
            user.uid,
            user.display_name,
            group_id,
            topic=options.topic,
            question_count=options.question_count,
        )
    except CommunityError as exc:
        _raise(exc)


@router.get("/{group_id}/insights")
def group_insights(
    group_id: str,
    user: CurrentUser = Depends(require_student),
):
    """Hot chapters + weak topics for the moderator panel (rule-based)."""
    try:
        return community.group_insights(group_id, user.uid)
    except CommunityError as exc:
        _raise(exc)


@router.get("/{group_id}/quizzes")
def list_group_quizzes(
    group_id: str,
    user: CurrentUser = Depends(require_student),
):
    try:
        return community.list_group_quizzes(group_id, user.uid)
    except CommunityError as exc:
        _raise(exc)


@router.get("/{group_id}/quizzes/{quiz_id}")
def get_group_quiz(
    group_id: str,
    quiz_id: str,
    user: CurrentUser = Depends(require_student),
):
    """Redacted quiz — no correct options or explanations before submit."""
    try:
        return community.get_group_quiz(group_id, quiz_id, user.uid)
    except CommunityError as exc:
        _raise(exc)


@router.post("/{group_id}/quizzes/{quiz_id}/attempt")
async def attempt_group_quiz(
    group_id: str,
    quiz_id: str,
    body: QuizAttemptRequest,
    user: CurrentUser = Depends(require_student),
):
    try:
        return await community.attempt_group_quiz(
            group_id,
            quiz_id,
            user.uid,
            user.display_name,
            body.answers,
            body.duration_seconds,
        )
    except CommunityError as exc:
        _raise(exc)
