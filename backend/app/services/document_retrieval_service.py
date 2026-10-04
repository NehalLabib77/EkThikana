"""Phase 14.3 — Document Retrieval Service.

Deterministic BM25-style lexical retrieval over Firestore chunk subcollections.

Design decisions:
  - No embeddings / vector DB.  Academic text (formulas, theorem names, chapter
    keywords) achieves high precision with BM25 + heading/keyword boost.
  - Retrieval is scoped to a single student's material — cross-user reads are
    blocked by ownership verification BEFORE any Firestore access.
  - Context budget: returned chunks are capped at ~3 500 tokens (~14 000 chars)
    to stay within the AI provider context windows used in Phase 14.

Context budget: ~3 500 tokens ≈ 14 000 chars  (GPT-4 / Gemini token ratio ≈ 4)
"""

from __future__ import annotations

import logging
import math
import re
from typing import Any

from fastapi import HTTPException

from app.core.auth import CurrentUser
from app.core.firebase import get_firestore
from app.services.permission_service import get_material_for_user

logger = logging.getLogger("gochano.doc_retrieval")

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

CONTEXT_BUDGET_CHARS = 14_000   # ≈ 3 500 tokens
DEFAULT_TOP_K = 3
MAX_TOP_K = 8

_STOP_WORDS = frozenset({
    "the", "a", "an", "is", "it", "in", "of", "to", "and", "or", "for",
    "on", "at", "by", "this", "that", "with", "are", "was", "be", "as",
    "from", "what", "how", "why", "can", "will", "does",
    "এর", "এই", "এবং", "বা", "হয়", "না", "কে", "যে", "তা", "করে",
})


# ---------------------------------------------------------------------------
# Tokeniser
# ---------------------------------------------------------------------------

def _tokenize(text: str) -> list[str]:
    """Return lower-cased, stop-word-filtered word tokens."""
    words = re.findall(r"\b[A-Za-z\u0980-\u09FF]{2,}\b", text.lower())
    return [w for w in words if w not in _STOP_WORDS]


# ---------------------------------------------------------------------------
# BM25 Scoring
# ---------------------------------------------------------------------------

def _bm25_score(
    query_tokens: list[str],
    doc_tokens: list[str],
    k1: float = 1.5,
    b: float = 0.75,
    avg_dl: float = 300.0,
) -> float:
    """Simplified BM25 score for a single document against a query."""
    dl = len(doc_tokens)
    freq: dict[str, int] = {}
    for t in doc_tokens:
        freq[t] = freq.get(t, 0) + 1

    score = 0.0
    for qt in query_tokens:
        f = freq.get(qt, 0)
        if f == 0:
            continue
        idf = math.log(1 + 1.0)  # simplified; corpus IDF not available per-query
        tf_norm = (f * (k1 + 1)) / (f + k1 * (1 - b + b * dl / avg_dl))
        score += idf * tf_norm

    return score


# ---------------------------------------------------------------------------
# Heading / Section Boost
# ---------------------------------------------------------------------------

