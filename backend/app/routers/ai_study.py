# Phase 3B — AI Study Intelligence endpoints.
#
# Assignment Assistant, Quiz Generator, Revision Assistant, Smart Study Planner.
# All reuse the existing AI service cascade (GROQ → Gemini → OpenRouter) and
# the existing quota system. No new AI infrastructure is created.

import json
import logging
from datetime import datetime, timezone
from typing import Any

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from app.core.auth import CurrentUser, require_student
from app.core.config import get_settings
from app.core.firebase import get_firestore
from app.schemas import _CamelModel
from app.services.ai_service import (
    AiFeature,
    generate,
    get_ai_usage,
)
from app.services.pdf_service import extract_pdf_text
from app.services.ocr_service import extract_text as ocr_extract_text
from app.services.permission_service import get_material_for_user, get_note_for_user
from app.routers.ai import _material_bytes

logger = logging.getLogger("gochano.ai_study")

router = APIRouter()


# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

async def _call_generate(uid: str, prompt: str, feature: str = AiFeature.CHAT) -> str:
    """Route through the existing AI cascade. Returns the response text."""
    try:
        return await generate(uid, prompt, feature=feature)
    except TypeError:
        return await generate(uid, prompt)


def _fetch_user_tasks(uid: str, limit: int = 100) -> list[dict[str, Any]]:
    """Fetch user's undone tasks from Firestore for context building."""
    db = get_firestore()
    if db is None:
        return []

    tasks = []
    docs = (
        db.collection("tasks")
        .where("ownerId", "==", uid)
        .limit(limit)
        .stream()
    )
    for snap in docs:
        data = snap.to_dict() or {}
        if data.get("done") is True:
            continue
        tasks.append({
            "id": snap.id,
            "title": data.get("title", ""),
            "type": data.get("type", "task"),
            "dueAt": data.get("dueAt"),
            "subjectId": data.get("subjectId"),
        })
    return tasks


def _fetch_user_notes(uid: str, limit: int = 10) -> list[dict[str, Any]]:
    """Fetch user's recent notes from Firestore for context building."""
    db = get_firestore()
    if db is None:
        return []

    notes = []
    docs = (
        db.collection("notes")
        .where("ownerId", "==", uid)
        .order_by("createdAt", direction="DESCENDING")
        .limit(limit)
        .stream()
    )
    for snap in docs:
        data = snap.to_dict() or {}
        notes.append({
            "id": snap.id,
            "title": data.get("title", ""),
            "content": data.get("content", "")[:500],  # Truncate for context
        })
    return notes


def _fetch_user_assignments(uid: str, limit: int = 50) -> list[dict[str, Any]]:
    """Fetch user's assignments (tasks with type='assignment') from Firestore."""
    db = get_firestore()
    if db is None:
        return []

    assignments = []
    docs = (
        db.collection("tasks")
        .where("ownerId", "==", uid)
        .where("type", "==", "assignment")
        .limit(limit)
        .stream()
    )
    for snap in docs:
        data = snap.to_dict() or {}
        if data.get("done") is True:
            continue
        assignments.append({
            "id": snap.id,
            "title": data.get("title", ""),
            "dueAt": data.get("dueAt"),
            "subjectId": data.get("subjectId"),
        })
    return assignments


# ---------------------------------------------------------------------------
# Assignment Assistant & Source Material Extraction
# ---------------------------------------------------------------------------

