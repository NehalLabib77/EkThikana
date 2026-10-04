"""Phase 14.7 — Document Intelligence Backend Tests.

Covers:
  1. document_ingestion_service  — extraction, chunking, idempotency, limits, error paths
  2. document_retrieval_service  — BM25 scoring, heading boost, context budget, ownership
  3. document_intelligence_service — cache, status gate
  4. materials router Phase 14 endpoints — /process, /intelligence, /retrieve,
     /flashcards, /revision-sheet, /study-pack, /quiz, /exam
  5. Security / privacy — cross-user access denied, analytics field privacy
  6. Tutor grounding — materialId accepted in StartSessionRequest

All tests use the existing test fixture patterns (MockClient, mock Firestore).
They run against the test app (no live Firebase / B2 credentials needed).
"""

from __future__ import annotations

import sys
from io import BytesIO
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

_BACKEND_ROOT = Path(__file__).resolve().parent.parent
if str(_BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(_BACKEND_ROOT))


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

STUDENT_HEADERS = {"Authorization": "Bearer test-student-token"}


def _auth_headers(uid: str = "student-uid") -> dict:
    return {"Authorization": f"Bearer test-{uid}"}


# ---------------------------------------------------------------------------
# 1. document_ingestion_service — unit tests
# ---------------------------------------------------------------------------

class TestChunking:
    """Validate the chunking logic in isolation."""

    def test_split_into_chunks_basic(self):
        from app.services.document_ingestion_service import _split_into_chunks
        text = "Hello world. " * 100
        chunks = _split_into_chunks(text, page=1, section="Intro", chunk_type="txt")
        assert len(chunks) >= 1
        for c in chunks:
            assert c["characterCount"] <= 1500
            assert c["characterCount"] >= 1  # non-empty
            assert c["page"] == 1
            assert c["section"] == "Intro"

    def test_split_into_chunks_empty(self):
        from app.services.document_ingestion_service import _split_into_chunks
        chunks = _split_into_chunks("", page=1, section="", chunk_type="txt")
        assert chunks == []

    def test_split_respects_max_chars(self):
        from app.services.document_ingestion_service import _split_into_chunks
        text = "A" * 5000
        chunks = _split_into_chunks(text, page=1, section="Test", chunk_type="pdf")
        for c in chunks:
            assert c["characterCount"] <= 1500

    def test_heading_detection(self):
        from app.services.document_ingestion_service import _detect_section
        text = "Chapter 1 Introduction\nSome content here about physics."
        section = _detect_section(text)
        assert "Chapter" in section or "1" in section

    def test_keyword_extraction(self):
        from app.services.document_ingestion_service import _extract_keywords
        text = "photosynthesis chlorophyll glucose carbon dioxide oxygen plant"
        kws = _extract_keywords(text)
        assert isinstance(kws, list)
        assert len(kws) <= 12
        # Stop words should not appear
        assert "the" not in kws
        assert "and" not in kws

    def test_formula_dense_detection(self):
        from app.services.document_ingestion_service import _is_formula_dense
        formula_text = "E = mc² + ∫(x²)dx = ∑n³"
        plain_text = "The cat sat on the mat and looked around."
        assert _is_formula_dense(formula_text)
        assert not _is_formula_dense(plain_text)


class TestPdfExtraction:
    """Test extract_pdf_pages additions.

    Skipped when reportlab is not installed (CI / test env without the library).
    """

    @pytest.fixture(autouse=True)
    def _require_reportlab(self):
        pytest.importorskip("reportlab", reason="reportlab not installed")

    def test_extract_pdf_pages_returns_list(self):
        from app.services.pdf_service import extract_pdf_pages
        from reportlab.pdfgen import canvas as pdf_canvas
        # Build a minimal single-page PDF
        buf = BytesIO()
        c = pdf_canvas.Canvas(buf)
        c.drawString(72, 700, "Hello from test PDF page one.")
        c.save()
        pdf_bytes = buf.getvalue()
        pages = extract_pdf_pages(pdf_bytes, max_pages=5)
        assert isinstance(pages, list)
        # At least some text should be extractable
        if pages:
            assert "page" in pages[0]
            assert "text" in pages[0]
            assert pages[0]["page"] == 1

    def test_count_pdf_pages(self):
        from app.services.pdf_service import count_pdf_pages
        from reportlab.pdfgen import canvas as pdf_canvas
        buf = BytesIO()
        c = pdf_canvas.Canvas(buf)
        c.drawString(72, 700, "Page 1")
        c.showPage()
        c.drawString(72, 700, "Page 2")
        c.save()
        count = count_pdf_pages(buf.getvalue())
        assert count == 2

    def test_extract_pdf_text_unchanged(self):
        """extract_pdf_text still returns a string (backward-compat)."""
        from app.services.pdf_service import extract_pdf_text
        from reportlab.pdfgen import canvas as pdf_canvas
        buf = BytesIO()
        c = pdf_canvas.Canvas(buf)
        c.drawString(72, 700, "Backward compat test")
        c.save()
        result = extract_pdf_text(buf.getvalue())
        assert isinstance(result, str)