def _heading_boost(query_tokens: list[str], chunk: dict) -> float:
    """Extra score for query tokens appearing in section heading or keywords."""
    section_tokens = _tokenize(chunk.get("section") or "")
    keyword_tokens = [k.lower() for k in (chunk.get("keywords") or [])]
    boost = 0.0
    for qt in query_tokens:
        if qt in section_tokens:
            boost += 2.0
        if qt in keyword_tokens:
            boost += 1.0
    # Formula-dense chunks get a small boost for science / math queries
    if chunk.get("isFormulaDense") and any(
        c in " ".join(query_tokens) for c in ["formula", "equation", "derive", "proof"]
    ):
        boost += 0.5
    return boost


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def retrieve_relevant_chunks(
    uid: str,
    material_id: str,
    query: str,
    top_k: int = DEFAULT_TOP_K,
    user: CurrentUser | None = None,
) -> list[dict[str, Any]]:
    """Return the top-K most relevant chunks for ``query`` from the material.

    Ownership is verified via ``get_material_for_user`` before any read.

    Args:
        uid:         Student UID (used for ownership check when ``user`` is None).
        material_id: Firestore material document ID.
        query:       Free-text student query or topic description.
        top_k:       Maximum chunks to return (capped at MAX_TOP_K).
        user:        Authenticated user object.  If supplied, permission check
                     uses the canonical ``get_material_for_user``; otherwise
                     a lightweight UID-equality ownership check is done.

    Returns:
        List of chunk dicts (including citation fields) ordered by score desc,
        capped to CONTEXT_BUDGET_CHARS total.
    """
    top_k = max(1, min(top_k, MAX_TOP_K))
    db = get_firestore()

    # --- Ownership gate ---
    if user is not None:
        material = get_material_for_user(material_id, user)
    else:
        snap = db.collection("materials").document(material_id).get()
        if not snap.exists:
            raise HTTPException(status_code=404, detail="Material not found")
        material = snap.to_dict() or {}
        if material.get("ownerId") != uid:
            raise HTTPException(status_code=403, detail="Access denied")
        material["id"] = snap.id

    material_title = material.get("title", "")

    # --- Load chunks ---
    chunks_ref = (
        db.collection("materials")
        .document(material_id)
        .collection("chunks")
    )
    chunk_docs = list(chunks_ref.order_by("chunkIndex").stream())

    if not chunk_docs:
        return []

    # --- Score ---
    query_tokens = _tokenize(query)
    if not query_tokens:
        # Return first top_k chunks by index as fallback
        scored = [(0.0, doc.to_dict() or {}) for doc in chunk_docs[:top_k]]
    else:
        scored_list: list[tuple[float, dict]] = []
        for doc in chunk_docs:
            data = doc.to_dict() or {}
            doc_tokens = _tokenize(data.get("text", ""))
            score = _bm25_score(query_tokens, doc_tokens)
            score += _heading_boost(query_tokens, data)
            scored_list.append((score, data))
        # Deterministic sort: score desc, chunkIndex asc as tie-breaker
        scored = sorted(
            scored_list,
            key=lambda t: (-t[0], int(t[1].get("chunkIndex", 0))),
        )

    # --- Select top-K within context budget ---
    selected: list[dict] = []
    total_chars = 0
    for score_val, chunk in scored:
        if len(selected) >= top_k:
            break
        chunk_chars = int(chunk.get("characterCount") or len(chunk.get("text", "")))
        if total_chars + chunk_chars > CONTEXT_BUDGET_CHARS:
            # Include partial chunk only if nothing selected yet
            if not selected:
                chunk = dict(chunk)
                chunk["text"] = chunk["text"][:CONTEXT_BUDGET_CHARS]
                chunk["characterCount"] = len(chunk["text"])
            else:
                break
        selected.append({
            "chunkId": chunk.get("chunkId", ""),
            "materialId": material_id,
            "title": material_title,
            "page": chunk.get("page", 1),
            "endPage": chunk.get("endPage", chunk.get("page", 1)),
            "section": chunk.get("section", ""),
            "chapter": chunk.get("chapter", ""),
            "text": chunk.get("text", ""),
            "characterCount": chunk.get("characterCount", 0),
            "keywords": chunk.get("keywords", []),
            "isFormulaDense": chunk.get("isFormulaDense", False),
            "score": round(score_val, 4),
        })
        total_chars += chunk.get("characterCount", 0)

    return selected


def build_grounded_context(chunks: list[dict], max_chars: int = CONTEXT_BUDGET_CHARS) -> str:
    """Format retrieved chunks into a grounded-context string for the AI prompt."""
    parts: list[str] = []
    total = 0
    for chunk in chunks:
        citation = f"[p.{chunk.get('page', '?')}"
        section = chunk.get("section", "")
        if section:
            citation += f" | {section[:60]}"
        citation += "]"
        block = f"{citation}\n{chunk.get('text', '')}"
        if total + len(block) > max_chars:
            remaining = max_chars - total
            if remaining > 200:
                block = block[:remaining] + "…"
            else:
                break
        parts.append(block)
        total += len(block)
    return "\n\n---\n\n".join(parts)
