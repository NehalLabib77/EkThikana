"""Phase 10 - Ziku AI Content Generation Studio.

One orchestration layer owns generated explanations, flashcards, revision
sheets and study packs. Source extraction stays in ``ai_study`` and quiz
generation stays in its existing route; this service only composes them with
the student's Mistake Memory and Adaptive Learning context.
"""

from __future__ import annotations

import json
import logging
import uuid
from datetime import date, datetime, timedelta, timezone
from typing import Any

from app.core.firebase import get_firestore
from app.services import academic_health_service as health
from app.services import ai_service
from app.services import mistake_memory_service as mistakes
from app.services import ziku_adaptive_service as adaptive

logger = logging.getLogger("gochano.content")

CONTENT_COLLECTION = "ai_content"
MAX_SOURCE_CHARS = 16000


def _today() -> date:
    return datetime.now(timezone.utc).date()


def _text(value: Any, default: str = "") -> str:
    if value is None:
        return default
    return str(value).strip()


def _parse_json(raw: Any) -> dict[str, Any]:
    if isinstance(raw, dict):
        return raw
    text = _text(raw)
    if text.startswith("```"):
        text = text.split("\n", 1)[-1]
    if text.endswith("```"):
        text = text[:-3].rstrip()
    try:
        value = json.loads(text)
    except (TypeError, ValueError, json.JSONDecodeError):
        return {}
    return value if isinstance(value, dict) else {}


def _topic_mistakes(uid: str, topic: str = "") -> list[dict[str, Any]]:
    rows = mistakes.get_review_queue(uid, limit=20)
    if topic.strip():
        wanted = topic.casefold()
        matching = [row for row in rows if wanted in _text(row.get("topic")).casefold()]
        if matching:
            return matching[:6]
    return rows[:6]


def _mistake_context(uid: str, topic: str = "") -> str:
    rows = _topic_mistakes(uid, topic)
    if not rows:
        return "No recorded mistakes are available."
    lines = []
    for row in rows:
        analysis = row.get("analysis") or {}
        reason = analysis.get("conceptGap") or analysis.get("mistakeReason") or "not analysed yet"
        lines.append(
            f"- {_text(row.get('topic'), 'General')}: {_text(reason)}; "
            f"{int(row.get('occurrences') or 1)} occurrence(s)"
        )
    return "\n".join(lines)


def _adaptive_context(uid: str) -> str:
    try:
        items = adaptive.get_curriculum(uid).get("items") or []
        return "\n".join(
            f"- {_text(item.get('topic'))}: {_text(item.get('reason'))}"
            for item in items[:5]
        ) or "No adaptive plan is available."
    except Exception as exc:  # pragma: no cover
        logger.debug("content adaptive context unavailable: %s", exc)
        return "No adaptive plan is available."


def _exam_context(uid: str) -> str:
    try:
        exam = health.collect_signals(uid).get("exam") or {}
        if exam.get("examDate"):
            return f"{_text(exam.get('title'), 'Upcoming exam')} on {_text(exam.get('examDate'))}"
    except Exception as exc:  # pragma: no cover
        logger.debug("content exam context unavailable: %s", exc)
    return "No upcoming exam is recorded."


def _save(uid: str, content_type: str, topic: str, source: str, payload: dict[str, Any]) -> dict[str, Any]:
    content_id = f"content_{uuid.uuid4().hex}"
    document = {
        "studentId": uid,
        "type": content_type,
        "topic": topic[:200],
        "sourceMaterial": source[:200],
        "generatedContent": payload,
        "createdAt": datetime.now(timezone.utc),
        "reviewStatus": "new",
    }
    db = get_firestore()
    if db is not None:
        try:
            db.collection(CONTENT_COLLECTION).document(content_id).set(document)
        except Exception as exc:  # pragma: no cover
            logger.warning("Could not persist generated content: %s", exc)
            from app.services.analytics_service import track_event

            track_event(uid, "content_generated", {"topic": topic, "content_type": content_type, "source": "ai_content"})
    return {"id": content_id, **document}


