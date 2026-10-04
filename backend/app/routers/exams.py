# Phase 3 — AI Real Exam Simulator endpoints.
#
# The hall is server-graded: questions leave this router without answers or
# explanations (``_redact_question``), attempts and results are written only
# here, and there is deliberately no endpoint to call for a hint mid-exam.
# Post-exam the result quietly lands in the Quiz system, Mistake Memory and
# Academic Health — see ``exam_simulator_service`` for those hand-offs.

from __future__ import annotations

from typing import Any, Literal

from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, UploadFile
from pydantic import BaseModel, Field

from app.core.auth import CurrentUser, require_student
from app.schemas import _CamelModel
from app.routers.ai_study import _extract_material_text, _extract_note_text
from app.services import exam_pro_service as exam_pro
from app.services import exam_simulator_service as exams
from app.services.exam_simulator_service import ExamError

router = APIRouter()


# ---------------------------------------------------------------------------
# request bodies
# ---------------------------------------------------------------------------
class ExamNegativeMarking(_CamelModel):
    enabled: bool = True
    penalty: float | None = Field(default=None, ge=0, le=50)


class ExamQuestionInput(_CamelModel):
    question: str = Field(default="", max_length=4000)
    type: Literal["mcq", "short_answer", "numerical"] = "mcq"
    options: list[str] = Field(default_factory=list, max_length=8)
    correct: str = Field(default="", max_length=500)
    explanation: str = Field(default="", max_length=2000)
    topic: str = Field(default="", max_length=120)
    marks: float = Field(default=0, ge=0, le=1000)
    difficulty: str = Field(default="", max_length=20)
    mistake_type: str = Field(default="", max_length=30)


class ExamCreateRequest(_CamelModel):
    subject: str = Field(default="", max_length=80)
    source: str = Field(default="ai", max_length=20)
    question_count: int = Field(default=25, ge=1, le=200)
    total_marks: float = Field(default=100, gt=0, le=10000)
    time_limit_minutes: int = Field(default=60, ge=1, le=480)
    negative_marking: ExamNegativeMarking = Field(
        default_factory=ExamNegativeMarking
    )
    correct_marks: float | None = Field(default=None, gt=0, le=1000)
    skip_marks: float = Field(default=0, ge=-100, le=100)
    difficulty: str = Field(default="medium", max_length=20)
    topic: str = Field(default="", max_length=200)
    title: str = Field(default="", max_length=200)
    # Phase 6 — the builder's optional "pause exam" setting.
    allow_pause: bool = True
    questions: list[ExamQuestionInput] | None = Field(default=None, max_length=200)
    source_exam_id: str = Field(default="", max_length=64)
    material_ids: list[str] = Field(default_factory=list, max_length=5)


class ExamSubmitRequest(_CamelModel):
    attempt_id: str = Field(min_length=1, max_length=64)
    answers: Any = Field(default_factory=list)
    time_spent_seconds: int | None = Field(default=None, ge=0, le=86400)
    marked_for_review: list[int] = Field(default_factory=list, max_length=400)
    with_ai_analysis: bool = True


class ExamProgressRequest(_CamelModel):
    """Spec 6.4 — what the hall saves while the paper is still open."""

    attempt_id: str = Field(min_length=1, max_length=64)
    answers: Any = Field(default_factory=list)
    marked_for_review: list[int] = Field(default_factory=list, max_length=400)
    remaining_seconds: int | None = Field(default=None, ge=0, le=86400)


class ExamPauseRequest(_CamelModel):
    attempt_id: str = Field(min_length=1, max_length=64)
    remaining_seconds: int | None = Field(default=None, ge=0, le=86400)


class ExamResumeRequest(_CamelModel):
    attempt_id: str | None = Field(default=None, max_length=64)


class ExamShareRequest(_CamelModel):
    share: bool = True


def _raise(exc: ExamError) -> None:
    raise HTTPException(status_code=exc.status, detail=exc.detail)


