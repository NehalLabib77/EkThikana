"""Phase 3C-3 — AI Study Recommendation Service.

Collects data from quiz_results, weak topics, tasks, assignments,
and focus sessions to generate personalized daily study recommendations.
Uses AI cascade with daily caching to minimize quota usage.
"""
from __future__ import annotations

import json
import logging
from datetime import datetime, timezone
from typing import Any

from app.core.firebase import get_firestore
from app.services.ai_service import AiFeature, generate

logger = logging.getLogger("gochano.ai_study")

# Cache duration: recommendations refresh once per day.
_CACHE_DAY_FORMAT = "%Y-%m-%d"


def _today_key() -> str:
    return datetime.now(timezone.utc).strftime(_CACHE_DAY_FORMAT)


def _fetch_cached_recommendation(uid: str) -> dict[str, Any] | None:
    """Return cached recommendation if it exists for today."""
    db = get_firestore()
    if db is None:
        return None

    today = _today_key()
    doc = (
        db.collection("users")
        .document(uid)
        .collection("learning_cache")
        .document(f"recommendation_{today}")
        .get()
    )

    if doc.exists:
        data = doc.to_dict() or {}
        recommendations = data.get("recommendations")
        if isinstance(recommendations, list) and recommendations:
            return {"recommendations": recommendations, "cached": True}
    return None


def _save_cached_recommendation(uid: str, recommendations: list[dict]) -> None:
    """Cache today's recommendation."""
    db = get_firestore()
    if db is None:
        return

    today = _today_key()
    ref = (
        db.collection("users")
        .document(uid)
        .collection("learning_cache")
        .document(f"recommendation_{today}")
    )
    ref.set({
        "recommendations": recommendations,
        "generatedAt": datetime.now(timezone.utc),
        "dayKey": today,
    })


def _collect_student_context(uid: str) -> dict[str, Any]:
    """Gather all relevant student data for recommendation generation."""
    db = get_firestore()
    if db is None:
        return {"weak_topics": [], "tasks": [], "assignments": [], "recent_quizzes": [], "focus_today": 0}

    # 1. Weak topics from quiz history
    from app.services.weak_topic_service import get_weak_topics
    weak_topics = get_weak_topics(uid, threshold=60)

    # 2. Undone tasks
    tasks = []
    try:
        docs = (
            db.collection("tasks")
            .where("ownerId", "==", uid)
            .limit(50)
            .stream()
        )
        for snap in docs:
            data = snap.to_dict() or {}
            if data.get("done") is True:
                continue
            tasks.append({
                "title": data.get("title", ""),
                "dueAt": str(data.get("dueAt", "")),
                "subjectId": data.get("subjectId", ""),
            })
    except Exception as e:
        logger.warning("Failed to fetch tasks: %s", e)

    # 3. Assignments (tasks with type='assignment')
    assignments = []
    try:
        docs = (
            db.collection("tasks")
            .where("ownerId", "==", uid)
            .where("type", "==", "assignment")
            .limit(20)
            .stream()
        )
        for snap in docs:
            data = snap.to_dict() or {}
            if data.get("done") is True:
                continue
            assignments.append({
                "title": data.get("title", ""),
                "dueAt": str(data.get("dueAt", "")),
                "subjectId": data.get("subjectId", ""),
            })
    except Exception as e:
        logger.warning("Failed to fetch assignments: %s", e)

    # 4. Recent quiz performance (last 5 quizzes)
    recent_quizzes = []
    try:
        docs = (
            db.collection("users")
            .document(uid)
            .collection("quiz_results")
            .order_by("createdAt", direction="DESCENDING")
            .limit(5)
            .stream()
        )
        for snap in docs:
            data = snap.to_dict() or {}
            recent_quizzes.append({
                "score": data.get("score", 0),
                "difficulty": data.get("difficulty", "medium"),
                "subjectId": data.get("subjectId", ""),
                "dayKey": data.get("dayKey", ""),
            })
    except Exception as e:
        logger.warning("Failed to fetch quiz results: %s", e)

    # 5. Today's focus session duration (minutes)
    focus_today = 0
    try:
        today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
        docs = (
            db.collection("users")
            .document(uid)
            .collection("focus_sessions")
            .where("dayKey", "==", today)
            .stream()
        )
        for snap in docs:
            data = snap.to_dict() or {}
            focus_today += (data.get("accumulatedSeconds") or 0) // 60
    except Exception as e:
        logger.warning("Failed to fetch focus sessions: %s", e)

    return {
        "weak_topics": weak_topics[:5],
        "tasks": tasks[:10],
        "assignments": assignments[:5],
        "recent_quizzes": recent_quizzes,
        "focus_today": focus_today,
    }


