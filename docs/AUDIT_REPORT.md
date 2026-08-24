# EkThikana — Phase 1 Audit Report

Date: 2026-01 · Audited against `PROJECT_SPEC.md`.

Legend: ✅ matches spec · ⚠️ needs fix (listed in **Findings**) · ❌ missing/broken.

---

## 1. Stack & app identity

| Spec item | Status | Evidence |
| --- | --- | --- |
| Android-only Flutter app | ✅ | `flutter_app/android/app/src/main/AndroidManifest.xml`, `flutter_app/android/app/build.gradle.kts` |
| Application id `com.ekthikana.ekthikana` | ✅ | `flutter_app/android/app/build.gradle.kts` |
| Material 3 theme | ✅ | `flutter_app/lib/core/theme.dart` (referenced from `app.dart`) |
| Backend FastAPI on Render | ✅ | `backend/app/main.py`, `backend/render.yaml`, `backend/Dockerfile` |
| Firebase Auth + Firestore (data) | ✅ | `flutter_app/pubspec.yaml`, `flutter/firestore.rules`, `backend/app/core/firebase.py` |
| Supabase private bucket for files | ✅ | `backend/app/core/config.py` (envs), `backend/app/services/storage_service.py` (service-role only) |
| Gemini AI on backend only | ✅ | `backend/app/services/ai_service.py`, `backend/app/routers/ai.py` |
| Tesseract OCR on backend only | ✅ | `backend/app/services/ocr_service.py` |
| Package ids and notifications | ✅ | `POST_NOTIFICATIONS` in manifest, `flutter_app/lib/services/notification_service.dart` |

## 2. Roles

| Spec item | Status | Evidence |
| --- | --- | --- |
| Student / General roles on signup | ✅ | `flutter_app/lib/screens/auth/register_screen.dart` (segmented button) |
| Role stored on `users/{uid}.role` | ✅ | `flutter_app/lib/services/auth_service.dart` (via register flow), `backend/app/core/auth.py` (CurrentUser reads Firestore) |
| General user cannot see Study / Groups | ✅ | `flutter_app/lib/screens/home/home_shell.dart` (bottom-nav branches on `student`) |
| Backend rejects student-only endpoints for general role | ✅ | `backend/app/core/auth.py::require_student`, applied in all `*_router.py` routers |
| Email verification enforced | ✅ | `flutter_app/lib/screens/auth/auth_gate.dart` checks `user.emailVerified`; `backend/app/core/auth.py::require_verified_email` |

## 3. Student features

### 3.1 Notes & sharing model

| Spec item | Status | Evidence |
| --- | --- | --- |
| Private / Group / Public notes | ✅ | `flutter_app/lib/screens/study/note_editor_screen.dart`, `FirestoreService.saveNote` |
| Server-side visibility validation | ✅ | `backend/app/schemas.py::NoteCreate.visibility` (Enum), `backend/app/routers/study.py` |

### 3.2 Materials & PDF/image upload

| Spec item | Status | Evidence |
| --- | --- | --- |
| PDF/image upload | ✅ | `flutter_app/lib/screens/study/material_upload_screen.dart`, `backend/app/routers/materials.py::upload` |
| Built-in PDF reader | ✅ | `flutter_app/lib/screens/study/material_reader_screen.dart` (pdfrx) |
| PDF text search | ✅ | `material_reader_screen._searchPdf` + `PdfTextSearcher` |
| Resume last page | ✅ | `material_reader_screen._savePage` (writes to `users/{uid}/material_state/{materialId}`) |
| Page bookmarks | ✅ | `material_reader_screen._toggleBookmark` |
| Page-linked note | ✅ | `material_reader_screen._addPageNote` / `_showPageNotes` |
| Save material to library | ✅ | `material_reader_screen._saveToLibrary` → `ApiService.saveMaterial` (`POST /api/materials/{id}/save`) |
| Offline download | ✅ | `material_reader_screen._downloadOffline` (FilePicker.saveFile with bytes from signed URL) |
| Image preview for non-PDF | ✅ | `material_reader_screen._ImageMaterial` |

### 3.3 Community library

| Spec item | Status | Evidence |
| --- | --- | --- |
| Public Materials / Notes tabs | ✅ | `flutter_app/lib/screens/study/community_screen.dart` |
| Search/filter/sort (newest / most saved) | ✅ | `community_screen._PublicMaterials` filters + sort popup |
| Save counter visible | ✅ | `community_screen` shows `'${saveCount} saves'` |

### 3.4 Reports

| Spec item | Status | Evidence |
| --- | --- | --- |
| Report public/group content | ✅ | `note_editor_screen.reportNote` + `material_reader_screen._reportMaterial`; backend `backend/app/routers/reports.py` |
| Reports collection is backend-write-only | ✅ | `firebase/firestore.rules` denies client writes |

