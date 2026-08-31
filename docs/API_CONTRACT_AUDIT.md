# API contract audit

> **Source.** Backend routers mounted under `/api` in `backend/app/main.py`.
> **Auth.** Every endpoint (except `/health`) requires `Authorization: Bearer <firebase-id-token>`. The dependency `app.core.auth.require_user` verifies the token and returns `UserContext(uid, email, role)`.

> **Symbol legend.**
> ✅ implemented · 🟡 partial · 🔴 missing · 🧹 legacy · ❓ needs live verification

---

## 1. `/api/health`

| Method | Path | Auth | Purpose | Status |
|---|---|---|---|---|
| GET | `/api/health` | none | Liveness | ✅ |

Response:
```json
{ "status": "ok" }
```

---

## 2. `/api/account`

| Method | Path | Auth | Purpose | Frontend consumer | Status |
|---|---|---|---|---|---|
| GET | `/api/account/me` | required | Profile snapshot (uid, email, role, displayName, photoUrl) | `profile_screen.dart` | ✅ |
| PATCH | `/api/account/me` | required | Update profile (displayName, photoUrl, language) | `profile_screen.dart` | ✅ |
| GET | `/api/account/export` | required | Streams JSON + PDF to client, also uploads to Storage | `profile_screen.dart` (export action) | ✅ |
| DELETE | `/api/account/delete` | required | Deletes Firestore + Storage + Postgres user data | `profile_screen.dart` | 🟡 (verify Postgres cleanup of `fare_reports`) |

---

## 3. `/api/study`

| Method | Path | Auth | Purpose | Frontend consumer | Status |
|---|---|---|---|---|---|
| GET | `/api/study/semesters` | required | List semesters | `academic_structure_screen.dart` | ✅ |
| POST | `/api/study/semesters` | required | Create | `academic_structure_screen.dart` | ✅ |
| PATCH | `/api/study/semesters/{id}` | required | Update | `academic_structure_screen.dart` | ✅ |
| DELETE | `/api/study/semesters/{id}` | required | Delete | `academic_structure_screen.dart` | ✅ |
| GET | `/api/study/subjects` | required | List subjects | `academic_structure_screen.dart` | ✅ |
| POST | `/api/study/subjects` | required | Create | `academic_structure_screen.dart` | ✅ |
| PATCH | `/api/study/subjects/{id}` | required | Update | `academic_structure_screen.dart` | ✅ |
| DELETE | `/api/study/subjects/{id}` | required | Delete | `academic_structure_screen.dart` | ✅ |
| GET | `/api/study/notes` | required | List notes | `notes_screen.dart` | ✅ |
| POST | `/api/study/notes` | required | Create | `note_editor_screen.dart` | ✅ |
| PATCH | `/api/study/notes/{id}` | required | Update | `note_editor_screen.dart` | ✅ |
| DELETE | `/api/study/notes/{id}` | required | Delete | `notes_screen.dart` | ✅ |
| GET | `/api/study/tasks` | required | List tasks | `tasks_screen.dart` | ✅ |
| POST | `/api/study/tasks` | required | Create | `tasks_screen.dart` | ✅ |
| PATCH | `/api/study/tasks/{id}` | required | Update | `tasks_screen.dart` | 🟡 (verify reminder reschedule on PATCH) |
| DELETE | `/api/study/tasks/{id}` | required | Delete | `tasks_screen.dart` | 🟡 (verify reminder cancel on DELETE) |

> Frontend actually reads/writes most of these directly through Firestore SDK. Backend is the **privileged fallback** and the only path used by `/api/study/tasks` when the client prefers the JWT-guarded surface.

---

## 4. `/api/materials`

| Method | Path | Auth | Purpose | Frontend consumer | Status |
|---|---|---|---|---|---|
| POST | `/api/materials/upload-url` | required | Returns signed upload URL + storage path | `material_upload_screen.dart` | ✅ |
| POST | `/api/materials/register` | required | Persists Firestore metadata after upload | `material_upload_screen.dart` | ✅ |
| GET | `/api/materials` | required | List user's materials | `materials_screen.dart` | ✅ |
| GET | `/api/materials/{id}/download-url` | required | Signed download URL (15 min TTL) | `material_reader_screen.dart` | ✅ |
| DELETE | `/api/materials/{id}` | required | Delete metadata + Storage object | `materials_screen.dart` | ✅ |
| PATCH | `/api/materials/{id}/replace` | required | Replace file in place; preserves Firestore id | `material_replace_flow` | 🟡 (verify flow exists end-to-end) |

