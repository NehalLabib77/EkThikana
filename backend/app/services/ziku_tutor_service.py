"""Phase 12 — Ziku Socratic AI Tutor Service.

Transform Ziku from an explanatory chatbot into an interactive, personalized Socratic tutor.
Orchestrates over existing systems:
  - Mistake Memory
  - Learning Memory
  - Adaptive Learning
  - Academic Health
  - Study Coach
  - Analytics Foundation
  - Quiz / Exam simulator
"""

from __future__ import annotations

import json
import logging
import re
from datetime import datetime, timezone
from typing import Any
from uuid import uuid4

from fastapi import HTTPException

from app.core import firebase
from app.services import academic_health_service as health
from app.services import ai_service
from app.services import analytics_service as analytics
from app.services import learning_memory_service as memory
from app.services import mistake_memory_service as mistakes

logger = logging.getLogger("gochano.tutor")

TUTOR_COLLECTION = "tutor_sessions"
VALID_MODES = {"socratic", "explain", "practice", "exam_prep"}

DIRECT_ANSWER_PATTERNS = [
    r"answer.*বলে দাও",
    r"উত্তর.*বলে দাও",
    r"just explain",
    r"explain it to me",
    r"explain directly",
    r"i don't want questions",
    r"don't ask me questions",
    r"just tell me",
    r"tell me the answer",
    r"give me the answer",
    r"direct answer",
    r"সরাসরি বুঝিয়ে দাও",
    r"সরাসরি উত্তর",
    r"উত্তর দিয়ে দাও",
]


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _to_iso(dt: datetime | None) -> str | None:
    return dt.isoformat() if dt else None


def _is_direct_answer_request(text: str) -> bool:
    cleaned = (text or "").strip().lower()
    for pattern in DIRECT_ANSWER_PATTERNS:
        if re.search(pattern, cleaned, re.IGNORECASE):
            return True
    return False


# ---------------------------------------------------------------------------
# 12.3 — Student-Level Adaptation Collector
# ---------------------------------------------------------------------------

def _gather_student_adaptation(uid: str, subject: str, topic: str) -> dict[str, Any]:
    """Inspect existing student memory, mistakes, and health without duplicating."""
    level = "intermediate"
    known_misconceptions: list[str] = []
    preferred_style = "concept_first"
    is_weak_topic = False

    # 1. Mistake Memory
    try:
        review_items = mistakes.get_review_queue(uid, limit=100)
        topic_lower = topic.strip().casefold()
        for item in review_items:
            m_topic = str(item.get("topic") or "").strip().casefold()
            if m_topic == topic_lower or topic_lower in m_topic:
                misc = str(item.get("why") or item.get("concept") or item.get("question") or "").strip()
                if misc and misc not in known_misconceptions:
                    known_misconceptions.append(misc[:120])
        if len(known_misconceptions) >= 2:
            is_weak_topic = True
            level = "beginner"
    except Exception as exc:
        logger.debug("Tutor adaptation: mistake read skipped: %s", exc)

    # 2. Learning Memory
    try:
        mem = memory.build_memory(uid, persist=False)
        style = str(mem.get("preferredLearningStyle") or "")
        if "example" in style.lower():
            preferred_style = "example_first"

        topics_data = mem.get("topics") or {}
        if isinstance(topics_data, dict) and topic in topics_data:
            acc = topics_data[topic].get("accuracy")
            if acc is not None:
                if acc < 50:
                    level = "beginner"
                    is_weak_topic = True
                elif acc >= 75:
                    level = "advanced"
    except Exception as exc:
        logger.debug("Tutor adaptation: learning memory read skipped: %s", exc)

    # 3. Academic Health
    try:
        h_score = health.get_academic_health(uid)
        score_val = h_score.get("score") or 70
        if score_val < 50:
            is_weak_topic = True
    except Exception as exc:
        logger.debug("Tutor adaptation: health score read skipped: %s", exc)

    return {
        "level": level,
        "knownMisconceptions": known_misconceptions[:5],
        "preferredStyle": preferred_style,
        "isWeakTopic": is_weak_topic,
    }


# ---------------------------------------------------------------------------
# 12.4 — Diagnostic Question Generator & Fallbacks
# ---------------------------------------------------------------------------