async def _extract_source_material_text(
    user: CurrentUser,
    source_text: str = "",
    material_id: str | None = None,
    note_id: str | None = None,
) -> str:
    """Extract and ground context from an existing note, uploaded material, or raw text.
    
    Safe, permission-checked, and reuses existing B2/Firestore pipelines.
    Never duplicates file storage or leaks other users' data.
    """
    extracted_parts = []
    if source_text and source_text.strip():
        extracted_parts.append(source_text.strip())

    if note_id and note_id.strip():
        try:
            note_data = get_note_for_user(note_id.strip(), user)
            note_content = (note_data.get("content") or "").strip()
            note_title = (note_data.get("title") or "").strip()
            if note_content:
                header = f"NOTE [{note_title}]:\n" if note_title else "NOTE CONTENT:\n"
                extracted_parts.append(f"{header}{note_content}")
        except HTTPException:
            raise
        except Exception as e:
            logger.warning("Could not read note for context: note_id=%s error=%s", note_id, type(e).__name__)

    if material_id and material_id.strip():
        try:
            material = get_material_for_user(material_id.strip(), user)
            raw = _material_bytes(material)
            mime_type = (material.get("mimeType") or "").lower()
            file_name = (material.get("fileName") or "").lower()

            mat_text = ""
            if "pdf" in mime_type or file_name.endswith(".pdf"):
                try:
                    mat_text = extract_pdf_text(raw)
                except Exception:
                    mat_text = ""
                if len(mat_text.strip()) < 40:
                    try:
                        mat_text = ocr_extract_text(raw, mime_type or "application/pdf")
                    except Exception:
                        pass
            elif mime_type.startswith("text/") or file_name.endswith(".txt"):
                try:
                    mat_text = raw.decode("utf-8", errors="replace")
                except Exception:
                    mat_text = ""
            elif "wordprocessingml" in mime_type or file_name.endswith(".docx") or file_name.endswith(".doc"):
                # Extract text using OCR or fallback digital decode
                try:
                    mat_text = ocr_extract_text(raw, mime_type)
                except Exception:
                    mat_text = ""

            if mat_text and mat_text.strip():
                mat_title = material.get("title") or material.get("fileName") or "Document"
                extracted_parts.append(f"DOCUMENT [{mat_title}]:\n{mat_text.strip()[:6000]}")
        except HTTPException:
            raise
        except Exception as e:
            logger.warning("Could not read material for context: material_id=%s error=%s", material_id, type(e).__name__)

    return "\n\n".join(extracted_parts)


class AssignmentExplainRequest(BaseModel):
    title: str = Field(..., min_length=1, max_length=500)
    description: str = Field(default="", max_length=5000)
    instructions: str = Field(default="", max_length=5000)
    source_text: str = Field(default="", max_length=10000)
    material_id: str | None = Field(default=None, max_length=120)
    note_id: str | None = Field(default=None, max_length=120)


class AssignmentBreakdownRequest(BaseModel):
    title: str = Field(..., min_length=1, max_length=500)
    description: str = Field(default="", max_length=5000)
    instructions: str = Field(default="", max_length=5000)
    deadline: str | None = Field(default=None, max_length=30)
    source_text: str = Field(default="", max_length=10000)
    material_id: str | None = Field(default=None, max_length=120)
    note_id: str | None = Field(default=None, max_length=120)


class AssignmentPlanRequest(BaseModel):
    title: str = Field(..., min_length=1, max_length=500)
    description: str = Field(default="", max_length=5000)
    instructions: str = Field(default="", max_length=5000)
    deadline: str = Field(..., min_length=1, max_length=30)
    source_text: str = Field(default="", max_length=10000)
    material_id: str | None = Field(default=None, max_length=120)
    note_id: str | None = Field(default=None, max_length=120)


@router.post("/assignment/explain")
async def assignment_explain(
    body: AssignmentExplainRequest,
    user: CurrentUser = Depends(require_student),
):
    """Explain what an assignment requires in simple terms."""
    logger.info("Assignment explain request: title_chars=%d has_material=%s has_note=%s",
                len(body.title), bool(body.material_id), bool(body.note_id))

    source_context = await _extract_source_material_text(
        user,
        source_text=body.source_text,
        material_id=body.material_id,
        note_id=body.note_id,
    )

    prompt = (
        "You are a study assistant helping a university student understand an assignment.\n"
        "Provide a clear, concise explanation of:\n"
        "1. What the assignment is asking for (objective)\n"
        "2. The key concepts and skills needed\n"
        "3. What a good submission looks like\n\n"
        "Do NOT provide answers or write the assignment. Only explain what is needed.\n"
        "Keep the response under 300 words.\n\n"
        f"ASSIGNMENT TITLE:\n{body.title}\n\n"
    )
    if body.description:
        prompt += f"DESCRIPTION:\n{body.description}\n\n"
    if body.instructions:
        prompt += f"INSTRUCTIONS:\n{body.instructions}\n\n"
    if source_context:
        prompt += f"REFERENCE SOURCE MATERIAL:\n{source_context}\n\n"

    result = await _call_generate(user.uid, prompt, feature=AiFeature.CHAT)
    return {"explanation": result}


