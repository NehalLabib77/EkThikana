"""Tests for AI provider fallback (Groq -> Gemini -> OpenRouter) and feature usage quotas."""

from __future__ import annotations

import sys
from pathlib import Path
from unittest.mock import AsyncMock, patch
import pytest
from fastapi import HTTPException

_BACKEND_ROOT = Path(__file__).resolve().parent.parent
if str(_BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(_BACKEND_ROOT))

from app.core.config import Settings, get_settings
from app.services.ai_service import (
    AiFeature,
    generate,
    generate_multimodal,
    get_ai_usage,
)


def _auth(fake_auth, uid):
    return {"Authorization": f"Bearer {fake_auth.issue(uid)}"}


def test_ai_usage_endpoint(client, fake_db, fake_auth):
    """GET /api/ai/usage returns remaining and used counters."""
    """GET /api/ai/usage returns remaining and used counters for all Phase 3A features."""
    uid = "test-ai-student"
    fake_db.seed("users", uid, {"role": "student"})

    resp = client.get(
        "/api/ai/usage",
        headers=_auth(fake_auth, uid),
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()

    # Step 6 required format
    assert "chat" in body
    assert body["chat"] == {"used": 0, "limit": 20, "remaining": 20}

    assert "note_ai" in body
    assert body["note_ai"] == {"used": 0, "limit": 5, "remaining": 5}

    assert "quiz" in body
    assert body["quiz"] == {"used": 0, "limit": 3, "remaining": 3}

    assert "study_plan" in body
    assert body["study_plan"] == {"used": 0, "limit": 1, "remaining": 1}

    # Backward compatibility
    assert "total" in body
    assert "features" in body
    assert "day" in body
    assert body["total"]["limit"] > 0
    assert body["total"]["used"] == 0
    assert body["total"]["remaining"] == body["total"]["limit"]

    # Check all features are present
    # Check legacy features are present
    assert AiFeature.NOTE in body["features"]
    assert AiFeature.PDF_QUESTION in body["features"]
    assert AiFeature.IMAGE_QUESTION in body["features"]
    assert AiFeature.COMMUTE_GUIDE in body["features"]
    assert AiFeature.PRESCRIPTION in body["features"]


def test_chat_daily_limit_and_user_isolation(fake_db, monkeypatch):
    """Chat feature has a 20/day limit, blocks at limit, and isolates users."""
    from app.services.ai_service import _consume_quota
    user_a = "user-chat-a"
    user_b = "user-chat-b"

    # Set chat daily limit to 3 for fast test verification
    monkeypatch.setattr(get_settings(), "ai_limit_chat_daily", 3)
    monkeypatch.setattr(get_settings(), "ai_daily_limit", 100)

    for _ in range(3):
        _consume_quota(user_a, feature=AiFeature.CHAT)

    usage_a = get_ai_usage(user_a)
    assert usage_a["chat"]["used"] == 3
    assert usage_a["chat"]["remaining"] == 0

    # 4th call for user_a fails
    with pytest.raises(HTTPException) as exc_info:
        _consume_quota(user_a, feature=AiFeature.CHAT)
    assert exc_info.value.status_code == 429
    assert "chat" in exc_info.value.detail.lower()

    # User B is completely isolated and still has 3 remaining
    usage_b = get_ai_usage(user_b)
    assert usage_b["chat"]["used"] == 0
    assert usage_b["chat"]["remaining"] == 3
    _consume_quota(user_b, feature=AiFeature.CHAT)
    assert get_ai_usage(user_b)["chat"]["used"] == 1


def test_monthly_limits_note_ai_and_quiz(fake_db, monkeypatch):
    """Note AI (5/mo) and Quiz (3/mo) limits block when exhausted."""
    from app.services.ai_service import _consume_quota
    uid = "monthly-user"

    monkeypatch.setattr(get_settings(), "ai_limit_note_monthly", 2)
    monkeypatch.setattr(get_settings(), "ai_limit_quiz_monthly", 2)

    # Note AI
    _consume_quota(uid, feature=AiFeature.NOTE_AI)
    _consume_quota(uid, feature=AiFeature.NOTE_AI)
    usage = get_ai_usage(uid)
    assert usage["note_ai"]["used"] == 2
    assert usage["note_ai"]["remaining"] == 0

    with pytest.raises(HTTPException) as exc_info:
        _consume_quota(uid, feature=AiFeature.NOTE_AI)
    assert exc_info.value.status_code == 429
    assert "note ai" in exc_info.value.detail.lower()

    # Quiz
    _consume_quota(uid, feature=AiFeature.QUIZ)
    assert get_ai_usage(uid)["quiz"]["used"] == 1
    assert get_ai_usage(uid)["quiz"]["remaining"] == 1

    _consume_quota(uid, feature=AiFeature.QUIZ)
    with pytest.raises(HTTPException) as exc_info2:
        _consume_quota(uid, feature=AiFeature.QUIZ)
    assert exc_info2.value.status_code == 429
    assert "quiz" in exc_info2.value.detail.lower()


def test_study_plan_active_limit(fake_db):
    """Study Plan allows only 1 active plan at a time."""
    from app.services.ai_service import _consume_quota
    uid = "study-plan-user"

    usage = get_ai_usage(uid)
    assert usage["study_plan"]["used"] == 0
    assert usage["study_plan"]["remaining"] == 1

    _consume_quota(uid, feature=AiFeature.STUDY_PLAN)
    usage_after = get_ai_usage(uid)
    assert usage_after["study_plan"]["used"] == 1
    assert usage_after["study_plan"]["remaining"] == 0

    with pytest.raises(HTTPException) as exc_info:
        _consume_quota(uid, feature=AiFeature.STUDY_PLAN)
    assert exc_info.value.status_code == 429
    assert "active study plan" in exc_info.value.detail.lower()


def test_ai_feature_quota_exhausted(fake_db, monkeypatch):
    """Feature-specific limit blocks further calls for that feature."""
    uid = "quota-test-user"
    from app.services.ai_service import _consume_quota

    # Set image question limit to 1
    monkeypatch.setattr(get_settings(), "ai_daily_limit_image", 1)
    monkeypatch.setattr(get_settings(), "ai_daily_limit", 30)

    # Call 1: should succeed and consume 1 quota
    _consume_quota(uid, feature=AiFeature.IMAGE_QUESTION)

    # Verify usage reflected in get_ai_usage
    usage = get_ai_usage(uid)
    assert usage["features"][AiFeature.IMAGE_QUESTION]["used"] == 1
    assert usage["features"][AiFeature.IMAGE_QUESTION]["remaining"] == 0
    assert usage["total"]["used"] == 1

    # Call 2: exceeds feature limit of 1
    with pytest.raises(HTTPException) as exc_info:
        _consume_quota(uid, feature=AiFeature.IMAGE_QUESTION)

    assert exc_info.value.status_code == 429
    assert "image question" in exc_info.value.detail.lower()


@pytest.mark.asyncio
async def test_groq_to_gemini_fallback_on_429(fake_db, monkeypatch):
    """When GROQ returns 429 quota exceeded, service falls back to Gemini."""
    uid = "fallback-user-1"
    fake_db.seed("users", uid, {"role": "student"})

    monkeypatch.setattr(get_settings(), "groq_api_key", "fake-groq-key")
    monkeypatch.setattr(get_settings(), "gemini_api_key", "fake-gemini-key")
    monkeypatch.setattr(get_settings(), "openrouter_api_key", "fake-or-key")

    mock_groq = AsyncMock(side_effect=HTTPException(status_code=429, detail="GROQ quota exceeded"))
    mock_gemini = AsyncMock(return_value="Gemini response text")
    mock_or = AsyncMock(return_value="OpenRouter response text")

    monkeypatch.setattr("app.services.ai_service._groq_generate", mock_groq)
    monkeypatch.setattr("app.services.ai_service._gemini_generate", mock_gemini)
    monkeypatch.setattr("app.services.ai_service._openrouter_generate", mock_or)

    result = await generate(uid, "test prompt", feature=AiFeature.NOTE)
    assert result == "Gemini response text"
    assert mock_groq.call_count == 1
    assert mock_gemini.call_count == 1
    assert mock_or.call_count == 0


@pytest.mark.asyncio
async def test_groq_and_gemini_to_openrouter_fallback(fake_db, monkeypatch):
    """When GROQ (504 timeout) and Gemini (502 unavailable) both fail, falls back to OpenRouter."""
    uid = "fallback-user-2"
    fake_db.seed("users", uid, {"role": "student"})

    monkeypatch.setattr(get_settings(), "groq_api_key", "fake-groq-key")
    monkeypatch.setattr(get_settings(), "gemini_api_key", "fake-gemini-key")
    monkeypatch.setattr(get_settings(), "openrouter_api_key", "fake-or-key")

    mock_groq = AsyncMock(side_effect=HTTPException(status_code=504, detail="GROQ timeout"))
    mock_gemini = AsyncMock(side_effect=HTTPException(status_code=502, detail="Gemini temporarily unavailable"))
    mock_or = AsyncMock(return_value="OpenRouter emergency success")

    monkeypatch.setattr("app.services.ai_service._groq_generate", mock_groq)
    monkeypatch.setattr("app.services.ai_service._gemini_generate", mock_gemini)
    monkeypatch.setattr("app.services.ai_service._openrouter_generate", mock_or)

    result = await generate(uid, "test prompt", feature=AiFeature.NOTE)
    assert result == "OpenRouter emergency success"
    assert mock_groq.call_count == 1
    assert mock_gemini.call_count == 1
    assert mock_or.call_count == 1


@pytest.mark.asyncio
async def test_all_providers_fail_raises_last_error(fake_db, monkeypatch):
    """When all three providers fail, raises the last provider's HTTPException."""
    uid = "fallback-user-3"
    fake_db.seed("users", uid, {"role": "student"})

    monkeypatch.setattr(get_settings(), "groq_api_key", "fake-groq-key")
    monkeypatch.setattr(get_settings(), "gemini_api_key", "fake-gemini-key")
    monkeypatch.setattr(get_settings(), "openrouter_api_key", "fake-or-key")

    mock_groq = AsyncMock(side_effect=HTTPException(status_code=502, detail="GROQ down"))
    mock_gemini = AsyncMock(side_effect=HTTPException(status_code=502, detail="Gemini down"))
    mock_or = AsyncMock(side_effect=HTTPException(status_code=502, detail="OpenRouter down"))

    monkeypatch.setattr("app.services.ai_service._groq_generate", mock_groq)
    monkeypatch.setattr("app.services.ai_service._gemini_generate", mock_gemini)
    monkeypatch.setattr("app.services.ai_service._openrouter_generate", mock_or)

    with pytest.raises(HTTPException) as exc_info:
        await generate(uid, "test prompt", feature=AiFeature.NOTE)

    assert exc_info.value.status_code == 502
    assert "OpenRouter" in exc_info.value.detail or "down" in exc_info.value.detail


@pytest.mark.asyncio
async def test_multimodal_fallback_cascade(fake_db, monkeypatch):
    """Multimodal generation falls back through Groq vision -> Gemini -> OpenRouter."""
    uid = "fallback-user-4"
    fake_db.seed("users", uid, {"role": "student"})

    monkeypatch.setattr(get_settings(), "groq_api_key", "fake-groq-key")
    monkeypatch.setattr(get_settings(), "gemini_api_key", "fake-gemini-key")
    monkeypatch.setattr(get_settings(), "openrouter_api_key", "fake-or-key")

    mock_groq_vision = AsyncMock(side_effect=HTTPException(status_code=500, detail="GROQ vision internal error"))
    mock_gemini_vision = AsyncMock(side_effect=HTTPException(status_code=429, detail="Gemini quota exceeded"))
    mock_or_vision = AsyncMock(return_value="OpenRouter vision response")

    monkeypatch.setattr("app.services.ai_service._groq_generate_multimodal", mock_groq_vision)
    monkeypatch.setattr("app.services.ai_service._gemini_generate_multimodal", mock_gemini_vision)
    monkeypatch.setattr("app.services.ai_service._openrouter_generate_multimodal", mock_or_vision)

    parts = [{"text": "describe image"}]
    result = await generate_multimodal(uid, parts, feature=AiFeature.IMAGE_QUESTION)
    assert result == "OpenRouter vision response"
    assert mock_groq_vision.call_count == 1
    assert mock_gemini_vision.call_count == 1
    assert mock_or_vision.call_count == 1
