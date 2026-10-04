"""Phase 15.1 — Past Question Intelligence Service.

Transforms existing Workspace materials (processed by Phase 14 Document
Ingestion) into structured exam-paper intelligence.

Design principles
-----------------
* REUSE Phase 14 chunks — never re-download or re-extract the raw file.
* Deterministic parsing first; AI only for topic classification where
  necessary.
* Idempotent: same materialId + analysisVersion → return cache unless
  force=True.
* No fabricated metadata — unknown fields stay null/unknown.
* Topic normalization aligns with canonical Learning Memory topics.
* No guaranteed-exam-prediction language anywhere.
"""

from __future__ import annotations

import hashlib
import json
import logging
import re
import uuid
from datetime import datetime, timezone
from typing import Any

from fastapi import HTTPException

from app.core.firebase import get_firestore
from app.services import ai_service
from app.services.ai_service import AiFeature
from app.services.permission_service import get_material_for_user

logger = logging.getLogger("gochano.past_paper")

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

ANALYSIS_VERSION = 1  # bump → forces re-analysis of all cached papers

# Firestore paths (user-scoped exam ecosystem)
EXAM_ECOSYSTEM_COL = "exam_ecosystem"
PAST_PAPERS_SUB = "past_papers"
TOPIC_STATS_SUB = "topic_stats"
QUESTIONS_SUB = "paper_questions"

# Deterministic question-type detection
_MCQ_OPTION_RE = re.compile(
    r"^\s*(?:[a-dA-D][).\]]|[iI]{1,3}[).\]]|\([a-dA-D]\))\s+\S",
    re.MULTILINE,
)
_QUESTION_NUM_RE = re.compile(
    r"^\s*(?:Q\.?\s*)?(\d+)[\s\.\)]\s+\S", re.MULTILINE | re.IGNORECASE
)
_MARKS_RE = re.compile(r"\[\s*(\d+)\s*(?:marks?|M)\s*\]", re.IGNORECASE)
_YEAR_RE = re.compile(r"\b(19|20)\d{2}\b")
_BOARD_KEYWORDS = {
    "bise": "BISE",
    "fbise": "FBISE",
    "edexcel": "Edexcel",
    "cambridge": "Cambridge",
    "ib": "IB",
    "cbse": "CBSE",
    "o level": "O-Level",
    "a level": "A-Level",
}
_SECTION_RE = re.compile(
    r"^\s*(?:section|part)\s+[a-zA-Z0-9]+\b", re.MULTILINE | re.IGNORECASE
)

# Topic normalization — strip trailing plural / common variants
_TOPIC_NORMALIZE_RE = re.compile(r"[''\"']s?\b|\blaw\b.*|s$", re.IGNORECASE)

# Supported question types (normalized)
VALID_Q_TYPES = frozenset([
    "mcq", "short", "creative", "essay", "numerical",
    "definition", "problem_solving", "mixed", "unknown",
])


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

def _now() -> datetime:
    return datetime.now(timezone.utc)


def _nowiso() -> str:
    return _now().isoformat()


def _db():
    db = get_firestore()
    if db is None:  # pragma: no cover
        raise HTTPException(status_code=503, detail="Database unavailable")
    return db


def _paper_col(uid: str):
    return _db().collection("users").document(uid).collection(
        EXAM_ECOSYSTEM_COL
    ).document("default").collection(PAST_PAPERS_SUB)


def _questions_col(uid: str):
    return _db().collection("users").document(uid).collection(
        EXAM_ECOSYSTEM_COL
    ).document("default").collection(QUESTIONS_SUB)


def _topic_stats_col(uid: str):
    return _db().collection("users").document(uid).collection(
        EXAM_ECOSYSTEM_COL
    ).document("default").collection(TOPIC_STATS_SUB)


def _load_chunks(material_id: str) -> list[dict[str, Any]]:
    """Load Phase 14 chunks for a material."""
    db = _db()
    try:
        docs = (
            db.collection("materials")
            .document(material_id)
            .collection("chunks")
            .order_by("chunkIndex")
            .limit(600)
            .stream()
        )
        return [d.to_dict() or {} for d in docs]
    except Exception as exc:
        logger.warning("Failed to load chunks for %s: %s", material_id, exc)
        return []


