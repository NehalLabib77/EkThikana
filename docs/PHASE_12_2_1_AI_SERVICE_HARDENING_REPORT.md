# Phase 12.2.1 — AI Service Hardening Report

**Project:** Gochano / EkThikana
**Phase:** 12.2.1 — AI Service Hardening
**Scope:** Production hardening of `ai_service.py` HTTP timeouts, addition of deterministic AI task classification layer (`ai_router_service.py`), and test verification.
**Status:** **`VERIFIED & COMPLETE`**

---

## 1. Changes Implemented

### 1.1 HTTP Client Timeout Hardening
- **Target:** `backend/app/services/ai_service.py` (`_http()` singleton).
- **Previous Configuration:**
  - Connect timeout: `15.0s`
  - Total timeout: `90.0s`
- **Hardened Production Configuration:**
  - Connect timeout: `8.0s`
  - Read timeout: `35.0s`
  - Write timeout: `35.0s`
  - Pool timeout: `10.0s`
- **Production Impact:** Eliminates connection pool starvation and thread lockups during upstream provider outages (Groq/Gemini/OpenRouter). Failing requests fail over cleanly to fallback providers within safe operational limits.

### 1.2 Deterministic AI Task Classification Layer
- **New Service:** `backend/app/services/ai_router_service.py`
- **Architecture:** Pure Python rule engine without any internal LLM calls or external network dependencies.
- **Classification Schema:**
  ```python
  def classify_task(
      task_type: str,
      feature: str | None = None,
      complexity: str | None = None,
  ) -> dict[str, str]:
      # Returns {"tier": "tier1" | "tier2" | "tier3", "reason": str}
  ```
- **Tier Taxonomy:**
  - **Tier 1 (Fast & Lightweight):** `mcq_checking`, `keyword_extraction`, `simple_classification`, `formatting`, `escape_hatch_check`, `intent_classification`.
  - **Tier 2 (Standard Reasoning & Content):** `normal_explanation`, `study_content_generation`, `normal_chat`, `ziku_chat`, `note_ai`, `quiz_generation`, `study_plan`, and default unclassified tasks.
  - **Tier 3 (Deep & Socratic Reasoning):** `socratic_tutor`, `tutor_reasoning`, `complex_math`, `complex_derivation`, `exam_intelligence`, `exam_simulator`, `exam_rescue`, `olympiad_problem`.
- **Complexity Overrides:**
  - Explicit `complexity="high"` / `"complex"` promotes tasks to `tier3`.
  - Explicit `complexity="low"` / `"simple"` demotes compatible tasks to `tier1`.

### 1.3 Backward-Compatible Public Interface
- **Target:** `backend/app/services/ai_service.py` (`generate` and `generate_multimodal`).
- **Signature Update:**
  ```python
  async def generate(
      uid: str,
      prompt: str,
      feature: str = AiFeature.NOTE,
      model_tier: str | None = None,
  ) -> str:
  ```
- **Behavior:** If `model_tier` is omitted (`None`), standard Groq $\to$ Gemini $\to$ OpenRouter cascade operates exactly as before without alteration.

---

## 2. Files Modified & Created

| File | Status | Description |
|---|:---:|---|
| `backend/app/services/ai_service.py` | **Modified** | Configured `httpx.Timeout(connect=8.0, read=35.0, write=35.0, pool=10.0)` in `_http()`; added optional `model_tier` keyword parameter to `generate` and `generate_multimodal`. |
| `backend/app/services/ai_router_service.py` | **Created** | Deterministic model tier classifier (`classify_task`, `route_task`, `classify_ai_task`). |
| `backend/tests/test_ai_router.py` | **Created** | Comprehensive test suite covering Tier 1, 2, 3 classification, complexity overrides, aliases, HTTP timeout parameters, and `generate(model_tier=...)` compatibility. |

---

## 3. Test Results & Verification

### 3.1 AI Router Suite (`backend/tests/test_ai_router.py`)
- **Command:** `python -m pytest tests/test_ai_router.py -v`
- **Result:** **8 passed in 0.27s**
  - `test_simple_mcq_task_returns_tier1` — **PASSED**
  - `test_normal_explanation_returns_tier2` — **PASSED**
  - `test_socratic_tutor_returns_tier3` — **PASSED**
  - `test_unknown_task_returns_tier2_default` — **PASSED**
  - `test_complexity_overrides` — **PASSED**
  - `test_router_aliases` — **PASSED**
  - `test_hardened_http_timeout_settings` — **PASSED**
  - `test_generate_accepts_optional_model_tier` — **PASSED**

### 3.2 Full AI Integration Suites
- **Command:** `python -m pytest tests/test_ai_router.py tests/test_ai_fallback_policy.py tests/test_ai_provider_fallback.py tests/test_ai_question.py tests/test_ziku_tutor.py -q`
- **Result:** **71 passed** (live run: `71 passed, 2 warnings in 2.01s`)

### 3.3 Full Backend Regression Baseline
- **Command:** `python -m pytest -q`
- **Phase delta:** `+8` new tests from `tests/test_ai_router.py`; 0 regressions.
- **Current repair-gate state (live run):** `942` collected → **933 passed, 9 failed**.
  The 9 failures are the pre-existing `test_ai_attachment.py` baseline for the non-existent
  `POST /api/ai/attachment-question` route and fail identically at `5a0bb7f`.

### 3.4 Git Whitespace and Formatting Check
- **Command:** `git diff --check`
- **Result:** `git -c core.whitespace=cr-at-eol diff --check` exits `0` — zero whitespace or
  line-ending defects. Plain `git diff --check` reports only `cr-at-eol` notices on added lines in
  `backend/tests/test_role_gate_coverage.py`, which is CRLF-authored at HEAD.

---

## 4. Backward Compatibility Confirmation

1. **Existing Service Callers Untouched:**
   - `ziku_tutor_service.py`: continues calling `await generate(uid, prompt, feature=AiFeature.CHAT)`.
   - `ziku_content_service.py`: continues calling `await generate(uid, prompt, feature=AiFeature.CONTENT)`.
   - `study_coach_service.py` & `exam_simulator_service.py`: completely unaffected.
2. **Existing HTTP Responses Unaltered:**
   - Error mapping (`_classify_ai_error`), quota consumption (`_consume_quota`), retry evaluation (`_is_retriable`), and activity logging (`record_ai_activity`) function without breaking changes.
3. **No Migration / DB Impact:**
   - Pure Python in-memory classification; no schema changes or database modifications.
