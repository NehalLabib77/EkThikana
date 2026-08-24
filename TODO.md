# TODO — EkThikana Implementation Phases

This is the working checklist for the EkThikana build. Every phase is gated by `PROJECT_SPEC.md`. The **Working rule** from the plan applies: audit first, then modify only what is incomplete, broken, insecure, or inconsistent. Anything already satisfying the spec is **not** rewritten.

> Mark items with `[x]` when complete, `[~]` when partial, `[ ]` when open. Each phase ends with a security check.

---

## Phase 0 — Spec & tracking

- [x] Author `PROJECT_SPEC.md` from the user request.
- [x] Author `TODO.md` (this file) with the phase list + External Credentials section.
- [x] Reconcile `.env.example` against `backend/app/core/config.py` (no edits required; values already match).
- [x] **Security check:** every required backend route from §9 of `PROJECT_SPEC.md` is listed in the spec.

## Phase 1 — Audit & gap report

- [x] Read every `backend/app/**/*.py`, `flutter_app/lib/**/*.dart`, `firebase/*`, and existing docs.
- [x] Produce `docs/AUDIT_REPORT.md` with ✅/⚠️/❌ for every spec bullet (auth, role gating, study, materials, groups, community, AI, daily-life, notifications, search, profile/export/delete, security, infra).
- [x] Derive the minimal change list — only ⚠️/❌ items become work in Phases 2–10.
- [x] **Security check:** every router enforces token + `email_verified` + role; `firestore.rules` denies client writes to `reports`, `ai_usage`, `upload_usage`.

### Phase 1 findings rolled into Phase 2–4

| ID | Severity | Item | Phased fix |
| --- | --- | --- | --- |
| F-1 | ⚠️ security tightness | `SIGNED_URL_TTL_SECONDS` default 3600s > spec ≤ 900s | Phase 2 — lower default to 900 and document |
| F-2 | ✅ process | Audit report mirrors Phase 1 work | Phase 1 close-out (this update) |
| F-3 | ✅ acceptable | AI result replaces note only after user taps "Replace" | None — matches spec |
| F-4 | ✅ acceptable | Five life modules share one generic CRUD screen | None — collection rules cover all |
| F-5 | ✅ acceptable | Universal search is client-side across owned records | None — matches spec wording |
| F-6 | ✅ aligned | `.env.example` matches `config.py` and `render.yaml` | None |

## Phase 2 — Auth & role gating

- [x] Fix gaps in `backend/app/core/auth.py` (`CurrentUser`, `require_student`, role from `users/{uid}`).
- [x] Fix gaps in `flutter_app/lib/services/auth_service.dart` (sign-in, `emailVerified`, role stream, account deletion with reauth).
- [x] Fix gaps in `flutter_app/lib/screens/home/home_shell.dart` (hide Study/Groups for General).
- [x] Fix gaps in `firestore.rules` (deny client role changes).
- [x] **F-1 fix:** lower default `SIGNED_URL_TTL_SECONDS` 3600 → 900 (`backend/app/core/config.py`) and update `backend/.env.example` to match. Test suite still green (14/14).
- [x] **Security check:** tests for missing token (401), unverified email (403), wrong role (403), role tampering rejected.

## Phase 3 — Study

- [x] Fix gaps in `flutter_app/lib/screens/study/` (semesters, subjects, notes, AI actions, study planner).
- [x] Verify `permission_service.py` enforces `private | group | public` visibility.
- [x] Verify AI features route through backend only (`/api/ai/note`, `/api/ai/pdf-question`, `/api/study/plan`).
- [x] **Security check:** no MCQ/auto-question endpoints; AI key never in Flutter; AI quota server-side.

## Phase 4 — PDF reader & storage