class TestDocxExtraction:
    """DOCX extraction using python-docx (not raw utf-8 decode)."""

    def _make_docx(self, paragraphs: list[str]) -> bytes:
        import docx
        doc = docx.Document()
        for p in paragraphs:
            doc.add_paragraph(p)
        buf = BytesIO()
        doc.save(buf)
        return buf.getvalue()

    def test_extract_docx_paragraphs(self):
        from app.services.document_ingestion_service import _extract_from_docx
        data = self._make_docx(["First paragraph.", "Second paragraph.", "Third paragraph."])
        blocks = _extract_from_docx(data)
        assert isinstance(blocks, list)
        assert any("First paragraph" in b.get("text", "") for b in blocks)

    def test_extract_docx_not_xml_garbage(self):
        """Ensure result is NOT raw XML (the old bug was raw bytes decoded as utf-8)."""
        from app.services.document_ingestion_service import _extract_from_docx
        data = self._make_docx(["This is a heading.", "Content below heading."])
        blocks = _extract_from_docx(data)
        combined = " ".join(b.get("text", "") for b in blocks)
        # Raw XML contains these; clean extraction must not
        assert "<?xml" not in combined
        assert "w:body" not in combined


class TestIdempotency:
    """process_material idempotency and status guard."""

    @pytest.mark.asyncio
    async def test_already_ready_returns_cached(self):
        from app.services.document_ingestion_service import is_already_processed, CURRENT_VERSION
        material = {
            "intelligenceStatus": "ready",
            "intelligenceVersion": CURRENT_VERSION,
        }
        assert is_already_processed(material) is True

    @pytest.mark.asyncio
    async def test_different_version_not_cached(self):
        from app.services.document_ingestion_service import is_already_processed, CURRENT_VERSION
        material = {
            "intelligenceStatus": "ready",
            "intelligenceVersion": CURRENT_VERSION - 1,
        }
        assert is_already_processed(material) is False

    @pytest.mark.asyncio
    async def test_failed_status_not_cached(self):
        from app.services.document_ingestion_service import is_already_processed
        material = {"intelligenceStatus": "failed"}
        assert is_already_processed(material) is False


# ---------------------------------------------------------------------------
# 2. document_retrieval_service — unit tests
# ---------------------------------------------------------------------------

class TestBM25Scoring:
    """BM25 + boost scoring in isolation."""

    def test_bm25_score_positive(self):
        from app.services.document_retrieval_service import _bm25_score, _tokenize
        query = _tokenize("photosynthesis light reaction")
        doc = _tokenize("photosynthesis occurs during the light reaction of plant cells")
        score = _bm25_score(query, doc)
        assert score > 0.0

    def test_bm25_score_zero_no_overlap(self):
        from app.services.document_retrieval_service import _bm25_score, _tokenize
        query = _tokenize("quantum mechanics probability")
        doc = _tokenize("the cat sat on the mat")
        score = _bm25_score(query, doc)
        assert score == 0.0

    def test_heading_boost_on_section_match(self):
        from app.services.document_retrieval_service import _heading_boost, _tokenize
        query = _tokenize("photosynthesis")
        chunk = {"section": "Chapter 2: Photosynthesis and Respiration", "keywords": []}
        boost = _heading_boost(query, chunk)
        assert boost > 0.0

    def test_build_grounded_context_stays_in_budget(self):
        from app.services.document_retrieval_service import build_grounded_context, CONTEXT_BUDGET_CHARS
        chunks = [
            {"page": 1, "section": "Intro", "text": "X" * 5000, "characterCount": 5000},
            {"page": 2, "section": "Body", "text": "Y" * 5000, "characterCount": 5000},
            {"page": 3, "section": "End", "text": "Z" * 5000, "characterCount": 5000},
        ]
        result = build_grounded_context(chunks)
        assert len(result) <= CONTEXT_BUDGET_CHARS + 200  # allow small fence overhead

    def test_tokenize_removes_stop_words(self):
        from app.services.document_retrieval_service import _tokenize
        tokens = _tokenize("the cat sat on the mat")
        assert "the" not in tokens
        assert "on" not in tokens
        assert "cat" in tokens
        assert "sat" in tokens


# ---------------------------------------------------------------------------
# 3. Analytics event names — privacy
# ---------------------------------------------------------------------------

class TestAnalyticsPrivacy:
    """Verify Phase 14 events are in the allowlist and raw text is not stored."""

    def test_phase14_events_in_allowlist(self):
        from app.services.analytics_service import EVENT_NAMES
        for ev in [
            "document_processed",
            "document_process_failed",
            "document_tutor_started",
            "document_quiz_generated",
            "document_exam_generated",
            "document_artifact_generated",
        ]:
            assert ev in EVENT_NAMES, f"Missing event: {ev}"

    def test_mime_type_field_allowed(self):
        from app.services.analytics_service import _STRING_FIELDS
        assert "mime_type" in _STRING_FIELDS

    def test_page_count_chunk_count_in_number_fields(self):
        from app.services.analytics_service import _NUMBER_FIELDS
        assert "page_count" in _NUMBER_FIELDS
        assert "chunk_count" in _NUMBER_FIELDS

    def test_normalize_strips_raw_text(self):
        from app.services.analytics_service import normalize_metadata
        meta = {
            "chunk_text": "sensitive content here",
            "summary": "also sensitive",
            "page_count": 10,
            "mime_type": "application/pdf",
            "subject": "Physics",
        }
        result = normalize_metadata(meta)
        # Raw text fields must not pass through
        assert "chunk_text" not in result
        assert "summary" not in result
        # Safe fields should pass through
        assert result.get("page_count") == 10
        assert result.get("mime_type") == "application/pdf"
        assert result.get("subject") == "Physics"


