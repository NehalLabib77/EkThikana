# Phase 3B — AI Study Intelligence endpoints.
#
# Assignment Assistant, Quiz Generator, Revision Assistant, Smart Study Planner.
# All reuse the existing AI service cascade (GROQ → Gemini → OpenRouter) and
# the existing quota system. No new AI infrastructure is created.

import json
import logging
import time
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
from app.services import storage_provider
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


class AssignmentExplainRequest(_CamelModel):
    title: str = Field(..., min_length=1, max_length=500)
    description: str = Field(default="", max_length=5000)
    instructions: str = Field(default="", max_length=5000)
    source_text: str = Field(default="", max_length=10000)
    material_id: str | None = Field(default=None, max_length=120)
    note_id: str | None = Field(default=None, max_length=120)


class AssignmentBreakdownRequest(_CamelModel):
    title: str = Field(..., min_length=1, max_length=500)
    description: str = Field(default="", max_length=5000)
    instructions: str = Field(default="", max_length=5000)
    deadline: str | None = Field(default=None, max_length=30)
    source_text: str = Field(default="", max_length=10000)
    material_id: str | None = Field(default=None, max_length=120)
    note_id: str | None = Field(default=None, max_length=120)


class AssignmentPlanRequest(_CamelModel):
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

class QuizGenerateRequest(_CamelModel):
    source: str = Field(default="", max_length=5000)
    source_ids: list[str] = Field(default_factory=list, max_length=3)
    topic: str = Field(default="", max_length=500)
    question_count: int = Field(default=5, ge=1, le=20)
    difficulty: str = Field(default="medium", pattern=r"^(easy|medium|hard)$")
    question_type: str = Field(default="mcq", pattern=r"^(mcq|short_answer|mixed)$")


def _extract_material_text(user: CurrentUser, material_id: str) -> str:
    """Extract text content from a material (PDF, DOC, DOCX, TXT).

    Supported: PDF, DOC, DOCX, TXT. Images are not supported.
    """
    try:
        material = get_material_for_user(material_id, user)
    except HTTPException:
        return ""

    mime = (material.get("mimeType") or "").lower()
    name = (material.get("fileName") or "").lower()

    # PDF
    if "pdf" in mime or name.endswith(".pdf"):
        try:
            raw = _material_bytes(material)
            return extract_pdf_text(raw, max_pages=10)[:8000]
        except Exception:
            return ""

    # DOC / DOCX / TXT — read as text
    try:
        raw = _material_bytes(material)
        return raw.decode("utf-8", errors="ignore")[:8000]
    except Exception:
        return ""


def _extract_note_text(user: CurrentUser, note_id: str) -> str:
    """Extract text content from a note."""
    try:
        note = get_note_for_user(note_id, user)
        return note.get("content", "")[:10000]
    except HTTPException:
        return ""


