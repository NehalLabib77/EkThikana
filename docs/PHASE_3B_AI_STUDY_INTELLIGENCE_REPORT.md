# Phase 3B — AI Study Intelligence Report

## Status

| Field | Value |
|-------|-------|
| Phase | 3B |
| Status | Complete |
| Last Updated | 2026-09-19 |

---

## Existing AI Foundation

| Provider | Model | Role |
|----------|-------|------|
| Groq | qwen/qwen3.8-27b | Primary |
| Gemini | gemini-3.1-flash-lite | Fallback |
| OpenRouter | qwen/qwen-2.5-72b-instruct:free | Emergency |

**Infrastructure Reused:**
- `ai_service.py` — 3-provider cascade (GROQ → Gemini → OpenRouter)
- `AiFeature` enum — feature quota tracking
- `_consume_quota()` — atomic Firestore transactions
- `get_ai_usage()` — usage counters
- `require_student` — Firebase auth dependency
- `FirestoreService` — Flutter Firestore client
- `ApiService` — Flutter HTTP client with 403 retry

---

## Feature Status

| Feature | Backend | Flutter | Status |
|---------|---------|---------|--------|
| Assignment Assistant | Complete | Complete | Done |
| Quiz Generator | Enhanced | Enhanced | Done |
| Smart Study Planner AI | Complete | Complete | Done |
| ~~Revision Assistant~~ | Removed | Removed | Removed |

---

## Architecture Changes

### Backend

**File:** `backend/app/routers/ai_study.py`

| Endpoint | Method | Feature |
|----------|--------|---------|
| `POST /api/ai/assignment/explain` | POST | Explain assignment requirements |
| `POST /api/ai/assignment/breakdown` | POST | Break down into sections/concepts |
| `POST /api/ai/assignment/plan` | POST | Deadline-aware study plan |
| `POST /api/ai/quiz/generate` | POST | Generate quiz from source materials |
| `POST /api/ai/planner/recommend` | POST | AI daily recommendations |
| `POST /api/ai/context` | POST | Enhanced AI context builder |

**Modified:** `backend/app/main.py` — router registration added

### Flutter

**Files:**
- `flutter_app/lib/features/study/presentation/ai/assignment_assistant_screen.dart`
- `flutter_app/lib/features/study/presentation/ai/quiz_generator_screen.dart`
- `flutter_app/lib/features/study/presentation/ai/material_picker_sheet.dart`
- `flutter_app/lib/features/study/presentation/ai/smart_planner_screen.dart`

**Modified files:**
- `flutter_app/lib/services/api_service.dart` — API methods for all endpoints
- `flutter_app/lib/features/study/presentation/workspace/workspace_view.dart` — quick access items
- `flutter_app/lib/features/profile/presentation/ai_usage_screen.dart` — updated description

---

## Quiz Generator Enhancement

### Source Material Support

Users can now generate quizzes from:
1. **Selected materials** — PDF, DOC, DOCX, JPG, PNG, TXT
2. **Manual text input** — paste notes, textbook content, topics
3. **Combined sources** — multiple materials + manual text

### Material Picker

- Scrollable list of user's uploaded materials
- Search bar for filtering by title/subject
- File type icons (PDF, DOC, IMG, TXT)
- Multi-select with chips
- Upload date display

### Quiz Generation Flow

```
User selects source material(s)
        ↓
Backend extracts content (PDF text, OCR, file read)
        ↓
Content combined with manual input
        ↓
AI generates quiz based ONLY on source content
        ↓
Questions returned as JSON
```

### API Request Format

```json
{
  "source": "manual text (optional)",
  "sourceIds": ["material_id_1", "material_id_2"],
  "topic": "optional topic focus",
  "questionCount": 5,
  "difficulty": "medium",
  "questionType": "mcq"
}
```

### Content Extraction

- **PDF:** `extract_pdf_text()` with OCR fallback
- **Images:** `ocr_extract_text()` for text extraction
- **Text files:** Direct UTF-8 decode
- **Notes:** Firestore `notes` collection content

---

## Quota Integration

| Feature | Quota | Period | Tracked Via |
|---------|-------|--------|-------------|
| Assignment Assistant | Future-ready | — | Not consumed yet (uses chat daily limit) |
| Quiz Generator | 3/month | Monthly | `AiFeature.QUIZ` |
| Smart Planner AI | Future-ready | — | Not consumed yet (uses chat daily limit) |

---

## Security Rules

