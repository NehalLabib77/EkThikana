from __future__ import annotations

import base64
import logging
import re
from datetime import datetime, timezone
from typing import Any

import httpx
from fastapi import HTTPException
from firebase_admin import firestore

from app.core.config import get_settings
from app.core.firebase import get_firestore

logger = logging.getLogger("gochano.ai")

# ---------------------------------------------------------------------------
# Shared HTTP client. One per process keeps the TLS handshake warm between
# requests and gives us connection pooling for the long-lived Render service.
# ---------------------------------------------------------------------------
_client: httpx.AsyncClient | None = None


def _http() -> httpx.AsyncClient:
    global _client
    if _client is None:
        _client = httpx.AsyncClient(
            timeout=httpx.Timeout(90.0, connect=15.0),
            limits=httpx.Limits(max_connections=8, max_keepalive_connections=4),
        )
    return _client


# ---------------------------------------------------------------------------
# Error classification. GROQ returns OpenAI-style errors:
#   { "error": { "message": "...", "type": "...", "code": "..." } }
# Gemini returns RFC-7807 style:
#   { "error": { "code": 429, "status": "RESOURCE_EXHAUSTED", "message": "..." } }
# We map both shapes to user-facing messages.
# ---------------------------------------------------------------------------
_QUOTA_TOKENS = (
    "RESOURCE_EXHAUSTED",
    "QUOTA_EXCEEDED",
    "quota",
    "rate limit",
    "rate-limit",
    "requests",
)
_PERMISSION_TOKENS = (
    "PERMISSION_DENIED",
    "API_KEY_INVALID",
    "API key not valid",
    "API_KEY_NOT_VALID",
    "UNAUTHENTICATED",
    "invalid_api_key",
)
_MODEL_TOKENS = (
    "NOT_FOUND",
    "model not found",
    "MODEL_NOT_FOUND",
    "INVALID_MODEL",
)
_INVALID_ARG_TOKENS = (
    "INVALID_ARGUMENT",
    "INVALID_VALUE",
    "BAD_REQUEST",
)
_SERVER_TOKENS = (
    "UNAVAILABLE",
    "INTERNAL",
    "DEADLINE_EXCEEDED",
    "try again later",
)


def _classify_ai_error(
    status_code: int, body_text: str, provider: str
) -> tuple[int, str]:
    """Translate (status, body, provider) into (HTTP_status, user_facing_message)."""
    blob = (body_text or "").lower()
    status_token = ""
    msg_token = ""
    try:
        m = re.search(
            r'"status"\s*:\s*"([^"]+)"', body_text or "", re.IGNORECASE
        )
        if m:
            status_token = m.group(1).upper()
        m = re.search(
            r'"message"\s*:\s*"([^"\\]*(?:\\.[^"\\]*)*)"',
            body_text or "",
            re.IGNORECASE,
        )
        if m:
            msg_token = m.group(1).lower()
    except Exception:
        pass

    haystack = " ".join([status_token, msg_token, blob]).lower()

    if any(tok.lower() in haystack for tok in _QUOTA_TOKENS) or status_code == 429:
        return 429, f"{provider} quota exceeded. Please try again later."
    if any(tok.lower() in haystack for tok in _PERMISSION_TOKENS):
        return 503, "AI service configuration error"
    if any(tok.lower() in haystack for tok in _MODEL_TOKENS):
        return 503, f"{provider} model configuration error."
    if any(tok.lower() in haystack for tok in _INVALID_ARG_TOKENS) and status_code < 500:
        return 400, "Invalid AI request"
    if any(tok.lower() in haystack for tok in _SERVER_TOKENS) or status_code >= 500:
        return 502, "AI provider temporarily unavailable."
    if status_code < 500:
        return 503, "AI service configuration error"
    return 502, "AI provider temporarily unavailable."


def _safe_snippet(body_text: str, limit: int = 240) -> str:
    return (body_text or "")[:limit].replace("\n", " ").replace("\r", " ")