async def _generate(uid: str, prompt: str) -> dict[str, Any]:
    try:
        raw = await ai_service.generate(uid, prompt, feature=ai_service.AiFeature.CONTENT)
        return _parse_json(raw)
    except Exception as exc:  # provider/quota failure: caller uses fallback
        logger.info("content generation fallback: %s", exc)
        return {}


def _explanation_fallback(topic: str, mistakes_text: str) -> dict[str, Any]:
    return {
        "simpleExplanation": f"{topic} is a concept you can understand by defining its main parts and linking them step by step.",
        "analogy": f"Think of {topic} as a familiar process with a clear cause and effect.",
        "formula": "Review the relevant formula from your course notes before substituting values.",
        "example": f"Work through one basic {topic} example, naming the rule used at every step.",
        "commonMistakes": [mistakes_text.splitlines()[0] if mistakes_text else "Skipping the definition before solving."],
        "practiceQuestion": f"Explain {topic} in your own words and solve one new example.",
        "source": "deterministic",
    }


async def generate_explanation(uid: str, *, topic: str, level: str, learning_style: str, source: str = "") -> dict[str, Any]:
    mistakes_text = _mistake_context(uid, topic)
    prompt = (
        "You are Ziku, a patient personal teacher. Return ONLY valid JSON with keys "
        "simpleExplanation, analogy, formula, example, commonMistakes (array), practiceQuestion.\n"
        f"TOPIC: {topic}\nSTUDENT LEVEL: {level}\nLEARNING STYLE: {learning_style}\n"
        f"PREVIOUS MISTAKES:\n{mistakes_text}\nSOURCE:\n{source[:MAX_SOURCE_CHARS]}\n"
        "Personalize the explanation around the student's actual mistakes. Do not invent facts beyond the source when a source is supplied."
    )
    payload = await _generate(uid, prompt)
    if not payload or not payload.get("simpleExplanation"):
        payload = _explanation_fallback(topic, mistakes_text)
    payload.setdefault("source", "ai")
    ai_service.record_ai_activity(uid, "content_explanations")
    return _save(uid, "explanation", topic, source, payload)


def _flashcard_fallback(topic: str, source: str) -> list[dict[str, Any]]:
    return [
        {"question": f"What is the central idea of {topic}?", "answer": f"State the definition of {topic} and its key condition.", "difficulty": "easy"},
        {"question": f"Why does {topic} matter?", "answer": f"Connect {topic} to one worked example from your notes.", "difficulty": "medium"},
        {"question": f"What common mistake should you avoid in {topic}?", "answer": "Check the direction, units and assumptions before finalising an answer.", "difficulty": "medium"},
    ]


async def generate_flashcards(uid: str, *, topic: str, source: str, count: int = 10) -> dict[str, Any]:
    prompt = (
        "Create flashcards from the supplied study material. Return ONLY JSON: "
        '{"flashcards":[{"question":"...","answer":"...","difficulty":"easy|medium|hard"}]}.'
        f"\nTOPIC: {topic}\nMISTAKES:\n{_mistake_context(uid, topic)}\nMATERIAL:\n{source[:MAX_SOURCE_CHARS]}"
    )
    payload = await _generate(uid, prompt)
    cards = payload.get("flashcards") if isinstance(payload.get("flashcards"), list) else []
    if not cards:
        cards = _flashcard_fallback(topic, source)
    review_date = (mistakes.review_due_date(0, _today()))
    cards = [
        {**card, "topic": topic, "reviewDate": review_date}
        for card in cards[: max(1, min(count, 30))]
        if isinstance(card, dict)
    ]
    ai_service.record_ai_activity(uid, "content_flashcards")
    return _save(uid, "flashcards", topic, source, {"flashcards": cards, "count": len(cards)})


