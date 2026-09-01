# Pre-implementation audit

> **Status legend.**
> ✅ WORKING · 🟡 PARTIAL · 🔴 MISSING · ⚠️ BROKEN · 🧹 LEGACY · ❓ NEEDS LIVE VERIFICATION

| # | Feature | Frontend | Backend | Database | Status | Action | Severity |
|---|---|---|---|---|---|---|---|
| 1 | Authentication (email + pwd) | `screens/auth/login_screen.dart`, `register_screen.dart`, `verify_email_screen.dart` | `app/core/auth.py` (Firebase ID-token dep) | Firebase Auth | ✅ WORKING | — | — |
| 2 | Email verification gate | `verify_email_screen.dart`, `auth_gate.dart` | Firebase Auth | Firebase Auth | ✅ WORKING | — | — |
| 3 | Role provisioning (student / general) | `auth_service.dart` writes role on first sign-in | `permission_service.py`, `app/routers/account.py` | Firestore `users/{uid}.role` | ✅ WORKING | — | — |
| 4 | Role enforcement (UI hide) | `home_shell.dart` rebuilds tabs | — | — | ✅ WORKING | — | — |
| 5 | Role enforcement (backend deny) | — | `permission_service.student_required` decorator | — | ✅ WORKING | — | — |
| 6 | Home (role-aware shell) | `screens/home/home_shell.dart` | — | — | ✅ WORKING | — | — |
| 7 | Home dashboard (bento) | `screens/home/dashboard/bento_dashboard_view.dart` + `widgets/bento/*` | — | — | 🟡 PARTIAL | Card composition works; "Community" tile exists conceptually but the prompt requires **Home \| Study \| Life \| Community \| Profile** — current tabs are **Home \| Study \| AI \| Life \| Profile**. AI is in nav; Community is **not** in nav. | P2 |
| 8 | Bottom nav floating glass | `_BentoFloatingNav` in `home_shell.dart` | — | — | ⚠️ BROKEN (UX) | `BackdropFilter(sigmaX:18,sigmaY:18)` + 30 px radius violates the brief's flat-UI rule. Replace with M3 `NavigationBar`. | P3 |
| 9 | Study workspace | `screens/study/study_screen.dart` | `app/routers/study.py` | Firestore `semesters`, `subjects`, `tasks` | ✅ WORKING | — | — |
| 10 | Semesters CRUD | `academic_structure_screen.dart` | study router | Firestore | 🟡 PARTIAL | Works but no archived/active semester split; semester-archived state never toggles task visibility. | P3 |
| 11 | Subjects CRUD | `academic_structure_screen.dart` | study router | Firestore | ✅ WORKING | — | — |
| 12 | Materials upload | `material_upload_screen.dart` | `app/routers/materials.py` + `storage_service.upload_bytes` | Firebase Storage | ✅ WORKING | — | — |
| 13 | Materials list / library | `materials_screen.dart`, `saved_materials_screen.dart` | materials router | Firestore + Storage | ✅ WORKING | — | — |
| 14 | PDF reader | `material_reader_screen.dart` (uses `pdfrx`) | — | — | ✅ WORKING | — | — |
| 15 | Notes CRUD | `notes_screen.dart`, `note_editor_screen.dart` | study router | Firestore | 🟡 PARTIAL | No autosave indicator; no markdown preview; no subject-suggest. | P3 |
| 16 | Tasks CRUD | `screens/tasks/tasks_screen.dart` | study router | Firestore | ✅ WORKING | — | — |
| 17 | Tasks reminders | `notification_service.dart` | — | local notifications | 🟡 PARTIAL | Schedules at task `dueAt`; **does not reschedule on edit/delete** — known P1 risk per brief. | P1 |
| 18 | Focus timer | `study/focus_timer_screen.dart` | — | — | ✅ WORKING | — | — |
| 19 | Study plan | `study/study_plan_screen.dart` | — | — | ✅ WORKING | — | — |
| 20 | Study stats | `study/study_stats_screen.dart` | — | — | 🟡 PARTIAL | Stats derived from tasks client-side only. No backend aggregation. | P3 |
| 21 | Monthly money (study hub) | `study/monthly_money_screen.dart` | — | Firestore | 🟡 PARTIAL | Reads transactions client-side. **Possible duplicate of Life/Expense** — see item 29. | P2 |
| 22 | Study groups (Shared Box) | `screens/groups/*` | `app/routers/groups.py` | Firestore `groups`, `group_resources` | ✅ WORKING | — | — |
| 23 | Group chat | `group_chat_screen.dart` | `part3.py` (group-message surface) | Firestore `group_chats` | 🟡 PARTIAL | Brief says **no group chat** ("no community chat/messages"); chat code exists in `part3.py`. Decision: **remove from active scope** per `docs/AUDIT_REPORT.md`. | P2 |
| 24 | Group admin / roles | `group_admin_screen.dart`, `group_detail_screen.dart` | groups router | Firestore | ✅ WORKING | — | — |
| 25 | AI Assistant | `study/ai_assistant_screen.dart` | `app/routers/ai.py` + `ai_service.py` (Gemini) | Firestore `ai_conversations` | 🟡 PARTIAL | Wired & quota-enforced; **not reachable from bottom nav** (moved out as part of P2). Document upload through AI needs explicit handler. | P1 |
| 26 | Document → AI (PDF/image) | `ai_assistant_screen.dart` | ai router | Firebase Storage | 🟡 PARTIAL | Upload pipeline exists via `storage_service`; **no UI to attach a doc on chat start**. | P1 |
| 27 | Universal search | `screens/search/universal_search_screen.dart` | (client-side) | Firestore | 🟡 PARTIAL | Search is role-aware but client-side only. Slow for >1k docs. | P4 |
| 28 | Daily expense | `life/daily_expenses_screen.dart`, `expense_tracker_screen.dart` | `part3.py` (financial surface) | Firestore `financial_transactions` (deterministic ID) | ✅ WORKING | Idempotent ledger per `PHASE_2_MIGRATION_REPORT.md`. | — |
| 29 | Expense consolidation (single source) | `financial_service.dart` + `monthly_money_screen.dart` | part3 | Firestore | 🟡 PARTIAL | Two read surfaces (`expense_tracker` + `monthly_money`) — verify only one user-facing module exists. | P2 |
| 30 | BazarBuddy | `life/bazar_buddy_screen.dart` | part3 | Firestore `bazar_items` | 🟡 PARTIAL | Shopping list works; **purchase auto-creates an expense**? Needs verification. | P2 |
| 31 | Budget / monthly summary | `monthly_money_screen.dart` | part3 | Firestore | 🟡 PARTIAL | Aggregates client-side; no plan-cap enforcement. | P3 |
| 32 | Medicine (hub) | `life/medicine_screen.dart` | health/prescriptions router | Firestore `medicines` | ✅ WORKING | — | — |
| 33 | Medicine form | `life/medicine_form_screen.dart` | health router | Firestore | ✅ WORKING | — | — |
| 34 | Medicine OCR | `life/medicine_ocr_screen.dart` | `app/routers/prescriptions.py` + `ocr_service.py` (Tesseract) | Storage (image) | 🟡 PARTIAL | OCR extracts well; **confirmation step before activation** is partial — verify the flow shows the parsed fields and only writes the medicine after user tap. | P1 |
| 35 | Medicine history | `life/medicine_history_screen.dart` | health router | Firestore | ✅ WORKING | — | — |
| 36 | Taken-dose → expense | `medicine_screen.dart` "Mark Taken" | part3 financial surface | Firestore | 🟡 PARTIAL | Deterministic ID prevents double-write; verify the actual path on edit/delete. | P2 |
| 37 | CommuteBD — places search | `life/commute_bd_screen.dart` | `app/routers/commute.py` (`/places/search`) | PostgreSQL `places` | ✅ WORKING | Phase 2 swap complete. | — |
| 38 | CommuteBD — routes | `life/commute_bd_screen.dart` | `commute/service.py` + `fare_engine.py` | PostgreSQL + OSRM/Nominatim | ✅ WORKING | OSRM/Nominatim are external. Public OSM quotas apply. | — |
| 39 | CommuteBD — fare report | `life/commute_bd_screen.dart` | `/api/commute/fare-report` | PostgreSQL `fare_reports` | ✅ WORKING | Per Phase 2 tests. | — |
| 40 | CommuteBD — PostGIS spatial | — | — | PostgreSQL | 🔴 MISSING | Migration installed extensions; **no `geometry` columns yet**. Spatial queries use Haversine on numeric lat/lng. | P4 (low impact at current scale) |
| 41 | CommuteBD — ML fare | — | `services/commute/ml_fare.py` | `.joblib` in Firebase Storage | 🟡 PARTIAL | Activates only when `COMMUTE_ML_MIN_*` thresholds are met. Cold-start path returns deterministic fallback. | P3 |
| 42 | Campus community | `screens/search/universal_search_screen.dart` (no dedicated hub) | — | — | 🔴 MISSING | Brief requires a Community surface in the bottom nav. Currently no `screens/community/` folder. | P2 |
| 43 | Profile | `screens/profile/profile_screen.dart` | `app/routers/account.py` (me/export/delete) | Firestore + Storage | ✅ WORKING | — | — |
| 44 | Account export (PDF + JSON) | `profile_screen.dart` | `account.export` | Firebase Storage + Firestore | ✅ WORKING | — | — |
| 45 | Account delete | `profile_screen.dart` | `account.delete` | Firebase + Storage + Postgres cleanup | 🟡 PARTIAL | Per `ARCHITECTURE.md`, legacy Firestore rows are cleaned up by `account.delete`. **Confirm Postgres `fare_reports` are also deleted** (FK cascade?). | P1 |
| 46 | Local notifications | `notification_service.dart` | — | `flutter_local_notifications` | 🟡 PARTIAL | Scheduled for tasks + medicine; **no reschedule on edit/delete** (same as 17). | P1 |
| 47 | Splash | `screens/system/gochano_splash_screen.dart` | — | — | ✅ WORKING | Hardened in commit `af831b3` (Phase H). | — |
| 48 | Theme — Material 3 + tokens | `core/theme.dart`, `design_tokens.dart` | — | — | 🟡 PARTIAL | Light theme complete; **dark theme is scaffolded only** (its own comment acknowledges this). | P2 |
| 49 | Bangla / English language | `core/language.dart` (`EkLanguage.text`) | — | — | 🟡 PARTIAL | Key surface exists; verify every visible string has a Bangla translation (audit needed). | P3 |
| 50 | File upload quota (15 MB / 100 MB / 10 / day) | — | `app/core/config.py` + storage/router guards | Firestore (counters) | ✅ WORKING | Per `test_part3.py` + `test_quotas.py`. | — |
| 51 | AI daily limit (30 / day) | — | `ai_service.py` + quota helper | Firestore (counters) | ✅ WORKING | Per `test_quotas.py`. | — |
| 52 | Firestore rules | `firebase/firestore.rules` | — | — | 🟡 PARTIAL | Need full rule review for owner-scope + role gates. Brief requires student-only enforcement at the rule layer. | P2 |
| 53 | Backend deployment (Render) | — | `backend/render.yaml`, `backend/Dockerfile` | — | ✅ WORKING | Docker runtime, free plan. | — |
| 54 | Android configuration | `flutter_app/android/` | — | — | 🟡 PARTIAL | `firebase_options.dart` is wired; `key.properties` is example-only. Release signing needs operator keys. | ❓ NEEDS LIVE VERIFICATION |
| 55 | Release Android build | — | — | — | ❓ NEEDS LIVE VERIFICATION | Cannot be executed in this environment; operator must run `flutter build appbundle --release` per `docs/PRODUCTION_CHECKLIST.md`. | — |

