"""Phase 10 - Ziku AI Content Generation Studio endpoints."""

from __future__ import annotations

from fastapi import APIRouter, Depends
from pydantic import Field

from app.core.auth import CurrentUser, require_student
from app.routers.ai_study import _extract_source_material_text
from app.schemas import _CamelModel
from app.services import ziku_content_service as content

router = APIRouter()


class ContentSourceRequest(_CamelModel):
    topic: str = Field(default="", max_length=200)
    source_text: str = Field(default="", max_length=10000)
    material_id: str | None = Field(default=None, max_length=120)
    note_id: str | None = Field(default=None, max_length=120)
    student_level: str = Field(default="university", max_length=80)
    learning_style: str = Field(default="clear examples", max_length=120)


class FlashcardRequest(ContentSourceRequest):
    count: int = Field(default=10, ge=1, le=30)


class StudyPackRequest(ContentSourceRequest):
    question_count: int = Field(default=5, ge=1, le=20)


async def _source(user: CurrentUser, body: ContentSourceRequest) -> str:
    return await _extract_source_material_text(
        user,
        source_text=body.source_text,
        material_id=body.material_id,
        note_id=body.note_id,
    )


@router.post("/explain")
async def explain(body: ContentSourceRequest, user: CurrentUser = Depends(require_student)):
    source = await _source(user, body)
    return await content.generate_explanation(
        user.uid,
        topic=body.topic or "the supplied topic",
        level=body.student_level,
        learning_style=body.learning_style,
        source=source,
    )


@router.post("/flashcards")
async def flashcards(body: FlashcardRequest, user: CurrentUser = Depends(require_student)):
    source = await _source(user, body)
    return await content.generate_flashcards(
        user.uid, topic=body.topic or "General", source=source, count=body.count
    )


@router.post("/revision-sheet")
async def revision_sheet(body: ContentSourceRequest, user: CurrentUser = Depends(require_student)):
    source = await _source(user, body)
    return await content.generate_revision_sheet(user.uid, topic=body.topic, source=source)


@router.post("/study-pack")
async def study_pack(body: StudyPackRequest, user: CurrentUser = Depends(require_student)):
    source = await _source(user, body)
    return await content.generate_study_pack(
        user.uid,
        topic=body.topic or "General",
        source=source,
        question_count=body.question_count,
    )