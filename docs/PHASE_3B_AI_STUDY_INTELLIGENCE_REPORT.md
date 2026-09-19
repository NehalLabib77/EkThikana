# Phase 3B — AI Study Intelligence Report

## Status

| Field | Value |
|-------|-------|
| Phase | 3B |
| Status | Complete |
| Last Updated | 2026-09-20 |

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
| Quiz Generator | Complete | Complete | Done |
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

### Supported Source Materials

| Source | Type | Extraction Method |
|--------|------|-------------------|
| PDF | Document | `extract_pdf_text()` — max 10 pages |
| DOC/DOCX | Document | Direct UTF-8 decode |
| TXT | Document | Direct UTF-8 decode |
| Notes | Note | Firestore `notes` collection content |
| Manual text | Input | User pasted text |

### Material Picker

- Scrollable list of user's uploaded **documents only** (images excluded)
- Search bar for filtering by title/subject
- File type icons: PDF, DOC, TXT
- Multi-select with chips
- Upload date display

### Quiz Generation Flow

```
Source Material
|
├── PDF
├── DOC/DOCX
├── TXT
├── Notes
└── Manual Text

        ↓

Text Extraction

        ↓

AI Quiz Generation

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

- **PDF:** `extract_pdf_text()` — limited to 10 pages, max 8000 chars
- **DOC/DOCX:** Direct UTF-8 decode, max 8000 chars
- **TXT:** Direct UTF-8 decode, max 8000 chars
- **Notes:** Firestore `notes` collection content, max 5000 chars per note
- **Total source limit:** 15000 chars max

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

### Backend
- `backend/app/main.py` — router import + registration
- `backend/app/routers/ai_study.py` — endpoints (6 endpoints)

### Flutter
- `flutter_app/lib/features/study/presentation/ai/assignment_assistant_screen.dart`
- `flutter_app/lib/features/study/presentation/ai/quiz_generator_screen.dart`
- `flutter_app/lib/features/study/presentation/ai/material_picker_sheet.dart`
- `flutter_app/lib/features/study/presentation/ai/smart_planner_screen.dart`
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

| Class | Before | After |
|-------|--------|-------|
| `QuizGenerateRequest` | `BaseModel` | `_CamelModel` |
| `AssignmentExplainRequest` | `BaseModel` | `_CamelModel` |
| `AssignmentBreakdownRequest` | `BaseModel` | `_CamelModel` |
| `AssignmentPlanRequest` | `BaseModel` | `_CamelModel` |
| `SmartPlannerRecommendRequest` | `BaseModel` | `_CamelModel` |
| `ContextBuilderRequest` | `BaseModel` | `_CamelModel` |

`_CamelModel` config:
- `alias_generator`: converts snake_case → camelCase
- `populate_by_name=True`: accepts both `sourceIds` and `source_ids`

### Validation

- Backend pytest: 523 passed, 0 failures

---

## Quiz Timeout Fix

### Root Cause

Large PDF extraction + huge AI prompts caused Render worker timeout (502).

### Optimizations

| Change | Before | After |
|--------|--------|-------|
| PDF extraction | All pages | Max 10 pages |
| Content per source | 3000 chars | 5000 chars |
| Total source limit | Unlimited | 15000 chars max |
| Text file limit | 10000 chars | 8000 chars |
| Timing logs | None | Extraction + AI timing |
| Error handling | Crash | Graceful timeout message |

### Validation

- Backend pytest: 523 passed, 0 failures

---

## Material System Fix

### Changes

| File | Change |
|------|--------|
| `material_picker_sheet.dart` | Shows only documents (PDF, DOC, DOCX, TXT) |
| `material_upload_screen.dart` | Added TXT to allowed extensions |
| `ai_study.py` | Image/OCR removed from quiz extraction |
| `utils.py` | Added TXT detection with printable-text heuristic |

### Quiz Source Scope

| Source | Supported |
|--------|-----------|
| PDF | Yes |
| DOC/DOCX | Yes |
| TXT | Yes |
| Notes | Yes |
| Manual pasted text | Yes |
| JPG/PNG images | No |

---

## Material Management Fix

### Changes

| File | Change |
|------|--------|
| `material_picker_sheet.dart` | Dual-mode picker: quiz (docs only) + general (all types + upload + delete) |
| `material_picker_sheet.dart` | Upload button with inline title dialog |
| `material_picker_sheet.dart` | Delete button with confirmation dialog |
| `material_picker_sheet.dart` | Runtime type detection (mimeType + fileName) |

### Picker Modes

**Quiz Mode** (`showMaterialPicker`):
- Shows only documents (PDF, DOC, DOCX, TXT)
- No upload button, no delete button
- Multi-select for quiz generation

**General Mode** (`showGeneralMaterialPicker`):
- Shows all materials with categories (Documents, Images)
- Upload button in search bar
- Delete button on each tile
- Categories: Documents (PDF, DOC, DOCX, TXT) + Images (JPG, PNG)

### Runtime Type Detection

Classifies materials by `mimeType` and `fileName` extension:
- PDF: `application/pdf` or `.pdf` → document
- DOC/DOCX: `application/msword` or `.doc/.docx` → document
- TXT: `text/plain` or `.txt` → document
- JPG/PNG: `image/*` or `.jpg/.jpeg/.png` → image

### Upload Flow

```
Tap upload icon → File picker → Select file → Title dialog → Upload → Refresh list
```

Supported: PDF, DOC, DOCX, TXT, JPG, JPEG, PNG

### Delete Flow

```
Tap delete icon → Confirmation dialog → Delete from Firestore + Storage → Refresh list
```

Owner-only via existing `ApiService.deleteMaterial()`.

### Validation

- Backend pytest: 523 passed, 0 failures
- Flutter analyze: No issues found

---

## Implementation Notes

1. **No duplicate AI infrastructure** — all features reuse existing `ai_service.py` cascade
2. **No API keys in Flutter** — all AI calls go through the backend
3. **No duplicate file system** — uses existing materials/notes storage
4. **Learning assistance only** — prompts instruct AI not to generate cheating answers
5. **Quiz quota enforced** — uses existing `AiFeature.QUIZ` monthly limit (3/month)
6. **Context builder safe** — only returns user's own data, never passwords/tokens

---

## Deployment

Phase 3B deployed via branch `gochano-ui-rebuild-v1`. Render auto-deploys on push.

---

**STOP** — Phase 3B complete. Do not start Phase 3C automatically.
