from typing import Literal

from pydantic import BaseModel, Field


class GroupCreate(BaseModel):
    name: str = Field(min_length=2, max_length=80)
    description: str = Field(default="", max_length=240)


class GroupJoin(BaseModel):
    invite_code: str = Field(min_length=4, max_length=20)


class AiNoteRequest(BaseModel):
    action: Literal["cleanup", "summary", "explain", "key_topics"]
    text: str = Field(min_length=1, max_length=50000)


class PdfQuestionRequest(BaseModel):
    material_id: str
    question: str = Field(min_length=2, max_length=1000)
    page: int | None = Field(default=None, ge=1)


class StudyPlanRequest(BaseModel):
    max_items: int = Field(default=8, ge=1, le=20)


class ReportRequest(BaseModel):
    target_type: Literal["material", "note"]
    target_id: str = Field(min_length=1, max_length=200)
    reason: Literal["spam", "copyright", "inappropriate", "misleading", "other"]
    details: str = Field(default="", max_length=1000)