# ---------------------------------------------------------------------------
# Daily-quota gate. Atomic Firestore transaction per (uid, day).
# ---------------------------------------------------------------------------
def _consume_quota(uid: str) -> None:
    settings = get_settings()
    if settings.ai_daily_limit <= 0:
        return

    today = datetime.now(timezone.utc).strftime("%Y%m%d")
    ref = get_firestore().collection("ai_usage").document(f"{uid}_{today}")
    tx = get_firestore().transaction()

    @firestore.transactional
    def bump(transaction):
        snap = ref.get(transaction=transaction)
        current = 0
        if snap.exists:
            current = int((snap.to_dict() or {}).get("count", 0))
        if current >= settings.ai_daily_limit:
            raise HTTPException(
                status_code=429, detail="Daily AI limit reached"
            )
        transaction.set(
            ref,
            {
                "uid": uid,
                "day": today,
                "count": current + 1,
                "updatedAt": firestore.SERVER_TIMESTAMP,
            },
            merge=True,
        )

    bump(tx)


# ---------------------------------------------------------------------------
# GROQ provider (OpenAI-compatible API).
# ---------------------------------------------------------------------------
async def _groq_generate(prompt: str) -> str:
    """Send a text prompt to GROQ and return the response text."""
    settings = get_settings()
    if not settings.groq_api_key:
        raise HTTPException(
            status_code=503, detail="AI service configuration error"
        )

    url = "https://api.groq.com/openai/v1/chat/completions"
    payload = {
        "model": settings.groq_model,
        "messages": [{"role": "user", "content": prompt}],
        "temperature": 0.3,
        "max_tokens": 1600,
    }

    logger.info(
        "GROQ generate: model=%s prompt_chars=%d",
        settings.groq_model,
        len(prompt),
    )

    try:
        response = await _http().post(
            url,
            headers={
                "Authorization": f"Bearer {settings.groq_api_key}",
                "Content-Type": "application/json",
            },
            json=payload,
        )
    except httpx.TimeoutException as exc:
        logger.warning("GROQ timeout: %s", exc)
        raise HTTPException(
            status_code=504, detail="AI request timed out."
        ) from exc
    except httpx.HTTPError as exc:
        logger.exception("GROQ network error: %s", exc)
        raise HTTPException(
            status_code=502,
            detail="AI provider temporarily unavailable.",
        ) from exc

    if response.status_code >= 400:
        snippet = _safe_snippet(response.text)
        logger.warning(
            "GROQ error: status=%s model=%s body=%s",
            response.status_code,
            settings.groq_model,
            snippet,
        )
        http_status, user_msg = _classify_ai_error(
            response.status_code, response.text, "GROQ"
        )
        raise HTTPException(status_code=http_status, detail=user_msg)

    data = response.json()
    try:
        text = data["choices"][0]["message"]["content"]
    except (KeyError, IndexError, TypeError):
        text = ""

    if not text.strip():
        logger.warning(
            "GROQ returned no text. model=%s payload_keys=%s",
            settings.groq_model,
            list(data.keys()) if isinstance(data, dict) else type(data).__name__,
        )
        raise HTTPException(
            status_code=502, detail="AI provider returned no text"
        )
    return text.strip()