def _full_text_from_chunks(chunks: list[dict]) -> str:
    parts = []
    for c in chunks:
        text = c.get("text") or c.get("content") or ""
        if text.strip():
            parts.append(text.strip())
    return "\n\n".join(parts)


def _detect_year(text: str) -> int | None:
    match = _YEAR_RE.search(text[:2000])
    if match:
        year = int(match.group())
        if 1980 <= year <= _now().year:
            return year
    return None


def _detect_board(text: str) -> str | None:
    lower = text[:3000].lower()
    for key, label in _BOARD_KEYWORDS.items():
        if key in lower:
            return label
    return None


def _detect_total_marks(text: str) -> int | None:
    patterns = [
        re.compile(r"total\s+marks?\s*[:=]\s*(\d+)", re.IGNORECASE),
        re.compile(r"maximum\s+marks?\s*[:=]\s*(\d+)", re.IGNORECASE),
        re.compile(r"full\s+marks?\s*[:=]\s*(\d+)", re.IGNORECASE),
    ]
    for p in patterns:
        m = p.search(text[:3000])
        if m:
            return int(m.group(1))
    return None


def _detect_duration(text: str) -> int | None:
    """Return duration in minutes."""
    m = re.search(r"(\d+)\s*(?:hour|hr)s?\s*(?:and\s*)?(\d+)?\s*(?:min|minutes?)?",
                  text[:2000], re.IGNORECASE)
    if m:
        hours = int(m.group(1))
        mins = int(m.group(2) or 0)
        return hours * 60 + mins
    m2 = re.search(r"(\d+)\s*(?:min|minutes?)", text[:2000], re.IGNORECASE)
    if m2:
        return int(m2.group(1))
    return None


def _normalize_question_type(raw: str) -> str:
    raw = (raw or "").lower().strip()
    if raw in VALID_Q_TYPES:
        return raw
    if "mcq" in raw or "multiple" in raw or "choice" in raw:
        return "mcq"
    if "short" in raw:
        return "short"
    if "essay" in raw or "long" in raw:
        return "essay"
    if "numer" in raw or "calc" in raw:
        return "numerical"
    if "defin" in raw:
        return "definition"
    if "problem" in raw or "solv" in raw:
        return "problem_solving"
    return "unknown"


def _normalize_topic(raw_topic: str) -> str:
    """Canonical topic normalization to prevent Newton Law / Newton's Law drift."""
    if not raw_topic:
        return ""
    normalized = raw_topic.strip()
    # lowercase for comparison; strip possessives and trailing 's'
    normalized = re.sub(r"'s?\s*$", "", normalized, flags=re.IGNORECASE)
    normalized = re.sub(r"\s+", " ", normalized)
    return normalized.strip()


def _question_fingerprint(paper_id: str, q_number: str, q_text: str) -> str:
    key = f"{paper_id}:{q_number}:{q_text[:120]}"
    return hashlib.sha256(key.encode()).hexdigest()[:24]


def _has_formula(text: str) -> bool:
    formula_markers = ["=", "²", "³", "√", "∫", "∑", "Δ", "α", "β", "γ",
                       "π", "±", "≈", "≠", "≤", "≥", "∞"]
    return any(m in text for m in formula_markers)


def _has_diagram_ref(text: str) -> bool:
    return bool(re.search(
        r"\b(?:figure|fig|diagram|chart|graph|table|image|see below)\b",
        text, re.IGNORECASE,
    ))


# ---------------------------------------------------------------------------
# Deterministic question extraction
# ---------------------------------------------------------------------------

