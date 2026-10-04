"""Phase 14.3 — Document Intelligence Service.

Generates and caches document-level intelligence from chunked material:
  1. Overview (title, subject, page count, sections, reading time)
  2. Smart Summary (short, detailed, exam-focused)
  3. Concept Map (concepts + prerequisites + formulas)
  4. Important Topics (ranked by importance + source pages)

All results are stored in the Firestore subcollection:
  materials/{materialId}/intelligence/overview

Cache reuse: if the cached document matches the current INTELLIGENCE_VERSION
and ``force=False``, no AI calls are made.

AI routing reuses the existing ai_router_service tier classification
and the canonical ai_service.generate() cascade (Groq → Gemini → OpenRouter).
No second AI provider cascade is created.
"""

from __future__ import annotations

import json
import logging
import re
from datetime import datetime, timezone
from typing import Any

from fastapi import HTTPException

from app.core.auth import CurrentUser
from app.core.firebase import get_firestore
from app.services import ai_service
from app.services.permission_service import get_material_for_user
from app.services.document_retrieval_service import retrieve_relevant_chunks

logger = logging.getLogger("gochano.doc_intelligence")

INTELLIGENCE_VERSION = 1
INTEL_COLLECTION = "intelligence"
INTEL_DOC_ID = "overview"

STATUS_READY  = "ready"
STATUS_FAILED = "failed"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _parse_json(raw: Any, fallback: Any = None) -> Any:
    if isinstance(raw, (dict, list)):
        return raw
    text = str(raw or "").strip()
    # Strip markdown code fence
    if text.startswith("```"):
        text = text.split("\n", 1)[-1]
    if text.endswith("```"):
        text = text[:-3].rstrip()
    try:
        return json.loads(text)
    except (ValueError, TypeError):
        return fallback


def _safe_list(value: Any, max_items: int = 20) -> list:
    if isinstance(value, list):
        return value[:max_items]
    return []


def _truncate(text: str, limit: int) -> str:
    return text[:limit] if len(text) > limit else text


# ---------------------------------------------------------------------------
# Representative text for prompting
# ---------------------------------------------------------------------------

def _build_document_sample(material_id: str, uid: str, user: CurrentUser) -> str:
    """Return up to 6 000 chars of representative chunk text for overview generation."""
    try:
        db = get_firestore()
        chunks_ref = (
            db.collection("materials")
            .document(material_id)
            .collection("chunks")
        )
        docs = list(chunks_ref.order_by("chunkIndex").limit(8).stream())
        parts = []
        total = 0
        for doc in docs:
            text = (doc.to_dict() or {}).get("text", "")
            if total + len(text) > 6000:
                text = text[:6000 - total]
            parts.append(text)
            total += len(text)
            if total >= 6000:
                break
        return "\n\n---\n\n".join(parts)
    except Exception as exc:
        logger.warning("Could not build document sample for intelligence: %s", exc)
        return ""


# ---------------------------------------------------------------------------
# Tier 1 — Classification & Overview
# ---------------------------------------------------------------------------

