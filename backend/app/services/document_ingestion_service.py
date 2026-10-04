"""Phase 14.2 — Document Ingestion Service.

Orchestrates the full lifecycle of turning a student-owned material file into
searchable, chunked, intelligence-ready content stored in Firestore subcollections:

    materials/{materialId}/chunks/{chunkId}

Lifecycle states written to the parent material document field
``intelligenceStatus``:

    uploaded → extracting → processing → ready
                                       ↘ failed

Idempotency: if ``intelligenceStatus == "ready"`` and
``intelligenceVersion == CURRENT_VERSION`` the cached result is returned
unless ``force=True``.

No new storage system, no new AI provider cascade.  Reuses:
  - pdf_service.extract_pdf_pages
  - ocr_service.extract_text  (fallback for scanned PDFs / images)
  - python-docx  (DOCX canonical fix)
  - permission_service.get_material_for_user
  - storage_provider / storage_service  (byte fetch)
"""

from __future__ import annotations

import logging
import math
import re
import uuid
from datetime import datetime, timezone
from io import BytesIO
from typing import Any

from fastapi import HTTPException

from app.core.auth import CurrentUser
from app.core.firebase import get_firestore
from app.services import storage_provider
from app.services.permission_service import get_material_for_user

logger = logging.getLogger("gochano.doc_ingest")

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

CURRENT_VERSION = 1
MAX_PAGES = 200
MAX_CHARS = 600_000
MAX_CHUNKS = 600
MAX_UPLOAD_BYTES = 25 * 1024 * 1024  # 25 MB

# Chunking windows (chars)
CHUNK_CONFIG: dict[str, dict] = {
    "pdf":  {"target": 1000, "max": 1500, "overlap": 150},
    "docx": {"target": 1000, "max": 1500, "overlap": 100},
    "ocr":  {"target":  800, "max": 1500, "overlap": 150},
    "txt":  {"target":  750, "max": 1500, "overlap": 100},
}
MIN_CHUNK_CHARS = 80

STATUS_EXTRACTING  = "extracting"
STATUS_PROCESSING  = "processing"
STATUS_READY       = "ready"
STATUS_FAILED      = "failed"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _now() -> datetime:
    return datetime.now(timezone.utc)


def _set_status(db, material_id: str, status: str, extra: dict | None = None) -> None:
    payload: dict[str, Any] = {
        "intelligenceStatus": status,
        "intelligenceUpdatedAt": _now().isoformat(),
    }
    if extra:
        payload.update(extra)
    try:
        db.collection("materials").document(material_id).update(payload)
    except Exception as exc:
        logger.warning("Could not update intelligenceStatus: %s", exc)


def _fetch_bytes(material: dict) -> bytes:
    """
    Download raw material bytes through the canonical storage provider.

    Supports the storage backends already handled by storage_provider,
    including Backblaze B2 and the legacy Firebase fallback.
    """
    file_path = material.get("filePath") or ""

    if not file_path:
        raise HTTPException(
            status_code=502,
            detail="Material has no file path",
        )

    try:
        resolution = storage_provider.resolve(material)
        data = storage_provider.download_for(resolution)

        if data is None:
            raise HTTPException(
                status_code=502,
                detail="Stored material file could not be downloaded",
            )

        return data

    except HTTPException:
        raise

    except Exception as exc:
        logger.exception("Material storage download failed")
        raise HTTPException(
            status_code=502,
            detail="Storage download failed",
        ) from exc


# ---------------------------------------------------------------------------
# Text Extraction
# ---------------------------------------------------------------------------

def _extract_from_pdf(data: bytes) -> tuple[list[dict], bool, int, int]:
    """Return (page_dicts, truncated, total_pages, processed_pages).

    Falls back to OCR when the text layer is empty/insufficient.
    """
    from app.services.pdf_service import extract_pdf_pages, count_pdf_pages

    total_pages = count_pdf_pages(data)
    pages = extract_pdf_pages(data, max_pages=MAX_PAGES)

    # Determine if OCR fallback is needed (< 20 chars average per page extracted)
    if pages:
        avg_chars = sum(len(p["text"]) for p in pages) / len(pages)
    else:
        avg_chars = 0.0

    if avg_chars < 20:
        logger.info("PDF text layer thin (avg %.0f chars/page) — trying OCR fallback", avg_chars)
        pages = _ocr_pdf_pages(data)
        if pages:
            logger.info("OCR extracted %d pages", len(pages))

    truncated = total_pages > MAX_PAGES
    return pages, truncated, total_pages, min(total_pages, MAX_PAGES)


