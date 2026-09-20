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
# Feature definitions & quota limits
# ---------------------------------------------------------------------------
class AiFeature:
    CHAT = "chat"
    NOTE_AI = "note_ai"
    QUIZ = "quiz"
    STUDY_PLAN = "study_plan"

    # Legacy / alias features
    NOTE = "note"
    PDF_QUESTION = "pdf_question"
    IMAGE_QUESTION = "image_question"
    COMMUTE_GUIDE = "commute_guide"
    PRESCRIPTION = "prescription"


def _get_feature_limit(feature: str) -> tuple[int, str]:
    """Return (limit, period) where period is 'daily', 'monthly', or 'active'."""
    settings = get_settings()
    if feature == AiFeature.CHAT:
        return settings.ai_limit_chat_daily, "daily"
    if feature in (AiFeature.NOTE_AI, AiFeature.NOTE):
        return settings.ai_limit_note_monthly, "monthly"
    if feature == AiFeature.QUIZ:
        return settings.ai_limit_quiz_monthly, "monthly"
    if feature == AiFeature.STUDY_PLAN:
        return settings.ai_limit_study_plan_active, "active"
    if feature == AiFeature.PDF_QUESTION:
        return settings.ai_daily_limit_pdf, "daily"
    if feature == AiFeature.IMAGE_QUESTION:
        return settings.ai_daily_limit_image, "daily"
    if feature == AiFeature.COMMUTE_GUIDE:
        return settings.ai_daily_limit_commute, "daily"
    if feature == AiFeature.PRESCRIPTION:
        return settings.ai_daily_limit_prescription, "daily"
    return settings.ai_daily_limit, "daily"


def _get_legacy_feature_limit(feature: str) -> int:
    settings = get_settings()
    limits = {
        AiFeature.NOTE: settings.ai_limit_note_monthly,
        AiFeature.PDF_QUESTION: settings.ai_daily_limit_pdf,
        AiFeature.IMAGE_QUESTION: settings.ai_daily_limit_image,
        AiFeature.COMMUTE_GUIDE: settings.ai_daily_limit_commute,
        AiFeature.PRESCRIPTION: settings.ai_daily_limit_prescription,
    }
    return limits.get(feature, settings.ai_daily_limit)


# ---------------------------------------------------------------------------
# Quota gate. Atomic Firestore transaction per (uid, period).
# ---------------------------------------------------------------------------
def _consume_quota(uid: str, feature: str = AiFeature.NOTE) -> None:
    settings = get_settings()
    feature_limit, period = _get_feature_limit(feature)

    now = datetime.now(timezone.utc)
    today = now.strftime("%Y%m%d")
    this_month = now.strftime("%Y%m")

    db = get_firestore()
    if db is None:
        return

    if period == "monthly":
        normalized = "note_ai" if feature in (AiFeature.NOTE_AI, AiFeature.NOTE) else feature
        ref = db.collection("ai_usage_monthly").document(f"{uid}_{this_month}")
        tx = db.transaction()

        @firestore.transactional
        def bump_monthly(transaction):
            snap = ref.get(transaction=transaction)
            features_map: dict[str, int] = {}
            if snap.exists:
                doc_data = snap.to_dict() or {}
                features_map = dict(doc_data.get("features", {}) or {})

            current_feature = int(features_map.get(normalized, 0))
            if feature_limit > 0 and current_feature >= feature_limit:
                feature_name = normalized.replace("_", " ")
                raise HTTPException(
                    status_code=429,
                    detail=f"Monthly AI limit reached for {feature_name}",
                )

            features_map[normalized] = current_feature + 1
            transaction.set(
                ref,
                {
                    "uid": uid,
                    "month": this_month,
                    "features": features_map,
                    "updatedAt": firestore.SERVER_TIMESTAMP,
                },
                merge=True,
            )

        bump_monthly(tx)

    elif period == "active":
        ref = db.collection("ai_usage_active").document(uid)
        tx = db.transaction()

        @firestore.transactional
        def bump_active(transaction):
            snap = ref.get(transaction=transaction)
            current_active = 0
            if snap.exists:
                doc_data = snap.to_dict() or {}
                current_active = int(doc_data.get("study_plan", 0))

            if feature_limit > 0 and current_active >= feature_limit:
                raise HTTPException(
                    status_code=429,
                    detail="Active study plan limit reached. Complete or archive existing plan first.",
                )

            transaction.set(
                ref,
                {
                    "uid": uid,
                    "study_plan": current_active + 1,
                    "updatedAt": firestore.SERVER_TIMESTAMP,
                },
                merge=True,
            )

        bump_active(tx)

    else:
        # Daily period (chat, legacy features)
        ref = db.collection("ai_usage").document(f"{uid}_{today}")
        tx = db.transaction()

        @firestore.transactional
        def bump_daily(transaction):
            snap = ref.get(transaction=transaction)
            current_total = 0
            features_map: dict[str, int] = {}
            if snap.exists:
                doc_data = snap.to_dict() or {}
                current_total = int(doc_data.get("count", 0))
                features_map = dict(doc_data.get("features", {}) or {})

            current_feature = int(features_map.get(feature, 0))

            if settings.ai_daily_limit > 0 and current_total >= settings.ai_daily_limit:
                raise HTTPException(
                    status_code=429, detail="Daily AI limit reached"
                )
            if feature_limit > 0 and current_feature >= feature_limit:
                feature_name = feature.replace("_", " ")
                raise HTTPException(
                    status_code=429,
                    detail=f"Daily AI limit reached for {feature_name}",
                )

            features_map[feature] = current_feature + 1
            transaction.set(
                ref,
                {
                    "uid": uid,
                    "day": today,
                    "count": current_total + 1,
                    "features": features_map,
                    "updatedAt": firestore.SERVER_TIMESTAMP,
                },
                merge=True,
            )

        bump_daily(tx)