def _revision_fallback(uid: str, topic: str) -> dict[str, Any]:
    queue = adaptive.get_revision_queue(uid).get("items") or []
    weak = [item.get("topic") for item in queue[:5]]
    return {
        "title": f"{_exam_context(uid)} Revision Sheet",
        "importantFormulas": [f"Review the core formulas for {topic or 'your weak topics'}."],
        "confusedConcepts": weak or [topic or "Your lowest-scoring topics"],
        "yourMistakes": _topic_mistakes(uid, topic)[:5],
        "lastMinuteChecklist": ["Define the concept", "Check units and signs", "Attempt one timed question"],
        "practiceQuestions": [f"Solve one exam-style question on {topic or 'your weakest topic'}."],
        "source": "deterministic",
    }


async def generate_revision_sheet(uid: str, *, topic: str = "", source: str = "") -> dict[str, Any]:
    fallback = _revision_fallback(uid, topic)
    prompt = (
        "Create a concise before-exam revision sheet. Return ONLY JSON with keys "
        "title, importantFormulas, confusedConcepts, yourMistakes, lastMinuteChecklist, practiceQuestions.\n"
        f"EXAM: {_exam_context(uid)}\nADAPTIVE PLAN:\n{_adaptive_context(uid)}\n"
        f"MISTAKES:\n{_mistake_context(uid, topic)}\nSOURCE:\n{source[:MAX_SOURCE_CHARS]}"
    )
    payload = await _generate(uid, prompt) or fallback
    payload.setdefault("source", "ai")
    ai_service.record_ai_activity(uid, "content_revision_sheets")
    return _save(uid, "revision_sheet", topic, source, payload)


async def generate_study_pack(uid: str, *, topic: str, source: str, question_count: int = 5) -> dict[str, Any]:
    prompt = (
        "Create a complete study pack summary from this material. Return ONLY JSON with keys "
        "summary and importantTopics (array). Do not create quiz questions in this response.\n"
        f"TOPIC: {topic}\nADAPTIVE CONTEXT:\n{_adaptive_context(uid)}\nMATERIAL:\n{source[:MAX_SOURCE_CHARS]}"
    )
    generated = await _generate(uid, prompt)
    summary = generated or {
        "summary": f"Review the main definitions, examples and mistakes in {topic or 'this material'}.",
        "importantTopics": [topic] if topic else ["Key concepts from the supplied material"],
        "source": "deterministic",
    }
    quiz: list[dict[str, Any]] = []
    try:
        from app.routers.ai_study import QuizGenerateRequest, quiz_generate
        from app.core.auth import CurrentUser

        # The existing quiz generator remains the only quiz-generation path.
        quiz_result = await quiz_generate(
            QuizGenerateRequest(source=source[:MAX_SOURCE_CHARS], topic=topic, question_count=question_count),
            CurrentUser(uid=uid, email="", role="student"),
        )
        quiz = quiz_result.get("quiz") or []
    except Exception as exc:  # pragma: no cover
        logger.info("study pack quiz fallback: %s", exc)
    cards = await generate_flashcards(uid, topic=topic, source=source, count=min(10, question_count * 2))
    revision = await generate_revision_sheet(uid, topic=topic, source=source)
    pack = {"summary": summary, "quiz": quiz, "flashcards": cards["generatedContent"], "revisionSheet": revision["generatedContent"], "source": summary.get("source", "ai")}
    ai_service.record_ai_activity(uid, "content_study_packs")
    return _save(uid, "study_pack", topic, source, pack)


def chat_context(uid: str) -> str | None:
    """One grounded teacher cue for the existing Ziku chat prompt."""
    rows = _topic_mistakes(uid)
    if not rows:
        return None
    top = rows[0]
    topic = _text(top.get("topic"), "this topic")
    occurrences = int(top.get("occurrences") or 1)
    reason = _text((top.get("analysis") or {}).get("conceptGap"), "a repeated concept gap")
    return (
        f"The student has made {occurrences} mistake(s) in {topic}; "
        f"teach the underlying idea before harder practice ({reason})."
    )