def _ocr_pdf_pages(data: bytes) -> list[dict]:
    """OCR fallback for scanned PDFs.  Returns same format as extract_pdf_pages."""
    try:
        from pdf2image import convert_from_bytes
        from app.services.ocr_service import extract_text as ocr_extract

        images = convert_from_bytes(data, dpi=150)
        results = []
        for i, img in enumerate(images[:MAX_PAGES]):
            img_bytes = BytesIO()
            img.save(img_bytes, format="PNG")
            text = ""
            try:
                result = ocr_extract(img_bytes.getvalue())
                text = getattr(result, "text", "") or str(result)
            except Exception:
                pass
            text = (text or "").strip()
            if len(text) >= MIN_CHUNK_CHARS:
                results.append({"page": i + 1, "text": text})
        return results
    except Exception as exc:
        logger.warning("OCR PDF fallback failed: %s", exc)
        return []


def _extract_from_docx(data: bytes) -> list[dict]:
    """Fix: use python-docx instead of raw utf-8 decode.

    Returns list of ``{"page": 1, "text": str, "section": str}`` dicts.
    DOCX has no real pages; all content is page=1 but sections are preserved.
    """
    try:
        import docx  # type: ignore[import]
        doc = docx.Document(BytesIO(data))
    except Exception as exc:
        logger.warning("python-docx parse failed (%s), falling back to utf-8 heuristic", exc)
        text = data.decode("utf-8", errors="replace")[:MAX_CHARS]
        return [{"page": 1, "text": text, "section": ""}] if text.strip() else []

    blocks: list[dict] = []
    current_section = ""
    buffer_parts: list[str] = []

    def _flush(section: str) -> None:
        joined = "\n".join(buffer_parts).strip()
        if joined:
            blocks.append({"page": 1, "text": joined, "section": section})
        buffer_parts.clear()

    for para in doc.paragraphs:
        style_name = (para.style.name or "").lower()
        text = para.text.strip()
        if not text:
            continue
        if "heading 1" in style_name:
            _flush(current_section)
            current_section = text
        elif "heading 2" in style_name:
            _flush(current_section)
            current_section = f"{current_section} > {text}" if current_section else text
        else:
            buffer_parts.append(text)

        # Flush large accumulations to keep blocks bounded
        if sum(len(p) for p in buffer_parts) > 2000:
            _flush(current_section)

    _flush(current_section)

    # Tables
    for table in doc.tables:
        rows = []
        for row in table.rows:
            cells = " | ".join(c.text.strip() for c in row.cells if c.text.strip())
            if cells:
                rows.append(cells)
        if rows:
            blocks.append({"page": 1, "text": "\n".join(rows), "section": current_section})

    return blocks


def _extract_from_txt(data: bytes) -> list[dict]:
    text = data.decode("utf-8", errors="replace")
    text = text[:MAX_CHARS].strip()
    if not text:
        return []
    return [{"page": 1, "text": text, "section": ""}]


# ---------------------------------------------------------------------------
# Heading Detection
# ---------------------------------------------------------------------------

_HEADING_RE = re.compile(
    r"^(?:"
    r"(?:Chapter|অধ্যায়|Section|অংশ)\s+\d+"
    r"|(?:\d+\.)+\s+"      # e.g. "1.2 ", "2.3.4 "
    r"|[A-Z][A-Z\s]{4,}$"  # ALL-CAPS line
    r")",
    re.MULTILINE | re.IGNORECASE,
)


def _detect_section(text: str) -> str:
    """Return the first detected heading-like line from the text block."""
    lines = text.splitlines()
    for line in lines[:6]:
        line = line.strip()
        if _HEADING_RE.match(line) and len(line) < 120:
            return line
    return ""


# ---------------------------------------------------------------------------
# Keyword Extraction
# ---------------------------------------------------------------------------

_STOP_WORDS = frozenset({
    "the", "a", "an", "is", "it", "in", "of", "to", "and", "or", "for",
    "on", "at", "by", "this", "that", "with", "are", "was", "be", "as",
    "from", "এর", "এই", "এবং", "বা", "হয়", "না", "কে", "যে", "তা",
})


def _extract_keywords(text: str, max_kw: int = 12) -> list[str]:
    words = re.findall(r"\b[A-Za-z\u0980-\u09FF]{4,}\b", text)
    freq: dict[str, int] = {}
    for w in words:
        w_low = w.lower()
        if w_low not in _STOP_WORDS:
            freq[w_low] = freq.get(w_low, 0) + 1
    return sorted(freq, key=lambda k: -freq[k])[:max_kw]