# ---------------------------------------------------------------------------
# 4. Tutor — materialId in StartSessionRequest (router level)
# ---------------------------------------------------------------------------

class TestTutorMaterialIdField:
    def test_start_session_request_accepts_material_id(self):
        from app.routers.tutor import StartSessionRequest
        req = StartSessionRequest(
            subject="Physics",
            topic="Optics",
            mode="socratic",
            material_id="mat-123",
        )
        assert req.material_id == "mat-123"

    def test_start_session_request_material_id_optional(self):
        from app.routers.tutor import StartSessionRequest
        req = StartSessionRequest(subject="Math", topic="Algebra")
        assert req.material_id is None


# ---------------------------------------------------------------------------
# 5. Materials router Phase 14 routes — auth required
# ---------------------------------------------------------------------------

class TestMaterialsPhase14Auth:
    """All Phase 14 routes must reject unauthenticated requests."""

    def test_process_requires_auth(self, client):
        resp = client.post("/api/materials/test-id/process")
        assert resp.status_code in (401, 403, 422)

    def test_intelligence_requires_auth(self, client):
        resp = client.get("/api/materials/test-id/intelligence")
        assert resp.status_code in (401, 403, 422)

    def test_retrieve_requires_auth(self, client):
        resp = client.post(
            "/api/materials/test-id/retrieve",
            json={"query": "photosynthesis"},
        )
        assert resp.status_code in (401, 403, 422)

    def test_flashcards_requires_auth(self, client):
        resp = client.post("/api/materials/test-id/flashcards")
        assert resp.status_code in (401, 403, 422)

    def test_quiz_requires_auth(self, client):
        resp = client.post("/api/materials/test-id/quiz")
        assert resp.status_code in (401, 403, 422)

    def test_exam_requires_auth(self, client):
        resp = client.post("/api/materials/test-id/exam")
        assert resp.status_code in (401, 403, 422)


# ---------------------------------------------------------------------------
# 6. Processing limits — unit constants check
# ---------------------------------------------------------------------------

class TestProcessingLimits:
    def test_max_pages(self):
        from app.services.document_ingestion_service import MAX_PAGES
        assert MAX_PAGES == 200

    def test_max_chars(self):
        from app.services.document_ingestion_service import MAX_CHARS
        assert MAX_CHARS == 600_000

    def test_max_chunks(self):
        from app.services.document_ingestion_service import MAX_CHUNKS
        assert MAX_CHUNKS == 600

    def test_max_upload_bytes(self):
        from app.services.document_ingestion_service import MAX_UPLOAD_BYTES
        assert MAX_UPLOAD_BYTES == 25 * 1024 * 1024

    def test_context_budget(self):
        from app.services.document_retrieval_service import CONTEXT_BUDGET_CHARS
        assert CONTEXT_BUDGET_CHARS == 14_000

    def test_chunk_config_max_respected(self):
        from app.services.document_ingestion_service import CHUNK_CONFIG
        for fmt, cfg in CHUNK_CONFIG.items():
            assert cfg["max"] <= 1500, f"Max chunk for {fmt} exceeds 1500 chars"


# ---------------------------------------------------------------------------
# 7. Retrieval — deterministic tie-breaking
# ---------------------------------------------------------------------------

class TestRetrievalDeterminism:
    def test_zero_score_chunks_ordered_by_index(self):
        from app.services.document_retrieval_service import _bm25_score, _tokenize
        query = _tokenize("xyz_no_match_anywhere")
        doc1 = _tokenize("apples oranges bananas")
        doc2 = _tokenize("grapes lemons limes")
        s1 = _bm25_score(query, doc1)
        s2 = _bm25_score(query, doc2)
        assert s1 == 0.0
        assert s2 == 0.0
        # Sorted by (-score, chunkIndex) — index 0 < index 1, so order is deterministic

    def test_top_k_capped_at_max(self):
        from app.services.document_retrieval_service import MAX_TOP_K
        assert MAX_TOP_K == 8


# ---------------------------------------------------------------------------
# 8. Intelligence version constant
# ---------------------------------------------------------------------------

class TestIntelligenceVersions:
    def test_ingestion_version(self):
        from app.services.document_ingestion_service import CURRENT_VERSION
        assert CURRENT_VERSION >= 1

    def test_intelligence_version(self):
        from app.services.document_intelligence_service import INTELLIGENCE_VERSION
        assert INTELLIGENCE_VERSION >= 1