---

## 5. `/api/groups`

| Method | Path | Auth | Purpose | Frontend consumer | Status |
|---|---|---|---|---|---|
| POST | `/api/groups` | required | Create group | `group_create_screen.dart` | ✅ |
| GET | `/api/groups` | required | List user's groups | `groups_screen.dart` | ✅ |
| GET | `/api/groups/{id}` | required | Group detail | `group_detail_screen.dart` | ✅ |
| PATCH | `/api/groups/{id}` | required admin | Update name | `group_admin_screen.dart` | ✅ |
| DELETE | `/api/groups/{id}` | required admin | Delete group | `group_admin_screen.dart` | ✅ |
| POST | `/api/groups/{id}/members` | required admin | Add member | `group_admin_screen.dart` | ✅ |
| DELETE | `/api/groups/{id}/members/{uid}` | required admin | Remove member | `group_admin_screen.dart` | ✅ |
| POST | `/api/groups/{id}/resources` | required member | Upload group resource | `group_resource_upload_screen.dart` | ✅ |
| GET | `/api/groups/{id}/resources` | required member | List group resources | `group_detail_screen.dart` | ✅ |
| GET | `/api/groups/{id}/resources/{rid}/download-url` | required member | Signed URL | `group_resource_screen.dart` | ✅ |
| DELETE | `/api/groups/{id}/resources/{rid}` | required uploader/admin | Delete | `group_detail_screen.dart` | ✅ |

`/api/groups/{id}/messages` — 🧹 LEGACY (group chat). Decision: remove or feature-flag.

---

## 6. `/api/ai`

| Method | Path | Auth | Purpose | Frontend consumer | Status |
|---|---|---|---|---|---|
| POST | `/api/ai/chat` | required | Send user message → Gemini → return reply + token count | `ai_assistant_screen.dart` | ✅ |
| GET | `/api/ai/history` | required | List conversations | `ai_assistant_screen.dart` | ✅ |
| GET | `/api/ai/conversations/{id}` | required | Get one conversation | `ai_assistant_screen.dart` | ✅ |
| DELETE | `/api/ai/conversations/{id}` | required | Delete conversation | `ai_assistant_screen.dart` | ✅ |
| POST | `/api/ai/upload` | required | Upload doc → signed URL → attach to conversation | (not yet wired in UI) | 🟡 |

Daily quota: 30 requests / day (enforced server-side). Configurable via `AI_DAILY_QUOTA`.

---

## 7. `/api/prescriptions`

| Method | Path | Auth | Purpose | Frontend consumer | Status |
|---|---|---|---|---|---|
| POST | `/api/prescriptions/upload` | required | Upload prescription image, get OCR result | `medicine_ocr_screen.dart` | ✅ |
| GET | `/api/prescriptions/{id}` | required | Fetch OCR result | `medicine_ocr_screen.dart` | ✅ |
| POST | `/api/prescriptions/{id}/confirm` | required | Confirm parsed fields → create Medicine + schedule doses | `medicine_ocr_screen.dart` | 🟡 (verify the explicit user-confirm step exists) |

---

## 8. `/api/commute`

| Method | Path | Auth | Purpose | Frontend consumer | Status |
|---|---|---|---|---|---|
| GET | `/api/commute/places/search?q=…` | required | Substring place search | `commute_bd_screen.dart` | ✅ |
| GET | `/api/commute/places/nearest?lat=&lng=&radius_km=` | required | Nearest place | `commute_bd_screen.dart` | ✅ |
| POST | `/api/commute/routes` | required | Compute route + fare | `commute_bd_screen.dart` | ✅ |
| POST | `/api/commute/fare-report` | required | Persist a fare report (deterministic ID) | `commute_bd_screen.dart` | ✅ |
| GET | `/api/commute/fare-report` | required | List user's reports | `commute_bd_screen.dart` | ✅ |

External calls: **OSRM** (route geometry/distance) + **Nominatim** (reverse geocoding). Public servers, public rate limits — keep an eye on usage.

---

## 9. `/api/reports`