def _extract_questions_deterministic(
    text: str, paper_id: str
) -> list[dict[str, Any]]:
    """
    Parse question blocks from raw text using deterministic rules.
    Returns list of partial question dicts (topic/classification left null).
    """
    lines = text.splitlines()
    questions: list[dict[str, Any]] = []
    current_block: list[str] = []
    current_number: str | None = None
    current_marks: int | None = None
    page_number = 1

    def _flush(q_num: str | None, block: list[str], marks: int | None) -> None:
        text_block = " ".join(block).strip()
        if not text_block or len(text_block) < 10:
            return
        q_type = "mcq" if _MCQ_OPTION_RE.search(text_block) else "unknown"
        if marks is None:
            m = _MARKS_RE.search(text_block)
            marks_val = int(m.group(1)) if m else None
        else:
            marks_val = marks
        qid = _question_fingerprint(paper_id, q_num or str(len(questions)), text_block)
        questions.append({
            "questionId": qid,
            "paperId": paper_id,
            "questionNumber": q_num or str(len(questions) + 1),
            "questionType": q_type,
            "marks": marks_val,
            "topic": None,
            "canonicalTopicId": None,
            "chapter": None,
            "subtopic": None,
            "difficulty": None,
            "cognitiveLevel": None,
            "sourcePage": page_number,
            "section": None,
            "questionText": text_block[:2000],
            "keywords": [],
            "hasFormula": _has_formula(text_block),
            "hasDiagramReference": _has_diagram_ref(text_block),
            "confidence": 0.6,
            "createdAt": _nowiso(),
        })

    for line in lines:
        # Track approximate page
        if re.match(r"^\s*(?:page|p\.?)\s*\d+", line, re.IGNORECASE):
            try:
                page_number = int(re.search(r"\d+", line).group())
            except Exception:
                pass

        # New question start?
        m = _QUESTION_NUM_RE.match(line)
        if m:
            if current_block:
                _flush(current_number, current_block, current_marks)
            current_number = m.group(1)
            current_marks = None
            marks_m = _MARKS_RE.search(line)
            if marks_m:
                current_marks = int(marks_m.group(1))
            current_block = [line]
        else:
            current_block.append(line)

    if current_block:
        _flush(current_number, current_block, current_marks)

    return questions


# ---------------------------------------------------------------------------
# AI topic classification (optional, bounded)
# ---------------------------------------------------------------------------

_CLASSIFY_PROMPT = """\
You are a subject matter classifier for an exam analysis system.
Given a list of exam question texts, classify each with:
  - topic (string, concise canonical form)
  - chapter (string or null)
  - subtopic (string or null)
  - questionType (one of: mcq, short, creative, essay, numerical, definition, problem_solving, mixed, unknown)
  - difficulty (easy, medium, hard, or null)
  - cognitiveLevel (recall, comprehension, application, analysis, or null)

Return ONLY a valid JSON array with one object per question, in input order.
Fields may be null. Do NOT invent information not present in the question text.
Do NOT include any commentary outside the JSON array.

Questions:
{questions_json}
"""

MAX_AI_CLASSIFY_BATCH = 8
MAX_Q_TEXT_FOR_AI = 400  # chars per question sent to AI


async def _ai_classify_questions(
    uid: str, questions: list[dict[str, Any]]
) -> list[dict[str, Any]]:
    """
    Use the canonical AI router to classify topics for unclassified questions.
    Only called when deterministic parsing leaves topic=None.
    Malformed AI output → safe fallback (fields stay null).
    """
    if not questions:
        return questions

    results = list(questions)
    batches = [questions[i:i + MAX_AI_CLASSIFY_BATCH]
               for i in range(0, len(questions), MAX_AI_CLASSIFY_BATCH)]

    for batch in batches:
        q_list = [
            {"index": i, "text": q["questionText"][:MAX_Q_TEXT_FOR_AI]}
            for i, q in enumerate(batch)
        ]
        prompt = _CLASSIFY_PROMPT.format(
            questions_json=json.dumps(q_list, ensure_ascii=False)
        )
        try:
            raw = await ai_service.generate(uid=uid, prompt=prompt,
                                            feature=AiFeature.ANALYSIS)
            parsed = json.loads(raw.strip())
            if not isinstance(parsed, list):
                raise ValueError("Expected list")
            for item in parsed:
                idx = item.get("index")
                if idx is None or not (0 <= idx < len(batch)):
                    continue
                orig = batch[idx]
                orig["topic"] = _normalize_topic(item.get("topic") or "")
                orig["chapter"] = item.get("chapter")
                orig["subtopic"] = item.get("subtopic")
                orig["questionType"] = _normalize_question_type(
                    item.get("questionType") or "unknown"
                )
                orig["difficulty"] = item.get("difficulty")
                orig["cognitiveLevel"] = item.get("cognitiveLevel")
                orig["confidence"] = 0.85
        except Exception as exc:
            logger.warning("AI topic classification failed (batch): %s", exc)
            # safe fallback: leave fields as-is

    return results