@router.post("/assignment/breakdown")
async def assignment_breakdown(
    body: AssignmentBreakdownRequest,
    user: CurrentUser = Depends(require_student),
):
    """Break down an assignment into required sections and concepts."""
    logger.info("Assignment breakdown request: title_chars=%d has_material=%s has_note=%s",
                len(body.title), bool(body.material_id), bool(body.note_id))

    source_context = await _extract_source_material_text(
        user,
        source_text=body.source_text,
        material_id=body.material_id,
        note_id=body.note_id,
    )

    prompt = (
        "You are a study assistant helping a university student plan their assignment.\n"
        "Break down the assignment into:\n"
        "1. Required sections/components (as a numbered list)\n"
        "2. Key concepts needed for each section\n"
        "3. Submission requirements\n"
        "4. Important points to remember\n\n"
        "Do NOT write the assignment content. Only outline the structure.\n"
        "Keep the response under 400 words.\n\n"
        f"ASSIGNMENT TITLE:\n{body.title}\n\n"
    )
    if body.description:
        prompt += f"DESCRIPTION:\n{body.description}\n\n"
    if body.instructions:
        prompt += f"INSTRUCTIONS:\n{body.instructions}\n\n"
    if body.deadline:
        prompt += f"DEADLINE: {body.deadline}\n\n"
    if source_context:
        prompt += f"REFERENCE SOURCE MATERIAL:\n{source_context}\n\n"

    result = await _call_generate(user.uid, prompt, feature=AiFeature.CHAT)
    return {"breakdown": result}


@router.post("/assignment/plan")
async def assignment_plan(
    body: AssignmentPlanRequest,
    user: CurrentUser = Depends(require_student),
):
    """Generate a deadline-aware study plan for an assignment."""
    logger.info("Assignment plan request: title_chars=%d deadline=%s has_material=%s has_note=%s",
                len(body.title), body.deadline, bool(body.material_id), bool(body.note_id))

    source_context = await _extract_source_material_text(
        user,
        source_text=body.source_text,
        material_id=body.material_id,
        note_id=body.note_id,
    )

    prompt = (
        "You are a study assistant helping a university student plan their assignment work.\n"
        "Create a day-by-day study plan from today until the deadline.\n"
        "For each day, specify:\n"
        "- What to work on\n"
        "- Estimated time needed\n"
        "- Tips for that day's work\n\n"
        "Be realistic about daily study time (2-4 hours per day).\n"
        "Include rest days if the deadline allows.\n"
        "Keep the response under 500 words.\n\n"
        f"ASSIGNMENT TITLE:\n{body.title}\n\n"
    )
    if body.description:
        prompt += f"DESCRIPTION:\n{body.description}\n\n"
    if body.instructions:
        prompt += f"INSTRUCTIONS:\n{body.instructions}\n\n"
    prompt += f"DEADLINE: {body.deadline}\n\n"
    if source_context:
        prompt += f"REFERENCE SOURCE MATERIAL:\n{source_context}\n\n"

    result = await _call_generate(user.uid, prompt, feature=AiFeature.CHAT)
    return {"plan": result}


# ---------------------------------------------------------------------------
# Quiz Generator
# ---------------------------------------------------------------------------

class QuizGenerateRequest(BaseModel):
    source: str = Field(..., min_length=1, max_length=500)
    topic: str = Field(default="", max_length=500)
    question_count: int = Field(default=5, ge=1, le=20)
    difficulty: str = Field(default="medium", pattern=r"^(easy|medium|hard)$")
    question_type: str = Field(default="mcq", pattern=r"^(mcq|short_answer|mixed)$")