async def _groq_generate_multimodal(parts: list[dict[str, Any]]) -> str:
    """Send a multimodal prompt (text + inline image) to GROQ vision model."""
    settings = get_settings()
    if not settings.groq_api_key:
        raise HTTPException(
            status_code=503, detail="AI service configuration error"
        )

    # GROQ vision models accept base64 images via OpenAI image_url format.
    # Convert our Gemini-style {"inline_data": {...}} parts to OpenAI format.
    openai_parts: list[dict[str, Any]] = []
    for part in parts:
        if "text" in part:
            openai_parts.append({"type": "text", "text": part["text"]})
        elif "inline_data" in part:
            mime = part["inline_data"].get("mime_type", "image/jpeg")
            data = part["inline_data"].get("data", "")
            openai_parts.append({
                "type": "image_url",
                "image_url": {"url": f"data:{mime};base64,{data}"},
            })

    # Use a vision-capable model; fall back to configured model if not set.
    vision_model = settings.groq_model
    url = "https://api.groq.com/openai/v1/chat/completions"
    payload = {
        "model": vision_model,
        "messages": [{"role": "user", "content": openai_parts}],
        "temperature": 0.3,
        "max_tokens": 1600,
    }

    logger.info(
        "GROQ multimodal: model=%s parts=%d",
        vision_model,
        len(parts),
    )

    try:
        response = await _http().post(
            url,
            headers={
                "Authorization": f"Bearer {settings.groq_api_key}",
                "Content-Type": "application/json",
            },
            json=payload,
        )
    except httpx.TimeoutException as exc:
        logger.warning("GROQ timeout (multimodal): %s", exc)
        raise HTTPException(
            status_code=504, detail="AI request timed out."
        ) from exc
    except httpx.HTTPError as exc:
        logger.exception("GROQ network error (multimodal): %s", exc)
        raise HTTPException(
            status_code=502,
            detail="AI provider temporarily unavailable.",
        ) from exc

    if response.status_code >= 400:
        snippet = _safe_snippet(response.text)
        logger.warning(
            "GROQ error (multimodal): status=%s model=%s body=%s",
            response.status_code,
            vision_model,
            snippet,
        )
        http_status, user_msg = _classify_ai_error(
            response.status_code, response.text, "GROQ"
        )
        raise HTTPException(status_code=http_status, detail=user_msg)

    data = response.json()
    try:
        text = data["choices"][0]["message"]["content"]
    except (KeyError, IndexError, TypeError):
        text = ""

    if not text.strip():
        logger.warning(
            "GROQ returned no text (multimodal). model=%s",
            vision_model,
        )
        raise HTTPException(
            status_code=502, detail="AI provider returned no text"
        )
    return text.strip()


# ---------------------------------------------------------------------------
# Gemini fallback provider.
# ---------------------------------------------------------------------------
async def _gemini_generate(prompt: str) -> str:
    """Send a text prompt to Gemini and return the response text."""
    settings = get_settings()
    if not settings.gemini_api_key:
        raise HTTPException(
            status_code=503, detail="AI service configuration error"
        )

    model = settings.gemini_model
    url = (
        "https://generativelanguage.googleapis.com/v1beta/models/"
        f"{model}:generateContent"
    )
    payload = {
        "contents": [{"parts": [{"text": prompt}]}],
        "generationConfig": {
            "temperature": 0.3,
            "maxOutputTokens": 1600,
        },
    }

    logger.info(
        "Gemini fallback generate: model=%s prompt_chars=%d",
        model,
        len(prompt),
    )

    try:
        response = await _http().post(
            url,
            headers={
                "x-goog-api-key": settings.gemini_api_key,
                "Content-Type": "application/json",
            },
            json=payload,
        )
    except httpx.TimeoutException as exc:
        logger.warning("Gemini timeout: %s", exc)
        raise HTTPException(
            status_code=504, detail="AI request timed out."
        ) from exc
    except httpx.HTTPError as exc:
        logger.exception("Gemini network error: %s", exc)
        raise HTTPException(
            status_code=502,
            detail="AI provider temporarily unavailable.",
        ) from exc

    if response.status_code >= 400:
        snippet = _safe_snippet(response.text)
        logger.warning(
            "Gemini error: status=%s model=%s body=%s",
            response.status_code,
            model,
            snippet,
        )
        http_status, user_msg = _classify_ai_error(
            response.status_code, response.text, "Gemini"
        )
        raise HTTPException(status_code=http_status, detail=user_msg)

    data = response.json()
    try:
        parts = data["candidates"][0]["content"]["parts"]
        text = "\n".join(p.get("text", "") for p in parts if p.get("text"))
    except Exception:
        text = ""

    if not text.strip():
        logger.warning(
            "Gemini returned no text. model=%s payload_keys=%s",
            model,
            list(data.keys()) if isinstance(data, dict) else type(data).__name__,
        )
        raise HTTPException(
            status_code=502, detail="AI provider returned no text"
        )
    return text.strip()


