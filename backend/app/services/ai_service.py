from datetime import datetime, timezone

import httpx
from fastapi import HTTPException
from firebase_admin import firestore

from app.core.config import get_settings
from app.core.firebase import get_firestore


def _consume_quota(uid: str):
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
            raise HTTPException(status_code=429, detail="Daily AI limit reached")
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


async def generate(uid: str, prompt: str) -> str:
    settings = get_settings()
    if not settings.gemini_api_key:
        raise HTTPException(status_code=503, detail="AI is not configured")

    _consume_quota(uid)

    url = (
        "https://generativelanguage.googleapis.com/v1beta/models/"
        f"{settings.gemini_model}:generateContent"
    )
    payload = {
        "contents": [{"parts": [{"text": prompt}]}],
        "generationConfig": {
            "temperature": 0.3,
            "maxOutputTokens": 1600,
        },
    }

    try:
        async with httpx.AsyncClient(timeout=90) as client:
            response = await client.post(
                url,
                headers={
                    "x-goog-api-key": settings.gemini_api_key,
                    "Content-Type": "application/json",
                },
                json=payload,
            )
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=502, detail=f"AI provider unavailable: {exc}")

    if response.status_code >= 400:
        raise HTTPException(status_code=502, detail="AI provider returned an error")

    data = response.json()
    try:
        parts = data["candidates"][0]["content"]["parts"]
        text = "\n".join(p.get("text", "") for p in parts if p.get("text"))
    except Exception:
        text = ""

    if not text.strip():
        raise HTTPException(status_code=502, detail="AI provider returned no text")
    return text.strip()