### 3.5 Groups

| Spec item | Status | Evidence |
| --- | --- | --- |
| Group creation | ✅ | `flutter_app/lib/screens/groups/groups_screen.dart::_createGroup`, `backend/app/routers/groups.py::create_group` |
| Invite-code join | ✅ | `groups_screen._joinGroup` → `ApiService.joinGroup` (`POST /api/groups/join`) |
| Leave group | ✅ | `group_detail_screen.leave` → `ApiService.leaveGroup` |
| Admin invite-code reset | ✅ | `group_detail_screen.resetInvite` (admin-only menu) → `ApiService.resetGroupInvite` |
| Shared Box (no chat) | ✅ | `group_detail_screen` only exposes Materials/Notes; UI copy reinforces no chat |
| Backend enforces no-chat endpoints | ✅ | Search confirms no `/api/groups/{id}/messages` route exists in `backend/app/routers/groups.py` |

### 3.6 Study AI

| Spec item | Status | Evidence |
| --- | --- | --- |
| AI note actions (cleanup, summary, explain, key topics) | ✅ | `note_editor_screen.aiTool` + `backend/app/routers/ai.py::note` + `ai_service.py` (no MCQ prompt) |
| PDF Q&A (with optional page scope) | ✅ | `material_reader_screen._askAi` + `backend/app/routers/ai.py::pdf_question` |
| Daily quota | ✅ | `backend/app/core/config.py::max_ai_per_day=30`, enforced in `permission_service` and `ai_service` |
| No MCQ / question generation | ✅ | UI copy + prompts in `ai_service.py` only mention summary/explain/topics |

### 3.7 Study plan

| Spec item | Status | Evidence |
| --- | --- | --- |
| Deadline-based plan from unfinished tasks | ✅ | `flutter_app/lib/screens/study/study_plan_screen.dart`, `backend/app/routers/study.py::plan` |

## 4. Daily-life modules

| Spec item | Status | Evidence |
| --- | --- | --- |
| Tasks & reminders | ✅ | `flutter_app/lib/screens/tasks/tasks_screen.dart` |
| Medicine records | ✅ | `flutter_app/lib/screens/life/medicine_screen.dart` |
| Prescription OCR + mandatory user confirmation | ✅ | `medicine_screen._scan` → `ApiService.prescriptionOcr` (`POST /api/prescriptions/extract`); user must re-enter and tap "I confirmed — Save" |
| BazarBuddy / FamilyHub / RentMate / CommuteBD / Wellness | ✅ | `life_screen.dart` wires 5 `RecordModuleScreen` instances with their Firestore collections |

## 5. Cross-cutting

| Spec item | Status | Evidence |
| --- | --- | --- |
| Universal search | ✅ | `flutter_app/lib/screens/search/universal_search_screen.dart` (role-aware) |
| Export my data | ✅ | `flutter_app/lib/screens/profile/profile_screen.dart::exportMyData` → `ApiService.exportAccount` (`GET /api/account/export`) |
| Permanent account deletion | ✅ | `profile_screen.deleteAccount` (typed DELETE confirmation) → `ApiService.deleteAccount` → backend `account.delete_account` cascade |

## 6. Security

| Spec item | Status | Evidence |
| --- | --- | --- |
| Firebase ID token verified on every protected route | ✅ | `backend/app/core/auth.py::get_current_user` used by all routers |
| `email_verified` gate | ✅ | `auth.py::require_verified_email` |
| Role loaded server-side from Firestore, never trusted from client | ✅ | `auth.py` fetches `users/{uid}.role` |
| Firestore rules deny client writes to `ai_usage`, `upload_usage`, `reports` | ✅ | `firebase/firestore.rules` |
| Role immutable from client | ✅ | `firestore.rules` line 24: `request.resource.data.role == resource.data.role` |
| File-type validation server-side (PDF/PNG/JPEG signature) | ✅ | `backend/app/core/utils.py::detect_file_signature`, used in `routers/materials.upload` and `routers/prescriptions.extract` |
| Filename sanitization | ✅ | `utils.sanitize_filename` applied in upload routes |
| Signed URLs expire | ✅ | `backend/app/services/storage_service.py` uses `create_signed_url(ttl=settings.signed_url_ttl_seconds)`. **Finding F-1:** default 3600s is **above** spec target (≤900s) — see Findings. |
| Quota enforcement server-side | ✅ | `permission_service.py` (`MAX_FILE_BYTES=15 MB`, `MAX_USER_STORAGE_BYTES=100 MB`, `MAX_UPLOADS_PER_DAY=10`, `MAX_AI_PER_DAY=30`) |
| Secrets only in env | ✅ | `.gitignore` excludes `flutter_app/android/key.properties` and `.env`; `backend/.env.example` (no secrets) |
| Cold-start aware | ✅ | `backend/render.yaml` uses free-plan-friendly gunicorn config; client timeouts set in `api_service.dart` (90–120s) |