---

## Legacy / dead code inventory

| File | Status | Recommendation |
|---|---|---|
| `backend/app/services/commute/supabase_repository.py` | 🧹 LEGACY — referenced only by `models.py`/`postgres_repository.py` docstrings and one test | Keep as historical evidence; mark with `# DEPRECATED — use CommutePostgresRepository` header. Do not delete (preserves Phase-2 audit trail). |
| `backend/app/core/config.py` fields: `supabase_url`, `supabase_service_role_key`, `supabase_bucket` | 🧹 LEGACY — kept for backwards-compat | Leave. Removing breaks Render env binding unless operator rotates env at the same time. |
| `flutter_app/lib/screens/home/widgets/brutalist.dart` | 🧹 LEGACY — superseded by `widgets/bento/` | Either remove after UX redesign, or keep as the brutalist design alternative. Currently used by `home_shell.dart` *only for legacy imports* (verify after UX change). |
| `flutter_app/lib/screens/home/home_shell.dart` `_BentoFloatingNav` | ⚠️ BROKEN (UX) — violates flat-UI rule | Replace with M3 `NavigationBar` during UX phase. |
| `backend/PHASE_2_MIGRATION_REPORT.md` | ✅ WORKING — canonical evidence | Keep. Cite it from CURRENT_PROJECT_MAP.md. |
| `flutter_app/lib/screens/groups/group_chat_screen.dart` | 🧹 LEGACY — out of active scope per `docs/AUDIT_REPORT.md` | Decision needed: remove or keep behind a feature flag. |
| `docs/PROJECT_SPEC.md`, `docs/TODO.md`, `docs/GOCHANO.md` (deleted in working tree) | 🧹 LEGACY — superseded by `docs/CURRENT_PROJECT_MAP.md` + `docs/PRE_IMPLEMENTATION_AUDIT.md` | Already deleted in working tree; keep the deletion. |
| `backend/COMMUTEBD_BACKEND_UPDATE.md` (deleted in working tree) | 🧹 LEGACY | Already deleted; keep deletion. |