_DETERMINISTIC_DIAGNOSTICS: dict[str, dict[str, str]] = {
    "beginner": {
        "math": "Can you explain in simple words what the main goal of this concept is, and give one simple real-world picture of it?",
        "physics": "Imagine you have to explain this phenomenon to a friend without using formulas. How would you describe what physically happens?",
        "chemistry": "What is happening at the molecular or atomic level during this process?",
        "biology": "What is the primary function of this system or process in an organism?",
        "general": "What is your current understanding of this topic? In your own words, what does it do or describe?",
    },
    "intermediate": {
        "math": "How does this concept connect to what you learned right before it, and what problem does it solve that simpler tools could not?",
        "physics": "What are the key quantities involved here, and how does changing one variable affect the behavior of the system?",
        "chemistry": "How do the reactants and energy conditions determine the direction and outcome of this process?",
        "biology": "How does this process regulate or interact with other related functions in the cell or organism?",
        "general": "What is the key mechanism or principle behind this topic, and how does it relate to adjacent concepts?",
    },
    "advanced": {
        "math": "Under what edge cases or boundary conditions does this theorem hold, and how would you prove or formalize its primary relationship?",
        "physics": "What conservation laws or fundamental symmetries govern this behavior in non-ideal or limiting scenarios?",
        "chemistry": "How do thermodynamic vs kinetic controls influence this pathway under varying parameters?",
        "biology": "What feedback loops or molecular checkpoints prevent errors or disequilibrium in this pathway?",
        "general": "What are the subtle caveats, assumptions, or limit conditions required for this principle to work correctly?",
    },
}


def _get_fallback_diagnostic(subject: str, topic: str, level: str) -> str:
    subj_key = "general"
    s_clean = subject.strip().lower()
    if any(k in s_clean for k in ["math", "calculus", "algebra", "গণিত"]):
        subj_key = "math"
    elif any(k in s_clean for k in ["phys", "পদার্থ"]):
        subj_key = "physics"
    elif any(k in s_clean for k in ["chem", "রসায়ন"]):
        subj_key = "chemistry"
    elif any(k in s_clean for k in ["bio", "জীব"]):
        subj_key = "biology"

    template = _DETERMINISTIC_DIAGNOSTICS.get(level, {}).get(subj_key) or _DETERMINISTIC_DIAGNOSTICS["intermediate"]["general"]
    return f"Let's explore {topic}. {template}"


async def _generate_diagnostic_question(
    uid: str, subject: str, topic: str, concept: str, adaptation: dict[str, Any]
) -> str:
    level = adaptation.get("level", "intermediate")
    misconceptions = adaptation.get("knownMisconceptions", [])
    prompt = (
        f"You are Ziku, a warm, pedagogical Socratic tutor for high school and university students.\n"
        f"Subject: {subject}\n"
        f"Topic: {topic}\n"
        f"Concept: {concept}\n"
        f"Student Level: {level}\n"
        f"Known past misconceptions: {', '.join(misconceptions) if misconceptions else 'None recorded'}\n\n"
        f"Task: Generate ONE concise, engaging diagnostic question to test the student's conceptual reasoning.\n"
        f"Rules:\n"
        f"1. DO NOT explain the answer.\n"
        f"2. Ask about intuition, geometric meaning, or the relationship with related concepts.\n"
        f"3. Frame in natural bilingual Bengali + English technical terms (or English if technical).\n"
        f"4. Keep it to 1-2 friendly sentences.\n"
        f"Output ONLY the question text."
    )
    try:
        response = await ai_service.generate(uid, prompt, feature=ai_service.AiFeature.CHAT)
        clean = (response or "").strip()
        if clean and len(clean) > 10:
            return clean
    except Exception as exc:
        logger.info("Tutor: diagnostic AI generation failed, using deterministic fallback: %s", exc)

    return _get_fallback_diagnostic(subject, topic, level)


# ---------------------------------------------------------------------------
# 12.5 — Response Evaluation Engine
# ---------------------------------------------------------------------------