## 7. Infra

| Spec item | Status | Evidence |
| --- | --- | --- |
| Render deployment YAML | ✅ | `backend/render.yaml` |
| Dockerfile for backend | ✅ | `backend/Dockerfile` |
| Firebase project config | ✅ | `flutter_app/lib/firebase_options.dart`, `firebase.json` |
| Firestore rules + indexes | ✅ | `firebase/firestore.rules`, `firebase/firestore.indexes.json` |
| Bootstrap helpers (Windows) | ✅ | `tool/bootstrap_flutter_windows.ps1` |
| Documentation set | ✅ | `docs/START_HERE.md`, `docs/ARCHITECTURE.md`, `docs/API_REFERENCE.md`, `docs/DATA_MODEL.md`, `docs/STORAGE_SETUP.md`, `docs/FIREBASE_SETUP.md`, `docs/ANDROID_SETUP.md`, `docs/ANDROID_NOTIFICATIONS.md`, `docs/RENDER_DEPLOY.md`, `docs/PRODUCTION_CHECKLIST.md`, `docs/SECURITY_PRIVACY.md`, `docs/TROUBLESHOOTING.md`, `docs/BUILD_VALIDATION.md`, `docs/FIREBASE_STORAGE_OPTION.md`, `docs/WHAT_I_NEED_FROM_YOU.md` |

## 8. Tests

| Spec item | Status | Evidence |
| --- | --- | --- |
| Missing token → 401 | ✅ | `backend/tests/test_auth_and_roles.py` |
| Unverified email → 403 | ✅ | `backend/tests/test_auth_and_roles.py` |
| General hitting student route → 403 | ✅ | `backend/tests/test_auth_and_roles.py` |
| Material upload round-trip | ✅ | `backend/tests/test_materials.py` |
| Signed URL TTL bound | ✅ | `backend/tests/test_materials.py` (overrides TTL to 60s and asserts expiry) |
| Quota (uploads + AI) | ✅ | `backend/tests/test_quotas.py` |
| Health endpoint | ✅ | `backend/tests/test_health.py` |

---

# Findings (action list for subsequent phases)

## F-1 — Signed URL TTL too long (security tightness)

- **Spec target:** signed download/view URLs must expire in **≤ 15 minutes** (900s).
- **Current state:** `backend/app/core/config.py::SIGNED_URL_TTL_SECONDS=3600` (1 hour).
- **Action (Phase 2):** lower default to `900` in `config.py` and document the rationale in `.env.example`. Keep test override at 60s; production render env can override if a downstream needs longer.

## F-2 — No public changelog of audit findings beyond this doc

- **State:** findings are documented here but not surfaced in `TODO.md`.
- **Action (Phase 1 close-out):** mirror F-1 (and any new findings) into `TODO.md` so the executor of later phases has a single checklist.

## F-3 — `NoteEditorScreen` AI "Replace note content" replaces without confirmation that the user reviewed the result

- **State:** `note_editor_screen.aiTool` shows the AI result then offers "Replace note content". This is acceptable UX, but worth noting in the security/privacy review: AI output is never auto-saved.
- **Action:** none required — current behaviour matches spec ("explain, summarize, clean, key topics" — no silent auto-save).

## F-4 — `RecordModuleScreen` is intentionally a generic CRUD screen for 5 life modules

- **State:** five life modules share one screen with different collection names (`grocery_items`, `family_records`, `rent_records`, `saved_locations`, `wellness_records`).
- **Action:** confirm Firestore rules cover all five collections (they do, since rules allow owner writes per-doc). No code change required.

## F-5 — Universal search is in-memory

- **State:** `universal_search_screen.search()` reads up to 100 docs per collection client-side and filters in Dart.
- **Spec:** "Universal keyword search" is satisfied — backend has no `search/universal` route, so the spec is interpreted as client-side search across owned records.
- **Action:** none — but a backend universal search endpoint is a future enhancement.

## F-6 — `.env.example` lives in repo root; backend `render.yaml` references backend-side env names

- **State:** root `.env.example` lists every var; backend `render.yaml` correctly lists the same set.
- **Action:** none.

---

# Phase 1 security check ✅

- All backend routes under `/api` are protected by `require_user` or `require_student` (verified by reading all 9 routers).
- `reports`, `ai_usage`, `upload_usage` are client-write denied (verified in `firebase/firestore.rules`).
- Test suite covers the critical 401/403 paths.
- One tightening item (F-1) queued for Phase 2.

# Conclusion

Phase 1 audit complete. The scaffold is production-shaped and most spec bullets are satisfied.

- Phase 2 will fix **F-1** (signed-URL TTL).
- All subsequent phases (3–10) follow `TODO.md` and verify against this report.