def _build_recommendation_prompt(context: dict[str, Any]) -> str:
    """Build the AI prompt from collected student data."""
    parts = []

    # Weak topics
    weak = context.get("weak_topics", [])
    if weak:
        weak_lines = [f"  - {t['topic']}: {t['average_score']}% ({t['attempts']} attempts)" for t in weak]
        parts.append(f"WEAK TOPICS (need improvement):\n" + "\n".join(weak_lines))

    # Tasks
    tasks = context.get("tasks", [])
    if tasks:
        task_lines = [f"  - {t['title']}" for t in tasks[:5]]
        parts.append(f"PENDING TASKS:\n" + "\n".join(task_lines))

    # Assignments
    assignments = context.get("assignments", [])
    if assignments:
        assign_lines = [f"  - {a['title']}" for a in assignments[:3]]
        parts.append(f"ASSIGNMENTS:\n" + "\n".join(assign_lines))

    # Recent quiz scores
    quizzes = context.get("recent_quizzes", [])
    if quizzes:
        quiz_lines = [f"  - Score: {q['score']}% (difficulty: {q['difficulty']})" for q in quizzes[:3]]
        parts.append(f"RECENT QUIZ SCORES:\n" + "\n".join(quiz_lines))

    # Focus time today
    focus = context.get("focus_today", 0)
    parts.append(f"TODAY'S STUDY TIME: {focus} minutes")

    context_text = "\n\n".join(parts) if parts else "No student data available yet."

    return (
        "You are a study advisor for a university student.\n"
        "Based on the student's data below, generate 3-5 specific, actionable study recommendations.\n"
        "Each recommendation should have a clear title, a brief reason, and a priority level.\n\n"
        "Student Data:\n"
        f"{context_text}\n\n"
        "Return ONLY valid JSON with this structure:\n"
        "{\n"
        '  "recommendations": [\n'
        "    {\n"
        '      "title": "Short action title",\n'
        '      "reason": "Why this is recommended (1-2 sentences)",\n'
        '      "priority": "high" or "medium" or "low"\n'
        "    }\n"
        "  ]\n"
        "}\n\n"
        "Rules:\n"
        "- Prioritize weak topics first\n"
        "- If there are overdue/upcoming tasks, mention them\n"
        "- If study time is low, suggest a study session\n"
        "- Keep reasons under 30 words each\n"
        "- Return ONLY the JSON, no extra text"
    )


def _generate_fallback_recommendations(context: dict[str, Any]) -> list[dict[str, Any]]:
    """Generate rule-based recommendations when AI is unavailable."""
    recs = []

    # Weak topics → high priority
    for t in context.get("weak_topics", [])[:2]:
        recs.append({
            "title": f"Review: {t['topic']}",
            "reason": f"Your average score is {t['average_score']}% after {t['attempts']} attempts. Focus on fundamentals.",
            "priority": "high",
        })

    # Assignments → high/medium priority
    for a in context.get("assignments", [])[:2]:
        recs.append({
            "title": f"Work on: {a['title']}",
            "reason": "You have a pending assignment. Start early to avoid last-minute stress.",
            "priority": "high",
        })

    # Low study time → medium priority
    focus = context.get("focus_today", 0)
    if focus < 30:
        recs.append({
            "title": "Start a study session",
            "reason": f"You've studied {focus} min today. Aim for at least 1-2 hours of focused study.",
            "priority": "medium",
        })

    # Tasks → low priority
    tasks = context.get("tasks", [])
    if tasks and len(recs) < 5:
        recs.append({
            "title": f"Complete {len(tasks)} pending task(s)",
            "reason": "You have undone tasks. Tackle the easiest ones first for momentum.",
            "priority": "low",
        })

    # If nothing to recommend
    if not recs:
        recs.append({
            "title": "Keep up the great work!",
            "reason": "No urgent items. Try taking a quiz to track your progress.",
            "priority": "low",
        })

    return recs[:5]


async def generate_study_recommendation(uid: str) -> dict[str, Any]:
    """Generate personalized study recommendation for the student.

    Checks cache first. If no cache, collects data, calls AI,
    caches result, and returns. Falls back to rule-based if AI fails.

    Returns:
        Dict with 'recommendations' list and 'cached' flag.
    """
    # 1. Check cache
    cached = _fetch_cached_recommendation(uid)
    if cached is not None:
        logger.info("Returning cached recommendation for uid=%s", uid)
        return cached

    # 2. Collect student context
    context = _collect_student_context(uid)

    # 3. Try AI generation
    recommendations = None
    try:
        prompt = _build_recommendation_prompt(context)
        result = await generate(uid, prompt, feature=AiFeature.CHAT)

        # Parse JSON response
        cleaned = result.strip()
        if cleaned.startswith("```"):
            cleaned = cleaned.split("\n", 1)[-1]
            if cleaned.endswith("```"):
                cleaned = cleaned[:-3]

        parsed = json.loads(cleaned)
        raw_recs = parsed.get("recommendations", [])

        # Validate structure
        recommendations = []
        for r in raw_recs:
            if isinstance(r, dict) and "title" in r:
                recommendations.append({
                    "title": str(r.get("title", ""))[:100],
                    "reason": str(r.get("reason", ""))[:200],
                    "priority": str(r.get("priority", "medium")),
                })

        if not recommendations:
            recommendations = _generate_fallback_recommendations(context)

    except Exception as e:
        logger.warning("AI recommendation failed, using fallback: %s", e)
        recommendations = _generate_fallback_recommendations(context)

    # 4. Cache and return
    _save_cached_recommendation(uid, recommendations)

    return {"recommendations": recommendations, "cached": False}