def _material_text(user: CurrentUser, material_ids: list[str]) -> str:
    """Optional source text for AI generation (notes and/or materials)."""
    parts: list[str] = []
    for material_id in material_ids:
        try:
            if str(material_id).startswith("note_"):
                text = _extract_note_text(user, str(material_id)[5:])
            else:
                text = _extract_material_text(user, str(material_id))
        except Exception:
            continue
        if text:
            parts.append(str(text)[:5000])
    return "\n\n".join(parts)


# ---------------------------------------------------------------------------
# static routes first: ``/create`` and ``/upload`` must not be swallowed by
# the ``/{exam_id}`` pattern below.
# ---------------------------------------------------------------------------
@router.post("/create")
async def create_exam(
    body: ExamCreateRequest,
    user: CurrentUser = Depends(require_student),
):
    """Build an exam from AI questions, an uploaded paper or saved questions."""
    try:
        return await exams.create_exam(
            user.uid,
            subject=body.subject,
            source=body.source,
            question_count=body.question_count,
            total_marks=body.total_marks,
            time_limit_minutes=body.time_limit_minutes,
            negative_marking=body.negative_marking.enabled,
            penalty=body.negative_marking.penalty,
            correct_marks=body.correct_marks,
            skip_marks=body.skip_marks,
            difficulty=body.difficulty,
            topic=body.topic,
            title=body.title,
            questions=[q.model_dump(by_alias=True) for q in (body.questions or [])] or None,
            source_exam_id=body.source_exam_id,
            material_text=_material_text(user, body.material_ids),
            allow_pause=body.allow_pause,
        )
    except ExamError as exc:
        _raise(exc)


@router.post("/upload")
async def upload_question_paper(
    file: UploadFile = File(...),
    subject: str = Form(""),
    questionCount: int = Form(25),
    user: CurrentUser = Depends(require_student),
):
    """Digitise a PDF / image / text paper into editable draft questions.

    Stateless on purpose: the student corrects the drafts on the client and
    sends them back with ``POST /create``, which is where the exam starts.
    """
    data = await file.read()
    try:
        return await exams.upload_paper(
            user.uid,
            filename=file.filename or "",
            content_type=file.content_type or "",
            data=data,
            subject=subject,
            question_count=questionCount,
        )
    except ExamError as exc:
        _raise(exc)


@router.get("")
def list_exams(
    limit: int = Query(default=20, ge=1, le=50),
    user: CurrentUser = Depends(require_student),
):
    """Recent exams — the "saved questions" picker and the history list."""
    items = exams.list_exams(user.uid, limit=limit)
    return {"exams": items, "count": len(items)}


# Phase 6 — the spec spells these two out as ``/api/exams/list`` and
# ``/api/exams/history``. They are declared here, before ``/{exam_id}``,
# otherwise the path parameter would swallow "list" and "history".
@router.get("/list")
def list_exams_alias(
    limit: int = Query(default=20, ge=1, le=50),
    user: CurrentUser = Depends(require_student),
):
    """Alias of ``GET /api/exams`` — same payload, spec-mandated path."""
    return list_exams(limit=limit, user=user)


@router.get("/history")
def exam_history(
    limit: int = Query(default=20, ge=1, le=50),
    user: CurrentUser = Depends(require_student),
):
    """"My Exams": the student's own finished papers and their improvement."""
    return exam_pro.history(user.uid, limit=limit)


@router.get("/shared/{code}")
def get_shared_paper(code: str, user: CurrentUser = Depends(require_student)):
    """Open a paper someone shared by code — questions only, never marks."""
    try:
        return exam_pro.get_shared(user.uid, code)
    except ExamError as exc:
        _raise(exc)


@router.get("/{exam_id}")
def get_exam(
    exam_id: str,
    includeQuestions: bool = Query(default=False),
    user: CurrentUser = Depends(require_student),
):
    """Exam metadata. Questions come back redacted — never the answers."""
    try:
        return exams.get_exam(
            user.uid, exam_id, include_questions=includeQuestions
        )
    except ExamError as exc:
        _raise(exc)


