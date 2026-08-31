# Data ownership

> Goal: for every piece of user-visible data, answer **(a) where it lives**, **(b) how it's read**, **(c) who can write it**, and **(d) who can read it**.

Storage layers, in priority order:

1. **Firestore** — owner-scoped, role-gated. Live counters, app metadata, AI conversations, study/tasks/notes/groups/expenses/medicines.
2. **PostgreSQL (Alembic + SQLAlchemy)** — CommuteBD dataset (`places`, `routes`, `fare_reports`, ...) and account metadata.
3. **Firebase Storage** — user files (`users/{uid}/materials/*`, prescriptions, AI inputs). Never `service_role`.
4. **Supabase Storage / Postgres** — LEGACY. Bindings kept for backwards compatibility. Not used by active code paths.

---

## A. Firestore

| Collection / path | Document shape (key fields) | Owner rule | Writes | Reads |
|---|---|---|---|---|
| `users/{uid}` | `email`, `displayName`, `photoUrl`, `role` (`student` \| `general`), `language` (`en` \| `bn`), `createdAt`, `dailyQuota{ai, upload, materials}, lastResetAt` | `request.auth.uid == uid` | Owner (client) + privileged backend (`part3.py`) | Owner (client) + backend (admin) |
| `semesters/{semesterId}` | `ownerUid`, `title`, `term`, `archived` (bool) | `request.auth.uid == resource.data.ownerUid` | Owner | Owner |
| `subjects/{subjectId}` | `ownerUid`, `semesterId`, `name`, `color`, `credits` | `request.auth.uid == resource.data.ownerUid` | Owner | Owner |
| `materials/{materialId}` | `ownerUid`, `semesterId?`, `subjectId?`, `title`, `storagePath`, `mime`, `sizeBytes`, `tags[]` | `request.auth.uid == resource.data.ownerUid` | Owner (client) + backend (storage replace) | Owner |
| `notes/{noteId}` | `ownerUid`, `semesterId?`, `subjectId?`, `title`, `body` | Owner | Owner | Owner |
| `tasks/{taskId}` | `ownerUid`, `title`, `dueAt`, `status`, `subjectId?`, `reminderOffset` | Owner | Owner | Owner |
| `groups/{groupId}` | `ownerUid`, `name`, `memberUids[]`, `adminUids[]`, `createdAt` | Members + admins | Member/admin | Member/admin |
| `group_resources/{resourceId}` | `groupId`, `uploaderUid`, `storagePath`, `title`, `mime` | Member | Uploader + member read | Member |
| `group_chats/{groupId}` (LEGACY per `docs/AUDIT_REPORT.md`) | `groupId`, `messages[]` | Member | Member | Member — **scope to be removed** |
| `ai_conversations/{convId}` | `ownerUid`, `messages[]`, `model`, `tokenCount` | Owner | Owner (client) + backend (after Gemini call) | Owner |
| `financial_transactions/{txId}` (deterministic: `hash(source, sourceRecordId)`) | `ownerUid`, `source` (`bazar` \| `medicine` \| `commute`), `amount`, `currency`, `createdAt` | Owner (own + write-once) | Backend (privileged) | Owner |
| `bazar_items/{itemId}` | `ownerUid`, `title`, `qty`, `purchasedAt?`, `cost?` | Owner | Owner | Owner |
| `medicines/{medId}` | `ownerUid`, `name`, `dosage`, `schedule[]`, `active` | Owner | Owner | Owner |
| `medicine_doses/{doseId}` | `ownerUid`, `medId`, `scheduledAt`, `takenAt?`, `confirmationState` | Owner | Owner | Owner |
| `notifications/{notifId}` | `ownerUid`, `kind`, `refId`, `title`, `body`, `scheduledAt` | Owner (local mirror) | Local notifications / FCM | Owner |
| `reports/{reportId}` | `ownerUid`, `kind` (`export` \| `commute`), `storagePath`, `generatedAt` | Owner | Backend | Owner |

**Firestore rules file:** `firebase/firestore.rules`.

---

## B. PostgreSQL (via SQLAlchemy)