---

## Risk register

| ID | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| R-1 | Re-introducing Supabase Storage by accident because legacy `supabase_*` env still resolves | LOW | HIGH | Add a Phase-2 sanity check at backend startup that logs the active storage backend. |
| R-2 | Alembic baseline migration missing → schema drift between ORM and DB | MEDIUM | HIGH | Operator runs `alembic revision --autogenerate -m "initial"` on real Postgres (Phase 2g). |
| R-3 | Dark mode parity breaks a screen after Material 3 re-color | MEDIUM | LOW | Visual QA per screen with `Theme.of(context).brightness == Brightness.dark` test. |
| R-4 | Bottom-nav UX change breaks IndexedStack state | LOW | MEDIUM | Preserve tab indices through `home_shell`; add integration test. |
| R-5 | Removing group chat breaks installed users who rely on it | LOW | MEDIUM | Wrap in a feature flag, not a hard removal, until v2. |
| R-6 | AI rate limit / quota error path crashes the app | LOW | MEDIUM | Already hardened in `9c49f86` ("fix AI assistant Gemini connection and error handling"). Keep the error envelope. |
| R-7 | Secret `FIREBASE_SERVICE_ACCOUNT_B64` accidentally committed | LOW | HIGH | `.gitignore` excludes `.env`; verify no `firebase-service-account.json` in the working tree. |