- [x] Fix gaps in `material_reader_screen.dart` (reader, text search, last-page resume, page bookmarks, page-linked notes).
- [x] Fix gaps in `materials.py` (file-signature validation, filename sanitize, randomized paths, short-lived signed URLs, 15 MB / 100 MB / 10/day).
- [x] Fix gaps in `storage_service.py` (Supabase service-role key only; no Render-disk persistence).
- [x] **Security check:** signed URL TTL ≤ 15 min; non-owner private denied; non-member group denied.

## Phase 5 — Groups

- [x] Fix gaps in `groups.py` and screens (create/join/leave/reset-invite, owner+admins+members).
- [x] Remove any chat/messaging surface if found (spec forbids).
- [x] **Security check:** admin-only invite reset; non-members cannot read group materials.

## Phase 6 — Community Library

- [x] Fix gaps in `community_screen.dart` and `saved_materials_screen.dart` (filters, search, sort, preview, save, download, report).
- [x] Fix gaps in `reports.py` if reports are not server-side-only.
- [x] **Security check:** verified-Student-only public read; `originalOwnerId` preserved on save; reports dedupe per `reporter+material`.

## Phase 7 — Study AI

- [x] Fix gaps in `ai_service.py` (Gemini call, retry/timeout, quota, no MCQ prompts, page-targeted extraction).
- [x] Fix gaps in `pdf_service.py` if extraction is unbounded.
- [x] **Security check:** AI key from env only; daily quota enforced; responses sanitized.

## Phase 8 — Daily-Life

- [x] Fix gaps in screens for Tasks, Reminders, Medicine, Prescription OCR, BazarBuddy, FamilyHub, RentMate, CommuteBD, Wellness.
- [x] Verify prescription flow requires user confirmation (`confirmedByUser: true`) before saving medicine.
- [x] **Security check:** OCR endpoint never auto-writes medicine records.

## Phase 9 — Search, notifications, profile/export/delete

- [x] Fix gaps in `universal_search_screen.dart` (role-aware results).
- [x] Fix gaps in `notification_service.dart` (timezone `Asia/Dhaka`).
- [x] Fix gaps in profile screen (export via `GET /api/account/export`, deletion via `DELETE /api/account`, confirmation dialog).
- [x] **Security check:** export scoped to requesting user; deletion cascades and is irreversible.

## Phase 10 — Production & security hardening

- [x] Fix gaps in `firebase.json`, `render.yaml`, `Dockerfile`, `firestore.indexes.json`, `.gitignore`.
- [x] Restrict CORS via env (no wildcard in production).
- [x] Run `pytest backend/tests/` and `flutter analyze`; fix only errors we caused or pre-existing failures.
- [x] Update `docs/PRODUCTION_CHECKLIST.md` and `docs/BUILD_VALIDATION.md` with actual run results.

## Phase 11 — Final audit

- [x] Re-walk `PROJECT_SPEC.md` line by line; record every ✅ in `docs/FINAL_AUDIT.md` with file:line evidence.
- [x] Mark project production-ready only after `docs/FINAL_AUDIT.md` is fully ticked.

---

## External credentials still required

The repository contains **no real secrets**. These placeholders must be provided by the operator and stored only in Render environment variables / `firebase_options.dart` / `google-services.json` (gitignored):

| Placeholder | Used by | Where it goes |
|---|---|---|
| `FIREBASE_PROJECT_ID` | Backend admin SDK | Render env |
| `FIREBASE_SERVICE_ACCOUNT_B64` | Backend admin SDK (base64-encoded service-account JSON) | Render env |
| `SUPABASE_URL` | Storage backend | Render env |
| `SUPABASE_SERVICE_ROLE_KEY` | Storage backend (private bucket) | Render env |
| `SUPABASE_BUCKET` | Storage backend | Render env (defaults to `ekthikana-files`) |
| `GEMINI_API_KEY` | Study AI | Render env |
| `GEMINI_MODEL` | Study AI | Render env (defaults to `gemini-3.7-flash`) |
| Firebase Web/Android config | Flutter client | `flutter_app/lib/firebase_options.dart` + `google-services.json` (gitignored) |

No real values are committed to source at any point.
