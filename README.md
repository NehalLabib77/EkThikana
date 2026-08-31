# Gochano

Gochano is an all-in-one student productivity platform that unifies **study
management**, **daily life organization**, **AI assistance**, and **personal
finance tracking** into a single Android-first mobile application.

It was built for students who currently juggle multiple separate apps for
class notes, group materials, reminders, expense tracking, commute planning,
and ad-hoc AI help. Gochano collapses those workflows into one cohesive
ecosystem where academic, daily-life, and financial data share a common
identity, a common design system, and a common backend.

The application targets two operating modes:

- **Student** — full academic workspace (semesters, subjects, notes,
  materials, group shared box, study AI, planner) plus personal life tools
  (medicine, shopping, expenses, commute, tasks).
- **General** — personal life tools only; academic surfaces are hidden in
  the UI and denied by backend / Firestore rules.

---

## Table of contents

> Each numbered link below lands on a self-contained segment. The
> same numbering is reflected in the per-segment headings so you can
> navigate with Ctrl+F.

**Part A — the project**

1. [What Gochano is, and what it isn't](#1-what-gochano-is-and-what-it-isnt)
2. [The two operating modes (Student vs General)](#2-the-two-operating-modes-student-vs-general)
3. [Why this app exists](#3-why-this-app-exists)
4. [Headline numbers](#4-headline-numbers)
5. [Quality gates we hold ourselves to](#5-quality-gates-we-hold-ourselves-to)

**Part B — architecture**

6. [Three-layer architecture](#6-three-layer-architecture)
7. [Operating principles](#7-operating-principles)
8. [Identity, roles, and authorization model](#8-identity-roles-and-authorization-model)
9. [Data ownership map](#9-data-ownership-map)
10. [File storage and signed URLs](#10-file-storage-and-signed-urls)
11. [The expense ledger contract](#11-the-expense-ledger-contract)

**Part C — the Flutter client**

12. [Flutter app at a glance](#12-flutter-app-at-a-glance)
13. [Screen layout (`lib/screens/*`)](#13-screen-layout-libscreens)
14. [Services layer (`lib/services/*`)](#14-services-layer-libservices)
15. [Models (`lib/models/*`)](#15-models-libmodels)
16. [Core helpers (`lib/core/*`)](#16-core-helpers-libcore)
17. [Shared widgets (`lib/widgets/*`)](#17-shared-widgets-libwidgets)
18. [Theming, design tokens, and a11y](#18-theming-design-tokens-and-a11y)
19. [Localization (English + Bangla)](#19-localization-english--bangla)
20. [Notifications](#20-notifications)
21. [Android build (`android/`)](#21-android-build-android)
22. [Branding assets (`assets/branding/`)](#22-branding-assets-assetsbranding)
23. [Flutter tests](#23-flutter-tests)

**Part D — the FastAPI backend**

24. [Backend at a glance](#24-backend-at-a-glance)
25. [Core (`app/core/`)](#25-core-appcore)
26. [Routers (`app/routers/`) — every endpoint](#26-routers-approuters--every-endpoint)
27. [Services (`app/services/`) — business logic](#27-services-appservices--business-logic)
28. [Database layer (`app/database/`)](#28-database-layer-appdatabase)
29. [Schemas (`app/schemas.py`)](#29-schemas-appschemaspy)
30. [`app/main.py` — the FastAPI entrypoint](#30-appmainpy--the-fastapi-entrypoint)
31. [Bundled datasets (`data/commutebd/`)](#31-bundled-datadatacommutebd)
32. [ML preparation (`ml/`)](#32-ml-preparation-ml)
33. [Migrations (`migrations/`)](#33-migrations-migrations)
34. [Operational scripts (`scripts/`)](#34-operational-scripts-scripts)
35. [Backend tests (`tests/`)](#35-backend-tests-tests)
36. [Requirements, Dockerfile, Render blueprint](#36-requirements-dockerfile-render-blueprint)

**Part E — managed services**

37. [Firebase (`firebase/`)](#37-firebase-firebase)
38. [Supabase (`supabase/`)](#38-supabase-supabase)

**Part F — operator documentation**

39. [`docs/` index](#39-docs-index)
40. [The P3 / P4 audit timeline](#40-the-p3--p4-audit-timeline)
41. [Operator scripts under `docs/`](#41-operator-scripts-under-docs)

**Part G — running the project**

42. [Setup from zero](#42-setup-from-zero)
43. [Environment variables — backend](#43-environment-variables--backend)
44. [Environment variables — Flutter](#44-environment-variables--flutter)
45. [Local phone testing](#45-local-phone-testing)
46. [Build a release APK or AAB](#46-build-a-release-apk-or-aabb)
47. [Deploy to Render](#47-deploy-to-render)
48. [Bringing Firebase online](#48-bringing-firebase-online)
49. [Bringing Supabase online](#49-bringing-supabase-online)

**Part H — operations & governance**

50. [Security posture](#50-security-posture)
51. [Observability (P4-1)](#51-observability-p4-1)
52. [Troubleshooting entrypoints](#52-troubleshooting-entrypoints)
53. [Roadmap](#53-roadmap)
54. [License, contribution, code of conduct](#54-license-contribution-code-of-conduct)

---

> **How to read this README.** Parts A–H walk the project
> end-to-end. Part A is the elevator pitch and the headline
> numbers. Part B is the architecture you must understand before
> touching any code. Parts C and D are file-by-file inventories of
> the Flutter client and the FastAPI backend. Part E covers the
> managed services. Part F indexes `docs/`. Part G is the runbook.
> Part H is the operational and governance posture.
>
> Every number on the dashboard at §4 is a fact pinned by tests —
> not aspirational. Cross-check against `docs/RELEASE_NOTES.md` and
> `docs/PHASE_*` audit docs.

---

## 1. What Gochano is, and what it isn't

Gochano is an **all-in-one student productivity platform** that
unifies **study management**, **daily life organization**, **AI
assistance**, and **personal finance tracking** into a single
Android-first mobile application.

It was built for students who currently juggle multiple separate
apps for class notes, group materials, reminders, expense tracking,
commute planning, and ad-hoc AI help. Gochano collapses those
workflows into one cohesive ecosystem where academic, daily-life,
and financial data share a common identity, a common design system,
and a common backend.

| It **is** | It **is not** |
|---|---|
| A Flutter Android app with a clear Student / General split | A cross-platform iOS app (Android-only by target SDK choice) |
| A FastAPI backend on Render | A multi-cloud deployment (Render is the supported target) |
| A project that owns its data layer (Firestore + Supabase) | A thin wrapper around a SaaS |
| A research vehicle for fares (BRTA buses, DMTCL Metro) | A general ride-hailing aggregator |
| An opinionated product — chat / DM / MCQ / quiz are explicitly **out of scope** | A platform that grows features by community vote |

The app targets two operating modes:

- **Student** — full academic workspace (semesters, subjects, notes,
  materials, group shared box, study AI, planner) plus personal life
  tools (medicine, shopping, expenses, commute, tasks).
- **General** — personal life tools only; academic surfaces are hidden
  in the UI and denied by backend / Firestore rules.

---

## 2. The two operating modes (Student vs General)

The role is enforced in three places: UI hiding, backend routes, and
Firestore security rules. None of them is sufficient on its own.

| Capability | Student role | General role |
|---|---|---|
| Semesters / subjects / notes / materials | ✅ | ❌ (UI hidden, backend denies) |
| Public Study Library / Community Library | ✅ | ❌ |
| Study Groups + shared box + optional chat | ✅ | ❌ |
| Study Planner | ✅ | ❌ |
| Study AI (note cleanup, summarize, PDF Q&A) | ✅ | ❌ (gated on `/api/ai/*`) |
| Medicine | ✅ | ✅ |
| BazarBuddy (shopping) | ✅ | ✅ |
| Daily Expenses | ✅ | ✅ |
| CommuteBD | ✅ | ✅ |
| Tasks & Reminders | ✅ | ✅ |
| Profile / expense summary / export / delete | ✅ | ✅ |
| Universal Search | role-aware | role-aware |

Each capability requires different data shapes, different collections,
and different backend routes. The three-enforcement rule keeps the
client from being trusted for authorization.

---

## 3. Why this app exists

Students typically piece together six separate apps:

1. A notes / PDF reader
2. A shared study-group chat or shared drive
3. A medicine / prescription tracker
4. A shopping list
5. A daily-expense tracker
6. A commute planner for an unfamiliar city
7. A task / reminder app
8. An AI assistant for explaining notes and PDFs

Gochano bundles all eight into one app with **a single sign-in, a
single identity, and a single source of truth for expenses**. The
goal isn't to be best-in-class in any single category — it's to be
best-in-class at the *hand-off* between them (a medicine dose
becomes an expense line; a purchase becomes an expense line; a
confirmed commute fare becomes an expense line; all flow into the
same daily / monthly / category aggregations).

The specific problems this solves:

- **Context switching** — academic, daily-life, and personal-finance
  data live in one app with one identity.
- **Group sharing** — students form a shared box for materials; an
  optional per-group chat can be enabled by the group owner.
- **Real money visibility** — a single idempotent expense ledger
  records daily spend, shopping purchases, taken medicine doses, and
  confirmed commute fares only.
- **AI without leaking secrets** — Gemini runs only on the backend;
  the Flutter client never holds an AI key.
- **Privacy** — files sit in a private Supabase bucket and are
  streamed via short-lived signed URLs.


# Part A — the project
## 4. Headline numbers

Every number below is a fact pinned by tests — not aspirational.
Cross-check against `docs/RELEASE_NOTES.md` and the per-phase audit
documents in `docs/PHASE_*`.

| Metric | Value | Source |
|---|---:|---|
| Backend pytest cases | 138 passing | `backend/tests/` |
| Flutter test cases | 126 passing | `flutter_app/test/` |
| Flutter analyzer issues | 0 | `flutter analyze` |
| Backend route modules | 12 + Internal + Health | `backend/app/routers/` |
| Flutter screens | ~25 | `flutter_app/lib/screens/` |
| Localizations | 2 (English, Bangla) | `lib/core/language/` |
| Audit phases shipped | P3-9, P3-10, P3-11, P4-1 | `docs/PHASE_*` |
| Security regressions pinned | 16 | `test_security_audit.py` |
| Performance regressions pinned | 11 | `test_performance_audit.py` |
| A11y regressions pinned | 20 | `accessibility_audit_test.dart` |
| Latency invariants pinned | 10 | `test_latency_middleware.py` |
| Signed-URL TTL | 900 s (15 min) | `app/services/storage.py` |
| Per-route latency window | 128 samples default | `app/core/latency.py` |
| Quota cache | per-user O(1) | `app/services/quotas.py` |
| OCR languages | `eng+ben` (Tesseract) | `app/services/ocr.py` |

---

## 5. Quality gates we hold ourselves to

Every PR is expected to keep these gates green:

- `cd flutter_app && flutter analyze` → no issues.
- `cd flutter_app && flutter test` → 126/126.
- `cd backend && python -m pytest -q` → 138 passed.
- No secrets in the repo (`grep -r "service_role\|BEGIN PRIVATE KEY"`).
- Architectural conformance with `docs/ARCHITECTURE.md`.

If a new feature changes one of the numbers in §4 — the test count,
the route count, the latency window default, the OCR language, the
signed-URL TTL — the change must be accompanied by an update to
the corresponding doc (phase audit, release notes, or this README).
A silent drift on these numbers is treated as a regression.

---

# Part B — architecture

## 6. Three-layer architecture

```text
+--------------------------------------------------+
|  Flutter Android client                          |
|   + Firebase Auth (email/password)               |
|   + Cloud Firestore (owner-scoped reads)         |
|   + HTTPS client  -->  FastAPI backend           |
+----------------------------+---------------------+
                             |
                             v
+--------------------------------------------------+
|  FastAPI backend (Render)                        |
|   + Firebase Admin SDK (token verification)      |
|   + Supabase Storage (signed URLs, 900s TTL)     |
|   + Gemini API (Study AI — server-side only)     |
|   + Tesseract OCR (eng+ben) — server-side        |
|   + OSM-compatible map / routing                 |
|   + Per-endpoint latency recorder (P4-1)         |
+----------------------------+---------------------+
                             |
                             v
+--------------------------------------------------+
|  Managed services                                |
|   + Firebase (Auth + Firestore)                  |
|   + Supabase (PostgreSQL + private Storage)      |
|   + Google Gemini (AI)                           |
+--------------------------------------------------+
```

### Layer responsibilities

- **Flutter client** — UI, navigation, local caching, secure ID-token
  storage, optimistic UI, and presentation of all data.
- **FastAPI backend** — privileged operations: storage uploads,
  downloads with signed URLs, Gemini calls, OCR, fare lookups,
  account export / delete, and any operation that requires a
  service key.
- **Managed services** — Firebase / Supabase / Gemini are touched
  **only** through the backend or directly from the Flutter client
  where the operation is owner-scoped and does not require a
  service key.

## 7. Operating principles

These are the rules every PR is measured against:

1. **The Flutter app never receives a service-role key or AI key.**
   Secrets live only on the backend, only in Render env vars
   (production) or `backend/.env` (development).
2. **Render's local disk is ephemeral.** All long-lived files live
   in Supabase and are served through short-lived signed URLs.
3. **Roles are enforced in three places:** UI hides, backend routes
   deny, Firestore rules deny. None of them is sufficient alone.
4. **The expense ledger is append-only per source record** with
   deterministic IDs. Retrying a network call never duplicates a
   charge.
5. **OCR is a suggestion.** The user must confirm before any
   medicine record, dose schedule, or reminder is created. OCR
   never writes to the expense ledger directly.
6. **AI lives only on the backend.** The Flutter app never talks to
   Gemini. AI prompts and responses are logged server-side for
   audit.
7. **Files are private.** The Supabase bucket is private; signed
   URLs expire within 15 minutes.
8. **Public deploys assume the safest default.** Endpoints that
   shouldn't be publicly reachable must return **404** when not
   configured (e.g. `GET /api/_internal/latency`), not 401.

## 8. Identity, roles, and authorization model

### Identity

- **Firebase Authentication** with email / password.
- The Flutter app receives a Firebase ID token at sign-in.
- Every protected backend call sends
  `Authorization: Bearer <id_token>`.
- The backend verifies the token with the Firebase Admin SDK before
  any data is touched.

### Roles

- The role is a custom claim on the Firebase user
  (`role: "student" | "general"`).
- The role is set **only** by the backend, on the `POST /api/users`
  endpoint, and **cannot** be supplied by the client.
- Revoked tokens are rejected with HTTP 401.
- Unverified emails are rejected with HTTP 403.

### Authorization surfaces

| Surface | Owner-scoped? | Role-gated? |
|---|---|---|
| Notes / materials (own) | ✅ (Firestore rules) | Student-only for academic |
| Public Study Library | server-authoritative | Student-only |
| Expense ledger | backend-authoritative | both roles |
| Medicine, Bazar, Commute, Tasks | owner-scoped | both roles |
| File uploads/downloads | signed URL | server-issued |

## 9. Data ownership map

| Data | Owner | Storage | Read path | Write path |
|---|---|---|---|---|
| Auth identity | user | Firebase Auth | server only | server only |
| User profile | user | Firestore `users/{uid}` | owner | server only |
| Semesters / subjects / notes | user | Firestore | owner | owner |
| Materials (files) | user | Supabase Storage | owner via signed URL | owner |
| Public Library | Gochano | Firestore | Student role | server only |
| Community Library | contributors | Firestore | Student role | contributor |
| Study Groups | group members | Firestore | members | members |
| Group shared box | group members | Supabase Storage + Firestore | members | members |
| Expenses | user | Firestore `expenses/{uid}/...` | owner | server (idempotent) |
| Medicine | user | Firestore | owner | owner |
| Bazar | user | Firestore | owner | owner |
| Commute fare history | user | Firestore | owner | server (on confirm) |
| Tasks | user | Firestore | owner | owner |

## 10. File storage and signed URLs

- Files are stored in the private Supabase bucket `ekthikana-files`.
- Uploads are mediated by the backend: the Flutter client sends
  bytes to the backend, which puts them in the bucket under a path
  scoped to the user or the group.
- Reads are mediated by **signed URLs** minted by the backend, with
  a TTL of **≤ 15 minutes** (900 s). The Flutter client downloads
  the bytes through this URL, never with the service-role key.
- Render's local disk is **not** used as permanent storage; the
  bucket is the source of truth.

## 11. The expense ledger contract

This is the most subtle invariant in the project. The expense ledger
is **not** "user-pressed-an-add-button." It is a derived view of:

- **Taken** medicine doses (with their snapshot unit price).
- **Purchased** shopping items.
- **Confirmed** commute fares (`actual_paid_bdt`, not the estimated
  fare).

All three sources push into the same expense collection under
`expenses/{uid}/...`. To prevent duplicate charges on retry:

- The expense record's ID is **deterministic** — it's derived from
  the source ID (the dose ID, the purchase ID, the commute ID).
- The Flutter client treats "create dose" / "confirm purchase" /
  "confirm fare" as a single network round-trip; the backend either
  succeeds or the client retries — never twice.
- This is the reason OCR is **never** an expense trigger: the user
  must confirm "take this dose" before any expense row is written.

---

# Part C — the Flutter client

## 12. Flutter app at a glance

- **Material 3** throughout, with a documented design-token system
  in `lib/core/design_tokens.dart`.
- **Single `MaterialApp`** with role-aware routing; the bottom-nav
  shell hides academic surfaces for General users.
- **All secret-bearing state lives on the backend.** The Flutter
  client holds only: Firebase ID token (in secure storage),
  Supabase signed URLs (transient), Firestore client config
  (public), and the `API_BASE_URL` build-time define.
- **`flutter analyze` is clean** (0 warnings, 0 infos).

## 13. Screen layout (`lib/screens/`)

| Subfolder | Screens |
|---|---|
| `auth/` | login, register, verify-email, auth gate |
| `home/` | dashboard, bottom-nav shell, splash handoff |
| `study/` | semesters list, semester detail, subject detail, notes, materials, PDF reader, AI assistant, planner |
| `groups/` | groups list, group detail (shared box, optional chat) |
| `tasks/` | tasks list, task detail, reminders |
| `life/` | medicine list, medicine detail, prescription-OCR camera, bazar list, bazar detail, expenses, expense detail, commute map, commute result, commute history |
| `profile/` | profile, expense summary, JSON export, account deletion |
| `search/` | role-aware universal search |
| `system/` | splash |

Each `screens/<area>/*.dart` file is a single screen with a single
`StatefulWidget` or `StatelessWidget`; cross-screen widgets live in
`lib/widgets/`.

## 14. Services layer (`lib/services/`)

The services layer owns all network and persistence calls. Screens
should not import `package:http` or `package:cloud_firestore`
directly — they call services.

| Service | Responsibility |
|---|---|
| `api_service.dart` | HTTPS wrapper around all FastAPI endpoints; sends `Authorization: Bearer <id_token>`; parses JSON |
| `auth_service.dart` | Firebase email/password sign-in / sign-up; token refresh; email verification gate |
| `firestore_service.dart` | Direct Firestore reads (notes, library, groups, expenses, ...) with the rules taking care of authorization |
| `financial_service.dart` | Expense aggregation helpers (daily, monthly, category, yearly) |
| `notification_service.dart` | `flutter_local_notifications` setup; per-dose and per-task reminder scheduling |

## 15. Models (`lib/models/`)

Plain Dart data classes that mirror the JSON shapes used by the
backend. Models are immutable, `==`-comparable, and serialize to /
from JSON via `fromJson` / `toJson`.

Examples: `Medicine`, `DoseRecord`, `BazarItem`, `Expense`,
`CommuteFareEstimate`, `CommuteRoute`, `Material`, `Note`,
`Subject`, `Semester`, `StudyGroup`, `StudyTask`, `UserProfile`, ...

## 16. Core helpers (`lib/core/`)

- `core/config.dart` — runtime constants (bucket name, collection
  names; the API base URL is from `--dart-define`).
- `core/design_tokens.dart` — color, typography, spacing tokens.
  **Single source of truth** for visual design.
- `core/theme.dart` — `ThemeData` builder from the tokens.
- `core/language/` — `EkLanguage` bilingual literals + loader
  (English + Bangla).
- `core/navigation.dart` — route names and `onGenerateRoute` for
  typed navigation.
- `core/ui/` — `BrandedLoader`, `NotificationHost`, etc.

## 17. Shared widgets (`lib/widgets/`)

- `branded_loader.dart` — Gochano-branded progress indicator used
  everywhere a screen awaits network state.
- `notification_host.dart` — SnackBar / banner dispatcher so
  screens emit consistent, accessible feedback.
- `gradient_hero_card.dart`, `module_tile.dart` — the design system
  pieces that compose the dashboard, with AA-contrast white text
  pinned by tests.

## 18. Theming, design tokens, and a11y

- All colors come from `core/design_tokens.dart`. Widgets do
  **not** hardcode hex literals.
- Module gradients (Study / Expenses / Medicine / Commute / Bazar /
  Tasks / AI) were darkened along one end-stop each, with hue
  drift asserted ≤ 0.5° in `docs/contrast_delta.ps1`. White text on
  every gradient clears WCAG AA body-text contrast (4.5:1).
- Every logo carries `semanticLabel: "Gochano logo"`.
- Every icon-only `IconButton` carries a `tooltip:`. The
  `audit_iconbuttons.ps1` script verifies this statically.
- `GestureDetector` usages that require a label are wrapped in
  `Semantics(button: true, label: "...")`. The `audit_gestures.ps1`
  script verifies coverage.

## 19. Localization (English + Bangla)

- `lib/core/language/ek_strings.dart` is the master literal table.
- `EkLanguage.text` is a synchronous bilingual literal map with
  both languages filled in (asserted non-empty + equal entry count
  by `translation_smoke_test.dart`).
- Switching languages does not require an app restart — the
  `Locale` flip is reactive through `MaterialApp`.

## 20. Notifications

- Powered by `flutter_local_notifications`; **local-only** (no FCM
  in this codebase).
- Medicine reminder rules route through the same engine as task
  reminders.
- Notification taps deep-link back into the relevant Medicine
  screen via the `NotificationHost` widget.

## 21. Android build (`android/`)

- `compileSdk` / `targetSdk` 34, `minSdk` 24.
- Standard `flutter_app/android/` Gradle layout.
- `key.properties.example` documents the keystore path /
  `storePassword` / `keyAlias` / `keyPassword` slots for release.
  `key.properties` itself is in `.gitignore`.
- `local.properties` is generated by `flutter pub get`; do not
  commit.

## 22. Branding assets (`assets/branding/`)

- `gochano_logo.svg` — primary brand mark.
- `gochano_logo_dark.svg` — dark-mode variant.
- `app_icon_*.png` — Android launcher icons in all density buckets.
- Never committed as raw hex / brand colors; everything
  theme-related flows through `design_tokens.dart`.

## 23. Flutter tests

Located under `flutter_app/test/`:

- `test/theme_parity_test.dart` — pins design-token usage across
  screens (~16 tests).
- `test/translation_smoke_test.dart` — every English literal has a
  non-empty Bengali counterpart (~70 tests).
- `test/a11y/accessibility_audit_test.dart` — icon-button labels,
  semantic labels on logos, gradient contrast at 4.5:1, gesture
  semantics (20 tests, P3-11).
- `test/` also contains contract tests for the financial ledger,
  medicine rules, bazar purchase flow, and commute fare engine.

The full Flutter suite runs from `flutter_app/` with `flutter test`.

---

# Part D — the FastAPI backend

## 24. Backend at a glance

- **Python 3.11+** (developed against 3.14; declared minimum is 3.11).
- **FastAPI** on **Uvicorn**, deployed on Render via Docker.
- **Firebase Admin** for token verification and Firestore.
- **Supabase Python client** for Storage (signed URLs, bucket ops).
- **`httpx.AsyncClient`** pooled at module scope for AI gateway calls.
- **`pypdf` + `pdf2image` + `pytesseract`** for OCR / PDF text.
- **Tesseract `eng+ben`** for prescription OCR.
- **OSM-compatible** routing for CommuteBD maps.
- **Per-endpoint latency recorder** (`app/core/latency.py`, P4-1).

## 25. Core (`app/core/`)

| File | Purpose |
|---|---|
| `config.py` | Pydantic-flavoured settings dataclass. Reads env vars: `APP_ENV`, Firebase, Supabase, Gemini, `OCR_LANG`, `CORS_ORIGINS`, `INTERNAL_METRICS_TOKEN` (P4-1) |
| `firebase_admin.py` | Lazy-init Firebase Admin SDK; avoids booting a credential at import time |
| `auth.py` | Bearer token extractor; verifies ID tokens; returns `(uid, claims, role)` |
| `latency.py` | `LatencyRecorder` (bounded ring buffer, nearest-rank percentiles), `latency_middleware`, `GET /api/_internal/latency` token-gated endpoint (P4-1) |
| `security.py` | CORS, role-gating decorators, request-scoped helpers |
| `errors.py` | Single error-shaping module — every router goes through this for consistent JSON error bodies |

## 26. Routers (`app/routers/`) — every endpoint

Each `.py` file under `app/routers/` is a single `APIRouter`,
mounted in `main.py` with explicit `prefix=` and `tags=`.

| Router | Prefix | Tags | What it owns |
|---|---|---|---|
| `health.py` | `/api` | Health | `GET /api/health` |
| `me.py` | `/api` | Account | `GET /api/me` (current user profile) |
| `materials.py` | `/api/materials` | Materials | Materials CRUD, signed-URL minting |
| `groups.py` | `/api/groups` | Groups | Groups CRUD, member add/remove, shared-box file ops |
| `study.py` | `/api/study` | Study | Semesters / subjects / notes / planner CRUD |
| `ai.py` | `/api/ai` | AI | Gemini-backed endpoints (`note_cleanup`, `summarize`, `pdf_qa`, planner assist) — Student-only |
| `prescriptions.py` | `/api/prescriptions` | Prescriptions | OCR endpoint (`POST /api/prescriptions/parse`) |
| `commute.py` | `/api/commute` | Commute | Fare estimation, route, fare-confirm (writes expense) |
| `account.py` | `/api` | Account | JSON export, account deletion |
| `reports.py` | `/api/reports` | Moderation | User/content reporting (Student-public surfaces) |
| `part3.py` | `/api` | PART3 | Cumulative endpoint set brought in by P3 |
| `latency.py` (internal) | (root) | Internal | `GET /api/_internal/latency` — gated by `X-Internal-Token` |

Total **16 routes** after P4-1 (was 15). Health probe and the
internal snapshot endpoint are the only two non-versioned paths.

## 27. Services (`app/services/`) — business logic

Services hold the business rules that routers call. Routers stay
thin — request parsing, auth checks, service dispatch, response
shaping.

| Service / subpackage | Responsibility |
|---|---|
| `services/storage.py` | Supabase Storage wrapper; upload bytes, mint signed URLs (TTL 900s), delete |
| `services/firestore_repo.py` | Typed access to Firestore collections (users, expenses, materials, notes, ...) |
| `services/quotas.py` | Per-user quota cache + quota checks (O(1) reads after P3-10) |
| `services/ocr.py` | Tesseract `eng+ben` wrapper around `pdf2image` + `pytesseract` |
| `services/ai_gateway.py` | Gemini client with module-level pooled `httpx.AsyncClient` |
| `services/pdf.py` | `pypdf`-based PDF text extraction with page tracking |
| `services/commute/` | Fare engine subpackage — deterministic BRTA / Metro lookups, crowd-sourced Rickshaw / CNG fares with source+confidence labels, ML fare blending |
| `services/expenses.py` | Expense ledger writer; deterministic IDs from source IDs |
| `services/account.py` | Account export (JSON), account deletion (cascade across collections + storage) |

## 28. Database layer (`app/database/`)

- SQLAlchemy + Alembic for the Supabase Postgres side (a small
  number of tables — mainly the commute fare datasets and ML
  feature snapshots; the rest of the app is Firestore).
- Migrations live under `migrations/` and `supabase/migrations/`.
- The Postgres layer is **read-mostly** at runtime; writes happen
  through the backend only.

## 29. Schemas (`app/schemas.py`)

- Pydantic models for every request / response body.
- Routers annotate their handlers with these schemas; FastAPI
  generates the OpenAPI spec from them.

## 30. `app/main.py` — the FastAPI entrypoint

The route table is constructed in a fixed order:

1. CORS middleware
2. **P4-1 latency middleware** (`app.middleware("http")(latency_middleware)`)
3. Health router
4. **P4-1 internal router** (`/api/_internal/latency`, between health and `me`)
5. Account `/me` router
6. Materials router
7. Groups router
8. AI router (Student-gated)
9. Prescriptions router (OCR endpoint)
10. Study router
11. Commute router
12. PART3 cumulative router
13. Reports router
14. Account (export / delete) router

The latency middleware measures `time.perf_counter()` before and
after every request, records the elapsed time into the global
`LatencyRecorder`, and emits one INFO log line per request
**except** for `/api/health` (kept out so liveness probes don't
drown the log pipeline).

## 31. Bundled datasets (`data/commutebd/`)

JSON / CSV files for the deterministic Bangladesh transit fare
engine:

- BRTA bus fare table (distance-band → BDT fare).
- DMTCL Metro fare table (station-to-station → BDT fare).
- Rickshaw / CNG crowd source samples (raw, ML-shaped).

Loaded at backend startup and indexed in memory for O(1) lookups.

## 32. ML preparation (`ml/`)

- `ml/train_fare_models.py` — entrypoint for retraining the
  Rickshaw / CNG fare models off the crowd-source data.
- The ML pipeline is **opt-in**: the deterministic BRTA / Metro
  fare engines always work; the ML fare blending only activates
  when a trained model checkpoint is present.

## 33. Migrations (`migrations/`)

SQL files for the Supabase Postgres side. Applied in lexicographic
order by the Supabase CLI:

- `001_gochano_commutebd_production.sql` — the BRTA / Metro fare
  tables, indexed for sub-millisecond lookup.

Other migration files live under `supabase/migrations/`.

## 34. Operational scripts (`scripts/`)

- `import_commutebd_to_supabase.py` — one-shot importer from
  `data/commutebd/*.json|csv` into the Supabase Postgres tables.

## 35. Backend tests (`tests/`)

| File | Count | Source |
|---|---:|---|
| `tests/test_health.py` | 6 | baseline |
| `tests/test_auth_and_roles.py` | 18 | baseline |
| `tests/test_materials.py` | 14 | baseline |
| `tests/test_commute_postgres.py` | 9 | baseline |
| `tests/test_ocr_parser.py` | 11 | baseline |
| `tests/test_part3.py` | 28 | baseline |
| `tests/test_quotas.py` | 15 | baseline |
| `tests/test_security_audit.py` | 16 | **P3-9** |
| `tests/test_performance_audit.py` | 11 | **P3-10** |
| `tests/test_latency_middleware.py` | 10 | **P4-1** |
| **Total** | **138** | |

The test harness lives in `tests/conftest.py` (~661 lines). It
installs **`FakeFirestore`, `FakeAuth`, `FakeSupabaseStorage`,
`FakeTransaction`** on `sys.modules` before `app.main` is imported,
so the production code paths run against hermetic fakes. The
`client` fixture monkey-patches every external collaborator
(Firebase, Storage, OCR, PDF, AI service stubs) at runtime, then
yields a `TestClient(fastapi_app)`.

## 36. Requirements, Dockerfile, Render blueprint

- `requirements.txt` — runtime deps (`fastapi`, `uvicorn[standard]`,
  `firebase-admin`, `supabase`, `httpx`, `pypdf`, `pdf2image`,
  `pytesseract`, `pillow`, `sqlalchemy`, `pydantic`, ...).
- `requirements-ml.txt` — adds `scikit-learn`, `numpy`, `pandas`
  for the optional ML fare blending path.
- `Dockerfile` — production image; installs Tesseract + Bengali
  language pack + Poppler + Python deps; runs Uvicorn.
- `render.yaml` — Render blueprint: web service, env vars (with
  secrets redacted), healthcheck on `/api/health`.

---

# Part E — managed services

## 37. Firebase (`firebase/`)

Two files:

- `firestore.rules` — security rules: role immutability,
  server-only writes on sensitive collections, owner-scoped reads.
  The client is **never** the authorization authority.
- `firestore.indexes.json` — composite indexes required by the
  queries in `app/routers/*.py` and the Flutter screens. Without
  these the relevant queries fall back to full-collection scans.

Reproducible deploy:

```bash
firebase use
firebase deploy --only firestore:rules,firestore:indexes
```

## 38. Supabase (`supabase/`)

- `config.toml` — local Supabase CLI config (mirror of the project
  settings).
- `migrations/` — SQL migrations applied to the project's Postgres
  database.

Two Supabase artefacts exist in production:

1. **A private Storage bucket** named `ekthikana-files`.
2. **A Postgres database** with the commute fare tables.

The service-role key exists **only** in Render env vars. The
Flutter app receives signed URLs only.

---

# Part F — operator documentation

## 39. `docs/` index

| File | Purpose |
|---|---|
| `START_HERE.md` | Single onboarding entrypoint — points at the right doc for each task |
| `FINAL_SETUP_GUIDE.md` | Recommended first-run guide |
| `ARCHITECTURE.md` | Deep dive into the three-layer architecture |
| `DATA_MODEL.md` | Firestore + Postgres schema, field-by-field |
| `API_REFERENCE.md` | Every backend endpoint with request / response shapes |
| `ANDROID_SETUP.md` | How to build and sign the Android release |
| `ANDROID_NOTIFICATIONS.md` | Notification setup + permission flow |
| `FIREBASE_SETUP.md` | Project creation, Auth, Firestore, deploy |
| `STORAGE_SETUP.md` | Supabase Storage bucket setup |
| `RENDER_DEPLOY.md` | Render service + env vars + healthcheck |
| `PRODUCTION_CHECKLIST.md` | Pre-launch sign-off |
| `SECURITY_PRIVACY.md` | Full security posture + privacy disclosures |
| `TROUBLESHOOTING.md` | Symptom → fix index |
| `GOCHANO_BRANDING.md` | Logo usage, color tokens, fonts |
| `BUILD_VALIDATION.md` | CI gate rationale |
| `FIREBASE_STORAGE_OPTION.md` | Why Supabase Storage rather than Firebase Storage |
| `WHAT_I_NEED_FROM_YOU.md` | Operator-facing checklist for first deploy |
| `AUDIT_REPORT.md` | Pre-P3 audit (superseded by phase docs) |
| `FINAL_AUDIT.md` | Pre-P3 audit (superseded by phase docs) |
| `PHASE_3_9_SECURITY_AUDIT.md` | 16 invariants pinned |
| `PHASE_3_10_PERFORMANCE_AUDIT.md` | 11 invariants pinned |
| `PHASE_3_11_ACCESSIBILITY_AUDIT.md` | 20 invariants pinned |
| `PHASE_4_1_LATENCY_MIDDLEWARE.md` | 10 invariants pinned |
| `FINAL_AUDIT_REPORT.md` | Cross-cutting summary of P3 |
| `RELEASE_NOTES.md` | User-visible + developer-visible P3 / P4 changes |

Two supplementary docs cover project-state snapshots:

- `CURRENT_PROJECT_MAP.md` — current state of the codebase.
- `CHANGE_PLAN.md` — intended sequencing of upcoming phases.

## 40. The P3 / P4 audit timeline

| Phase | Theme | Files added | Tests pinned | Doc |
|---|---|---|---|---|
| P3-9 | Security audit | `test_security_audit.py` | 16 | `PHASE_3_9_SECURITY_AUDIT.md` |
| P3-10 | Performance audit | `test_performance_audit.py` | 11 | `PHASE_3_10_PERFORMANCE_AUDIT.md` |
| P3-11 | Accessibility audit | `accessibility_audit_test.dart` | 20 | `PHASE_3_11_ACCESSIBILITY_AUDIT.md` |
| P3-12 | Consolidation | — | 0 | `FINAL_AUDIT_REPORT.md`, `RELEASE_NOTES.md` |
| P4-1 | Observability (latency) | `test_latency_middleware.py` + `app/core/latency.py` | 10 | `PHASE_4_1_LATENCY_MIDDLEWARE.md` |

Net: +57 backend + Flutter test cases, 4 phase documents, 1 new
internal endpoint.

## 41. Operator scripts under `docs/`

- `docs/contrast.ps1`, `docs/contrast_v2.ps1` — WCAG ratio scans
  for module gradient stops.
- `docs/contrast_search.ps1` — automatic search for the smallest
  darkening factor that puts every stop past 4.5:1.
- `docs/contrast_medicine.ps1` — secondary scan for the medicine
  module.
- `docs/contrast_dark.ps1` — dark-mode counterpart of `contrast.ps1`.
- `docs/contrast_delta.ps1` — verifies hue drift ≤ 0.5° for the
  darkened stops.
- `docs/audit_iconbuttons.ps1` — static scan asserting every
  `IconButton` carries a `tooltip:`.
- `docs/audit_gestures.ps1` — static scan asserting gesture-only
  widgets are wrapped in `Semantics`.

These exist so the accessibility and brand audits are repeatable
without manual spreadsheet work.

---

# Part G — running the project

## 42. Setup from zero

These instructions assume Windows / macOS / Linux with Flutter and
Python 3.11+ installed.

```bash
# 1. Backend (local)
cd backend
python -m venv .venv
# Windows
.venv\Scripts\Activate.ps1
# macOS / Linux
source .venv/bin/activate
pip install -r requirements.txt

# Optional ML deps
pip install -r requirements-ml.txt

uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

```bash
# 2. Flutter app (local)
cd flutter_app
flutter pub get
flutterfire configure         # writes firebase_options.dart
flutter run --dart-define=API_BASE_URL=https://YOUR-SERVICE.onrender.com
```

## 43. Environment variables — backend

Set in Render's dashboard or `backend/.env` for local. **Never
commit secrets.**

| Variable | Purpose |
|---|---|
| `APP_ENV` | `production` / `staging` / `development` |
| `FIREBASE_PROJECT_ID` | Firebase project id (matches FlutterFire config) |
| `FIREBASE_SERVICE_ACCOUNT_B64` | Base64 of Firebase service-account JSON |
| `SUPABASE_URL` | Supabase project URL or bare project ref |
| `SUPABASE_SERVICE_ROLE_KEY` | Supabase service-role key (server only) |
| `SUPABASE_BUCKET` | Private bucket name (default `ekthikana-files`) |
| `GEMINI_API_KEY` | Gemini key (server only) |
| `GEMINI_MODEL` | Optional. Default Gemini model id |
| `OCR_LANG` | Tesseract language (default `eng+ben`) |
| `CORS_ORIGINS` | Comma-separated allow-list |
| `INTERNAL_METRICS_TOKEN` | **P4-1.** When set, `GET /api/_internal/latency` returns the snapshot. When unset (the default), the endpoint returns 404. |
| `GOCHANO_LATENCY_WINDOW` | **P4-1.** Optional integer; per-route sample window. Default 128. |

## 44. Environment variables — Flutter

Passed at build time as `--dart-define`:

| Variable | Purpose |
|---|---|
| `API_BASE_URL` | Render HTTPS URL — required in release builds |

## 45. Local phone testing

The Flutter app on a physical Android phone cannot reach
`127.0.0.1`. Two options:

- **Use `adb reverse`**:

  ```bash
  adb reverse tcp:8000 tcp:8000
  flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000
  ```

- **Use the Render URL.** Cleanest for QA across real devices.

## 46. Build a release APK or AAB

```bash
# APK for sideload testing
flutter build apk --release \
  --dart-define=API_BASE_URL=https://YOUR-SERVICE.onrender.com

# AAB for Play Store
flutter build appbundle --release \
  --dart-define=API_BASE_URL=https://YOUR-SERVICE.onrender.com
```

Sign the bundle with your own upload key. See
[`docs/ANDROID_SETUP.md`](docs/ANDROID_SETUP.md) for keystore prep.

## 47. Deploy to Render

1. Push to a private GitHub repo.
2. Render → **New → Web Service** → connect the repo.
3. **Root directory:** `backend`.
4. **Runtime:** Docker (image from `backend/Dockerfile`).
5. Import `backend/render.yaml` as a blueprint, or set env vars
   manually.
6. Confirm `GET /api/health` returns `200 OK` after deploy.

## 48. Bringing Firebase online

1. In the Firebase console, reuse the existing Gochano project (or
   create a new one — the FlutterFire project id is referenced in
   `flutter_app/firebase.json`).
2. Enable **Authentication → Sign-in method → Email / Password**.
3. Create the **Firestore** database in production mode, in a
   region close to your Render service.
4. From the repo root:

   ```bash
   firebase use
   firebase deploy --only firestore:rules,firestore:indexes
   ```

## 49. Bringing Supabase online

1. Create the Supabase project.
2. **Storage → New bucket** named `ekthikana-files`,
   visibility **Private**.
3. Apply the SQL in `supabase/migrations/*` to the production
   database.
4. Copy the **Project URL** and the **`service_role` key** into
   Render env vars.

---

# Part H — operations & governance

## 50. Security posture

- **Never** commit `.env`, service-account JSON, Supabase
  `service_role` keys, or Gemini keys.
- All secrets stay in Render env vars or local `backend/.env`.
- The Flutter app receives only the Firebase ID token and the
  public Render URL.
- Service-role Supabase access exists only on the backend.
- Downloads use short-lived signed URLs (TTL ≤ 15 minutes).
- Roles are enforced in both UI (hiding) and backend / Firestore
  rules (denying) — the client is never trusted for authorization.
- Prescription OCR is a suggestion only; the user must confirm
  before any medicine record, dose schedule, or reminder is saved.
- The Gemini API is never invoked from the Flutter app.
- Render's local disk is **not** used as permanent storage.
- Production builds must point at the Render HTTPS URL — never at
  `http://127.0.0.1`.

For the full posture — including role-immutability tests,
signed-URL TTL pinning, and the unverified-email gate — see
[`docs/SECURITY_PRIVACY.md`](docs/SECURITY_PRIVACY.md).

## 51. Observability (P4-1)

- A small in-process `LatencyRecorder` (`app/core/latency.py`)
  tracks per-route wall-clock latency with a bounded ring buffer
  (default 128 samples).
- Every request contributes one sample, keyed on
  `(method, route-template)`. The percentile set (p50 / p95 /
  p99 / mean) is computed via nearest-rank, clamped at `n-1`.
- Aggregates are exposed at `GET /api/_internal/latency`, gated by
  the `X-Internal-Token` header. When `INTERNAL_METRICS_TOKEN` is
  unset (the default) the endpoint returns **404**, so a public
  Render deploy never accidentally exposes the snapshot.
- `/api/health` does **not** emit a per-request INFO log line, so
  the liveness probe doesn't drown the log pipeline.
- The quantile formula is pinned by 10 regression tests in
  `backend/tests/test_latency_middleware.py`. A refactor that
  flips to linear interpolation would change p95 from 190 → 195 on
  the pinned input and fail loudly — the change is then
  intentional.

## 52. Troubleshooting entrypoints

- Symptom catalogues by category: `docs/TROUBLESHOOTING.md`.
- "What does my doctor / operator / lawyer need to see?": the
  per-topic docs in the `docs/` index (§39).
- "Why doesn't this rule match?": `docs/FIREBASE_SETUP.md` →
  firestore rules test command.
- "Why is my p95 high?": `GET /api/_internal/latency` after setting
  `INTERNAL_METRICS_TOKEN`, then `docs/PHASE_4_1_LATENCY_MIDDLEWARE.md`
  §5 for interpreting the response.

## 53. Roadmap

Possible future improvements:

- **Per-route latency histograms over time (P4-2).** A ring buffer
  of recent snapshots to enable drift detection. P4-1 ships the
  point-in-time snapshot.
- **`lifespan` context manager for clean shutdown of pooled
  clients.** Currently the AI gateway's `httpx.AsyncClient` has no
  graceful shutdown path; matters more as we add pooled clients.
- **OCR request-deduplication cache.** The OCR endpoint
  (`/api/prescriptions/parse`) repeats work across concurrent
  identical uploads; a 30-second TTL keying on the file hash would
  cut billable OCR calls by ~40% in the common case.
- **ML-based fare prediction.** Per-route learned fare blending on
  top of the deterministic BRTA / Metro lookup, off the
  `ml/train_fare_models.py` pipeline.
- **Better OCR accuracy.** On-device fallback and richer Bengali
  parsing for prescription text.
- **More AI capabilities.** Controlled summarization of uploaded
  materials, study-plan assistance, AI-assisted revision notes.
- **Offline-first sync.** Full Firestore-backed offline queue with
  conflict resolution for notes and materials.
- **More productivity features.** Calendar export, recurring tasks,
  richer study statistics, shared household expenses within the
  spending-only contract.
- **Localization.** Extend the existing English / Bangla toggle to
  additional languages.

Explicit non-goals: chat / DM / MCQ / quiz / live-transport
(real-time vehicle tracking) features are **out of scope**.

## 54. License, contribution, code of conduct

### License

This repository is provided **as-is** for the Gochano project.
Unless a `LICENSE` file is added, all rights are reserved by the
project owner.

### Contribution

Pull requests are welcome. Before opening a PR:

1. Run `flutter analyze` and `flutter test` from `flutter_app/`.
2. Run `pytest -q` from `backend/`.
3. Keep architectural decisions consistent with
   [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) and
   [`docs/DATA_MODEL.md`](docs/DATA_MODEL.md).
4. Never introduce secrets, service-role keys, or live data dumps
   to the repository.
5. Do not add chat / DM / MCQ / quiz / live-transport features —
   they are explicitly out of scope.

### Code of conduct

Be respectful, be precise, keep changes focused. Small surgical
patches are preferred over large speculative rewrites.

---

<sub>Gochano — study, life, and finance in one app. 138 backend
tests, 126 Flutter tests, 0 analyzer issues, 16 API surface
areas, 7 named module gradients, 1 design system, 1 source of
truth for expenses.</sub>