def get_ai_usage(uid: str) -> dict[str, Any]:
    """Retrieve AI usage counters and remaining limits for the user."""
    settings = get_settings()
    now = datetime.now(timezone.utc)
    today = now.strftime("%Y%m%d")
    this_month = now.strftime("%Y%m")
    db = get_firestore()

    # Daily document
    snap_daily = db.collection("ai_usage").document(f"{uid}_{today}").get() if db is not None else None
    daily_data = (snap_daily.to_dict() or {}) if (snap_daily is not None and snap_daily.exists) else {}
    current_total = int(daily_data.get("count", 0))
    daily_features = dict(daily_data.get("features", {}) or {})

    # Monthly document
    snap_monthly = db.collection("ai_usage_monthly").document(f"{uid}_{this_month}").get() if db is not None else None
    monthly_data = (snap_monthly.to_dict() or {}) if (snap_monthly is not None and snap_monthly.exists) else {}
    monthly_features = dict(monthly_data.get("features", {}) or {})

    # Active document
    snap_active = db.collection("ai_usage_active").document(uid).get() if db is not None else None
    active_data = (snap_active.to_dict() or {}) if (snap_active is not None and snap_active.exists) else {}
    active_plans = int(active_data.get("study_plan", 0))

    # Phase 3A: Four feature usage limits
    chat_used = int(daily_features.get(AiFeature.CHAT, 0))
    chat_limit = settings.ai_limit_chat_daily
    chat_remaining = max(0, chat_limit - chat_used) if chat_limit > 0 else -1

    note_used = int(monthly_features.get("note_ai", 0))
    note_limit = settings.ai_limit_note_monthly
    note_remaining = max(0, note_limit - note_used) if note_limit > 0 else -1

    quiz_used = int(monthly_features.get(AiFeature.QUIZ, 0))
    quiz_limit = settings.ai_limit_quiz_monthly
    quiz_remaining = max(0, quiz_limit - quiz_used) if quiz_limit > 0 else -1

    study_plan_used = active_plans
    study_plan_limit = settings.ai_limit_study_plan_active
    study_plan_remaining = max(0, study_plan_limit - study_plan_used) if study_plan_limit > 0 else -1

    # Legacy features structure
    all_features = [
        AiFeature.NOTE,
        AiFeature.PDF_QUESTION,
        AiFeature.IMAGE_QUESTION,
        AiFeature.COMMUTE_GUIDE,
        AiFeature.PRESCRIPTION,
    ]
    features_status: dict[str, dict[str, int]] = {}
    for f in all_features:
        f_limit = _get_legacy_feature_limit(f)
        if f == AiFeature.NOTE:
            f_used = note_used
            f_rem = note_remaining
        else:
            f_used = int(daily_features.get(f, 0))
            f_rem = max(0, f_limit - f_used) if f_limit > 0 else -1
        features_status[f] = {
            "used": f_used,
            "limit": f_limit,
            "remaining": f_rem,
        }

    total_remaining = (
        max(0, settings.ai_daily_limit - current_total)
        if settings.ai_daily_limit > 0
        else -1
    )

    return {
        "chat": {
            "used": chat_used,
            "limit": chat_limit,
            "remaining": chat_remaining,
        },
        "note_ai": {
            "used": note_used,
            "limit": note_limit,
            "remaining": note_remaining,
        },
        "quiz": {
            "used": quiz_used,
            "limit": quiz_limit,
            "remaining": quiz_remaining,
        },
        "study_plan": {
            "used": study_plan_used,
            "limit": study_plan_limit,
            "remaining": study_plan_remaining,
        },
        "day": today,
        "total": {
            "used": current_total,
            "limit": settings.ai_daily_limit,
            "remaining": total_remaining,
        },
        "features": features_status,
    }


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
# OpenRouter emergency fallback provider (OpenAI-compatible API).
# ---------------------------------------------------------------------------
async def _openrouter_generate(prompt: str) -> str:
    """Send a text prompt to OpenRouter and return the response text."""
    settings = get_settings()
    if not settings.openrouter_api_key:
        raise HTTPException(
            status_code=503, detail="AI service configuration error"
        )

    base = (settings.openrouter_base_url or "https://openrouter.ai/api/v1").rstrip("/")
    url = f"{base}/chat/completions"
    payload = {
        "model": settings.openrouter_model,
        "messages": [{"role": "user", "content": prompt}],
        "temperature": 0.3,
        "max_tokens": 1600,
    }

    logger.info(
        "OpenRouter generate: model=%s prompt_chars=%d",
        settings.openrouter_model,
        len(prompt),
    )

    try:
        response = await _http().post(
            url,
            headers={
                "Authorization": f"Bearer {settings.openrouter_api_key}",
                "Content-Type": "application/json",
                "HTTP-Referer": "https://gochano.com",
                "X-Title": "Gochano",
            },
            json=payload,
        )
    except httpx.TimeoutException as exc:
        logger.warning("OpenRouter timeout: %s", exc)
        raise HTTPException(
            status_code=504, detail="AI request timed out."
        ) from exc
    except httpx.HTTPError as exc:
        logger.exception("OpenRouter network error: %s", exc)
        raise HTTPException(
            status_code=502,
            detail="AI provider temporarily unavailable.",
        ) from exc

    if response.status_code >= 400:
        snippet = _safe_snippet(response.text)
        logger.warning(
            "OpenRouter error: status=%s model=%s body=%s",
            response.status_code,
            settings.openrouter_model,
            snippet,
        )
        http_status, user_msg = _classify_ai_error(
            response.status_code, response.text, "OpenRouter"
        )
        raise HTTPException(status_code=http_status, detail=user_msg)

    data = response.json()
    try:
        text = data["choices"][0]["message"]["content"]
    except (KeyError, IndexError, TypeError):
        text = ""

    if not text.strip():
        logger.warning(
            "OpenRouter returned no text. model=%s payload_keys=%s",
            settings.openrouter_model,
            list(data.keys()) if isinstance(data, dict) else type(data).__name__,
        )
        raise HTTPException(
            status_code=502, detail="AI provider returned no text"
        )
    return text.strip()