# ---------------------------------------------------------------------------
# Past paper persistence
# ---------------------------------------------------------------------------

def _paper_cache_key(material_id: str, version: int) -> str:
    return f"{material_id}__v{version}"


def _load_cached_paper(uid: str, material_id: str) -> dict[str, Any] | None:
    try:
        docs = (
            _paper_col(uid)
            .where("materialId", "==", material_id)
            .where("analysisVersion", "==", ANALYSIS_VERSION)
            .limit(1)
            .stream()
        )
        for doc in docs:
            data = doc.to_dict() or {}
            if data.get("status") == "ready":
                return {"paperId": doc.id, **data}
    except Exception as exc:
        logger.warning("Cache load failed: %s", exc)
    return None


def _save_paper(uid: str, paper_id: str, data: dict[str, Any]) -> None:
    try:
        _paper_col(uid).document(paper_id).set(data)
    except Exception as exc:
        logger.error("Failed to save past paper %s: %s", paper_id, exc)


def _save_questions(uid: str, questions: list[dict[str, Any]]) -> int:
    """Batch-write questions; return count written."""
    if not questions:
        return 0
    db = _db()
    batch = db.batch()
    col = _questions_col(uid)
    for q in questions:
        ref = col.document(q["questionId"])
        batch.set(ref, q)
    try:
        batch.commit()
        return len(questions)
    except Exception as exc:
        logger.error("Failed to save questions: %s", exc)
        return 0


def _delete_paper_questions(uid: str, paper_id: str) -> None:
    try:
        docs = (
            _questions_col(uid)
            .where("paperId", "==", paper_id)
            .limit(500)
            .stream()
        )
        db = _db()
        batch = db.batch()
        for doc in docs:
            batch.delete(doc.reference)
        batch.commit()
    except Exception as exc:
        logger.warning("Failed to delete questions for %s: %s", paper_id, exc)


# ---------------------------------------------------------------------------
# Topic statistics (aggregated per-topic across all papers)
# ---------------------------------------------------------------------------

def _build_topic_stats(
    uid: str, exam_context: str | None = None
) -> list[dict[str, Any]]:
    """
    Aggregate per-topic historical stats across all past papers for a user.
    Returns list of topic stat dicts with historicalFrequencyScore.
    """
    try:
        q_docs = _questions_col(uid).limit(2000).stream()
    except Exception:
        return []

    # Aggregate
    from collections import defaultdict
    topic_data: dict[str, dict] = defaultdict(lambda: {
        "topic": "",
        "papers": set(),
        "questions": 0,
        "marks": 0,
        "years": set(),
        "recentYears": set(),
        "questionTypes": defaultdict(int),
        "difficulties": defaultdict(int),
    })

    current_year = _now().year
    for doc in q_docs:
        q = doc.to_dict() or {}
        topic = q.get("topic") or "Unknown"
        if not topic:
            topic = "Unknown"
        td = topic_data[topic]
        td["topic"] = topic
        td["papers"].add(q.get("paperId", ""))
        td["questions"] += 1
        td["marks"] += q.get("marks") or 0
        year = None
        # year stored on paper, not question — skip for now; aggregated separately
        qt = q.get("questionType") or "unknown"
        td["questionTypes"][qt] += 1
        diff = q.get("difficulty") or "unknown"
        td["difficulties"][diff] += 1

    if not topic_data:
        return []

    # Compute historicalFrequencyScore (0-100, deterministic)
    max_papers = max(len(td["papers"]) for td in topic_data.values()) or 1
    max_questions = max(td["questions"] for td in topic_data.values()) or 1

    stats = []
    for topic, td in topic_data.items():
        paper_freq = (len(td["papers"]) / max_papers) * 100
        q_freq = (td["questions"] / max_questions) * 100
        hist_score = round(0.6 * paper_freq + 0.4 * q_freq)

        # Frequency label (historical description only)
        if hist_score >= 80:
            freq_label = "Very Frequently Tested"
        elif hist_score >= 60:
            freq_label = "Frequently Tested"
        elif hist_score >= 40:
            freq_label = "Moderately Tested"
        elif hist_score >= 20:
            freq_label = "Occasionally Tested"
        else:
            freq_label = "Low Historical Frequency"

        stats.append({
            "topic": topic,
            "paperFrequency": len(td["papers"]),
            "questionFrequency": td["questions"],
            "marksFrequency": td["marks"],
            "questionTypeDistribution": dict(td["questionTypes"]),
            "difficultyDistribution": dict(td["difficulties"]),
            "historicalFrequencyScore": hist_score,
            "frequencyLabel": freq_label,
            "updatedAt": _nowiso(),
        })

    stats.sort(key=lambda x: x["historicalFrequencyScore"], reverse=True)
    return stats


