"""Phase 12 — Ziku Socratic AI Tutor Router."""

from typing import Optional

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, Field

from app.core.auth import CurrentUser, require_student
from app.services import ziku_tutor_service as tutor

router = APIRouter()


class StartSessionRequest(BaseModel):
    subject: str = Field(..., min_length=1)
    topic: str = Field(..., min_length=1)
    concept: Optional[str] = None
    mode: Optional[str] = "socratic"


class RespondRequest(BaseModel):
    response: str = Field(..., min_length=1)


class StepRequest(BaseModel):
    session_id: Optional[str] = None
    sessionId: Optional[str] = None
    response: str = Field(..., min_length=1)


class SwitchModeRequest(BaseModel):
    mode: str = Field(..., min_length=1)


class SwitchModeRequestBody(BaseModel):
    session_id: Optional[str] = None
    sessionId: Optional[str] = None
    mode: str = Field(..., min_length=1)


class HintRequest(BaseModel):
    session_id: Optional[str] = None
    sessionId: Optional[str] = None


class CompleteRequest(BaseModel):
    session_id: Optional[str] = None
    sessionId: Optional[str] = None


@router.post("/start")
@router.post("/session")
async def start_session(
    body: StartSessionRequest,
    user: CurrentUser = Depends(require_student),
):
    return await tutor.start_session(
        user_id=user.uid,
        subject=body.subject,
        topic=body.topic,
        concept=body.concept,
        mode=body.mode or "socratic",
    )


@router.post("/step")
async def step_post(
    body: StepRequest,
    user: CurrentUser = Depends(require_student),
):
    s_id = body.session_id or body.sessionId
    if not s_id:
        from fastapi import HTTPException
        raise HTTPException(status_code=422, detail="session_id is required")
    return await tutor.respond_to_step(
        user_id=user.uid,
        session_id=s_id,
        student_response=body.response,
    )


@router.post("/{session_id}/respond")
async def respond(
    session_id: str,
    body: RespondRequest,
    user: CurrentUser = Depends(require_student),
):
    return await tutor.respond_to_step(
        user_id=user.uid,
        session_id=session_id,
        student_response=body.response,
    )


@router.post("/hint")
async def hint_post(
    body: HintRequest,
    user: CurrentUser = Depends(require_student),
):
    s_id = body.session_id or body.sessionId
    if not s_id:
        from fastapi import HTTPException
        raise HTTPException(status_code=422, detail="session_id is required")
    return await tutor.request_hint(
        user_id=user.uid,
        session_id=s_id,
    )


@router.post("/{session_id}/hint")
async def hint(
    session_id: str,
    user: CurrentUser = Depends(require_student),
):
    return await tutor.request_hint(
        user_id=user.uid,
        session_id=session_id,
    )


@router.post("/switch-mode")
async def switch_mode_post(
    body: SwitchModeRequestBody,
    user: CurrentUser = Depends(require_student),
):
    s_id = body.session_id or body.sessionId
    if not s_id:
        from fastapi import HTTPException
        raise HTTPException(status_code=422, detail="session_id is required")
    return await tutor.switch_mode(
        user_id=user.uid,
        session_id=s_id,
        new_mode=body.mode,
    )


@router.post("/{session_id}/mode")
async def switch_mode(
    session_id: str,
    body: SwitchModeRequest,
    user: CurrentUser = Depends(require_student),
):
    return await tutor.switch_mode(
        user_id=user.uid,
        session_id=session_id,
        new_mode=body.mode,
    )


@router.post("/complete")
async def complete_post(
    body: CompleteRequest,
    user: CurrentUser = Depends(require_student),
):
    s_id = body.session_id or body.sessionId
    if not s_id:
        from fastapi import HTTPException
        raise HTTPException(status_code=422, detail="session_id is required")
    return await tutor.complete_session(
        user_id=user.uid,
        session_id=s_id,
    )


@router.post("/{session_id}/complete")
async def complete(
    session_id: str,
    user: CurrentUser = Depends(require_student),
):
    return await tutor.complete_session(
        user_id=user.uid,
        session_id=session_id,
    )


@router.get("/recent")
async def recent_sessions(
    limit: int = Query(10, ge=1, le=50),
    user: CurrentUser = Depends(require_student),
):
    return await tutor.get_recent_sessions(
        user_id=user.uid,
        limit=limit,
    )


@router.get("/{session_id}")
async def get_session(
    session_id: str,
    user: CurrentUser = Depends(require_student),
):
    return await tutor.get_session(
        user_id=user.uid,
        session_id=session_id,
    )


