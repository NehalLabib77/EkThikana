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


_RETRIABLE_STATUSES: set[int] = {429, 500, 502, 503, 504}


def _is_retriable(exc: HTTPException) -> bool:
    """Return True if an HTTPException represents a retriable transient error."""
    if exc.status_code not in _RETRIABLE_STATUSES:
        return False
    if exc.status_code == 503 and "configuration" in str(exc.detail).lower():
        return False
    return True


# ---------------------------------------------------------------------------
# Feature definitions & quota limits
# ---------------------------------------------------------------------------
class AiFeature:
    CHAT = "chat"
    NOTE_AI = "note_ai"
    QUIZ = "quiz"
    STUDY_PLAN = "study_plan"

    # Phase 1 — mistake memory: one request analyses a whole batch of a
    # student's recorded mistakes (see mistake_memory_service).
    MISTAKE = "mistake_analysis"
    ADAPTIVE_TEXTBOOK = "adaptive_textbook"
    CONTENT = "content_generation"

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
    if feature in (AiFeature.MISTAKE, AiFeature.ADAPTIVE_TEXTBOOK, AiFeature.CONTENT):
        return settings.ai_limit_mistake_daily, "daily"
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
def quota_enforcement_enabled() -> bool:
    """True when Gochano's own AI limits return HTTP 429 (safe default)."""
    settings = get_settings()
    try:
        return bool(settings.ai_quota_enforcement)
    except AttributeError:  # pragma: no cover - older Settings objects
        return True