async def _openrouter_generate_multimodal(parts: list[dict[str, Any]]) -> str:
    """Send a multimodal prompt (text + inline image) to OpenRouter vision model."""
    settings = get_settings()
    if not settings.openrouter_api_key:
        raise HTTPException(
            status_code=503, detail="AI service configuration error"
        )

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

    base = (settings.openrouter_base_url or "https://openrouter.ai/api/v1").rstrip("/")
    url = f"{base}/chat/completions"
    payload = {
        "model": settings.openrouter_model,
        "messages": [{"role": "user", "content": openai_parts}],
        "temperature": 0.3,
        "max_tokens": 1600,
    }

    logger.info(
        "OpenRouter multimodal: model=%s parts=%d",
        settings.openrouter_model,
        len(parts),
    )

    try:
        response = await _http().post(
            url,
            headers={
                "Authorization": f"Bearer {settings.openrouter_api_key}",
                "Content-Type": "application/json",
                "HTTP-Referer": "https://gochano.com",
                "X-Title": "Gochano",
            },
            json=payload,
        )
    except httpx.TimeoutException as exc:
        logger.warning("OpenRouter timeout (multimodal): %s", exc)
        raise HTTPException(
            status_code=504, detail="AI request timed out."
        ) from exc
    except httpx.HTTPError as exc:
        logger.exception("OpenRouter network error (multimodal): %s", exc)
        raise HTTPException(
            status_code=502,
            detail="AI provider temporarily unavailable.",
        ) from exc

    if response.status_code >= 400:
        snippet = _safe_snippet(response.text)
        logger.warning(
            "OpenRouter error (multimodal): status=%s model=%s body=%s",
            response.status_code,
            settings.openrouter_model,
            snippet,
        )
        http_status, user_msg = _classify_ai_error(
            response.status_code, response.text, "OpenRouter"
        )
        raise HTTPException(status_code=http_status, detail=user_msg)

    data = response.json()
    try:
        text = data["choices"][0]["message"]["content"]
    except (KeyError, IndexError, TypeError):
        text = ""

    if not text.strip():
        logger.warning(
            "OpenRouter returned no text (multimodal). model=%s",
            settings.openrouter_model,
        )
        raise HTTPException(
            status_code=502, detail="AI provider returned no text"
        )
    return text.strip()


