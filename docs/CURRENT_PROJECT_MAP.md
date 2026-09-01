# Gochano — current project map

> **Source-of-truth precedence.** This map is generated from the current
> source tree (commit `9c49f86` + 132 uncommitted items).
> Where the README disagrees with the code, the **code wins** — see
> `docs/PRE_IMPLEMENTATION_AUDIT.md` and
> `backend/PHASE_2_MIGRATION_REPORT.md` for the canonical Phase 2 decisions.

---

## 1. Identity

| Item | Value |
|---|---|
| Brand (user-facing) | **Gochano** |
| Brand tagline | "One Place for Everything" |
| Product type | Student-only super-app (Android-first) |
| Repository | `d:\EkThikana_Full_Production_Starter` |
| Active branch | `before-final-fix` |
| Active release commit | `9c49f86` — *fix AI assistant Gemini connection and error handling* |
| Compatibility identifiers kept | `ekthikana-api` (Render service), `com.ekthikana.ekthikana` (Android package id), `ekthikana-files` (storage bucket) — *intentionally not renamed to preserve existing Firebase/Render bindings* |

---

## 2. Three-layer runtime

```text
┌──────────────────────────────────────────────────────────────────────┐
│ Flutter Android client  (flutter_app/lib/...)                       │
│   - Firebase Authentication (email/password)                         │
│   - Cloud Firestore (owner-scoped reads)                             │
│   - HTTPS client → FastAPI backend                                   │
│   - Local notifications (flutter_local_notifications + timezone)      │
│   - Local PDF rendering (pdfrx)                                      │
│   - OSM map / routing via flutter_map + latlong2 + geolocator         │
└────────────────────────────────┬─────────────────────────────────────┘
                                 │ HTTPS (idToken)
                                 ▼
┌──────────────────────────────────────────────────────────────────────┐
│ FastAPI backend on Render  (backend/app/...)                         │
│   - Firebase Admin SDK (Auth + Firestore read + Storage)             │
│   - SQLAlchemy 2.x → PostgreSQL on Render                            │
│   - alembic migrations (1 version: initial_commutebd)                │
│   - Gemini (google-generativeai) — backend-only                       │
│   - Tesseract OCR (pytesseract) for prescriptions                    │
│   - OSRM (routing) + Nominatim (geocoding) for CommuteBD             │
└────────────────────────────────┬─────────────────────────────────────┘
                                 │
                                 ▼
┌──────────────────────────────────────────────────────────────────────┐
│ Managed services                                                     │
│   - Firebase Auth + Firestore + Storage + FCM                        │
│   - Render Postgres  (one DB for CommuteDB + future Firestore-mig.) │
│   - Render web service for the FastAPI container                     │
└──────────────────────────────────────────────────────────────────────┘
```

---

## 3. Module & screen map

### 3.1 Flutter screens

```
flutter_app/lib/screens/
├── auth/                login, register, verify_email, auth_gate
├── home/                dashboard, home_shell, widgets/brutalist
│   ├── dashboard/       bento dashboard view (large cards layout)
│   └── widgets/         brutalist primitives (legacy pill nav)
├── study/               study_screen, semesters, subjects, materials,
│                         notes, note_editor, material_upload,
│                         material_reader, saved_materials,
│                         ai_assistant, study_plan, study_stats,
│                         focus_timer, monthly_money
├── life/                life_screen hub, daily_expenses,
│                         expense_tracker, bazar_buddy, commute_bd,
│                         medicine_screen hub, medicine_ocr,
│                         medicine_form, medicine_history
├── groups/              groups_screen, group_detail, group_admin,
│                         group_chat
├── tasks/               tasks_screen
├── profile/             profile_screen
├── search/              universal_search_screen
└── system/              gochano_splash_screen
```

### 3.2 Flutter services

```
flutter_app/lib/services/
├── auth_service.dart       FirebaseAuth + role bootstrap
├── api_service.dart        HTTPS client → FastAPI backend
├── firestore_service.dart  owner-scoped CRUD helpers
├── study_service.dart      study data aggregator
├── financial_service.dart  expense summary streams
├── monthly_money_service.dart
├── notification_service.dart   local notifications
└── offline_service.dart    offline queue
```

### 3.3 Flutter widget library

```
flutter_app/lib/widgets/
├── bento/                  bento widget library (barrel: bento_bar.dart)
│   ├── bento_action_card.dart
│   ├── bento_card.dart        (base 28-radius surface)
│   ├── bento_colors.dart      (module palettes: study/ai/medicine/...)
│   ├── bento_icon.dart
│   ├── bento_illustration.dart
│   ├── bento_large_card.dart
│   ├── bento_small_card.dart
│   └── bento_stat_card.dart
├── empty_illustrations.dart
├── gochano_app_bar.dart
├── gochano_loading.dart
├── gochano_primitives.dart
├── location_picker.dart
└── notification_action_host.dart
```