async def _generate_overview(uid: str, sample: str, material: dict) -> dict:
    """Tier 1: Fast classification — title, subject, sections, reading time."""
    title = material.get("title", "Unknown Document")
    subject = material.get("subject", "")
    page_count = int(material.get("intelligenceTotalPages") or 0)
    word_count = int(material.get("intelligenceProcessedChars") or 0) // 5  # rough estimate
    reading_min = max(1, word_count // 200)
    chunk_count = int(material.get("intelligenceChunkCount") or 0)

    prompt = (
        f"You are an academic document classifier. Analyze this excerpt from a student's "
        f"study document and respond ONLY with valid JSON.\n\n"
        f"Title: {title}\n"
        f"Subject hint: {subject}\n"
        f"Pages: {page_count}\n\n"
        f"EXCERPT:\n{_truncate(sample, 3000)}\n\n"
        f"Respond with JSON:\n"
        f'{{"subject": "...", "chapter": "...", "detectedSections": ["sec1", "sec2"], "curriculumLevel": "SSC/HSC/Admission/University/Other"}}'
    )

    raw = ""
    try:
        raw = await ai_service.generate(uid, prompt, feature="keyword_extraction")
    except Exception as exc:
        logger.warning("Overview AI call failed: %s", exc)
        raw = "{}"

    parsed = _parse_json(raw, {})
    detected_sections = _safe_list(parsed.get("detectedSections") or [], 20)

    return {
        "title": title,
        "subject": parsed.get("subject") or subject or "",
        "chapter": parsed.get("chapter") or "",
        "curriculumLevel": parsed.get("curriculumLevel") or "",
        "pageCount": page_count,
        "wordCount": word_count,
        "estimatedReadMinutes": reading_min,
        "chunkCount": chunk_count,
        "detectedSections": [str(s)[:120] for s in detected_sections],
    }


# ---------------------------------------------------------------------------
# Tier 2 — Summary
# ---------------------------------------------------------------------------

async def _generate_summary(uid: str, sample: str, title: str) -> dict:
    """Tier 2: Analytical — short, detailed, and exam-focused summaries."""
    prompt = (
        f"You are an expert academic tutor. Summarize this study material for a Bangladeshi "
        f"student preparing for board/admission exams.\n\n"
        f"Document: {title}\n\n"
        f"EXCERPT:\n{_truncate(sample, 5000)}\n\n"
        f"Respond with JSON:\n"
        f'{{"short": "2-3 sentence overview", '
        f'"detailed": "5-8 sentence comprehensive summary covering main topics", '
        f'"examFocused": "3-5 most important exam points from this material"}}'
    )

    raw = ""
    try:
        raw = await ai_service.generate(uid, prompt, feature="content_generation")
    except Exception as exc:
        logger.warning("Summary AI call failed: %s", exc)
        raw = "{}"

    parsed = _parse_json(raw, {})
    return {
        "short": _truncate(str(parsed.get("short") or ""), 400),
        "detailed": _truncate(str(parsed.get("detailed") or ""), 1200),
        "examFocused": _truncate(str(parsed.get("examFocused") or ""), 800),
    }


# ---------------------------------------------------------------------------
# Tier 2 — Concept Map
# ---------------------------------------------------------------------------

async def _generate_concept_map(uid: str, sample: str, title: str) -> list[dict]:
    """Tier 2: Directed concept graph with prerequisites and formulas."""
    prompt = (
        f"You are an academic concept-map generator for a Bangladeshi student. "
        f"Extract a concept map from this study material.\n\n"
        f"Document: {title}\n\n"
        f"EXCERPT:\n{_truncate(sample, 4000)}\n\n"
        f"Return a JSON array (max 12 concepts):\n"
        f'[{{"name": "concept name", "description": "brief 1-sentence description", '
        f'"prerequisites": ["prereq1"], "formulas": ["formula1"]}}]'
    )

    raw = ""
    try:
        raw = await ai_service.generate(uid, prompt, feature="content_generation")
    except Exception as exc:
        logger.warning("Concept map AI call failed: %s", exc)
        raw = "[]"

    parsed = _parse_json(raw, [])
    if not isinstance(parsed, list):
        return []

    concept_map = []
    for item in parsed[:12]:
        if not isinstance(item, dict):
            continue
        concept_map.append({
            "name": _truncate(str(item.get("name") or ""), 120),
            "description": _truncate(str(item.get("description") or ""), 300),
            "prerequisites": [str(p)[:80] for p in _safe_list(item.get("prerequisites"), 5)],
            "formulas": [str(f)[:200] for f in _safe_list(item.get("formulas"), 5)],
        })
    return concept_map


# ---------------------------------------------------------------------------
# Tier 2 — Important Topics
# ---------------------------------------------------------------------------

async def _generate_important_topics(uid: str, material_id: str, sample: str, title: str, user: CurrentUser) -> list[dict]:
    """Tier 2: Ranked topics with source page citations."""
    prompt = (
        f"You are an academic priority analyst for Bangladeshi board/admission exams (SSC, HSC, University Admission). "
        f"Identify the most important exam topics from this study material.\n\n"
        f"Document: {title}\n\n"
        f"EXCERPT:\n{_truncate(sample, 4000)}\n\n"
        f"Return a JSON array (max 10 topics) sorted by importance:\n"
        f'[{{"topic": "topic name", "importanceScore": 0.9, '
        f'"keyInsight": "why this is exam-important (1 sentence)"}}]'
    )

    raw = ""
    try:
        raw = await ai_service.generate(uid, prompt, feature="content_generation")
    except Exception as exc:
        logger.warning("Important topics AI call failed: %s", exc)
        raw = "[]"

    parsed = _parse_json(raw, [])
    if not isinstance(parsed, list):
        return []

    # Enrich with source pages via retrieval
    topics_out = []
    for item in parsed[:10]:
        if not isinstance(item, dict):
            continue
        topic_name = str(item.get("topic") or "")[:120]
        source_pages: list[int] = []
        try:
            chunks = retrieve_relevant_chunks(uid, material_id, topic_name, top_k=2, user=user)
            source_pages = sorted({c.get("page", 1) for c in chunks if c.get("page")})
        except Exception:
            pass
        topics_out.append({
            "topic": topic_name,
            "importanceScore": min(1.0, max(0.0, float(item.get("importanceScore") or 0.5))),
            "sourcePages": source_pages[:5],
            "keyInsight": _truncate(str(item.get("keyInsight") or ""), 300),
        })

    return topics_out


# ---------------------------------------------------------------------------
# Cache layer
# ---------------------------------------------------------------------------

def _load_cached(material_id: str) -> dict | None:
    db = get_firestore()
    ref = (
        db.collection("materials")
        .document(material_id)
        .collection(INTEL_COLLECTION)
        .document(INTEL_DOC_ID)
    )
    snap = ref.get()
    if not snap.exists:
        return None
    data = snap.to_dict() or {}
    if int(data.get("intelligenceVersion") or 0) == INTELLIGENCE_VERSION:
        return data
    return None


def _store_cached(material_id: str, owner_id: str, payload: dict) -> None:
    db = get_firestore()
    ref = (
        db.collection("materials")
        .document(material_id)
        .collection(INTEL_COLLECTION)
        .document(INTEL_DOC_ID)
    )
    ref.set(payload)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

async def get_document_intelligence(
    material_id: str,
    user: CurrentUser,
    force: bool = False,
) -> dict[str, Any]:
    """Generate (or return cached) document intelligence.

    Checks ingestion status first — raises 409 if material is not yet ready.

    Args:
        material_id: Firestore material document ID.
        user:        Authenticated student.
        force:       Regenerate even if cached.
    """
    db = get_firestore()
    material = get_material_for_user(material_id, user)

    # Gate: must be processed first
    status = material.get("intelligenceStatus")
    if status != "ready":
        if status in ("extracting", "processing"):
            raise HTTPException(
                status_code=409,
                detail=f"Document is still being processed (status: {status}). Please try again shortly.",
            )
        raise HTTPException(
            status_code=409,
            detail=f"Document has not been processed yet (status: {status or 'uploaded'}). "
                   "Call POST /process first.",
        )

    # Serve from cache
    if not force:
        cached = _load_cached(material_id)
        if cached:
            logger.info("Serving cached intelligence for %s", material_id)
            return {**cached, "cached": True}

    uid = user.uid
    owner_id = material.get("ownerId", uid)
    title = material.get("title", "")

    # Build representative sample
    sample = _build_document_sample(material_id, uid, user)
    if not sample:
        raise HTTPException(status_code=422, detail="No chunk content available for intelligence generation.")

    truncated = bool(material.get("intelligenceTruncated"))

    # Run AI tiers
    overview = await _generate_overview(uid, sample, material)
    summary = await _generate_summary(uid, sample, title)
    concept_map = await _generate_concept_map(uid, sample, title)
    important_topics = await _generate_important_topics(uid, material_id, sample, title, user)

    payload: dict[str, Any] = {
        "status": STATUS_READY,
        "materialId": material_id,
        "ownerId": owner_id,
        "overview": overview,
        "summary": summary,
        "conceptMap": concept_map,
        "importantTopics": important_topics,
        "generatedAt": _now(),
        "intelligenceVersion": INTELLIGENCE_VERSION,
        "truncated": truncated,
    }

    # Cache it
    try:
        _store_cached(material_id, owner_id, payload)
    except Exception as exc:
        logger.warning("Failed to cache intelligence for %s: %s", material_id, exc)

    return {**payload, "cached": False}
