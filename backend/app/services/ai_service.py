from __future__ import annotations

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
# Gemini error classification. Gemini returns RFC-7807 style envelopes:
#   { "error": { "code": 429, "status": "RESOURCE_EXHAUSTED", "message": "..." } }
# We map the common shapes to user-facing messages.
# ---------------------------------------------------------------------------
_QUOTA_TOKENS = (
    "RESOURCE_EXHAUSTED",
    "QUOTA_EXCEEDED",
    "quota",
    "rate limit",
    "rate-limit",
)
_PERMISSION_TOKENS = (
    "PERMISSION_DENIED",
    "API_KEY_INVALID",
    "API key not valid",
    "API_KEY_NOT_VALID",
    "UNAUTHENTICATED",
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


def _classify_gemini_error(
    status_code: int, body_text: str
) -> tuple[int, str]:
    """Translate (status, body) into (HTTP_status, user_facing_message)."""
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
        return 429, "Gemini quota exceeded. Please try again later."
    if any(tok.lower() in haystack for tok in _PERMISSION_TOKENS):
        return 503, "AI service configuration error"
    if any(tok.lower() in haystack for tok in _MODEL_TOKENS):
        return 503, "Gemini model configuration error."
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
# Public surface.
# ---------------------------------------------------------------------------
async def generate(uid: str, prompt: str) -> str:
    settings = get_settings()
    if not settings.gemini_api_key:
        logger.error("GEMINI_API_KEY is empty on the server.")
        raise HTTPException(
            status_code=503, detail="AI service configuration error"
        )
    _consume_quota(uid)

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
        "AI generate: uid=%s model=%s prompt_chars=%d",
        uid,
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
        logger.warning("AI provider timeout: %s", exc)
        raise HTTPException(
            status_code=504, detail="AI request timed out."
        ) from exc
    except httpx.HTTPError as exc:
        logger.exception("AI provider network error: %s", exc)
        raise HTTPException(
            status_code=502,
            detail="AI provider temporarily unavailable.",
        ) from exc

    if response.status_code >= 400:
        snippet = _safe_snippet(response.text)
        logger.warning(
            "AI provider error: status=%s model=%s body=%s",
            response.status_code,
            model,
            snippet,
        )
        http_status, user_msg = _classify_gemini_error(
            response.status_code, response.text
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
            "AI provider returned no text. model=%s payload_keys=%s",
            model,
            list(data.keys()) if isinstance(data, dict) else type(data).__name__,
        )
        raise HTTPException(
            status_code=502, detail="AI provider returned no text"
        )
    return text.strip()


# ---------------------------------------------------------------------------
# Multimodal helper (image / scanned PDF). Accepts the same `parts` shape as
# the Gemini SDK: a list of {"text": ...} / {"inline_data": {...}} dicts.
# Used by the AI image / OCR flows.
# ---------------------------------------------------------------------------
async def generate_multimodal(uid: str, parts: list[dict[str, Any]]) -> str:
    """Send a multimodal prompt (text + inline image bytes) to Gemini."""
    settings = get_settings()
    if not settings.gemini_api_key:
        logger.error("GEMINI_API_KEY is empty on the server.")
        raise HTTPException(
            status_code=503, detail="AI service configuration error"
        )
    _consume_quota(uid)

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
        "AI multimodal: uid=%s model=%s parts=%d",
        uid,
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
        logger.warning("AI provider timeout (multimodal): %s", exc)
        raise HTTPException(
            status_code=504, detail="AI request timed out."
        ) from exc
    except httpx.HTTPError as exc:
        logger.exception("AI provider network error (multimodal): %s", exc)
        raise HTTPException(
            status_code=502,
            detail="AI provider temporarily unavailable.",
        ) from exc

    if response.status_code >= 400:
        snippet = _safe_snippet(response.text)
        logger.warning(
            "AI provider error (multimodal): status=%s model=%s body=%s",
            response.status_code,
            model,
            snippet,
        )
        http_status, user_msg = _classify_gemini_error(
            response.status_code, response.text
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
            "AI provider returned no text (multimodal). model=%s",
            model,
        )
        raise HTTPException(
            status_code=502, detail="AI provider returned no text"
        )
    return text.strip()
