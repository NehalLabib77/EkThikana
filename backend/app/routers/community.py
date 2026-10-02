# Phase 7 — Ziku Learning Community endpoints (spec §7.3 / §7.4 / §7.6).
#
# The Question Bank, Learning Points and Exam Challenges all live behind
# ``/api/community``. Nothing here re-implements groups or chat: group
# membership checks call into ``community_service``, which reads the same
# ``groups`` documents ``routers/groups.py`` writes.
#
# Privacy note — challenges and their answer keys never leave the service
# unredacted: ``_public_challenge`` only ships questions to a participant
# at ``start``, and results are visible only to the two participants.

from __future__ import annotations

from typing import Any, Literal

from fastapi import APIRouter, Depends, HTTPException

from app.core.auth import CurrentUser, require_student
from app.schemas import _CamelModel
from app.services import community_service as community
from app.services import community_intelligence_service as intelligence
from app.services.community_service import CommunityError
from app.services.exam_simulator_service import ExamError

router = APIRouter()


# ---------------------------------------------------------------------------
# request bodies
# ---------------------------------------------------------------------------
class PostCreateRequest(_CamelModel):
    kind: Literal["question", "solution", "notes", "achievement", "discussion", "study_challenge"] = "question"
    title: str = ""
    body: str = ""
    category: str = ""
    group_id: str = ""
    attachments: list[dict[str, Any]] = []


class AnswerRequest(_CamelModel):
    body: str = ""


class ChallengeCreateRequest(_CamelModel):
    title: str = ""
    exam_id: str = ""
    question_count: int = 10
    time_limit_minutes: int = 15
    opponent_id: str = ""


class ChallengeJoinRequest(_CamelModel):
    code: str = ""


class ChallengeSubmitRequest(_CamelModel):
    answers: list[Any] = []
    duration_seconds: int = 0


class CommunityQuestionRequest(PostCreateRequest):
    kind: Literal["question"] = "question"


class CommunityGroupRequest(_CamelModel):
    name: str = ""
    description: str = ""
    category: str = ""
    kind: str = "study"


def _raise(exc: CommunityError | ExamError) -> None:
    raise HTTPException(status_code=exc.status, detail=exc.detail)


@router.get("/feed")
def community_feed(
    kind: str = "",
    category: str = "",
    limit: int = 30,
    user: CurrentUser = Depends(require_student),
):
    return intelligence.feed(user.uid, kind=kind, category=category, limit=limit)


@router.post("/questions")
async def community_question(
    body: CommunityQuestionRequest,
    user: CurrentUser = Depends(require_student),
):
    try:
        post = await community.create_post(
            user.uid,
            user.display_name,
            kind="question",
            title=body.title,
            body=body.body,
            category=body.category,
            group_id=body.group_id,
            attachments=body.attachments,
        )
        return {"post": post, "understanding": intelligence.question_context(user.uid, body.body or body.title)}
    except CommunityError as exc:
        _raise(exc)


@router.post("/groups")
def community_group(
    body: CommunityGroupRequest,
    user: CurrentUser = Depends(require_student),
):
    from app.routers.groups import create_group
    from app.schemas import GroupCreate

    return create_group(
        GroupCreate(name=body.name, description=body.description, category=body.category, kind=body.kind),
        user,
    )


@router.get("/group-insights")
def community_group_insights(
    group_id: str,
    user: CurrentUser = Depends(require_student),
):
    try:
        return intelligence.group_insights(group_id, user.uid)
    except CommunityError as exc:
        _raise(exc)


@router.post("/challenge")
def community_challenge(
    body: ChallengeCreateRequest,
    user: CurrentUser = Depends(require_student),
):
    if not body.exam_id:
        raise HTTPException(status_code=400, detail="examId is required")
    try:
        return community.create_challenge(
            user.uid,
            user.display_name,
            title=body.title,
            exam_id=body.exam_id,
            question_count=body.question_count,
            time_limit_minutes=body.time_limit_minutes,
            opponent_id=body.opponent_id,
        )
    except (CommunityError, ExamError) as exc:
        _raise(exc)


# ---------------------------------------------------------------------------
# Question Bank — posts, answers, Learning Points (spec 7.3 / 7.5 / 7.6)
# ---------------------------------------------------------------------------
@router.get("/posts")
def list_posts(
    kind: str = "",
    category: str = "",
    group_id: str = "",
    popular: bool = False,
    limit: int = 30,
    user: CurrentUser = Depends(require_student),
):
    """List learning posts (question/solution/notes/achievement).

    Ordered newest-first, or by answers+useful marks when ``popular=true``.
    """
    try:
        return community.list_posts(
            kind=kind,
            category=category,
            group_id=group_id,
            popular=popular,
            limit=limit,
            uid=user.uid,
        )
    except CommunityError as exc:
        _raise(exc)


