"""AI Router Service — Deterministic AI Task Classification Foundation.

Classifies incoming AI tasks into appropriate model tiers (Tier 1, Tier 2, Tier 3)
without making LLM calls. Provides the routing foundation for Phase 12.2.1.
"""

from __future__ import annotations

from typing import Literal

TIER_1 = "tier1"
TIER_2 = "tier2"
TIER_3 = "tier3"

ModelTier = Literal["tier1", "tier2", "tier3"]

_TIER_1_TASKS: set[str] = {
    "mcq_checking",
    "mcq_check",
    "mcq_validation",
    "mcq_grading",
    "keyword_extraction",
    "keyword",
    "keywords",
    "simple_classification",
    "classification",
    "formatting",
    "json_formatting",
    "clean_text",
    "escape_hatch_check",
    "intent_classification",
    "sentiment_analysis",
}

_TIER_3_TASKS: set[str] = {
    "socratic_tutor",
    "socratic_tutoring",
    "socratic",
    "socratic_tutor_reasoning",
    "tutor_reasoning",
    "tutor",
    "complex_math",
    "complex_math_derivation",
    "complex_derivation",
    "math_derivation",
    "derivation",
    "proof",
    "exam_intelligence",
    "exam_simulator",
    "exam_rescue",
    "olympiad_problem",
}

_TIER_2_TASKS: set[str] = {
    "normal_explanation",
    "explanation",
    "concept_explanation",
    "study_content_generation",
    "content_generation",
    "flashcards",
    "revision_sheet",
    "study_pack",
    "normal_chat",
    "normal_ziku_chat",
    "ziku_chat",
    "chat",
    "note_ai",
    "quiz_generation",
    "study_plan",
    "study_coach",
}


def classify_task(
    task_type: str,
    feature: str | None = None,
    complexity: str | None = None,
) -> dict[str, str]:
    """Lightweight deterministic AI task classifier.

    Maps a task to an optimal model tier without calling any LLM.
    Returns:
        {
            "tier": "tier1" | "tier2" | "tier3",
            "reason": str
        }
    """
    norm_task = (task_type or "").strip().lower().replace("-", "_").replace(" ", "_")
    norm_feature = (feature or "").strip().lower().replace("-", "_").replace(" ", "_") if feature else ""
    norm_complexity = (complexity or "").strip().lower() if complexity else ""

    # 1. Complexity override
    if norm_complexity in ("high", "complex", "deep"):
        return {
            "tier": TIER_3,
            "reason": f"High task complexity requested for task '{task_type}'",
        }
    if norm_complexity in ("low", "simple", "minimal") and norm_task not in _TIER_3_TASKS:
        return {
            "tier": TIER_1,
            "reason": f"Low task complexity specified for task '{task_type}'",
        }

    # 2. Tier 1 matches
    if norm_task in _TIER_1_TASKS:
        return {
            "tier": TIER_1,
            "reason": f"Lightweight task '{task_type}' routed to tier 1",
        }

    # 3. Tier 3 matches
    if norm_task in _TIER_3_TASKS:
        return {
            "tier": TIER_3,
            "reason": f"Complex or Socratic reasoning task '{task_type}' routed to tier 3",
        }
    if norm_feature in ("tutor", "socratic", "exam_rescue"):
        return {
            "tier": TIER_3,
            "reason": f"High-reasoning feature '{feature}' routed to tier 3",
        }

    # 4. Tier 2 matches
    if norm_task in _TIER_2_TASKS:
        return {
            "tier": TIER_2,
            "reason": f"Standard generation task '{task_type}' routed to tier 2",
        }

    # 5. Default fallback to Tier 2
    return {
        "tier": TIER_2,
        "reason": f"Defaulting unknown or standard task '{task_type}' to tier 2",
    }


# Backwards-compatible / intuitive aliases
route_task = classify_task
classify_ai_task = classify_task