@router.post("/quiz/generate")
async def quiz_generate(
    body: QuizGenerateRequest,
    user: CurrentUser = Depends(require_student),
):
    """Generate a quiz from notes, materials, or topics.

    Uses the existing QUIZ quota (3/month).
    """
    difficulty_map = {
        "easy": "basic recall and understanding",
        "medium": "application and analysis",
        "hard": "synthesis, evaluation, and complex problem-solving",
    }
    difficulty_desc = difficulty_map.get(body.difficulty, "medium")

    type_map = {
        "mcq": "Multiple choice questions (4 options each, one correct)",
        "short_answer": "Short answer questions (1-3 sentence answers)",
        "mixed": "A mix of multiple choice and short answer questions",
    }
    type_desc = type_map.get(body.question_type, "mcq")

    prompt = (
        "You are a quiz generator for university students.\n"
        f"Generate {body.question_count} {type_desc} questions.\n"
        f"Difficulty level: {difficulty_desc}.\n\n"
    )

    if body.topic:
        prompt += f"TOPIC: {body.topic}\n\n"

    prompt += (
        f"SOURCE MATERIAL:\n{body.source}\n\n"
        "For each question, provide:\n"
        "- The question\n"
        "- For MCQ: 4 options (A, B, C, D) with the correct answer marked\n"
        "- For short answer: a model answer (2-3 sentences)\n"
        "- A brief explanation of why the answer is correct\n\n"
        "Format your response as JSON with this structure:\n"
        "{\n"
        '  "questions": [\n'
        "    {\n"
        '      "question": "...",\n'
        '      "type": "mcq" or "short_answer",\n'
        '      "options": ["A", "B", "C", "D"],  // only for mcq\n'
        '      "correct": "A",  // the correct option letter or short answer\n'
        '      "explanation": "..."\n'
        "    }\n"
        "  ]\n"
        "}\n\n"
        "IMPORTANT: Return ONLY valid JSON. No additional text before or after."
    )

    result = await _call_generate(user.uid, prompt, feature=AiFeature.QUIZ)

    # Try to parse as JSON; if parsing fails, return as plain text
    try:
        # Strip markdown code fences if present
        cleaned = result.strip()
        if cleaned.startswith("```"):
            cleaned = cleaned.split("\n", 1)[-1]
            if cleaned.endswith("```"):
                cleaned = cleaned[:-3]
        parsed = json.loads(cleaned)
        return {"quiz": parsed.get("questions", []), "raw": result}
    except (json.JSONDecodeError, KeyError):
        return {"quiz": [], "raw": result}


# ---------------------------------------------------------------------------
# Revision Assistant
# ---------------------------------------------------------------------------

class RevisionPlanRequest(BaseModel):
    subject: str = Field(..., min_length=1, max_length=200)
    exam_date: str = Field(..., min_length=1, max_length=30)
    topics: list[str] = Field(default_factory=list, max_length=20)
    notes_summary: str = Field(default="", max_length=5000)


@router.post("/revision/plan")
async def revision_plan(
    body: RevisionPlanRequest,
    user: CurrentUser = Depends(require_student),
):
    """Generate a revision checklist and schedule for exam preparation."""
    topics_text = "\n".join(f"- {t}" for t in body.topics) if body.topics else "Not specified"

    prompt = (
        "You are a study assistant helping a university student prepare for an exam.\n"
        "Create a comprehensive revision plan.\n\n"
        f"SUBJECT: {body.subject}\n"
        f"EXAM DATE: {body.exam_date}\n"
        f"TOPICS TO COVER:\n{topics_text}\n\n"
    )
    if body.notes_summary:
        prompt += f"NOTES SUMMARY:\n{body.notes_summary}\n\n"

    prompt += (
        "Provide:\n"
        "1. A revision checklist (all topics that need review)\n"
        "2. Priority ranking (most important topics first)\n"
        "3. Day-by-day revision schedule from now until the exam\n"
        "4. Suggested review order (what to study when)\n"
        "5. Tips for effective revision of this subject\n\n"
        "Be realistic about daily study time (3-5 hours per day).\n"
        "Include practice questions in the last 2-3 days.\n"
        "Keep the response under 600 words.\n"
    )

    result = await _call_generate(user.uid, prompt, feature=AiFeature.CHAT)
    return {"revision_plan": result}