- Only user's own materials are accessible via `get_material_for_user()`
- Only user's own notes are accessible via `get_note_for_user()`
- Never send passwords, tokens, or other user data
- User isolation enforced via `require_student` + Firestore `ownerId` checks
- No cheating answers — learning assistance only
- Quiz generates questions ONLY from provided source material

---

## Testing Results

### Backend

- **523 tests passed** (pytest)
- **0 failures**
- All existing tests continue to pass

### Flutter

- **flutter analyze: No issues found**
- No warnings, no errors, no info messages

---

## Files Summary

### Backend (1 file modified, 1 file created)
- `backend/app/main.py` — router import + registration
- `backend/app/routers/ai_study.py` — endpoints (6 endpoints, ~550 lines)

### Flutter (4 files created, 3 files modified)
- `flutter_app/lib/features/study/presentation/ai/assignment_assistant_screen.dart` — new file
- `flutter_app/lib/features/study/presentation/ai/quiz_generator_screen.dart` — enhanced with materials
- `flutter_app/lib/features/study/presentation/ai/material_picker_sheet.dart` — new file
- `flutter_app/lib/features/study/presentation/ai/smart_planner_screen.dart` — new file
- `flutter_app/lib/services/api_service.dart` — API methods
- `flutter_app/lib/features/study/presentation/workspace/workspace_view.dart` — quick access items
- `flutter_app/lib/features/profile/presentation/ai_usage_screen.dart` — updated description

### Removed
- `flutter_app/lib/features/study/presentation/ai/revision_assistant_screen.dart` — deleted

---

## Quiz Source Wiring Fix

### Root Cause

Flutter sent `sourceIds` (camelCase) but backend `QuizGenerateRequest` used plain `BaseModel`, which only accepts `source_ids` (snake_case). Material IDs were silently ignored.

### Fix

Changed all request classes in `ai_study.py` from `BaseModel` to `_CamelModel`:

| Class | Field | Before | After |
|-------|-------|--------|-------|
| `QuizGenerateRequest` | `source_ids` | `BaseModel` | `_CamelModel` |
| `AssignmentExplainRequest` | all fields | `BaseModel` | `_CamelModel` |
| `AssignmentBreakdownRequest` | all fields | `BaseModel` | `_CamelModel` |
| `AssignmentPlanRequest` | all fields | `BaseModel` | `_CamelModel` |
| `SmartPlannerRecommendRequest` | all fields | `BaseModel` | `_CamelModel` |
| `ContextBuilderRequest` | all fields | `BaseModel` | `_CamelModel` |

`_CamelModel` config:
- `alias_generator`: converts snake_case → camelCase
- `populate_by_name=True`: accepts both `sourceIds` and `source_ids`

### Validation

- Backend pytest: 523 passed, 0 failures

---

## Quiz Timeout Fix

### Root Cause

Large source extraction (PDF read, OCR) + huge AI prompts caused Render worker timeout (502).

### Optimizations

| Change | Before | After |
|--------|--------|-------|
| PDF extraction | All pages | Max 10 pages |
| OCR in quiz | Fallback when text < 40 chars | Skipped entirely |
| Content per source | 3000 chars | 5000 chars |
| Total source limit | Unlimited | 15000 chars max |
| Text file limit | 10000 chars | 8000 chars |
| Timing logs | None | Extraction + AI timing |
| Error handling | Crash | Graceful timeout message |

### Files Changed

- `backend/app/routers/ai_study.py` — quiz endpoint optimization
- `backend/app/services/pdf_service.py` — `max_pages` parameter added

### Validation

- Backend pytest: 523 passed, 0 failures

---

## Implementation Notes

1. **No duplicate AI infrastructure** — all features reuse existing `ai_service.py` cascade
2. **No API keys in Flutter** — all AI calls go through the backend
3. **No duplicate file system** — uses existing materials/notes storage
4. **Learning assistance only** — prompts instruct AI not to generate cheating answers
5. **Quiz quota enforced** — uses existing `AiFeature.QUIZ` monthly limit (3/month)
6. **Context builder safe** — only returns user's own data, never passwords/tokens
7. **Source material extraction** — reuses existing PDF/OCR services

---

## Deployment Issue (Physical Test)

**Issue:** Phase 3B routes missing in production.

**Root Cause:** Phase 3B code was never committed to the deployed branch.

**Fix:** Committed and pushed all Phase 3B files:
```
commit 32ee098 feat: Phase 3B — AI Study Intelligence
```

**Validation:** Render will auto-deploy from `gochano-ui-rebuild-v1` branch.

---

**STOP** — Phase 3B complete. Do not start Phase 3C automatically.