async def _evaluate_student_reasoning(
    uid: str,
    subject: str,
    topic: str,
    question: str,
    student_response: str,
    step: int,
    adaptation: dict[str, Any],
) -> dict[str, Any]:
    prompt = (
        f"You are Ziku, an expert Socratic tutor evaluating a student's conceptual answer.\n"
        f"Subject: {subject}\n"
        f"Topic: {topic}\n"
        f"Question asked: {question}\n"
        f"Student's response: {student_response}\n\n"
        f"Evaluate the student's answer. Respond ONLY with valid JSON in this exact structure:\n"
        f"{{\n"
        f'  "understanding": "correct" | "partial" | "misconception" | "unknown",\n'
        f'  "confidence": 0.0 to 1.0,\n'
        f'  "misconception": "brief description of misconception or none",\n'
        f'  "missingConcepts": ["concept1", "concept2"],\n'
        f'  "nextAction": "question" | "hint" | "explanation" | "practice" | "complete",\n'
        f'  "feedback": "Friendly, encouraging feedback in natural Bengali with English terms explaining what was right, what was missing, and the next step/question."\n'
        f"}}"
    )

    try:
        raw = await ai_service.generate(uid, prompt, feature=ai_service.AiFeature.CHAT)
        match = re.search(r"\{.*\}", raw, re.DOTALL)
        if match:
            parsed = json.loads(match.group(0))
            understanding = str(parsed.get("understanding") or "partial").lower()
            if understanding not in {"correct", "partial", "misconception", "unknown"}:
                understanding = "partial"
            return {
                "understanding": understanding,
                "confidence": max(0.0, min(1.0, float(parsed.get("confidence") or 0.7))),
                "misconception": str(parsed.get("misconception") or ""),
                "missingConcepts": [str(c) for c in (parsed.get("missingConcepts") or [])],
                "nextAction": str(parsed.get("nextAction") or "question"),
                "feedback": str(parsed.get("feedback") or "").strip(),
            }
    except Exception as exc:
        logger.info("Tutor: AI response evaluation failed, using deterministic evaluation: %s", exc)

    # Deterministic rule-based evaluation fallback
    words = student_response.strip().split()
    if len(words) < 3:
        return {
            "understanding": "partial",
            "confidence": 0.4,
            "misconception": "incomplete explanation",
            "missingConcepts": [topic],
            "nextAction": "hint",
            "feedback": (
                f"তোমার উত্তরটা খুব সংক্ষিপ্ত হয়েছে। "
                f"{topic}-এর মূল সম্পর্ক বা ধারণাটি আরেকটু বুঝিয়ে বলো—চল একটা ছোট ক্লু দিয়ে সাহায্য করি।"
            ),
        }
    return {
        "understanding": "partial",
        "confidence": 0.65,
        "misconception": "",
        "missingConcepts": [],
        "nextAction": "question" if step < 3 else "complete",
        "feedback": (
            f"তোমার মূল চিন্তাধারা দারুণ! ধারণার প্রথম দিকটা তুমি সঠিকভাবে ধরতে পেরেছ। "
            f"এবার ভাবো তো, এই বিষয়টি কীভাবে আরও জটিল পরিস্থিতিতে কাজ করবে?"
        ),
    }


# ---------------------------------------------------------------------------
# 12.6 — Progressive Hint Ladder
# ---------------------------------------------------------------------------

def _build_hint(topic: str, question: str, hints_used: int, adaptation: dict[str, Any]) -> str:
    """Progressive hint ladder:
    Hint 1: Small conceptual cue
    Hint 2: Stronger relationship cue
    Hint 3: Worked direction / partial setup
    After 3: Direct short explanation
    """
    if hints_used == 1:
        return f"💡 ক্লু ১ (Conceptual Cue): {topic}-এর সংজ্ঞার দিকে তাকাও। এটি কোন জিনিসটি পরিমাপ বা সঞ্চয় (accumulate) করে?"
    elif hints_used == 2:
        return f"💡 ক্লু ২ (Relationship Cue): চিন্তা করো বিপরীত প্রক্রিয়ার কথা—যদি ডিফারেন্সিয়েশন রেট বের করে, তবে {topic} কী করে?"
    elif hints_used == 3:
        return f"💡 ক্লু ৩ (Partial Setup): ছোট ছোট টুকরো যোগ করে পুরো ক্ষেত্রফল বা মোট মান বের করার কথাই এখানে ভাবা হচ্ছে।"
    else:
        return f"📖 সংক্ষিপ্ত ব্যাখ্যা: {topic} মূলত একটি প্রক্রিয়া যা ছোট পরিবর্তনের যোগফল হিসেবে মোট পরিবর্তন বা ক্ষেত্রফল নির্ধারণ করে। এবার এই ধারণার উপর ভিত্তি করে উত্তরটি সাজাও।"


# ---------------------------------------------------------------------------
# 12.7 & 12.2 — Direct Explanation Generator (Explain Mode)
# ---------------------------------------------------------------------------