async def _gemini_generate_multimodal(parts: list[dict[str, Any]]) -> str:
    """Send a multimodal prompt to Gemini."""
    settings = get_settings()
    if not settings.gemini_api_key:
        raise HTTPException(
            status_code=503, detail="AI service configuration error"
        )

    model = settings.gemini_model
    url = (
        "https://generativelanguage.googleapis.com/v1beta/models/"
        f"{model}:generateContent"
    )
    payload = {
        "contents": [{"parts": parts}],
        "generationConfig": {
            "temperature": 0.3,
            "maxOutputTokens": 1600,
        },
    }

    logger.info(
        "Gemini fallback multimodal: model=%s parts=%d",
        model,
        len(parts),
    )

    try:
        response = await _http().post(
            url,
            headers={
                "x-goog-api-key": settings.gemini_api_key,
                "Content-Type": "application/json",
            },
            json=payload,
        )
    except httpx.TimeoutException as exc:
        logger.warning("Gemini timeout (multimodal): %s", exc)
        raise HTTPException(
            status_code=504, detail="AI request timed out."
        ) from exc
    except httpx.HTTPError as exc:
        logger.exception("Gemini network error (multimodal): %s", exc)
        raise HTTPException(
            status_code=502,
            detail="AI provider temporarily unavailable.",
        ) from exc

    if response.status_code >= 400:
        snippet = _safe_snippet(response.text)
        logger.warning(
            "Gemini error (multimodal): status=%s model=%s body=%s",
            response.status_code,
            model,
            snippet,
        )
        http_status, user_msg = _classify_ai_error(
            response.status_code, response.text, "Gemini"
        )
        raise HTTPException(status_code=http_status, detail=user_msg)

    data = response.json()
    try:
        out_parts = data["candidates"][0]["content"]["parts"]
        text = "\n".join(p.get("text", "") for p in out_parts if p.get("text"))
    except Exception:
        text = ""

    if not text.strip():
        logger.warning(
            "Gemini returned no text (multimodal). model=%s",
            model,
        )
        raise HTTPException(
            status_code=502, detail="AI provider returned no text"
        )
    return text.strip()


# ---------------------------------------------------------------------------
# Public surface — GROQ primary, Gemini fallback.
# ---------------------------------------------------------------------------
async def generate(uid: str, prompt: str) -> str:
    """Text generation: tries GROQ first, falls back to Gemini."""
    settings = get_settings()
    _consume_quota(uid)

    # Try GROQ if configured.
    if settings.groq_api_key:
        try:
            return await _groq_generate(prompt)
        except HTTPException as exc:
            # If GROQ fails with a config error (bad key, wrong model),
            # fall through to Gemini. Other errors (timeout, rate limit)
            # are raised directly.
            if exc.status_code == 503 and "configuration" in (exc.detail or ""):
                logger.warning(
                    "GROQ config error, falling back to Gemini: %s",
                    exc.detail,
                )
            else:
                raise

    # Gemini fallback.
    if settings.gemini_api_key:
        return await _gemini_generate(prompt)

    logger.error("No AI provider configured (neither GROQ nor GEMINI_API_KEY).")
    raise HTTPException(
        status_code=503, detail="AI service configuration error"
    )


async def generate_multimodal(uid: str, parts: list[dict[str, Any]]) -> str:
    """Multimodal generation (image + text): tries GROQ vision, falls back to Gemini."""
    settings = get_settings()
    _consume_quota(uid)

    # Try GROQ vision if configured.
    if settings.groq_api_key:
        try:
            return await _groq_generate_multimodal(parts)
        except HTTPException as exc:
            if exc.status_code == 503 and "configuration" in (exc.detail or ""):
                logger.warning(
                    "GROQ config error (multimodal), falling back to Gemini: %s",
                    exc.detail,
                )
            else:
                raise

    # Gemini fallback.
    if settings.gemini_api_key:
        return await _gemini_generate_multimodal(parts)

    logger.error("No AI provider configured for multimodal (neither GROQ nor GEMINI_API_KEY).")
    raise HTTPException(
        status_code=503, detail="AI service configuration error"
    )