# ---------------------------------------------------------------------------
# Smart Study Planner AI
# ---------------------------------------------------------------------------

class SmartPlannerRecommendRequest(BaseModel):
    available_hours: int = Field(default=4, ge=1, le=12)
    preferred_subjects: list[str] = Field(default_factory=list, max_length=10)


@router.post("/planner/recommend")
async def smart_planner_recommend(
    body: SmartPlannerRecommendRequest,
    user: CurrentUser = Depends(require_student),
):
    """AI-powered daily study recommendations.

    Uses the user's tasks, assignments, and deadlines to generate
    personalized study recommendations for today.
    """
    # Build context from user's data
    tasks = _fetch_user_tasks(user.uid)
    assignments = _fetch_user_assignments(user.uid)

    if not tasks and not assignments:
        return {
            "recommendation": "No tasks or assignments found. Add some tasks with due dates to get AI-powered study recommendations.",
            "items": [],
        }

    # Format tasks for the prompt
    task_lines = []
    now = datetime.now(timezone.utc)

    for t in tasks:
        due = t.get("dueAt")
        due_str = ""
        if due:
            if hasattr(due, "to_datetime"):
                due = due.to_datetime()
            if isinstance(due, datetime):
                if due.tzinfo is None:
                    due = due.replace(tzinfo=timezone.utc)
                days_until = (due - now).days
                if days_until < 0:
                    due_str = " [OVERDUE]"
                elif days_until == 0:
                    due_str = " [DUE TODAY]"
                elif days_until == 1:
                    due_str = " [DUE TOMORROW]"
                else:
                    due_str = f" [DUE IN {days_until} DAYS]"
        task_lines.append(f"- {t['title']}{due_str}")

    task_list = "\n".join(task_lines) if task_lines else "No active tasks"

    prompt = (
        "You are a smart study planner for a university student.\n"
        f"The student has {body.available_hours} hours available today.\n\n"
        f"TODAY'S TASKS AND ASSIGNMENTS:\n{task_list}\n\n"
    )

    if body.preferred_subjects:
        prompt += f"PREFERRED SUBJECTS: {', '.join(body.preferred_subjects)}\n\n"

    prompt += (
        "Create a daily study recommendation:\n"
        "1. Prioritized task list (what to do first, second, etc.)\n"
        "2. Time allocation for each task\n"
        "3. Specific tips for each task\n"
        "4. A suggested study schedule with breaks\n\n"
        "Focus on:\n"
        "- Overdue tasks first\n"
        "- Tasks due today or tomorrow\n"
        "- Important assignments with approaching deadlines\n\n"
        "Keep the response under 400 words.\n"
    )

    result = await _call_generate(user.uid, prompt, feature=AiFeature.CHAT)
    return {"recommendation": result}


# ---------------------------------------------------------------------------
# AI Context Builder — Enhanced context for all AI features
# ---------------------------------------------------------------------------

class ContextBuilderRequest(BaseModel):
    context_type: str = Field(
        ...,
        min_length=1,
        max_length=50,
        pattern=r"^(assignment|quiz|revision|planner)$",
    )
    extra_context: str = Field(default="", max_length=5000)


@router.post("/context")
async def build_context(
    body: ContextBuilderRequest,
    user: CurrentUser = Depends(require_student),
):
    """Build enhanced AI context from the user's study data.

    Safely fetches only the user's own data. Never includes passwords,
    tokens, or other users' data.
    """
    context: dict[str, Any] = {
        "context_type": body.context_type,
        "generated_at": datetime.now(timezone.utc).isoformat(),
    }

    # Always include tasks and assignments for study-related context
    context["tasks"] = _fetch_user_tasks(user.uid, limit=20)
    context["assignments"] = _fetch_user_assignments(user.uid, limit=10)

    # Include notes for quiz/revision context
    if body.context_type in ("quiz", "revision"):
        context["notes"] = _fetch_user_notes(user.uid, limit=5)

    if body.extra_context:
        context["extra"] = body.extra_context

    return context