async def _generate_direct_explanation(
    uid: str, subject: str, topic: str, concept: str, adaptation: dict[str, Any]
) -> str:
    style = adaptation.get("preferredStyle", "concept_first")
    misconceptions = adaptation.get("knownMisconceptions", [])
    prompt = (
        f"You are Ziku, a clear and encouraging tutor.\n"
        f"The student requested a direct explanation rather than Socratic questions.\n"
        f"Subject: {subject}\n"
        f"Topic: {topic}\n"
        f"Concept: {concept}\n"
        f"Preferred Style: {style} (if example_first, give a real concrete example first)\n"
        f"Past Misconceptions to clarify: {', '.join(misconceptions) if misconceptions else 'None'}\n\n"
        f"Provide a clear, engaging explanation in natural Bengali with English technical terminology.\n"
        f"Structure:\n"
        f"1. Core concept intuition (with an example if style is example_first)\n"
        f"2. Key mathematical / physical relationship\n"
        f"3. Common pitfall to avoid\n"
        f"Keep it concise (3 short paragraphs)."
    )
    try:
        resp = await ai_service.generate(uid, prompt, feature=ai_service.AiFeature.CHAT)
        if resp and len(resp.strip()) > 20:
            return resp.strip()
    except Exception as exc:
        logger.info("Tutor: direct explanation generation failed: %s", exc)

    return (
        f"চল {topic} সহজে বুঝে নিই:\n\n"
        f"১. মূল ধারণা: {topic} হলো পরিবর্তনের হারকে উল্টে মোট পরিমাণ নির্ণয় করা (যেমন বেগ থেকে দূরত্ব)।\n"
        f"২. সম্পর্ক: এটি বিপরীত গাণিতিক প্রক্রিয়ার মাধ্যমে কাজ করে এবং ক্ষুদ্রাতিক্ষুদ্র অংশের যোগফল দেয়।\n"
        f"৩. সাধারণ ভুল: কনস্ট্যান্ট বা বাউন্ডারি লিমিট উপেক্ষা করা। সবসময় শুরুর ও শেষের শর্ত খেয়াল রাখবে।"
    )


# ---------------------------------------------------------------------------
# 12.8 — Mastery Estimation Engine
# ---------------------------------------------------------------------------

def _calculate_mastery(
    history: list[dict[str, Any]], hints_used: int, mode: str
) -> tuple[float, str, str]:
    """Derive deterministic mastery estimate based on observable evidence."""
    if not history:
        return 0.5, "developing", "Requires practice"

    evaluations = [h.get("evaluation") for h in history if h.get("evaluation")]
    if not evaluations:
        return 0.5, "developing", "Needs active check"

    correct_count = sum(1 for e in evaluations if e.get("understanding") == "correct")
    partial_count = sum(1 for e in evaluations if e.get("understanding") == "partial")
    misc_count = sum(1 for e in evaluations if e.get("understanding") == "misconception")
    total_evals = max(1, len(evaluations))

    base_score = (correct_count * 1.0 + partial_count * 0.6 + misc_count * 0.2) / total_evals
    # Small penalty for heavy hint usage
    hint_penalty = min(0.2, (hints_used * 0.05))
    final_score = max(0.1, min(1.0, round(base_score - hint_penalty, 2)))

    if final_score >= 0.85:
        band = "mastered"
        gap = "Minimal gap — ready for challenging problem solving"
    elif final_score >= 0.70:
        band = "proficient"
        gap = "Good conceptual foundation — review boundary edge cases"
    elif final_score >= 0.50:
        band = "developing"
        gap = "Understands core concept — needs practice connecting sub-steps"
    else:
        band = "introductory"
        gap = "Early stage — needs guided worked examples and revision"

    return final_score, band, gap


# ---------------------------------------------------------------------------
# Persistence & Database Helpers
# ---------------------------------------------------------------------------

def _sessions_col():
    db = firebase.get_firestore()
    return db.collection(TUTOR_COLLECTION) if db is not None else None


def _load_session(uid: str, session_id: str) -> dict[str, Any]:
    col = _sessions_col()
    if col is None:
        raise HTTPException(status_code=500, detail="Database unavailable")
    doc_snap = col.document(session_id).get()
    if not doc_snap.exists:
        raise HTTPException(status_code=404, detail="Tutoring session not found")
    data = doc_snap.to_dict() or {}
    if data.get("studentId") != uid:
        raise HTTPException(status_code=403, detail="Forbidden: session ownership required")
    return data


def _save_session(session_id: str, data: dict[str, Any]) -> None:
    col = _sessions_col()
    if col is not None:
        try:
            col.document(session_id).set(data)
        except Exception:
            logger.exception("Could not save tutoring session %s", session_id)


# ---------------------------------------------------------------------------
# 12.1 — Public Tutoring Service API
# ---------------------------------------------------------------------------