---

## 4. Backend surface

### 4.1 Routers (mounted under `/api`)

| Router | Prefix | Purpose |
|---|---|---|
| `health.py` | `/api/health` | liveness |
| `account.py` (`me`) | `/api/...` | account bootstrap, role provisioning |
| `groups.py` | `/api/groups/...` | study-group CRUD + sharing |
| `materials.py` | `/api/materials/...` | uploaded file metadata + upload pipeline |
| `ai.py` | `/api/ai/...` | AI Assistant endpoints (Gemini) |
| `prescriptions.py` | `/api/prescriptions/...` | OCR → structured prescription |
| `study.py` | `/api/study/...` | semesters, subjects, tasks |
| `part3.py` | `/api/...` | group chat + monthly money + focus timer (PART 3 surface) |
| `reports.py` | `/api/reports/...` | moderation queue |
| `account.py` | `/api/account/...` | account export / delete |
| `commute.py` | `/api/commute/...` | CommuteBD — routes, fare report, places search |

### 4.2 Services

| Service | Responsibility |
|---|---|
| `ai_service.py` | Gemini client + quota + error classification |
| `ocr_service.py` | Tesseract prescription parser |
| `pdf_service.py` | Local PDF text extraction |
| `permission_service.py` | Student/General role gates |
| `storage_service.py` | **Firebase Storage** upload / signed URL / delete (Phase 2) |
| `commute/service.py` | CommuteBD orchestration (Phase 2 — Postgres-backed) |
| `commute/fare_engine.py` | Fare rules engine |
| `commute/routing.py` | OSM/OSRM/Nominatim routing provider |
| `commute/data_repository.py` | Synthetic CSV fallback (rickshaw distance only) |
| `commute/ml_fare.py` | Learned fare model (downloads `.joblib` via storage) |
| `commute/crowd.py` | Crowd-sourced fare confidence aggregator |
| `commute/supabase_repository.py` | **Legacy** — kept as historical reference (not imported by `service.py`) |

### 4.3 Database layer

```
backend/app/database/
├── connection.py                 engine + sessionmaker; SQLite fallback
├── models.py                     SQLAlchemy ORM
└── repositories/
    ├── postgres_repository.py    CommuteDB primary read repo (Phase 2)
    └── fare_report_repository.py community fare report (insert + list)
```

### 4.4 Migrations

| File | Status |
|---|---|
| `alembic/versions/20260829080000_initial_commutebd.py` | **Active** — installs `postgis` + `pg_trgm` extensions, adds `latitude`/`longitude` numeric columns + indexes on CommuteDB tables |
| `0001_initial.py` | **Not yet generated** — Phase 2g should run `alembic revision --autogenerate` against a real Postgres (per `PHASE_2_MIGRATION_REPORT.md` §4.4) |

---

## 5. Current storage & AI architecture

| Concern | Active binding | Source |
|---|---|---|
| File storage | **Firebase Storage** (`firebase_admin.storage`) | `backend/app/services/storage_service.py` |
| Object download URLs | **V4 signed URLs** (15-minute TTL) | same |
| Database | **PostgreSQL via SQLAlchemy** (`DATABASE_URL`) — SQLite fallback | `backend/app/database/connection.py` |
| Spatial data | **PostGIS extensions installed** — but no `geometry` columns on tables yet (numeric `lat`/`lng` only) | `alembic/versions/20260829080000_initial_commutebd.py` |
| Auth | Firebase Authentication | `backend/app/core/firebase.py` |
| Realtime app data | Cloud Firestore | `flutter_app` (FirestoreService) |
| AI | **Gemini** (`gemini-2.5-flash` config default; `gemini-3.7-flash` in `render.yaml`/`.env.example`) | `backend/app/services/ai_service.py` + `app/core/config.py` |
| Routing | OSRM + Nominatim | `backend/app/services/commute/routing.py` |
| ML fare model | `.joblib` in Firebase Storage; downloaded via `ml_fare.py` | `backend/ml/train_fare_models.py` |
| Reverse geocoding | Nominatim (public OSM) | same |

> **The README text** (`private Supabase Storage`) and the legacy
> `supabase_*` env vars in `config.py` + `render.yaml` are the **old
> Phase-1 binding**. They are kept only for backwards-compat and to
> preserve history; the **active code path uses Firebase Storage**.
> Migration evidence lives in `backend/PHASE_2_MIGRATION_REPORT.md`.

---

## 6. Theme & UX tokens