| Table (model) | Active read path | Active write path | Notes |
|---|---|---|---|
| `users` (`app/database/models.py`) | Backend `/api/account/*` | Backend (privileged) | One row per Firebase user; mirrors `users/{uid}.role`. |
| `semesters`, `subjects` | Backend study endpoints (legacy fallback) | Backend study endpoints | Phase-2 unified on Firestore; Postgres rows kept for analysis. |
| `resources` | Backend materials endpoints | Backend materials endpoints | Same — Firestore is the active store; Postgres is the analytics mirror. |
| `tasks`, `expenses`, `groups`, `group_resources` | Backend | Backend | Phase-2 mirrored tables; Firestore is live UI source. |
| `places` (`CommutePlace`) | CommuteBD `/api/commute/places/search` | Backend (seed script `import_commutebd_to_supabase.py`) | Active source of truth for place search. |
| `routes` (`CommuteRoute`) | CommuteBD route solver | Backend route solver | Active store. |
| `fare_reports` | `/api/commute/fare-report` | CommuteBD report builder | Append-only with deterministic IDs. |
| `ml_fare_models` | `services/commute/ml_fare.py` | Training script (`ml/train_fare_models.py`) | Large-binary `.joblib` actually stored in Firebase Storage; row holds the storage path. |
| `alembic_version` | Alembic | Alembic | Migration tracking. |

**Migrations folder:** `backend/alembic/versions/`.
**Phase-2 migration:** `20260829080000_initial_commutebd.py` (PostGIS extensions + lat/lng indexes).

---

## C. Firebase Storage

| Path | Owner | Writes | Reads |
|---|---|---|---|
| `users/{uid}/materials/{materialId}.{ext}` | `{uid}` | Owner (via signed URL returned by backend `/api/materials/upload-url`) | Owner (signed URL, 15-min TTL) |
| `users/{uid}/prescriptions/{imageId}.{ext}` | `{uid}` | Owner | Owner + backend OCR |
| `users/{uid}/ai/{convId}/{fileId}.{ext}` | `{uid}` | Owner | Owner + backend (Gemini) |
| `users/{uid}/reports/{reportId}.pdf` | `{uid}` | Backend (account.export) | Owner |
| `ml-fare-models/*.joblib` | System | Training pipeline | Backend (downloads on boot) |

**Storage client:** `backend/app/services/storage_service.py` (`firebase_admin.storage`).
**Signed URLs:** `@google-cloud-storage` client, 15-minute TTL.

---

## D. Local cache (Android)

| Key | Purpose | Cleared on logout? |
|---|---|---|
| `ek_auth_id_token` (encrypted SharedPreferences) | Firebase ID token for backend calls | Yes |
| `ek_language` | "en" \| "bn" | Yes |
| `ek_theme_mode` | "light" \| "dark" \| "system" | Yes |
| `ek_user_role` | "student" \| "general" (cached from `users/{uid}`) | Yes |
| Task & notification queue (`flutter_local_notifications`) | Local notifications | Yes (clear on logout) |

---

## E. Constants that bind to legacy data (DO NOT BREAK)

These names appear in code, Render env, Android manifest, and Firebase Web config. **Do not rename in this cycle**:

| Constant | Where | Why |
|---|---|---|
| `ekthikana-api` | Render service name | Live deployment identity |
| `com.ekthikana.ekthikana` | Android `applicationId` | Live Play Store identifier |
| `ekthikana-files` | Firebase Storage bucket | Live bucket identity |
| `supabase_url`, `supabase_service_role_key`, `supabase_bucket` | `config.py`, `render.yaml` | Backwards-compat. Removing breaks Render env binding. |
| `ekthikana_*` Dart package import paths | All Flutter files | Maintain import continuity. |

---

## F. Sealed access paths

These flows never expose a server secret to the Flutter app:

- ✅ Backend → Supabase service-role calls (CommuteDB was the original path; now Postgres-only).
- ✅ Backend → Gemini API key (`ai_service.py`).
- ✅ Backend → Firebase service-account JSON (`firebase.py`).
- ✅ Backend → Tesseract OCR (local in-process).
- ✅ Flutter → Firebase ID token (per-user, short-lived).
- ✅ Flutter → signed URL from Firebase Storage (15-min TTL).

---

## G. Account deletion

`account.delete` flow must remove:

1. Firestore: `users/{uid}` + every sub-document under owner-keyed collections.
2. Firebase Storage: every file under `users/{uid}/...`.
3. PostgreSQL: every row in `users` and `fare_reports`; dependent rows cascade.
4. Local SharedPreferences.
5. Local notifications.

Confirmed by `docs/ARCHITECTURE.md` "Legacy records may only be referenced by account-deletion cleanup so old data is not stranded."