async def start_session(
    uid: str | None = None,
    subject: str = "",
    topic: str = "",
    concept: str | None = None,
    mode: str = "socratic",
    user_id: str | None = None,
) -> dict[str, Any]:
    uid = uid or user_id or ""
    norm_mode = mode.lower().strip()
    if norm_mode not in VALID_MODES:
        norm_mode = "socratic"

    concept_str = (concept or topic).strip()
    session_id = f"tutor_{uuid4().hex}"
    now = _now()

    # Gather prior signals (Mistake Memory, Learning Memory, Health)
    adaptation = _gather_student_adaptation(uid, subject, topic)

    if norm_mode == "explain":
        initial_message = await _generate_direct_explanation(uid, subject, topic, concept_str, adaptation)
        step_type = "explanation"
        current_question = ""
    else:
        diagnostic = await _generate_diagnostic_question(uid, subject, topic, concept_str, adaptation)
        initial_message = (
            f"আগে দেখি তুমি conceptটা কতটুকু বুঝো।\n"
            f"একটা ছোট প্রশ্ন: {diagnostic}"
        )
        step_type = "diagnostic"
        current_question = diagnostic

    session_doc = {
        "sessionId": session_id,
        "studentId": uid,
        "subject": subject.strip(),
        "topic": topic.strip(),
        "concept": concept_str,
        "mode": norm_mode,
        "currentStep": 1,
        "stepType": step_type,
        "tutorMessage": initial_message,
        "currentQuestion": current_question,
        "masteryEstimate": 0.5,
        "confidenceBand": "introductory",
        "remainingGap": "",
        "misconceptions": adaptation.get("knownMisconceptions", []),
        "questionsAsked": 1 if current_question else 0,
        "hintsUsed": 0,
        "adaptation": adaptation,
        "lastEvaluation": None,
        "history": [
            {
                "role": "tutor",
                "content": initial_message,
                "stepType": step_type,
                "timestamp": _to_iso(now),
            }
        ],
        "summary": None,
        "completed": False,
        "startedAt": now,
        "updatedAt": now,
        "completedAt": None,
    }

    _save_session(session_id, session_doc)

    # Analytics event
    analytics.track_event(
        user_id=uid,
        event_name="tutor_session_started",
        metadata={
            "subject": subject,
            "topic": topic,
            "mode": norm_mode,
            "feature": "ai_tutor",
        },
    )

    return {
        "sessionId": session_id,
        "status": "active",
        "mode": norm_mode,
        "subject": subject,
        "topic": topic,
        "concept": concept_str,
        "step": 1,
        "currentStep": 1,
        "stepType": step_type,
        "tutorMessage": initial_message,
        "question": initial_message,
        "understanding": "unknown",
        "understandingLevel": 0.0,
        "masteryScore": 0.0,
        "hintsUsed": 0,
        "progress": 0.2,
        "canRequestHint": norm_mode == "socratic",
        "canSwitchMode": True,
        "completed": False,
    }