@router.post("/{exam_id}/start")
def start_exam(exam_id: str, user: CurrentUser = Depends(require_student)):
    """Open the hall: creates the attempt and starts the countdown clock."""
    try:
        return exams.start_attempt(user.uid, exam_id)
    except ExamError as exc:
        _raise(exc)


@router.post("/{exam_id}/submit")
async def submit_exam(
    exam_id: str,
    body: ExamSubmitRequest,
    user: CurrentUser = Depends(require_student),
):
    """Grade on the server, then hand the result to the memory systems."""
    try:
        return await exams.submit_attempt(
            user.uid,
            exam_id,
            attempt_id=body.attempt_id,
            answers=body.answers,
            time_spent_seconds=body.time_spent_seconds,
            marked_for_review=body.marked_for_review,
            with_ai_analysis=body.with_ai_analysis,
        )
    except ExamError as exc:
        _raise(exc)


@router.get("/{exam_id}/analysis")
async def exam_analysis(
    exam_id: str,
    attemptId: str | None = Query(default=None),
    withAi: bool = Query(default=False),
    user: CurrentUser = Depends(require_student),
):
    """Score, accuracy, time management, weak topics, mistakes and Ziku's plan."""
    try:
        return await exams.get_analysis(
            user.uid,
            exam_id,
            attempt_id=attemptId,
            with_ai=withAi,
        )
    except ExamError as exc:
        _raise(exc)


# ---------------------------------------------------------------------------
# Phase 6 — Real Exam Simulator Pro: the controls, the history and sharing.
# All grading still happens in ``/submit``; nothing here touches an answer.
# ---------------------------------------------------------------------------
@router.get("/{exam_id}/result")
def exam_result(
    exam_id: str,
    attemptId: str | None = Query(default=None),
    user: CurrentUser = Depends(require_student),
):
    """One finished attempt in the submit payload shape — for My Exams."""
    try:
        return exam_pro.latest_result(user.uid, exam_id, attempt_id=attemptId)
    except ExamError as exc:
        _raise(exc)


@router.post("/{exam_id}/save")
def save_exam_progress(
    exam_id: str,
    body: ExamProgressRequest,
    user: CurrentUser = Depends(require_student),
):
    """Spec 6.4 — answers, flags and remaining time, kept server-side."""
    try:
        return exam_pro.save_progress(
            user.uid,
            exam_id,
            attempt_id=body.attempt_id,
            answers=body.answers,
            marked_for_review=body.marked_for_review,
            remaining_seconds=body.remaining_seconds,
        )
    except ExamError as exc:
        _raise(exc)


@router.post("/{exam_id}/pause")
def pause_exam(
    exam_id: str,
    body: ExamPauseRequest,
    user: CurrentUser = Depends(require_student),
):
    """Freeze the clock when the paper's builder allowed a pause."""
    try:
        return exam_pro.pause_attempt(
            user.uid,
            exam_id,
            attempt_id=body.attempt_id,
            remaining_seconds=body.remaining_seconds,
        )
    except ExamError as exc:
        _raise(exc)


@router.post("/{exam_id}/resume")
def resume_exam(
    exam_id: str,
    body: ExamResumeRequest | None = None,
    user: CurrentUser = Depends(require_student),
):
    """Reopen the unfinished attempt — 404 when the client should start fresh."""
    try:
        return exam_pro.resume_attempt(
            user.uid,
            exam_id,
            attempt_id=(body.attempt_id if body else None) or None,
        )
    except ExamError as exc:
        _raise(exc)


@router.post("/{exam_id}/share")
def share_exam(
    exam_id: str,
    body: ExamShareRequest,
    user: CurrentUser = Depends(require_student),
):
    """Spec 6.10 — turn a paper's share link on or off (never the marks)."""
    try:
        return exam_pro.set_visibility(user.uid, exam_id, share=body.share)
    except ExamError as exc:
        _raise(exc)
