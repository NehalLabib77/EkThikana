"""Regression tests for the Groq → Gemini fallback policy (Phase 6.1).

The ``generate()`` function in ``app.services.ai_service`` must attempt
Gemini exactly once when Groq fails with a retriable provider error.
Non-retriable errors (400, 401, 403, config errors) must propagate
without triggering a Gemini attempt.
"""

from __future__ import annotations

import sys
from pathlib import Path
from unittest.mock import AsyncMock, patch, MagicMock

import pytest
from fastapi import HTTPException

_BACKEND_ROOT = Path(__file__).resolve().parent.parent
if str(_BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(_BACKEND_ROOT))

from app.services.ai_service import (
    _is_retriable,
    _RETRIABLE_STATUSES,
    generate,
    generate_multimodal,
)


# ---------------------------------------------------------------------------
# 1. _is_retriable() unit tests
# ---------------------------------------------------------------------------

class TestIsRetriable:
    """Unit tests for the centralised retriable-error decision."""

    @pytest.mark.parametrize("status", [429, 500, 502, 503, 504])
    def test_retriable_statuses(self, status):
        exc = HTTPException(status_code=status, detail="provider error")
        assert _is_retriable(exc) is True

    @pytest.mark.parametrize("status", [400, 401, 403])
    def test_non_retriable_client_errors(self, status):
        exc = HTTPException(status_code=status, detail="bad request")
        assert _is_retriable(exc) is False

    def test_config_error_503_is_not_retriable(self):
        """503 + 'configuration' indicates a bad API key — not transient."""
        exc = HTTPException(status_code=503, detail="AI service configuration error")
        assert _is_retriable(exc) is False

    def test_503_without_configuration_is_retriable(self):
        """503 without 'configuration' is a transient provider error."""
        exc = HTTPException(status_code=503, detail="AI provider temporarily unavailable.")
        assert _is_retriable(exc) is True

    def test_timeout_504_is_retriable(self):
        exc = HTTPException(status_code=504, detail="AI request timed out.")
        assert _is_retriable(exc) is True

    def test_network_error_502_is_retriable(self):
        exc = HTTPException(status_code=502, detail="AI provider temporarily unavailable.")
        assert _is_retriable(exc) is True

    def test_rate_limit_429_is_retriable(self):
        exc = HTTPException(status_code=429, detail="GROQ quota exceeded.")
        assert _is_retriable(exc) is True


# ---------------------------------------------------------------------------
# 2. generate() fallback integration tests
# ---------------------------------------------------------------------------

def _make_settings(groq_key="g-key", gemini_key="g-key"):
    """Return a minimal settings object with API keys."""
    s = MagicMock()
    s.groq_api_key = groq_key
    s.groq_model = "llama-3"
    s.gemini_api_key = gemini_key
    return s