```text
flutter_app/lib/core/
├── app_config.dart         Compile-time flags (validator helper)
├── design_tokens.dart      20 semantic spacing tokens, typography scale
├── language.dart          Bangla / English key surface (EkLanguage.text)
├── navigation.dart         GlobalKey<NavigatorState> + cold-start reset
├── theme.dart              EkTheme.light() / EkTheme.dark()
└── ui.dart                 Primitive UI helpers
```

- Material 3 + seed `Color(0xFF5B3DF5)` (purple) — defined in `design_tokens.dart`
- Card radius 18, 1 px line border (M3 baseline)
- NavigationBar height 70, FAB purple, FilledButton min size 48 × 14 radius
- Dark mode `EkTheme.dark()` is **scaffolded but incomplete** per the
  comment at the top of `theme.dart` itself. Many screens still hardcode
  `EkColors.card` / `EkColors.text`, which breaks dark mode parity.

---

## 7. Roles

| Role | Surfaces | Backend |
|---|---|---|
| `student` | Home + Study + Life + Profile (+ AI shortcut, + Community) | All routes permitted by role decorator |
| `general` | Home + Life + Profile (no academic shells) | Backend decorators deny study/groups/etc. |

Role enforcement happens in **two places**: the role-aware Flutter shell
(`home_shell.dart` rebuilds tabs based on role) **and** the FastAPI
`permission_service` decorator.

---

## 8. Active tests & CI posture

```
backend/tests/
├── conftest.py                   in-memory SQLite + Firebase stubs
├── test_auth_and_roles.py        auth gate (3 tests)
├── test_commute_postgres.py      CommuteDB Postgres-backed (8 tests, new in Phase 2)
├── test_health.py                /healthz (1 test)
├── test_materials.py             materials upload + signed URL (5 tests)
├── test_ocr_parser.py            parser unit (1 test)
├── test_part3.py                 AI/account/quotas (34 tests)
└── test_quotas.py                per-user & plan quotas (5 tests)
```

Phase 2 reports **57 tests pass** in this in-memory SQLite mode
(`PHASE_2_MIGRATION_REPORT.md` §4.1). No CI workflow file is committed in
the repo (no `.github/workflows/`).

---

## 9. Uncommitted delta in the working tree

| Prefix | Count | What it means |
|---|---|---|
| `D` | 92 | Deleted historical reports (Phase-level progress write-ups) and Python recon scripts (`_p3_*.py`, `_audit_*.py`, etc.) — these are leaf cleanup, not feature loss |
| `M` | 29 | Active-code edits — Flutter home shell, theme, splash, study, bento dashboard, medicine screen, group chat, bazar buddy, AI assistant, material reader; backend `config.py`, `ai.py`, `commute.py`, services, render.yaml, env example |
| `??` | 11 | New Phase-2 backend surface: `PHASE_2_MIGRATION_REPORT.md`, `alembic.ini`, `alembic/`, `app/database/`, `tests/test_commute_postgres.py`, `delivery/`, `flutter_app/lib/screens/home/dashboard/`, `flutter_app/lib/widgets/bento/`, `tool/make_delivery.ps1` |

> **No destructive action was taken.** Every deleted item is a
> self-authored progress report or a one-shot recon script. None of the
> deletions removes application code.

---

## 10. Where to look for each kind of truth

| If you're looking for | Open this file |
|---|---|
| Active binding decisions | `backend/PHASE_2_MIGRATION_REPORT.md` |
| Active binding snapshot | this file (CURRENT_PROJECT_MAP.md) |
| README status | README is **stale** — refer to source |
| Backend audit | `docs/PRE_IMPLEMENTATION_AUDIT.md` |
| Proposed changes | `docs/CHANGE_PLAN.md` |
| Data ownership | `docs/DATA_OWNERSHIP.md` |
| API contracts | `docs/API_CONTRACT_AUDIT.md` |
| Database schema | `docs/DATABASE_AUDIT.md` |

---

## 11. What was deliberately NOT done yet

| Item | Owner / next step |
|---|---|
| Generate `alembic/versions/0001_initial.py` autogenerate baseline | Operator on real Postgres (Phase 2g) |
| Add PostGIS `Geometry` columns + spatial indexes on commute tables | Operator decision (lowest-impact spatial query wins are numeric lat/lng + Haversine for current scale) |
| Complete dark mode parity across all screens | UI redesign phase (Phase 4-5) — `theme.dart` already notes its own incompleteness |
| Remove legacy `supabase_*` env vars | Cosmetic — keeping them avoids re-binding Render env. Defer to v2. |
| Replace floating glass `BackdropFilter` nav with M3 `NavigationBar` | UX redesign — see `docs/CHANGE_PLAN.md` |
| Move "AI" out of bottom nav (study-only entry) | UX redesign — see `docs/CHANGE_PLAN.md` |