async def respond_to_step(
    uid: str | None = None,
    session_id: str = "",
    student_response: str = "",
    user_id: str | None = None,
) -> dict[str, Any]:
    uid = uid or user_id or ""
    session = _load_session(uid, session_id)
    if session.get("completed"):
        return {
            "sessionId": session_id,
            "status": "completed",
            "mode": session.get("mode", "socratic"),
            "step": session.get("currentStep", 1),
            "currentStep": session.get("currentStep", 1),
            "tutorMessage": "This tutoring session is already completed.",
            "stepType": "completed",
            "completed": True,
            "summary": session.get("summary"),
        }

    now = _now()
    response_text = (student_response or "").strip()
    session["updatedAt"] = now
    adaptation = session.get("adaptation") or {}
    subject = session.get("subject", "General")
    topic = session.get("topic", "General")
    concept = session.get("concept", topic)
    current_step = int(session.get("currentStep") or 1)
    hints_used = int(session.get("hintsUsed") or 0)

    # 12.7 — Direct Answer Escape check
    if _is_direct_answer_request(response_text):
        session["mode"] = "explain"
        explanation = await _generate_direct_explanation(uid, subject, topic, concept, adaptation)
        tutor_message = (
            f"অবশ্যই! চল প্রশ্ন বাদ দিয়ে সরাসরি ধারণাটি স্পষ্ট করে নিই:\n\n{explanation}"
        )
        session["stepType"] = "explanation"
        session["tutorMessage"] = tutor_message
        session["currentStep"] = current_step + 1
        session["history"].append({"role": "student", "content": response_text, "timestamp": _to_iso(now)})
        session["history"].append({"role": "tutor", "content": tutor_message, "stepType": "explanation", "timestamp": _to_iso(now)})
        _save_session(session_id, session)

        analytics.track_event(
            user_id=uid,
            event_name="tutor_mode_changed",
            metadata={"subject": subject, "topic": topic, "mode": "explain"},
        )

        return {
            "sessionId": session_id,
            "status": "active",
            "mode": "explain",
            "step": session["currentStep"],
            "currentStep": session["currentStep"],
            "stepType": "explanation",
            "tutorMessage": tutor_message,
            "directExplanation": explanation,
            "understanding": "unknown",
            "understandingLevel": 0.5,
            "masteryScore": 0.5,
            "hintsUsed": hints_used,
            "progress": 0.6,
            "canRequestHint": False,
            "canSwitchMode": True,
            "completed": False,
        }

    # Evaluate student reasoning
    current_q = session.get("currentQuestion") or f"Explain {topic}"
    evaluation = await _evaluate_student_reasoning(
        uid=uid,
        subject=subject,
        topic=topic,
        question=current_q,
        student_response=response_text,
        step=current_step,
        adaptation=adaptation,
    )

    session["lastEvaluation"] = evaluation
    session["currentStep"] = current_step + 1
    session["history"].append({
        "role": "student",
        "content": response_text,
        "evaluation": evaluation,
        "timestamp": _to_iso(now),
    })

    # Mistake Memory integration: track repeated misconceptions
    misconception_text = evaluation.get("misconception")
    if misconception_text and len(misconception_text.strip()) > 3:
        session["misconceptions"].append(misconception_text.strip()[:120])

    # Decide next pedagogical step
    understanding = evaluation.get("understanding", "partial")
    is_ready_to_complete = current_step >= 3 or understanding == "correct" or evaluation.get("nextAction") == "complete"

    if is_ready_to_complete:
        # Final mastery check & completion
        mastery_est, band, gap = _calculate_mastery(session["history"], hints_used, session.get("mode", "socratic"))
        session["masteryEstimate"] = mastery_est
        session["confidenceBand"] = band
        session["remainingGap"] = gap
        session["completed"] = True
        session["completedAt"] = now
        session["stepType"] = "completed"

        summary = {
            "topic": topic,
            "overview": f"Completed interactive tutoring session on {topic}.",
            "whatYouUnderstood": [
                f"Demonstrated {understanding} reasoning on {concept}",
                "Successfully engaged in interactive inquiry",
            ],
            "conceptsMastered": [concept],
            "conceptsToReview": [gap] if gap else ["Continue standard spaced repetition"],
            "needsReview": [gap] if gap else ["Continue standard spaced repetition"],
            "hintsUsed": hints_used,
            "masteryEstimate": mastery_est,
            "masteryBand": band.capitalize(),
            "confidenceBand": band,
            "recommendedNextAction": "Take 5-question practice quiz to consolidate mastery",
            "recommendedRoute": "/api/quiz/generate",
        }
        session["summary"] = summary

        closing_msg = (
            f"{evaluation.get('feedback', '')}\n\n"
            f"🎉 চমৎকার! আমরা {topic}-এর মূল ধারণা সফলভাবে আলোচনা করেছি।\n"
            f"তোমার অর্জিত পারদর্শিতা: {band.capitalize()} ({int(mastery_est * 100)}%)।"
        )
        session["tutorMessage"] = closing_msg
        session["history"].append({
            "role": "tutor",
            "content": closing_msg,
            "stepType": "completed",
            "timestamp": _to_iso(now),
        })

        _save_session(session_id, session)

        # 12.11 Analytics
        duration = int((now - session.get("startedAt", now)).total_seconds())
        analytics.track_event(
            user_id=uid,
            event_name="tutor_session_completed",
            metadata={
                "subject": subject,
                "topic": topic,
                "mode": session.get("mode", "socratic"),
                "duration_seconds": duration,
                "hints_used": hints_used,
                "mastery_band": band,
            },
        )

        return {
            "sessionId": session_id,
            "status": "completed",
            "mode": session.get("mode", "socratic"),
            "step": session["currentStep"],
            "currentStep": session["currentStep"],
            "stepType": "completed",
            "tutorMessage": closing_msg,
            "evaluation": evaluation,
            "understanding": understanding,
            "understandingLevel": mastery_est,
            "masteryScore": mastery_est,
            "masteryBand": band.capitalize(),
            "hintsUsed": hints_used,
            "progress": 1.0,
            "canRequestHint": False,
            "canSwitchMode": False,
            "completed": True,
            "summary": summary,
        }

    # Socratic continuation: ask next question or provide guided reflection
    tutor_feedback = evaluation.get("feedback") or "তোমার উত্তর পেয়েছি। চল আরেকটু গভীরে যাই।"
    session["stepType"] = "question"
    session["tutorMessage"] = tutor_feedback
    session["currentQuestion"] = tutor_feedback
    session["history"].append({
        "role": "tutor",
        "content": tutor_feedback,
        "stepType": "question",
        "timestamp": _to_iso(now),
    })

    _save_session(session_id, session)

    progress_val = min(0.85, 0.2 + (current_step * 0.25))
    return {
        "sessionId": session_id,
        "status": "active",
        "mode": session.get("mode", "socratic"),
        "step": session["currentStep"],
        "currentStep": session["currentStep"],
        "stepType": "question",
        "tutorMessage": tutor_feedback,
        "nextQuestion": tutor_feedback,
        "evaluation": evaluation,
        "understanding": understanding,
        "understandingLevel": min(0.9, 0.2 + (current_step * 0.2)),
        "masteryScore": min(0.9, 0.2 + (current_step * 0.2)),
        "hintsUsed": hints_used,
        "progress": progress_val,
        "canRequestHint": True,
        "canSwitchMode": True,
        "completed": False,
    }