| Method | Path | Auth | Purpose | Frontend consumer | Status |
|---|---|---|---|---|---|
| GET | `/api/reports/{kind}` | required | Streams generated PDF / JSON | `profile_screen.dart` | ✅ |

---

## 10. `/api/part3`

This router wraps the legacy Part-3 endpoints (financial surfaces, BazarBuddy, medicine taken dose, task reminders). Most of these are read/write-mirrors of Firestore — the backend path is **privileged** but the live UI surface is Firestore-direct.

| Method | Path | Purpose | Status |
|---|---|---|---|
| POST | `/api/part3/financial-transactions` | Write idempotent expense | ✅ |
| GET | `/api/part3/financial-transactions` | List user's transactions | ✅ |
| POST | `/api/part3/bazar-items` | Add bazar item (optionally creates expense) | 🟡 |
| POST | `/api/part3/bazar-items/{id}/purchase` | Mark purchased, create expense | 🟡 |
| POST | `/api/part3/medicine-doses` | Mark dose taken, optionally create expense | 🟡 |
| POST | `/api/part3/task-reminders` | Schedule a reminder | 🟡 |
| PATCH | `/api/part3/task-reminders/{id}` | Reschedule reminder on edit | 🟡 |
| DELETE | `/api/part3/task-reminders/{id}` | Cancel reminder on task delete | 🟡 |

---

## 11. Error envelope

```json
{ "detail": "human-readable message", "code": "stable.error.code" }
```

The brief's centralized error handling target should normalize on this shape and ensure every router returns it (not raw exception text).

---

## 12. Auth + role enforcement summary

| Layer | Where | What |
|---|---|---|
| Firebase ID token verify | `app/core/auth.py` `require_user` | required on all but `/health` |
| Role check | `app/core/permission_service.py` | `student_required` decorator on student-only routers |
| UI hide | `screens/auth/auth_gate.dart` + `home_shell.dart` tab rebuild | hides Study tab + AI tab for `general` role |
| Firestore rules | `firebase/firestore.rules` | owner-scope enforced |

---

## 13. CORS

`config.cors_origins` includes `http://localhost:50505` (dev). Production needs the live Flutter Web origin if/when added — currently Android-only so irrelevant.

---

## 14. Outbound dependencies

| Service | Used by | Quota / cost |
|---|---|---|
| Firebase Auth | auth | Free tier |
| Firestore | app data | Free tier — verify quotas before viral growth |
| Firebase Storage | files | Pay-as-you-go after free 5 GB |
| Gemini API | AI | Free tier `gemini-2.5-flash`; verify model selection |
| OSRM (public) | route geometry | Public servers; rate-limited |
| Nominatim (public) | reverse geocoding | 1 req/s policy |
| Tesseract OCR | prescriptions | local in-process |
| Render | hosting | free plan — verify cold-start acceptable |
| Backblaze B2 (planned) | — | NOT active. See CURRENT_PROJECT_MAP.md. |

---

## 15. Endpoint coverage map (every screen that needs network)

| Flutter screen | Backend endpoints used |
|---|---|
| `login_screen`, `register_screen`, `verify_email_screen` | Firebase Auth SDK only |
| `home_shell` | Firebase Auth + `account.me` |
| `dashboard` (bento) | Firestore streams only |
| `academic_structure_screen` | `/api/study/semesters`, `/api/study/subjects` (privileged fallback) |
| `materials_screen`, `material_upload_screen`, `material_reader_screen` | `/api/materials/*` |
| `notes_screen`, `note_editor_screen` | `/api/study/notes/*` |
| `tasks_screen` | `/api/study/tasks/*` |
| `groups_screen`, `group_create_screen`, `group_admin_screen`, `group_detail_screen`, `group_resource_*` | `/api/groups/*` |
| `ai_assistant_screen` | `/api/ai/*` |
| `medicine_screen`, `medicine_form_screen`, `medicine_history_screen`, `medicine_ocr_screen` | `/api/prescriptions/*` + `/api/part3/medicine-doses` |
| `daily_expenses_screen`, `expense_tracker_screen` | `/api/part3/financial-transactions` |
| `bazar_buddy_screen` | `/api/part3/bazar-items/*` |
| `commute_bd_screen` | `/api/commute/*` |
| `profile_screen` | `/api/account/*`, `/api/reports/{kind}` |