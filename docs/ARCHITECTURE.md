# EkThikana architecture

## High-level

EkThikana is a single-product app with two user roles (Student, General) running on:

- **Flutter (Android)** — UI, auth, Firestore reads, signed-URL consumption, PDF reader, OCR upload, notifications.
- **FastAPI (Python 3.12)** — privileged operations: file storage uploads/downloads, AI calls, quotas, reporting, account deletion, signed URLs.
- **Firebase** — Authentication (email/password), Cloud Firestore (data + permissions), Cloud Functions not required.
- **Supabase Storage** — private object bucket for all user-uploaded files. The service-role key never leaves the backend.
- **Gemini Developer API** — Study AI (`/api/ai/note`, `/api/ai/pdf-question`). Optional; app remains functional if disabled.

```
┌──────────────┐   Firebase ID token    ┌──────────────────────┐
│ Flutter app  │ ──────────────────────▶│ FastAPI backend      │
│  (Android)   │ ◀────────────────────  │  (Render)            │
│              │   signed URLs / JSON   │                      │
└──────┬───────┘                        └──────┬───────────────┘
       │  Firestore reads/writes                │
       │  (Firestore Security Rules)           │
       ▼                                       ▼
┌──────────────┐                        ┌──────────────┐
│ Cloud        │                        │ Supabase     │
│ Firestore    │                        │ Storage      │
└──────────────┘                        │ (private)    │
                                        └──────────────┘
```

## Module map

### Backend (`backend/app/`)

- `core/auth.py` — Firebase ID-token verification, `CurrentUser` dependency, `require_student` role guard, `delete_account` cascading.
- `core/config.py` — `pydantic-settings` env loader. `get_settings()` is cached.
- `core/firebase.py` — Firebase Admin SDK bootstrap (`_ensure_firebase`) and Firestore client getter.
- `core/utils.py` — filename safety, supported-file detection, keyword extraction.
- `routers/account.py` — `DELETE /api/account`, `GET /api/account/export`.
- `routers/ai.py` — `POST /api/ai/note`, `POST /api/ai/pdf-question`.
- `routers/groups.py` — Group create/join/leave, member-management rules.
- `routers/health.py` — `GET /api/health`.
- `routers/materials.py` — Upload, signed-URL minting, save, delete.
- `routers/me.py` — Profile read/update.
- `routers/prescriptions.py` — OCR upload + line extraction (no auto-save of medicine data).
- `routers/reports.py` — In-app content reporting.
- `routers/study.py` — Study-plan generation using AI (no MCQs).
- `services/ai_service.py` — Quota + Gemini call.
- `services/ocr_service.py` — Tesseract wrapper.
- `services/pdf_service.py` — Page-targeted PDF text extraction.
- `services/permission_service.py` — Material/note access decisions (owner / public / group member).
- `services/storage_service.py` — Supabase Storage adapter (upload, signed URL, download, delete).

### Flutter (`flutter_app/lib/`)

- `core/app_config.dart` — `API_BASE_URL` via `--dart-define`.
- `core/theme.dart`, `core/ui.dart` — Material 3 theme and shared widgets.
- `services/auth_service.dart` — Email/password sign-in/up, email-verification gating, current-user stream, role lookup, account deletion with credential reauth.
- `services/api_service.dart` — HTTP client over Firebase ID tokens, with `materialUrl`, `reportContent`, `exportAccount`, AI endpoints.
- `services/firestore_service.dart` — Typed CRUD helpers per module.
- `services/notification_service.dart` — Local notifications for tasks/medicines.
- `screens/auth/` — Sign-in, sign-up, email-verification.
- `screens/home/` — Role-aware dashboard.
- `screens/study/` — Notes, materials, PDF reader, community, study plan, saved materials.
- `screens/groups/` — Group browsing, member management.
- `screens/tasks/` — Task & reminder CRUD.
- `screens/life/` — Medicines, Bazar, Family, Rent, Commute, Wellness.
- `screens/profile/` — Profile + export + delete account.
- `screens/search/` — Universal role-aware search.

## Data ownership

All collections are partitioned by `ownerId == request.auth.uid` (Firestore rules), except:

- `users/{uid}` — the user owns their profile.
- `materials/{id}` — owner writes everything; public materials are world-readable to verified students; group materials readable to group members.
- `groups/{id}` — owner writes membership; members read.
- `reports/{id}` — backend-only; Flutter cannot read or write.
- `ai_usage/{uid_day}`, `upload_usage/{uid_day}` — backend-only quota documents.

## Why this split

- **Flutter holds no secrets.** The service-role Supabase key, the Gemini key, and the Firebase Admin credential never enter the client. All privileged operations cross the backend boundary.
- **Backend holds no permanent blobs.** Local disk is not used for user data. Files live in Supabase; bytes flow through signed URLs.
- **Quotas live in Firestore.** AI and upload daily counters live in documents that only the backend can mutate (`firestore.rules` denies client writes), making tamper-resistant metering cheap.

## Failure modes

- **Cold starts.** Render free-tier sleeps. The first request after idle returns slowly; Flutter surfaces a retryable message.
- **Email verification.** Every data route requires a verified email. Sign-in alone does not grant data access.
- **Role changes.** `users.role` is set at profile creation and is immutable from the client. To switch roles, create a new account.