class TestGenerateFallback:
    """Integration tests for generate() → Gemini fallback on retriable errors."""

    @pytest.mark.asyncio
    async def test_groq_success_no_fallback(self):
        """When Groq succeeds, Gemini is never called."""
        settings = _make_settings()
        with patch("app.services.ai_service.get_settings", return_value=settings), \
             patch("app.services.ai_service._consume_quota"), \
             patch("app.services.ai_service._groq_generate", new_callable=AsyncMock, return_value="groq answer") as mock_groq, \
             patch("app.services.ai_service._gemini_generate", new_callable=AsyncMock) as mock_gemini:
            result = await generate("uid", "test prompt")
        assert result == "groq answer"
        mock_groq.assert_called_once()
        mock_gemini.assert_not_called()

    @pytest.mark.asyncio
    @pytest.mark.parametrize("status,detail", [
        (429, "GROQ quota exceeded."),
        (500, "AI provider temporarily unavailable."),
        (502, "AI provider temporarily unavailable."),
        (503, "AI provider temporarily unavailable."),
        (504, "AI request timed out."),
    ])
    async def test_retriable_error_falls_back_to_gemini(self, status, detail):
        """Retriable Groq errors trigger exactly one Gemini attempt."""
        settings = _make_settings()
        groq_exc = HTTPException(status_code=status, detail=detail)
        with patch("app.services.ai_service.get_settings", return_value=settings), \
             patch("app.services.ai_service._consume_quota"), \
             patch("app.services.ai_service._groq_generate", new_callable=AsyncMock, side_effect=groq_exc), \
             patch("app.services.ai_service._gemini_generate", new_callable=AsyncMock, return_value="gemini answer") as mock_gemini:
            result = await generate("uid", "test prompt")
        assert result == "gemini answer"
        mock_gemini.assert_called_once()

    @pytest.mark.asyncio
    @pytest.mark.parametrize("status,detail", [
        (400, "Invalid AI request"),
        (401, "Unauthorized"),
        (403, "Forbidden"),
    ])
    async def test_non_retriable_error_propagates(self, status, detail):
        """Non-retriable errors propagate WITHOUT triggering Gemini."""
        settings = _make_settings()
        groq_exc = HTTPException(status_code=status, detail=detail)
        with patch("app.services.ai_service.get_settings", return_value=settings), \
             patch("app.services.ai_service._consume_quota"), \
             patch("app.services.ai_service._groq_generate", new_callable=AsyncMock, side_effect=groq_exc), \
             patch("app.services.ai_service._gemini_generate", new_callable=AsyncMock) as mock_gemini:
            with pytest.raises(HTTPException) as exc_info:
                await generate("uid", "test prompt")
        assert exc_info.value.status_code == status
        mock_gemini.assert_not_called()

    @pytest.mark.asyncio
    async def test_config_error_503_no_fallback(self):
        """503 + 'configuration' must NOT trigger Gemini — the config is broken."""
        settings = _make_settings()
        groq_exc = HTTPException(status_code=503, detail="AI service configuration error")
        with patch("app.services.ai_service.get_settings", return_value=settings), \
             patch("app.services.ai_service._consume_quota"), \
             patch("app.services.ai_service._groq_generate", new_callable=AsyncMock, side_effect=groq_exc), \
             patch("app.services.ai_service._gemini_generate", new_callable=AsyncMock) as mock_gemini:
            with pytest.raises(HTTPException) as exc_info:
                await generate("uid", "test prompt")
        assert exc_info.value.status_code == 503
        assert "configuration" in exc_info.value.detail
        mock_gemini.assert_not_called()

    @pytest.mark.asyncio
    async def test_gemini_failure_propagates(self):
        """When Groq fails AND Gemini also fails, the Gemini error propagates."""
        settings = _make_settings()
        groq_exc = HTTPException(status_code=502, detail="provider down")
        gemini_exc = HTTPException(status_code=502, detail="gemini down")
        with patch("app.services.ai_service.get_settings", return_value=settings), \
             patch("app.services.ai_service._consume_quota"), \
             patch("app.services.ai_service._groq_generate", new_callable=AsyncMock, side_effect=groq_exc), \
             patch("app.services.ai_service._gemini_generate", new_callable=AsyncMock, side_effect=gemini_exc):
            with pytest.raises(HTTPException) as exc_info:
                await generate("uid", "test prompt")
        assert "gemini" in exc_info.value.detail.lower() or "down" in exc_info.value.detail.lower()

    @pytest.mark.asyncio
    async def test_no_gemini_key_propagates_config_error(self):
        """When Gemini is not configured, retriable Groq errors yield 503 config error."""
        settings = _make_settings(gemini_key=None)
        groq_exc = HTTPException(status_code=502, detail="provider down")
        with patch("app.services.ai_service.get_settings", return_value=settings), \
             patch("app.services.ai_service._consume_quota"), \
             patch("app.services.ai_service._groq_generate", new_callable=AsyncMock, side_effect=groq_exc), \
             patch("app.services.ai_service._gemini_generate", new_callable=AsyncMock) as mock_gemini:
            with pytest.raises(HTTPException) as exc_info:
                await generate("uid", "test prompt")
        assert exc_info.value.status_code == 503
        assert "configuration" in exc_info.value.detail
        mock_gemini.assert_not_called()

    @pytest.mark.asyncio
    async def test_maximum_one_gemini_attempt(self):
        """Even if _gemini_generate is somehow called twice, only one attempt is made."""
        settings = _make_settings()
        groq_exc = HTTPException(status_code=429, detail="rate limited")
        with patch("app.services.ai_service.get_settings", return_value=settings), \
             patch("app.services.ai_service._consume_quota"), \
             patch("app.services.ai_service._groq_generate", new_callable=AsyncMock, side_effect=groq_exc), \
             patch("app.services.ai_service._gemini_generate", new_callable=AsyncMock, return_value="ok") as mock_gemini:
            result = await generate("uid", "test prompt")
        assert result == "ok"
        # generate() calls _gemini_generate exactly once, never loops
        mock_gemini.assert_called_once()