def _persist_topic_stats(uid: str, stats: list[dict[str, Any]]) -> None:
    if not stats:
        return
    db = _db()
    batch = db.batch()
    col = _topic_stats_col(uid)
    for stat in stats[:200]:  # cap
        topic_key = hashlib.sha256(
            stat["topic"].encode()
        ).hexdigest()[:20]
        ref = col.document(topic_key)
        batch.set(ref, stat)
    try:
        batch.commit()
    except Exception as exc:
        logger.warning("Failed to persist topic stats: %s", exc)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

async def analyze_past_paper(
    uid: str,
    material_id: str,
    user: Any,  # CurrentUser
    *,
    exam_name: str | None = None,
    board: str | None = None,
    subject: str | None = None,
    year: int | None = None,
    session: str | None = None,
    paper_code: str | None = None,
    force: bool = False,
) -> dict[str, Any]:
    """
    Main entry point: analyze a Workspace material as a past exam paper.

    Flow:
      1. Check cache (materialId + analysisVersion).
      2. Load Phase 14 chunks (no re-download if already processed).
      3. If no chunks → trigger Phase 14 processing first.
      4. Deterministic question extraction.
      5. AI topic classification for unclassified questions (optional).
      6. Persist paper metadata + questions.
      7. Rebuild topic statistics.
      8. Return analysis summary.
    """
    # 1. Permission check — reuse Phase 14 material gate
    try:
        material = get_material_for_user(material_id, user)
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=404, detail=f"Material not found: {exc}")

    # 2. Cache check
    if not force:
        cached = _load_cached_paper(uid, material_id)
        if cached:
            logger.info("Returning cached past paper analysis for %s", material_id)
            return cached

    # 3. Load Phase 14 chunks
    chunks = _load_chunks(material_id)
    if not chunks:
        # Phase 14 not yet processed — trigger it
        try:
            from app.services.document_ingestion_service import (
                process_material,
                is_already_processed,
            )
            if not is_already_processed(material):
                await process_material(material_id, user)
            chunks = _load_chunks(material_id)
        except Exception as exc:
            logger.warning("Could not trigger Phase 14 processing: %s", exc)

    if not chunks:
        raise HTTPException(
            status_code=422,
            detail="Material has no extractable text. "
                   "Ensure Phase 14 processing succeeded.",
        )

    # 4. Extract full text from chunks
    full_text = _full_text_from_chunks(chunks)

    # 5. Auto-detect metadata (never fabricate)
    detected_year = year or _detect_year(full_text)
    detected_board = board or _detect_board(full_text)
    detected_marks = _detect_total_marks(full_text)
    detected_duration = _detect_duration(full_text)
    detected_source = material.get("fileType") or material.get("type") or "unknown"

    # 6. Deterministic question extraction
    paper_id = str(uuid.uuid4())
    questions = _extract_questions_deterministic(full_text, paper_id)

    # 7. AI classification for unclassified questions (bounded)
    unclassified = [q for q in questions if not q.get("topic")]
    if unclassified:
        questions = await _ai_classify_questions(uid, questions)

    # 8. Build paper record
    now_str = _nowiso()
    paper_data = {
        "paperId": paper_id,
        "ownerId": uid,
        "materialId": material_id,
        "examName": exam_name or material.get("title") or material.get("name") or None,
        "boardOrAuthority": detected_board,
        "subject": subject or material.get("subject") or None,
        "year": detected_year,
        "session": session,
        "paperCode": paper_code,
        "totalMarks": detected_marks,
        "durationMinutes": detected_duration,
        "language": "en",
        "sourceType": detected_source,
        "analysisVersion": ANALYSIS_VERSION,
        "status": "ready",
        "questionCount": len(questions),
        "chunkCount": len(chunks),
        "createdAt": now_str,
        "processedAt": now_str,
    }

    # 9. Persist
    _save_paper(uid, paper_id, paper_data)
    _save_questions(uid, questions)

    # 10. Rebuild topic statistics
    stats = _build_topic_stats(uid)
    _persist_topic_stats(uid, stats)

    logger.info(
        "Past paper analyzed: materialId=%s paperId=%s questions=%d",
        material_id, paper_id, len(questions),
    )

    return {
        **paper_data,
        "topicStatsCount": len(stats),
        "questions": questions[:20],  # preview only; full list via separate endpoint
    }