def _consume_quota(uid: str, feature: str = AiFeature.NOTE) -> None:
    settings = get_settings()
    feature_limit, period = _get_feature_limit(feature)
    enforce = quota_enforcement_enabled()

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
                if enforce:
                    feature_name = normalized.replace("_", " ")
                    raise HTTPException(
                        status_code=429,
                        detail=f"Monthly AI limit reached for {feature_name}",
                    )
                logger.warning(
                    "Monthly AI limit reached for %s but AI_QUOTA_ENFORCEMENT=false; "
                    "counter still increments.",
                    normalized,
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

            if feature_limit > 0 and current_active >= feature_limit and enforce:
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

            if enforce:
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
            elif feature_limit > 0 and current_feature >= feature_limit:
                logger.warning(
                    "Daily AI limit reached for %s but AI_QUOTA_ENFORCEMENT=false; "
                    "counter still increments.",
                    feature,
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


# ---------------------------------------------------------------------------
# Lifetime AI activity counters (server-side source of truth).
#
# One document per authenticated user: ``ai_usage_summary/{uid}``. Only
# integer counters are written — never prompt text, replies, materials, or
# any other user content. Every write is an atomic Firestore transaction and
# always keyed by the authenticated UID, so user A can never read or bump
# user B's numbers.
# ---------------------------------------------------------------------------
AI_ACTIVITY_TYPES: tuple[str, ...] = (
    "ai_chat_messages",
    "ai_notes",
    "pdf_questions",
    "image_questions",
    "quiz_generations",
    "quiz_questions",
    "assignment_uses",
    "planner_plans",
    "exam_rescue_plans",
    "study_recommendations",
    "commute_guides",
    "mistake_analyses",
    "content_explanations",
    "content_flashcards",
    "content_revision_sheets",
    "content_study_packs",
)


def record_ai_activity(uid: str, activity_type: str, count: int = 1) -> None:
    """Atomically bump lifetime AI usage counters for the authenticated user.

    Failures are logged but never break the AI response the user is waiting
    for: usage analytics must not take a working feature down.
    """
    if not uid or activity_type not in AI_ACTIVITY_TYPES:
        logger.warning("record_ai_activity ignored: invalid activity_type=%r", activity_type)
        return
    if count <= 0:
        return

    db = get_firestore()
    if db is None:
        return

    ref = db.collection("ai_usage_summary").document(uid)
    try:
        tx = db.transaction()

        @firestore.transactional
        def bump(transaction):
            snap = ref.get(transaction=transaction)
            data = snap.to_dict() if snap.exists else {}
            current = int(data.get(activity_type, 0) or 0)
            transaction.set(
                ref,
                {
                    "uid": uid,
                    activity_type: current + count,
                    "updatedAt": firestore.SERVER_TIMESTAMP,
                },
                merge=True,
            )

        bump(tx)
        event_name = {
            "ai_chat_messages": "ai_chat_used",
            "content_explanations": "ai_teacher_used",
            "content_flashcards": "content_generated",
            "content_revision_sheets": "content_generated",
            "content_study_packs": "study_pack_created",
        }.get(activity_type)
        if event_name:
            from app.services.analytics_service import track_event

            track_event(uid, event_name, {"feature": activity_type})
    except Exception:  # pragma: no cover - defensive
        logger.exception("record_ai_activity failed for activity_type=%s", activity_type)


def get_ai_activity_summary(uid: str) -> dict[str, int]:
    """Read one user's lifetime AI activity counters (own document only)."""
    db = get_firestore()
    counters: dict[str, int] = {key: 0 for key in AI_ACTIVITY_TYPES}
    if db is None:
        return counters
    try:
        snap = db.collection("ai_usage_summary").document(uid).get()
        data = snap.to_dict() if (snap is not None and snap.exists) else {}
    except Exception:  # pragma: no cover - defensive
        logger.exception("get_ai_activity_summary failed")
        return counters
    for key in AI_ACTIVITY_TYPES:
        try:
            counters[key] = int((data or {}).get(key, 0) or 0)
        except (TypeError, ValueError):
            counters[key] = 0
    return counters



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
        # Phase AI-FLOAT-1: lifetime activity inventory + enforcement switch.
        "quota_enforcement_enabled": quota_enforcement_enabled(),
        "summary": get_ai_activity_summary(uid),
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
    if isinstance(settings.groq_api_key, str) and settings.groq_api_key.strip():
        try:
            return await _groq_generate(prompt)
        except HTTPException as exc:
            if not _is_retriable(exc):
                raise
            logger.warning(
                "GROQ generate failed (status=%d, detail=%s). Falling back...",
                exc.status_code,
                exc.detail,
            )
            if not (isinstance(settings.gemini_api_key, str) and settings.gemini_api_key.strip()):
                raise HTTPException(
                    status_code=503, detail="AI service configuration error"
                ) from exc
            errors.append(("GROQ", exc))

    # 2. Secondary fallback: Gemini
    if isinstance(settings.gemini_api_key, str) and settings.gemini_api_key.strip():
        try:
            return await _gemini_generate(prompt)
        except HTTPException as exc:
            logger.warning(
                "Gemini generate failed (status=%d, detail=%s). Falling back...",
                exc.status_code,
                exc.detail,
            )
            if not (isinstance(settings.openrouter_api_key, str) and settings.openrouter_api_key.strip()):
                raise
            errors.append(("Gemini", exc))

    # 3. Tertiary emergency fallback: OpenRouter
    if isinstance(settings.openrouter_api_key, str) and settings.openrouter_api_key.strip():
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
    if isinstance(settings.groq_api_key, str) and settings.groq_api_key.strip():
        try:
            return await _groq_generate_multimodal(parts)
        except HTTPException as exc:
            if not _is_retriable(exc):
                raise
            logger.warning(
                "GROQ multimodal failed (status=%d, detail=%s). Falling back...",
                exc.status_code,
                exc.detail,
            )
            if not (isinstance(settings.gemini_api_key, str) and settings.gemini_api_key.strip()):
                raise HTTPException(
                    status_code=503, detail="AI service configuration error"
                ) from exc
            errors.append(("GROQ", exc))

    # 2. Secondary fallback: Gemini vision
    if isinstance(settings.gemini_api_key, str) and settings.gemini_api_key.strip():
        try:
            return await _gemini_generate_multimodal(parts)
        except HTTPException as exc:
            logger.warning(
                "Gemini multimodal failed (status=%d, detail=%s). Falling back...",
                exc.status_code,
                exc.detail,
            )
            if not (isinstance(settings.openrouter_api_key, str) and settings.openrouter_api_key.strip()):
                raise
            errors.append(("Gemini", exc))

    # 3. Tertiary emergency fallback: OpenRouter vision
    if isinstance(settings.openrouter_api_key, str) and settings.openrouter_api_key.strip():
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


# ---------------------------------------------------------------------------
# Multi-turn Ziku chat (Phase AI-FLOAT-1).
#
# The client sends the bounded conversation it already holds; the server is
# the source of truth for what is accepted and forwarded:
#   * only ``user`` / ``assistant`` roles are accepted,
#   * only the most recent CHAT_HISTORY_LIMIT turns are forwarded,
#   * the final message must be from the user,
#   * no prompt/reply content is ever written to usage analytics.
# ---------------------------------------------------------------------------
MAX_CHAT_MESSAGES = 20
CHAT_HISTORY_LIMIT = 10
CHAT_ALLOWED_ROLES = ("user", "assistant")


def normalize_chat_messages(raw: Any) -> list[dict[str, str]]:
    """Validate, order-preserve, and bound an inbound chat history.

    Returns the messages that will actually be forwarded to the model.
    Raises HTTPException(400) when the payload is malformed.
    """
    if not isinstance(raw, list) or not raw:
        raise HTTPException(status_code=400, detail="messages must be a non-empty list")

    cleaned: list[dict[str, str]] = []
    for item in raw:
        if not isinstance(item, dict):
            raise HTTPException(status_code=400, detail="each message must be an object")
        role = item.get("role")
        content = item.get("content")
        if role not in CHAT_ALLOWED_ROLES:
            raise HTTPException(status_code=400, detail="role must be 'user' or 'assistant'")
        if not isinstance(content, str) or not content.strip():
            raise HTTPException(status_code=400, detail="message content must be a non-empty string")
        if len(content) > 8000:
            raise HTTPException(status_code=400, detail="message content is too long")
        cleaned.append({"role": role, "content": content.strip()})

    if len(cleaned) > MAX_CHAT_MESSAGES:
        raise HTTPException(
            status_code=400,
            detail=f"messages must contain at most {MAX_CHAT_MESSAGES} entries",
        )
    if cleaned[-1]["role"] != "user":
        raise HTTPException(status_code=400, detail="last message must come from the user")

    # Bounded history: keep the most recent turns, always preserving order.
    return cleaned[-CHAT_HISTORY_LIMIT:]


def _academic_health_context(uid: str) -> str | None:
    """Score + weak topic + revision queue, or ``None`` when unavailable.

    Chat must never fail because scoring did, so every path here swallows.
    """
    try:
        from app.services.academic_health_service import chat_context_line

        return chat_context_line(uid)
    except Exception as exc:  # pragma: no cover - defensive
        logger.debug("academic health: chat context unavailable (%s)", exc)
        return None


def _coach_context(uid: str) -> str | None:
    """Today's Study Coach mission, or ``None`` when there is nothing to add.

    Phase 4 — Ziku answers with the student's real plan in hand (weakest
    topic, why it is weak, the mission steps, the exam countdown) instead of
    generic advice. The service is cache-first and swallows every failure, so
    a chat message can never go down with the coach.
    """
    try:
        from app.services.study_coach_service import chat_context

        return chat_context(uid)
    except Exception as exc:  # pragma: no cover - defensive
        logger.debug("study coach: chat context unavailable (%s)", exc)
        return None


def _adaptive_context(uid: str) -> str | None:
    """Phase 9 learning focus, kept optional so chat never depends on it."""
    try:
        from app.services.learning_memory_service import chat_context

        return chat_context(uid)
    except Exception as exc:  # pragma: no cover - defensive
        logger.debug("adaptive context unavailable (%s)", exc)
        return None


def build_chat_system_prompt(
    current_destination: str | None = None,
    app_mode: str | None = None,
    context_material_title: str | None = None,
    academic_health: str | None = None,
    coach_context: str | None = None,
    adaptive_context: str | None = None,
) -> str:
    lines = [
        "You are Ziku, the in-app study assistant for Gochano, a university "
        "student app in Bangladesh.",
        "Answer clearly and concisely. Stay on study, coursework, planning and "
        "exam topics. Never invent fees, dates, routes, medical or financial facts.",
        "Language policy — infer the student's language from their message and "
        "the conversation history (never ask a separate detection question):",
        "- Banglish (Bangla written in Latin/script letters, e.g. "
        '"amar kal exam ase kivabe porbo"): always reply in Bangla script '
        "(বাংলা). Never reply in Banglish.",
        "- Bangla script input: reply primarily in Bangla.",
        "- English input: reply in English.",
        "- Mixed Bangla + English input: use natural Bangla sentence structure "
        "while keeping useful English technical terms in English (e.g. API, "
        "Flutter, assignment, quiz, optical fiber, Total Internal Reflection, "
        "database, algorithm, exam, PDF, task, plan) instead of forcing "
        "awkward Bangla translations.",
        "- Never transliterate a whole Bangla reply into Latin/Banglish unless "
        'the student explicitly asks for it (e.g. "Banglish e bolo"); when they '
        "explicitly request Banglish, Banglish is allowed for that response.",
        "Apply these language rules to every reply, including follow-up turns "
        "in a multi-turn conversation.",
        "Format replies with plain paragraphs, **bold** for emphasis, and "
        "simple '- ' bullet or '1.' numbered lists when listing steps.",
    ]
    if context_material_title:
        lines.append(f"Attached study material: {context_material_title}.")
    if academic_health:
        lines.append(
            f"{academic_health} Use it to personalise advice; do not quote "
            "exact numbers back unless the student asks for them."
        )
    if coach_context:
        lines.append(
            f"Personalised plan: {coach_context} Use it to steer the advice "
            "and to open with what matters today. Weave it in naturally - "
            "never dump analytics, and never claim certainty beyond it."
        )
    if adaptive_context:
        lines.append(
            f"Adaptive learning focus: {adaptive_context} Use this to tailor "
            "the explanation and revision advice without dumping analytics."
        )
    if current_destination:
        lines.append(f"Student is currently on: {current_destination}.")
    if app_mode:
        lines.append(f"App mode: {app_mode}.")
    return "\n".join(lines)


def build_followup_suggestions(reply: str, last_user_text: str) -> list[str]:
    """Deterministic, context-aware follow-up chips for the next user turn.

    Deliberately not an extra model call: suggestions must never spend a
    second AI request (and second unit of quota) for one student message.
    """
    topic = " ".join((last_user_text or "").strip().split())[:80].strip(" ?.")
    reply_head = " ".join((reply or "").strip().split())[:80].strip(" ?.")

    if topic:
        candidates = [
            f"Explain {topic} more simply",
            f"Give me an example of {topic}",
            f"Quiz me on {topic}",
        ]
    else:
        candidates = []

    if reply_head:
        candidates.append(f"What should I read next about {reply_head}?")
    candidates.extend(
        [
            "How should I revise this for an exam?",
            "Make me 3 practice questions on this",
        ]
    )

    seen: set[str] = set()
    out: list[str] = []
    for cand in candidates:
        key = cand.lower()
        if key in seen or not cand.strip():
            continue
        seen.add(key)
        out.append(cand)
        if len(out) == 3:
            break
    return out


async def _post_openai_chat(
    url: str,
    headers: dict[str, str],
    payload: dict[str, Any],
    provider: str,
    model: str,
) -> str:
    """POST an OpenAI-style chat payload and return the assistant text."""
    logger.info("%s chat: model=%s messages=%d", provider, model, len(payload.get("messages", [])))
    try:
        response = await _http().post(url, headers=headers, json=payload)
    except httpx.TimeoutException as exc:
        logger.warning("%s chat timeout: %s", provider, exc)
        raise HTTPException(status_code=504, detail="AI request timed out.") from exc
    except httpx.HTTPError as exc:
        logger.warning("%s chat network error: %s", provider, exc)
        raise HTTPException(
            status_code=502, detail="AI provider temporarily unavailable."
        ) from exc

    if response.status_code >= 400:
        logger.warning(
            "%s chat error: status=%s model=%s body=%s",
            provider,
            response.status_code,
            model,
            _safe_snippet(response.text),
        )
        http_status, user_msg = _classify_ai_error(
            response.status_code, response.text, provider
        )
        raise HTTPException(status_code=http_status, detail=user_msg)

    data = response.json()
    try:
        text = data["choices"][0]["message"]["content"]
    except (KeyError, IndexError, TypeError):
        text = ""

    if not (text or "").strip():
        raise HTTPException(status_code=502, detail="AI provider returned no text")
    return text.strip()


async def _groq_chat(messages: list[dict[str, str]], system_prompt: str) -> str:
    settings = get_settings()
    if not (isinstance(settings.groq_api_key, str) and settings.groq_api_key.strip()):
        raise HTTPException(status_code=503, detail="AI service configuration error")

    payload = {
        "model": settings.groq_model,
        "messages": [
            {"role": "system", "content": system_prompt},
            *messages,
        ],
        "temperature": 0.4,
        "max_tokens": 1400,
    }
    return await _post_openai_chat(
        "https://api.groq.com/openai/v1/chat/completions",
        {
            "Authorization": f"Bearer {settings.groq_api_key}",
            "Content-Type": "application/json",
        },
        payload,
        "GROQ",
        settings.groq_model,
    )


async def _openrouter_chat(messages: list[dict[str, str]], system_prompt: str) -> str:
    settings = get_settings()
    if not (isinstance(settings.openrouter_api_key, str) and settings.openrouter_api_key.strip()):
        raise HTTPException(status_code=503, detail="AI service configuration error")

    base = (settings.openrouter_base_url or "https://openrouter.ai/api/v1").rstrip("/")
    payload = {
        "model": settings.openrouter_model,
        "messages": [
            {"role": "system", "content": system_prompt},
            *messages,
        ],
        "temperature": 0.4,
        "max_tokens": 1400,
    }
    return await _post_openai_chat(
        f"{base}/chat/completions",
        {
            "Authorization": f"Bearer {settings.openrouter_api_key}",
            "Content-Type": "application/json",
            "HTTP-Referer": "https://gochano.com",
            "X-Title": "Gochano",
        },
        payload,
        "OpenRouter",
        settings.openrouter_model,
    )


async def _gemini_chat(messages: list[dict[str, str]], system_prompt: str) -> str:
    settings = get_settings()
    if not (isinstance(settings.gemini_api_key, str) and settings.gemini_api_key.strip()):
        raise HTTPException(status_code=503, detail="AI service configuration error")

    # Gemini has no separate system channel in this payload shape, so the
    # system prompt is folded into the first turn (always a user turn).
    contents: list[dict[str, Any]] = []
    for idx, msg in enumerate(messages):
        role = "model" if msg["role"] == "assistant" else "user"
        text = msg["content"]
        if idx == 0:
            text = f"{system_prompt}\n\n{text}"
        contents.append({"role": role, "parts": [{"text": text}]})

    model = settings.gemini_model
    url = (
        "https://generativelanguage.googleapis.com/v1beta/models/"
        f"{model}:generateContent"
    )
    payload = {
        "contents": contents,
        "generationConfig": {"temperature": 0.4, "maxOutputTokens": 1400},
    }

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
        raise HTTPException(status_code=504, detail="AI request timed out.") from exc
    except httpx.HTTPError as exc:
        raise HTTPException(
            status_code=502, detail="AI provider temporarily unavailable."
        ) from exc

    if response.status_code >= 400:
        logger.warning(
            "Gemini chat error: status=%s model=%s body=%s",
            response.status_code,
            model,
            _safe_snippet(response.text),
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
        raise HTTPException(status_code=502, detail="AI provider returned no text")
    return text.strip()


async def chat_generate(
    uid: str,
    messages: list[dict[str, str]],
    current_destination: str | None = None,
    app_mode: str | None = None,
    context_material_title: str | None = None,
) -> dict[str, Any]:
    """Multi-turn chat with the same GROQ -> Gemini -> OpenRouter cascade.

    ``messages`` must already be normalized by :func:`normalize_chat_messages`.
    Returns ``{"reply": str, "suggested_followups": list[str]}``.
    """
    settings = get_settings()
    try:
        _consume_quota(uid, feature=AiFeature.CHAT)
    except TypeError:
        _consume_quota(uid)

    system_prompt = build_chat_system_prompt(
        current_destination=current_destination,
        app_mode=app_mode,
        context_material_title=context_material_title,
        academic_health=_academic_health_context(uid),
        coach_context=_coach_context(uid),
        adaptive_context=_adaptive_context(uid),
    )

    errors: list[tuple[str, HTTPException]] = []

    if isinstance(settings.groq_api_key, str) and settings.groq_api_key.strip():
        try:
            reply = await _groq_chat(messages, system_prompt)
            return {
                "reply": reply,
                "suggested_followups": build_followup_suggestions(
                    reply, messages[-1]["content"]
                ),
            }
        except HTTPException as exc:
            if not _is_retriable(exc):
                raise
            logger.warning("GROQ chat failed (status=%d). Falling back...", exc.status_code)
            if not (isinstance(settings.gemini_api_key, str) and settings.gemini_api_key.strip()):
                raise HTTPException(
                    status_code=503, detail="AI service configuration error"
                ) from exc
            errors.append(("GROQ", exc))

    if isinstance(settings.gemini_api_key, str) and settings.gemini_api_key.strip():
        try:
            reply = await _gemini_chat(messages, system_prompt)
            return {
                "reply": reply,
                "suggested_followups": build_followup_suggestions(
                    reply, messages[-1]["content"]
                ),
            }
        except HTTPException as exc:
            logger.warning("Gemini chat failed (status=%d). Falling back...", exc.status_code)
            if not (isinstance(settings.openrouter_api_key, str) and settings.openrouter_api_key.strip()):
                raise
            errors.append(("Gemini", exc))

    if isinstance(settings.openrouter_api_key, str) and settings.openrouter_api_key.strip():
        try:
            reply = await _openrouter_chat(messages, system_prompt)
            return {
                "reply": reply,
                "suggested_followups": build_followup_suggestions(
                    reply, messages[-1]["content"]
                ),
            }
        except HTTPException as exc:
            logger.warning("OpenRouter chat failed (status=%d).", exc.status_code)
            errors.append(("OpenRouter", exc))

    if not errors:
        logger.error("No AI provider configured for chat.")
        raise HTTPException(status_code=503, detail="AI service configuration error")

    raise errors[-1][1]
