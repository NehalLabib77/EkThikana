"""Tests for Phase 12.2.1 AI Router and AI Service Hardening."""

from __future__ import annotations

import pytest

from app.services.ai_router_service import (
    TIER_1,
    TIER_2,
    TIER_3,
    classify_ai_task,
    classify_task,
    route_task,
)
from app.services.ai_service import _http, generate


def test_simple_mcq_task_returns_tier1():
    """Simple MCQ checking task must return tier1."""
    res = classify_task("mcq_checking")
    assert res["tier"] == TIER_1
    assert "tier 1" in res["reason"]

    # Also verify common variants
    assert classify_task("mcq_check")["tier"] == TIER_1
    assert classify_task("keyword_extraction")["tier"] == TIER_1
    assert classify_task("simple_classification")["tier"] == TIER_1
    assert classify_task("formatting")["tier"] == TIER_1


def test_normal_explanation_returns_tier2():
    """Normal explanation task must return tier2."""
    res = classify_task("normal_explanation")
    assert res["tier"] == TIER_2
    assert "tier 2" in res["reason"]

    # Also verify content generation and normal chat
    assert classify_task("study_content_generation")["tier"] == TIER_2
    assert classify_task("normal_chat")["tier"] == TIER_2
    assert classify_task("ziku_chat")["tier"] == TIER_2
    assert classify_task("concept_explanation")["tier"] == TIER_2


def test_socratic_tutor_returns_tier3():
    """Socratic tutor reasoning must return tier3."""
    res = classify_task("socratic_tutor")
    assert res["tier"] == TIER_3
    assert "tier 3" in res["reason"]

    # Also verify complex math and exam intelligence
    assert classify_task("complex_math")["tier"] == TIER_3
    assert classify_task("complex_derivation")["tier"] == TIER_3
    assert classify_task("exam_intelligence")["tier"] == TIER_3
    assert classify_task("tutor_reasoning")["tier"] == TIER_3


def test_unknown_task_returns_tier2_default():
    """Unknown or unclassified task must default to tier2."""
    res = classify_task("random_unknown_task_xyz")
    assert res["tier"] == TIER_2
    assert "Defaulting" in res["reason"]


def test_complexity_overrides():
    """Explicit complexity override should adjust model tier appropriately."""
    # High complexity escalates standard task to tier3
    res_high = classify_task("normal_explanation", complexity="high")
    assert res_high["tier"] == TIER_3

    # Low complexity downgrades standard task to tier1
    res_low = classify_task("normal_explanation", complexity="low")
    assert res_low["tier"] == TIER_1


def test_router_aliases():
    """Verify route_task and classify_ai_task aliases work identically."""
    assert route_task("mcq_checking")["tier"] == TIER_1
    assert classify_ai_task("socratic_tutor")["tier"] == TIER_3


def test_hardened_http_timeout_settings():
    """Verify that _http() client is configured with production-safe timeouts."""
    client = _http()
    assert client.timeout.connect == 8.0
    assert client.timeout.read == 35.0
    assert client.timeout.write == 35.0
    assert client.timeout.pool == 10.0


@pytest.mark.asyncio
async def test_generate_accepts_optional_model_tier(monkeypatch):
    """ai_service.generate must accept optional model_tier without breaking."""
    async def mock_groq(prompt: str) -> str:
        return "mocked answer"

    import app.services.ai_service as ai_mod
    monkeypatch.setattr(ai_mod, "_consume_quota", lambda uid, feature=None: None)
    monkeypatch.setattr(ai_mod, "_groq_generate", mock_groq)

    # Calling with model_tier=None (default)
    res_default = await generate("user_123", "Hello", model_tier=None)
    assert res_default == "mocked answer"

    # Calling with explicit model_tier
    res_tiered = await generate("user_123", "Hello", model_tier="tier1")
    assert res_tiered == "mocked answer"