async def request_hint(
    uid: str | None = None,
    session_id: str = "",
    user_id: str | None = None,
) -> dict[str, Any]:
    uid = uid or user_id or ""
    session = _load_session(uid, session_id)
    if session.get("completed"):
        raise HTTPException(status_code=400, detail="Cannot request hint on a completed session")

    hints_used = int(session.get("hintsUsed") or 0) + 1
    session["hintsUsed"] = hints_used
    session["updatedAt"] = _now()

    topic = session.get("topic", "General")
    adaptation = session.get("adaptation") or {}
    hint_msg = _build_hint(topic, session.get("currentQuestion", ""), hints_used, adaptation)

    session["history"].append({
        "role": "tutor",
        "content": hint_msg,
        "stepType": "hint",
        "timestamp": _to_iso(_now()),
    })
    _save_session(session_id, session)

    analytics.track_event(
        user_id=uid,
        event_name="tutor_hint_used",
        metadata={
            "subject": session.get("subject", "General"),
            "topic": topic,
            "hints_used": hints_used,
        },
    )

    hint_level = min(3, hints_used)
    hint_type = "conceptual" if hint_level == 1 else "relationship" if hint_level == 2 else "worked_setup"

    return {
        "sessionId": session_id,
        "hint": hint_msg,
        "hintLevel": hint_level,
        "hintType": hint_type,
        "hintsUsed": hints_used,
        "maxHintsReached": hints_used >= 3,
        "canRequestMoreHints": hints_used < 3,
    }


async def switch_mode(
    uid: str | None = None,
    session_id: str = "",
    new_mode: str = "",
    mode: str | None = None,
    user_id: str | None = None,
) -> dict[str, Any]:
    uid = uid or user_id or ""
    target_mode = (new_mode or mode or "").lower().strip()
    if target_mode not in VALID_MODES:
        raise HTTPException(status_code=400, detail=f"Invalid mode: {target_mode}")

    session = _load_session(uid, session_id)
    if session.get("completed"):
        raise HTTPException(status_code=400, detail="Cannot switch mode on a completed session")

    session["mode"] = target_mode
    session["updatedAt"] = _now()

    topic = session.get("topic", "General")
    if target_mode == "practice":
        switch_msg = f"📝 প্র্যাকটিস মোড চালু করা হয়েছে। {topic}-এর উপর একটি ছোট কুইজ দিয়ে তোমার জ্ঞান যাচাই করো।"
    elif target_mode == "exam_prep":
        switch_msg = f"🎯 পরীক্ষার প্রস্তুতি মোড চালু হয়েছে। বিগত পরীক্ষার ভুল এবং গুরুত্বপূর্ণ পয়েন্টে নজর দেওয়া হবে।"
    elif target_mode == "explain":
        switch_msg = f"📖 সরাসরি ব্যাখ্যা মোড চালু হয়েছে। এবার বিস্তারিত আলোচনা করা হবে।"
    else:
        switch_msg = f"💡 সক্রেটিক মোড সক্রিয়। প্রশ্নোত্তরের মাধ্যমে নিজে চিন্তা করে শিখো।"

    session["tutorMessage"] = switch_msg
    session["history"].append({
        "role": "tutor",
        "content": switch_msg,
        "stepType": "mode_switch",
        "timestamp": _to_iso(_now()),
    })
    _save_session(session_id, session)

    analytics.track_event(
        user_id=uid,
        event_name="tutor_mode_changed",
        metadata={
            "subject": session.get("subject", "General"),
            "topic": topic,
            "mode": target_mode,
        },
    )

    return {
        "sessionId": session_id,
        "mode": target_mode,
        "prompt": switch_msg,
        "tutorMessage": switch_msg,
    }