@router.post("/posts")
async def create_post(
    body: PostCreateRequest,
    user: CurrentUser = Depends(require_student),
):
    """Create a learning post. AI tags subject+chapter and flags likely
    duplicates (offline: rule-based fallback)."""
    try:
        return await community.create_post(
            user.uid,
            user.display_name,
            kind=body.kind,
            title=body.title,
            body=body.body,
            category=body.category,
            group_id=body.group_id,
            attachments=body.attachments,
        )
    except CommunityError as exc:
        _raise(exc)


@router.get("/posts/{post_id}")
def get_post(
    post_id: str,
    user: CurrentUser = Depends(require_student),
):
    try:
        return community.get_post(post_id, user.uid)
    except CommunityError as exc:
        _raise(exc)


@router.post("/posts/{post_id}/answers")
def add_answer(
    post_id: str,
    body: AnswerRequest,
    user: CurrentUser = Depends(require_student),
):
    try:
        return community.add_answer(user.uid, user.display_name, post_id, body.body)
    except CommunityError as exc:
        _raise(exc)


@router.post("/posts/{post_id}/answers/{answer_id}/accept")
def accept_answer(
    post_id: str,
    answer_id: str,
    user: CurrentUser = Depends(require_student),
):
    """Spec 7.6 — +5 Learning Points for the answer's author."""
    try:
        return community.accept_answer(user.uid, post_id, answer_id)
    except CommunityError as exc:
        _raise(exc)


@router.post("/posts/{post_id}/answers/{answer_id}/helpful")
def mark_helpful(
    post_id: str,
    answer_id: str,
    user: CurrentUser = Depends(require_student),
):
    """Spec 7.6 — +3 Learning Points for a helpful explanation."""
    try:
        return community.mark_helpful(user.uid, post_id, answer_id)
    except CommunityError as exc:
        _raise(exc)


@router.post("/posts/{post_id}/useful")
def mark_useful(
    post_id: str,
    user: CurrentUser = Depends(require_student),
):
    """Spec 7.6 — +10 Learning Points the first time a notes post is
    marked useful by a peer."""
    try:
        return community.mark_useful(user.uid, post_id)
    except CommunityError as exc:
        _raise(exc)


@router.get("/leaderboard")
def leaderboard(
    scope: str = "global",
    group_id: str = "",
    limit: int = 20,
    user: CurrentUser = Depends(require_student),
):
    """Top contributors — Learning Points only, never scores or mistakes."""
    if scope not in ("global", "group"):
        raise HTTPException(status_code=400, detail="scope must be global or group")
    try:
        return community.leaderboard(
            scope=scope,
            group_id=group_id,
            limit=limit,
            uid=user.uid,
        )
    except CommunityError as exc:
        _raise(exc)


# ---------------------------------------------------------------------------
# Exam Challenge Mode (spec 7.4)
# ---------------------------------------------------------------------------
@router.post("/challenges")
def create_challenge(
    body: ChallengeCreateRequest,
    user: CurrentUser = Depends(require_student),
):
    """Challenge a classmate with one of your exam papers (server-graded)."""
    if not body.exam_id:
        raise HTTPException(status_code=400, detail="examId is required")
    try:
        return community.create_challenge(
            user.uid,
            user.display_name,
            title=body.title,
            exam_id=body.exam_id,
            question_count=body.question_count,
            time_limit_minutes=body.time_limit_minutes,
            opponent_id=body.opponent_id,
        )
    except (CommunityError, ExamError) as exc:
        _raise(exc)


@router.post("/challenges/join")
def join_challenge(
    body: ChallengeJoinRequest,
    user: CurrentUser = Depends(require_student),
):
    try:
        return community.join_challenge(user.uid, user.display_name, body.code)
    except CommunityError as exc:
        _raise(exc)


@router.get("/challenges")
def list_challenges(
    user: CurrentUser = Depends(require_student),
):
    return community.list_challenges(user.uid)


@router.get("/challenges/{challenge_id}")
def get_challenge(
    challenge_id: str,
    user: CurrentUser = Depends(require_student),
):
    try:
        return community.get_challenge(challenge_id, user.uid)
    except CommunityError as exc:
        _raise(exc)


@router.post("/challenges/{challenge_id}/decline")
def decline_challenge(
    challenge_id: str,
    user: CurrentUser = Depends(require_student),
):
    try:
        return community.decline_challenge(user.uid, challenge_id)
    except CommunityError as exc:
        _raise(exc)


@router.post("/challenges/{challenge_id}/start")
def start_challenge(
    challenge_id: str,
    user: CurrentUser = Depends(require_student),
):
    """Serve the redacted questions and stamp this participant's clock."""
    try:
        return community.start_challenge(challenge_id, user.uid)
    except CommunityError as exc:
        _raise(exc)


@router.post("/challenges/{challenge_id}/submit")
def submit_challenge(
    challenge_id: str,
    body: ChallengeSubmitRequest,
    user: CurrentUser = Depends(require_student),
):
    """Server-side grading + the accuracy/time/topic comparison once both
    participants have finished."""
    try:
        return community.submit_challenge(
            challenge_id,
            user.uid,
            body.answers,
            body.duration_seconds,
        )
    except CommunityError as exc:
        _raise(exc)