@router.post("/quiz/generate")
async def quiz_generate(
    body: QuizGenerateRequest,
    user: CurrentUser = Depends(require_student),
):
    """Generate a quiz from notes, materials, or topics.

    Uses the existing QUIZ quota (3/month).
    Supports source material IDs for content-based quiz generation.
    """
    t0 = time.monotonic()
    logger.info(
        "Quiz generate: source_ids=%d has_source_text=%d topic=%s",
        len(body.source_ids), len(body.source), bool(body.topic),
    )

    # Build source content from material IDs
    source_parts = []
    MAX_PER_SOURCE = 5000  # chars per material/note
    MAX_TOTAL_SOURCE = 15000  # chars total for all sources combined

    # Extract content from selected materials
    for mid in body.source_ids:
        if mid.startswith("note_"):
            text = _extract_note_text(user, mid[5:])
            if text.strip():
                source_parts.append(f"[Note]:\n{text[:MAX_PER_SOURCE]}")
        else:
            text = _extract_material_text(user, mid)
            if text.strip():
                source_parts.append(f"[Material]:\n{text[:MAX_PER_SOURCE]}")

    # Add manually entered source text
    if body.source.strip():
        source_parts.append(body.source[:MAX_PER_SOURCE])

    combined_source = "\n\n".join(source_parts)
    # Truncate total to protect AI call
    combined_source = combined_source[:MAX_TOTAL_SOURCE]

    t_extract = time.monotonic()
    logger.info(
        "Material extraction completed: %.2f seconds, %d chars",
        t_extract - t0, len(combined_source),
    )

    if not combined_source.strip():
        return {
            "quiz": [],
            "raw": "",
            "error": "No source material provided. Please select materials or enter source text.",
        }

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
        "IMPORTANT: Generate questions ONLY based on the provided source material.\n"
        "Do NOT use external knowledge.\n\n"
    )

    if body.topic:
        prompt += f"TOPIC: {body.topic}\n\n"

    prompt += (
        f"SOURCE MATERIAL:\n{combined_source}\n\n"
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

    try:
        result = await _call_generate(user.uid, prompt, feature=AiFeature.QUIZ)
    except Exception as exc:
        logger.warning("Quiz AI call failed: %s", exc)
        return {
            "quiz": [],
            "raw": "",
            "error": "Source material is too large. Please reduce file size or select fewer materials.",
        }

    t_ai = time.monotonic()
    logger.info("AI generation completed: %.2f seconds", t_ai - t_extract)

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
# Smart Study Planner AI
# ---------------------------------------------------------------------------

class SmartPlannerRecommendRequest(_CamelModel):
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

# ---------------------------------------------------------------------------
# Quiz Results Persistence
# ---------------------------------------------------------------------------

class QuizResultRequest(_CamelModel):
    subject_id: str | None = Field(default=None, max_length=120)
    material_id: str | None = Field(default=None, max_length=120)
    questions: list[dict[str, Any]] = Field(..., min_length=1, max_length=50)
    user_answers: list[str] = Field(..., min_length=1, max_length=50)
    correct_answers: list[str] = Field(..., min_length=1, max_length=50)
    score: int = Field(..., ge=0, le=100)
    topic_scores: dict[str, int] = Field(default_factory=dict)
    difficulty: str = Field(default="medium", max_length=20)
    time_spent_seconds: int = Field(default=0, ge=0, le=86400)


@router.post("/quiz/save-result")
async def quiz_save_result(
    body: QuizResultRequest,
    user: CurrentUser = Depends(require_student),
):
    """Persist a completed quiz result to the user's Firestore subcollection.

    Stores: questions, user answers, correct answers, score, topic breakdown,
    difficulty, and time spent. Only the owner can write their own results.
    """
    db = get_firestore()
    if db is None:
        raise HTTPException(status_code=503, detail="Firestore unavailable")

    total = len(body.questions)
    correct_count = sum(
        1 for i, qa in enumerate(body.user_answers)
        if i < len(body.correct_answers) and qa.strip().lower() == body.correct_answers[i].strip().lower()
    )

    doc_ref = (
        db.collection("users")
        .document(user.uid)
        .collection("quiz_results")
        .document()
    )

    now = datetime.now(timezone.utc)
    result_data = {
        "ownerId": user.uid,
        "subjectId": body.subject_id or "",
        "materialId": body.material_id or "",
        "questions": body.questions,
        "userAnswers": body.user_answers,
        "correctAnswers": body.correct_answers,
        "totalQuestions": total,
        "correctCount": correct_count,
        "score": body.score,
        "topicScores": body.topic_scores,
        "difficulty": body.difficulty,
        "timeSpentSeconds": body.time_spent_seconds,
        "createdAt": now,
        "dayKey": now.strftime("%Y-%m-%d"),
        "monthKey": now.strftime("%Y-%m"),
    }

    doc_ref.set(result_data)

    logger.info(
        "Quiz result saved: uid=%s score=%d/%d difficulty=%s",
        user.uid, correct_count, total, body.difficulty,
    )

    return {
        "quizId": doc_ref.id,
        "score": body.score,
        "correctCount": correct_count,
        "totalQuestions": total,
    }


@router.get("/quiz/history")
async def quiz_history(
    limit: int = 20,
    user: CurrentUser = Depends(require_student),
):
    """Fetch the user's quiz history, newest first.

    Returns quiz results with scores and topic breakdowns for
    learning progress tracking.
    """
    db = get_firestore()
    if db is None:
        raise HTTPException(status_code=503, detail="Firestore unavailable")

    docs = (
        db.collection("users")
        .document(user.uid)
        .collection("quiz_results")
        .order_by("createdAt", direction="DESCENDING")
        .limit(min(limit, 100))
        .stream()
    )

    results = []
    for snap in docs:
        data = snap.to_dict() or {}
        results.append({
            "quizId": snap.id,
            "subjectId": data.get("subjectId", ""),
            "materialId": data.get("materialId", ""),
            "totalQuestions": data.get("totalQuestions", 0),
            "correctCount": data.get("correctCount", 0),
            "score": data.get("score", 0),
            "topicScores": data.get("topicScores", {}),
            "difficulty": data.get("difficulty", "medium"),
            "timeSpentSeconds": data.get("timeSpentSeconds", 0),
            "createdAt": data.get("createdAt"),
            "dayKey": data.get("dayKey", ""),
        })

    return {"results": results, "count": len(results)}


@router.get("/quiz/history/{quiz_id}")
async def quiz_history_detail(
    quiz_id: str,
    user: CurrentUser = Depends(require_student),
):
    """Fetch a single quiz result with full question details."""
    db = get_firestore()
    if db is None:
        raise HTTPException(status_code=503, detail="Firestore unavailable")

    doc = (
        db.collection("users")
        .document(user.uid)
        .collection("quiz_results")
        .document(quiz_id)
        .get()
    )

    if not doc.exists:
        raise HTTPException(status_code=404, detail="Quiz result not found")

    data = doc.to_dict() or {}
    return {
        "quizId": doc.id,
        "ownerId": data.get("ownerId", ""),
        "subjectId": data.get("subjectId", ""),
        "materialId": data.get("materialId", ""),
        "questions": data.get("questions", []),
        "userAnswers": data.get("userAnswers", []),
        "correctAnswers": data.get("correctAnswers", []),
        "totalQuestions": data.get("totalQuestions", 0),
        "correctCount": data.get("correctCount", 0),
        "score": data.get("score", 0),
        "topicScores": data.get("topicScores", {}),
        "difficulty": data.get("difficulty", "medium"),
        "timeSpentSeconds": data.get("timeSpentSeconds", 0),
        "createdAt": data.get("createdAt"),
        "dayKey": data.get("dayKey", ""),
    }


# ---------------------------------------------------------------------------
# AI Context Builder — Enhanced context for all AI features
# ---------------------------------------------------------------------------

class ContextBuilderRequest(_CamelModel):
    context_type: str = Field(
        ...,
        min_length=1,
        max_length=50,
        pattern=r"^(assignment|quiz|planner)$",
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

    # Include notes for quiz context
    if body.context_type == "quiz":
        context["notes"] = _fetch_user_notes(user.uid, limit=5)

    if body.extra_context:
        context["extra"] = body.extra_context

    return context


# ---------------------------------------------------------------------------
# Phase 3C-2 — Learning Insights / Weak Topic Detection
# ---------------------------------------------------------------------------

@router.get("/learning/weak-topics")
async def learning_weak_topics(
    threshold: int = 60,
    user: CurrentUser = Depends(require_student),
):
    """Identify topics where the student needs improvement.

    Aggregates topicScores across quiz history and returns topics
    with average score below the threshold. Only the authenticated
    user's own quiz data is analyzed.
    """
    from app.services.weak_topic_service import get_weak_topics

    weak = get_weak_topics(user.uid, threshold=threshold)
    return {
        "weak_topics": weak,
        "count": len(weak),
        "threshold": threshold,
    }


@router.get("/learning/summary")
async def learning_summary(
    user: CurrentUser = Depends(require_student),
):
    """Get a summary of the user's learning performance.

    Returns overall stats: total quizzes, average score, topic counts,
    strong topics, and weak topics.
    """
    from app.services.weak_topic_service import get_learning_summary

    summary = get_learning_summary(user.uid)
    return summary


# ---------------------------------------------------------------------------
# Phase 3C-3 — AI Study Recommendation
# ---------------------------------------------------------------------------

@router.get("/learning/recommendations")
async def learning_recommendations(
    user: CurrentUser = Depends(require_student),
):
    """Get personalized AI study recommendations.

    Analyzes weak topics, tasks, assignments, and recent quiz performance
    to generate actionable study recommendations. Results are cached
    daily to minimize AI quota usage.
    """
    from app.services.ai_recommendation_service import generate_study_recommendation

    result = await generate_study_recommendation(user.uid)
    return result


# ---------------------------------------------------------------------------
# Phase 4-1 — AI Recommendation Feedback
# ---------------------------------------------------------------------------

ALLOWED_FEATURES = {"study_recommendation"}
ALLOWED_FEEDBACK = {"helpful", "not_helpful"}


class AiFeedbackRequest(_CamelModel):
    feature: str = Field(..., min_length=1, max_length=50)
    recommendation_id: str = Field(default="", max_length=200)
    feedback: str = Field(..., pattern=r"^(helpful|not_helpful)$")


@router.post("/feedback")
async def submit_feedback(
    body: AiFeedbackRequest,
    user: CurrentUser = Depends(require_student),
):
    """Submit feedback on an AI recommendation.

    Stores feedback in the user's ai_feedback subcollection.
    Only the authenticated user can create their own feedback.
    Duplicate feedback on the same recommendation is prevented.
    """
    if body.feature not in ALLOWED_FEATURES:
        raise HTTPException(
            status_code=400,
            detail=f"Feature '{body.feature}' is not allowed. Allowed: {sorted(ALLOWED_FEATURES)}",
        )

    db = get_firestore()
    if db is None:
        raise HTTPException(status_code=503, detail="Firestore unavailable")

    # Check for duplicate feedback on same recommendation
    existing = (
        db.collection("users")
        .document(user.uid)
        .collection("ai_feedback")
        .where("feature", "==", body.feature)
        .where("recommendationId", "==", body.recommendation_id)
        .limit(1)
        .stream()
    )
    for snap in existing:
        if snap.exists:
            return {
                "status": "already_submitted",
                "message": "Feedback already submitted for this recommendation.",
            }

    # Create feedback document
    doc_ref = (
        db.collection("users")
        .document(user.uid)
        .collection("ai_feedback")
        .document()
    )

    now = datetime.now(timezone.utc)
    doc_ref.set({
        "ownerId": user.uid,
        "feature": body.feature,
        "recommendationId": body.recommendation_id,
        "feedback": body.feedback,
        "createdAt": now,
        "dayKey": now.strftime("%Y-%m-%d"),
    })

    logger.info(
        "AI feedback submitted: uid=%s feature=%s feedback=%s",
        user.uid, body.feature, body.feedback,
    )

    return {
        "status": "submitted",
        "feedbackId": doc_ref.id,
    }