# ---------------------------------------------------------------------------
# Public surface — Cascade: GROQ primary -> Gemini fallback -> OpenRouter emergency.
# ---------------------------------------------------------------------------
async def generate(uid: str, prompt: str, feature: str = AiFeature.NOTE) -> str:
    """Text generation: tries GROQ, falls back to Gemini, then OpenRouter."""
    settings = get_settings()
    try:
        _consume_quota(uid, feature=feature)
    except TypeError:
        _consume_quota(uid)

    errors: list[tuple[str, HTTPException]] = []

    # 1. Primary: GROQ
    if settings.groq_api_key:
        try:
            return await _groq_generate(prompt)
        except HTTPException as exc:
            logger.warning(
                "GROQ generate failed (status=%d, detail=%s). Falling back...",
                exc.status_code,
                exc.detail,
            )
            errors.append(("GROQ", exc))

    # 2. Secondary fallback: Gemini
    if settings.gemini_api_key:
        try:
            return await _gemini_generate(prompt)
        except HTTPException as exc:
            logger.warning(
                "Gemini generate failed (status=%d, detail=%s). Falling back...",
                exc.status_code,
                exc.detail,
            )
            errors.append(("Gemini", exc))

    # 3. Tertiary emergency fallback: OpenRouter
    if settings.openrouter_api_key:
        try:
            return await _openrouter_generate(prompt)
        except HTTPException as exc:
            logger.warning(
                "OpenRouter generate failed (status=%d, detail=%s).",
                exc.status_code,
                exc.detail,
            )
            errors.append(("OpenRouter", exc))

    if not errors:
        logger.error(
            "No AI provider configured (GROQ, GEMINI, and OPENROUTER all unconfigured)."
        )
        raise HTTPException(
            status_code=503, detail="AI service configuration error"
        )

    # All attempted providers failed. Re-raise the most informative error.
    provider, last_err = errors[-1]
    logger.error(
        "All AI providers exhausted (%s). Final error from %s: %s",
        ", ".join(p for p, _ in errors),
        provider,
        last_err.detail,
    )
    raise last_err


async def generate_multimodal(
    uid: str,
    parts: list[dict[str, Any]],
    feature: str = AiFeature.IMAGE_QUESTION,
) -> str:
    """Multimodal generation: tries GROQ vision, falls back to Gemini, then OpenRouter."""
    settings = get_settings()
    try:
        _consume_quota(uid, feature=feature)
    except TypeError:
        _consume_quota(uid)

    errors: list[tuple[str, HTTPException]] = []

    # 1. Primary: GROQ vision
    if settings.groq_api_key:
        try:
            return await _groq_generate_multimodal(parts)
        except HTTPException as exc:
            logger.warning(
                "GROQ multimodal failed (status=%d, detail=%s). Falling back...",
                exc.status_code,
                exc.detail,
            )
            errors.append(("GROQ", exc))

    # 2. Secondary fallback: Gemini vision
    if settings.gemini_api_key:
        try:
            return await _gemini_generate_multimodal(parts)
        except HTTPException as exc:
            logger.warning(
                "Gemini multimodal failed (status=%d, detail=%s). Falling back...",
                exc.status_code,
                exc.detail,
            )
            errors.append(("Gemini", exc))

    # 3. Tertiary emergency fallback: OpenRouter vision
    if settings.openrouter_api_key:
        try:
            return await _openrouter_generate_multimodal(parts)
        except HTTPException as exc:
            logger.warning(
                "OpenRouter multimodal failed (status=%d, detail=%s).",
                exc.status_code,
                exc.detail,
            )
            errors.append(("OpenRouter", exc))

    if not errors:
        logger.error(
            "No AI provider configured for multimodal generation."
        )
        raise HTTPException(
            status_code=503, detail="AI service configuration error"
        )

    provider, last_err = errors[-1]
    logger.error(
        "All multimodal AI providers exhausted (%s). Final error from %s: %s",
        ", ".join(p for p, _ in errors),
        provider,
        last_err.detail,
    )
    raise last_err