def list_past_papers(uid: str, *, limit: int = 50) -> list[dict[str, Any]]:
    """List all past papers for a user."""
    try:
        docs = _paper_col(uid).order_by("processedAt").limit(limit).stream()
        return [{"paperId": d.id, **(d.to_dict() or {})} for d in docs]
    except Exception as exc:
        logger.warning("list_past_papers failed: %s", exc)
        return []


def get_past_paper(uid: str, paper_id: str) -> dict[str, Any]:
    """Get a single past paper record."""
    try:
        doc = _paper_col(uid).document(paper_id).get()
        if not doc.exists:
            raise HTTPException(status_code=404, detail="Past paper not found")
        return {"paperId": doc.id, **(doc.to_dict() or {})}
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


def get_past_paper_questions(
    uid: str, paper_id: str, *, limit: int = 200
) -> list[dict[str, Any]]:
    """Return questions for a past paper (paginated)."""
    try:
        docs = (
            _questions_col(uid)
            .where("paperId", "==", paper_id)
            .limit(limit)
            .stream()
        )
        return [d.to_dict() or {} for d in docs]
    except Exception as exc:
        logger.warning("get_past_paper_questions failed: %s", exc)
        return []


def get_historical_insights(uid: str) -> dict[str, Any]:
    """
    Return aggregated historical exam insights for the UI.
    Uses cached topic stats — no AI call.
    """
    # Papers summary
    papers = list_past_papers(uid)
    years_covered = sorted({p.get("year") for p in papers if p.get("year")})
    subjects = sorted({p.get("subject") for p in papers if p.get("subject")})

    # Topic stats
    try:
        stat_docs = _topic_stats_col(uid).order_by(
            "historicalFrequencyScore", direction="DESCENDING"
        ).limit(50).stream()
        topic_stats = [d.to_dict() or {} for d in stat_docs]
    except Exception:
        topic_stats = []

    return {
        "papersAnalyzed": len(papers),
        "yearsCovered": years_covered,
        "subjects": subjects,
        "totalQuestions": sum(p.get("questionCount", 0) for p in papers),
        "topicStats": topic_stats,
        "lastUpdated": _nowiso(),
    }


def delete_past_paper(uid: str, paper_id: str) -> None:
    """
    Remove a past paper analysis.
    Does NOT delete the original Workspace material.
    Deletes derived question records.
    """
    # Verify ownership
    doc = _paper_col(uid).document(paper_id).get()
    if not doc.exists:
        raise HTTPException(status_code=404, detail="Past paper not found")
    data = doc.to_dict() or {}
    if data.get("ownerId") != uid:
        raise HTTPException(status_code=403, detail="Access denied")

    _delete_paper_questions(uid, paper_id)
    _paper_col(uid).document(paper_id).delete()
    logger.info("Deleted past paper %s for user %s", paper_id, uid)