async def complete_session(
    uid: str | None = None,
    session_id: str = "",
    user_id: str | None = None,
) -> dict[str, Any]:
    uid = uid or user_id or ""
    session = _load_session(uid, session_id)
    now = _now()
    topic = session.get("topic", "General")
    concept = session.get("concept", topic)
    hints_used = int(session.get("hintsUsed") or 0)

    if session.get("completed"):
        summary = session.get("summary") or {}
        return {
            "sessionId": session_id,
            "status": "completed",
            "mode": session.get("mode", "socratic"),
            "stepsCount": session.get("currentStep", 1),
            "hintsUsed": hints_used,
            "masteryScore": session.get("masteryEstimate", 0.5),
            "masteryBand": session.get("confidenceBand", "developing").capitalize(),
            "summary": summary,
            "completedAt": _to_iso(session.get("completedAt") or now),
        }

    mastery_est, band, gap = _calculate_mastery(session.get("history", []), hints_used, session.get("mode", "socratic"))

    summary = {
        "topic": topic,
        "overview": f"Completed interactive tutoring session on {topic}.",
        "whatYouUnderstood": [
            f"Covered conceptual framework of {concept}",
            "Actively engaged with guided tutor questions",
        ],
        "conceptsMastered": [concept],
        "conceptsToReview": [gap] if gap else ["Maintain spaced revision schedule"],
        "needsReview": [gap] if gap else ["Maintain spaced revision schedule"],
        "hintsUsed": hints_used,
        "masteryEstimate": mastery_est,
        "masteryBand": band.capitalize(),
        "confidenceBand": band,
        "recommendedNextAction": "Take 5-question practice quiz to consolidate mastery",
        "recommendedRoute": "/api/quiz/generate",
    }

    session["completed"] = True
    session["completedAt"] = now
    session["updatedAt"] = now
    session["masteryEstimate"] = mastery_est
    session["confidenceBand"] = band
    session["remainingGap"] = gap
    session["summary"] = summary
    session["stepType"] = "completed"

    _save_session(session_id, session)

    duration = int((now - session.get("startedAt", now)).total_seconds())
    analytics.track_event(
        user_id=uid,
        event_name="tutor_session_completed",
        metadata={
            "subject": session.get("subject", "General"),
            "topic": topic,
            "mode": session.get("mode", "socratic"),
            "duration_seconds": duration,
            "hints_used": hints_used,
            "mastery_band": band,
        },
    )

    return {
        "sessionId": session_id,
        "status": "completed",
        "mode": session.get("mode", "socratic"),
        "stepsCount": session.get("currentStep", 1),
        "hintsUsed": hints_used,
        "masteryScore": mastery_est,
        "masteryBand": band.capitalize(),
        "summary": summary,
        "completedAt": _to_iso(now),
    }


async def get_session(
    uid: str | None = None,
    session_id: str = "",
    user_id: str | None = None,
) -> dict[str, Any]:
    uid = uid or user_id or ""
    return _load_session(uid, session_id)


async def get_recent_sessions(
    uid: str | None = None,
    limit: int = 10,
    user_id: str | None = None,
) -> list[dict[str, Any]]:
    uid = uid or user_id or ""
    col = _sessions_col()
    if col is None:
        return []
    try:
        query = col.where("studentId", "==", uid).limit(limit)
        results = []
        for snap in query.stream():
            data = snap.to_dict() or {}
            results.append({
                "sessionId": data.get("sessionId"),
                "subject": data.get("subject"),
                "topic": data.get("topic"),
                "mode": data.get("mode"),
                "masteryEstimate": data.get("masteryEstimate"),
                "confidenceBand": data.get("confidenceBand"),
                "completed": data.get("completed", False),
                "startedAt": _to_iso(data.get("startedAt")),
                "completedAt": _to_iso(data.get("completedAt")),
            })
        return results
    except Exception as exc:
        logger.debug("Tutor: get_recent_sessions failed: %s", exc)
        return []