class TestGenerateMultimodalFallback:
    """Same fallback policy for generate_multimodal (image + text)."""

    @pytest.mark.asyncio
    async def test_groq_multimodal_success_no_fallback(self):
        settings = _make_settings()
        with patch("app.services.ai_service.get_settings", return_value=settings), \
             patch("app.services.ai_service._consume_quota"), \
             patch("app.services.ai_service._groq_generate_multimodal", new_callable=AsyncMock, return_value="groq vision"), \
             patch("app.services.ai_service._gemini_generate_multimodal", new_callable=AsyncMock) as mock_gemini:
            result = await generate_multimodal("uid", [{"text": "hi"}])
        assert result == "groq vision"
        mock_gemini.assert_not_called()

    @pytest.mark.asyncio
    async def test_retriable_error_falls_back_to_gemini_multimodal(self):
        settings = _make_settings()
        groq_exc = HTTPException(status_code=429, detail="rate limited")
        with patch("app.services.ai_service.get_settings", return_value=settings), \
             patch("app.services.ai_service._consume_quota"), \
             patch("app.services.ai_service._groq_generate_multimodal", new_callable=AsyncMock, side_effect=groq_exc), \
             patch("app.services.ai_service._gemini_generate_multimodal", new_callable=AsyncMock, return_value="gemini vision") as mock_gemini:
            result = await generate_multimodal("uid", [{"text": "hi"}])
        assert result == "gemini vision"
        mock_gemini.assert_called_once()

    @pytest.mark.asyncio
    async def test_non_retriable_error_propagates_multimodal(self):
        settings = _make_settings()
        groq_exc = HTTPException(status_code=400, detail="bad request")
        with patch("app.services.ai_service.get_settings", return_value=settings), \
             patch("app.services.ai_service._consume_quota"), \
             patch("app.services.ai_service._groq_generate_multimodal", new_callable=AsyncMock, side_effect=groq_exc), \
             patch("app.services.ai_service._gemini_generate_multimodal", new_callable=AsyncMock) as mock_gemini:
            with pytest.raises(HTTPException) as exc_info:
                await generate_multimodal("uid", [{"text": "hi"}])
        assert exc_info.value.status_code == 400
        mock_gemini.assert_not_called()


# ---------------------------------------------------------------------------
# 3. _classify_ai_error edge cases
# ---------------------------------------------------------------------------

from app.services.ai_service import _classify_ai_error


class TestClassifyAiError:
    def test_429_quota_returns_429(self):
        status, msg = _classify_ai_error(429, '{"error":{"message":"rate limit"}}', "GROQ")
        assert status == 429

    def test_500_server_error_returns_502(self):
        status, msg = _classify_ai_error(500, '{"error":{"message":"internal"}}', "GROQ")
        assert status == 502

    def test_400_bad_request_returns_400(self):
        status, msg = _classify_ai_error(400, '{"error":{"message":"INVALID_ARGUMENT"}}', "GROQ")
        assert status == 400

    def test_config_error_returns_503(self):
        status, msg = _classify_ai_error(401, '{"error":{"message":"API key not valid"}}', "GROQ")
        assert status == 503
        assert "configuration" in msg.lower()