def _is_formula_dense(text: str) -> bool:
    """Heuristic: many digits, operators, subscripts → likely formula-heavy."""
    formula_chars = len(re.findall(r"[=+\-*/^√∫∑∏²³₀₁₂₃₄₅₆₇₈₉]", text))
    return formula_chars / max(len(text), 1) > 0.03


# ---------------------------------------------------------------------------
# Chunking
# ---------------------------------------------------------------------------

def _split_into_chunks(
    text: str,
    page: int,
    section: str,
    chunk_type: str,
) -> list[dict]:
    """Split a text block into bounded chunks with overlap."""
    cfg = CHUNK_CONFIG.get(chunk_type, CHUNK_CONFIG["txt"])
    target = cfg["target"]
    max_c = cfg["max"]
    overlap = cfg["overlap"]

    chunks: list[dict] = []
    start = 0
    text_len = len(text)

    while start < text_len:
        end = min(start + target, text_len)

        # Try to break at sentence boundary
        if end < text_len:
            for sep in (". ", "। ", "\n\n", "\n", " "):
                idx = text.rfind(sep, start + overlap, end)
                if idx != -1:
                    end = idx + len(sep)
                    break

        end = min(end, start + max_c)
        chunk_text = text[start:end].strip()

        if len(chunk_text) >= MIN_CHUNK_CHARS:
            chunks.append({
                "text": chunk_text,
                "page": page,
                "endPage": page,
                "section": section,
                "characterCount": len(chunk_text),
                "keywords": _extract_keywords(chunk_text),
                "isFormulaDense": _is_formula_dense(chunk_text),
            })

        # Advance with overlap
        next_start = end - overlap
        if next_start <= start:
            next_start = start + max(target // 2, 1)
        start = next_start

    return chunks


# ---------------------------------------------------------------------------
# Chunk Persistence
# ---------------------------------------------------------------------------

def _delete_existing_chunks(db, material_id: str) -> None:
    """Atomically remove stale chunks before re-processing."""
    chunks_ref = db.collection("materials").document(material_id).collection("chunks")
    batch_size = 400
    while True:
        docs = list(chunks_ref.limit(batch_size).stream())
        if not docs:
            break
        batch = db.batch()
        for doc in docs:
            batch.delete(doc.reference)
        batch.commit()


def _store_chunks(db, material_id: str, owner_id: str, chunks: list[dict]) -> int:
    """Write chunks in batches of ≤ 400.  Returns count stored."""
    chunks_ref = db.collection("materials").document(material_id).collection("chunks")
    batch_size = 400
    total = 0
    for i in range(0, len(chunks), batch_size):
        batch = db.batch()
        for j, chunk in enumerate(chunks[i : i + batch_size]):
            chunk_id = str(uuid.uuid4())
            doc_ref = chunks_ref.document(chunk_id)
            batch.set(doc_ref, {
                "chunkId": chunk_id,
                "materialId": material_id,
                "ownerId": owner_id,
                "chunkIndex": i + j,
                "page": chunk.get("page", 1),
                "endPage": chunk.get("endPage", chunk.get("page", 1)),
                "section": chunk.get("section", ""),
                "chapter": chunk.get("chapter", ""),
                "text": chunk["text"],
                "characterCount": chunk.get("characterCount", len(chunk["text"])),
                "keywords": chunk.get("keywords", []),
                "isFormulaDense": chunk.get("isFormulaDense", False),
                "createdAt": _now().isoformat(),
            })
            total += 1
        batch.commit()
    return total


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def is_already_processed(material: dict) -> bool:
    """Return True if intelligence is cached and still current."""
    return (
        material.get("intelligenceStatus") == STATUS_READY
        and int(material.get("intelligenceVersion", 0) or 0) == CURRENT_VERSION
    )


async def process_material(
    material_id: str,
    user: CurrentUser,
    force: bool = False,
) -> dict[str, Any]:
    """Top-level ingestion entry point called by the API route.

    Returns a status dict immediately.  Heavy extraction runs synchronously
    inside this coroutine (FastAPI route is async; extraction is CPU-bound but
    bounded by MAX_CHARS / MAX_PAGES limits so it stays within Render's 30s
    request window in practice).

    Args:
        material_id:  Firestore material document ID.
        user:         Authenticated student (UID and role already verified).
        force:        Re-process even if ``intelligenceStatus == "ready"``.
    """
    db = get_firestore()
    material = get_material_for_user(material_id, user)
    owner_id = material.get("ownerId", user.uid)
    mime = (material.get("mimeType") or "").lower()

    # Idempotency guard
    if not force and is_already_processed(material):
        logger.info("Material %s already processed (v%d) — serving cache", material_id, CURRENT_VERSION)
        return {
            "materialId": material_id,
            "intelligenceStatus": STATUS_READY,
            "cached": True,
            "intelligenceVersion": CURRENT_VERSION,
        }

    # Acquire processing lease (prevent double-processing)
    if material.get("intelligenceStatus") in (STATUS_EXTRACTING, STATUS_PROCESSING):
        if not force:
            return {
                "materialId": material_id,
                "intelligenceStatus": material.get("intelligenceStatus"),
                "cached": False,
                "message": "Already processing. Poll GET /intelligence for status.",
            }

    _set_status(db, material_id, STATUS_EXTRACTING)

    # ---------- Fetch bytes ----------
    try:
        data = _fetch_bytes(material)
    except HTTPException:
        _set_status(db, material_id, STATUS_FAILED, {"intelligenceError": "Storage fetch failed"})
        raise

    if len(data) > MAX_UPLOAD_BYTES:
        _set_status(db, material_id, STATUS_FAILED, {"intelligenceError": "File exceeds 25 MB limit"})
        raise HTTPException(status_code=413, detail="Document exceeds 25 MB processing limit")

    # ---------- Extract ----------
    pages_data: list[dict] = []
    chunk_type = "txt"
    total_pages = 1
    processed_pages = 1
    truncated = False

    try:
        if "pdf" in mime:
            pages_data, truncated, total_pages, processed_pages = _extract_from_pdf(data)
            chunk_type = "pdf"
        elif mime in (
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            "application/msword",
        ) or "docx" in mime or "doc" in mime:
            pages_data = _extract_from_docx(data)
            chunk_type = "docx"
        else:
            pages_data = _extract_from_txt(data)
            chunk_type = "txt"
    except Exception as exc:
        _set_status(db, material_id, STATUS_FAILED, {"intelligenceError": f"Extraction failed: {exc}"})
        raise HTTPException(status_code=422, detail=f"Could not extract text from document: {exc}") from exc

    if not pages_data:
        _set_status(db, material_id, STATUS_FAILED, {
            "intelligenceError": "No extractable text found (empty or fully image-based unsupported format)"
        })
        raise HTTPException(status_code=422, detail="No extractable text found in this document")

    _set_status(db, material_id, STATUS_PROCESSING)

    # ---------- Truncate & chunk ----------
    all_chunks: list[dict] = []
    total_chars = 0

    for page_block in pages_data:
        if len(all_chunks) >= MAX_CHUNKS:
            truncated = True
            break
        text = page_block.get("text", "").strip()
        if not text:
            continue

        # Enforce character budget
        remaining_chars = MAX_CHARS - total_chars
        if remaining_chars <= 0:
            truncated = True
            break
        if len(text) > remaining_chars:
            text = text[:remaining_chars]
            truncated = True

        page_no = page_block.get("page", 1)
        section = page_block.get("section") or _detect_section(text)

        new_chunks = _split_into_chunks(text, page_no, section, chunk_type)

        for chunk in new_chunks:
            if len(all_chunks) >= MAX_CHUNKS:
                truncated = True
                break
            all_chunks.append(chunk)
            total_chars += chunk["characterCount"]

    if not all_chunks:
        _set_status(db, material_id, STATUS_FAILED, {"intelligenceError": "Chunking produced no content"})
        raise HTTPException(status_code=422, detail="Document text was too short to process")

    # ---------- Persist chunks ----------
    _delete_existing_chunks(db, material_id)
    chunk_count = _store_chunks(db, material_id, owner_id, all_chunks)

    # ---------- Update material status ----------
    _set_status(db, material_id, STATUS_READY, {
        "intelligenceVersion": CURRENT_VERSION,
        "intelligenceChunkCount": chunk_count,
        "intelligenceTruncated": truncated,
        "intelligenceTotalPages": total_pages,
        "intelligenceProcessedPages": processed_pages,
        "intelligenceProcessedChars": total_chars,
        "intelligenceProcessedAt": _now().isoformat(),
    })

    logger.info(
        "Material %s processed: %d chunks, %d chars, truncated=%s",
        material_id, chunk_count, total_chars, truncated,
    )

    return {
        "materialId": material_id,
        "intelligenceStatus": STATUS_READY,
        "chunkCount": chunk_count,
        "processedChars": total_chars,
        "truncated": truncated,
        "totalPages": total_pages,
        "processedPages": processed_pages,
        "intelligenceVersion": CURRENT_VERSION,
        "cached": False,
    }
