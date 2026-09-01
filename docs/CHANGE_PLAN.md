# Change plan

> **Inputs.** `CURRENT_PROJECT_MAP.md`, `PRE_IMPLEMENTATION_AUDIT.md`, `DATA_OWNERSHIP.md`, `DATABASE_AUDIT.md`, `API_CONTRACT_AUDIT.md`.
>
> **Severity scale.**
> - **P0** — blocker. Do not ship without it.
> - **P1** — broken behaviour the brief explicitly calls out.
> - **P2** — required by the brief (UX, dark mode, parity).
> - **P3** — UX polish.
> - **P4** — optional / nice-to-have / deferred.

---

## Summary

| Severity | Count | Examples |
|---|---|---|
| P0 | 2 | Backend startup misconfig guard; Postgres baseline migration |
| P1 | 5 | Task reminder reschedule / cancel on edit+delete; Material replace flow; AI doc upload wired; Prescription confirm step; Account delete cleans Postgres |
| P2 | 6 | Material 3 `NavigationBar` (no glass blur); 5-tab structure Home\|Study\|Life\|Community\|Profile; AI out of bottom nav; Dark mode parity; Community hub; Firestore rules role gates; Material replace end-to-end |
| P3 | 8 | Bangla parity audit; Brutalist legacy removal; Bottom-nav blur; Archived-semester task visibility; Markdown notes; AI doc upload UI; Budget plan-cap; ML fare activation |
| P4 | 3 | PostGIS `geometry` columns; Universal search server-side; Spatial / composite indexes |

Total: 24 changes.

---

## P0 — Blockers

### P0-1 — Backend fail-fast on misconfig
- **Current behaviour.** `connection.py` silently falls back to SQLite if `DATABASE_URL` is empty. `config.py` reads `supabase_*` env vars even though they're never used by active code paths.
- **Problem.** A Render misconfig (e.g. blank `DATABASE_URL`) keeps the API "running" against a non-persistent SQLite that loses data on every deploy. Same for legacy Supabase bindings: someone may try to enable them and reintroduce the Supabase path.
- **Target behaviour.** When `app_env == production` and `database_url` is empty, log a startup error and `raise`. Log a warning when `supabase_url` is set (informational; do not abort). On boot, log the active backend surface: `storage=firebase db=postgres ai=gemini`.
- **Files.** `backend/app/main.py` (startup hook), `backend/app/database/connection.py` (guard), `backend/app/core/config.py` (warn on `supabase_*`).
- **DB.** none.
- **API.** none.
- **Risk.** low.
- **Test.** unit test that sets `app_env=production`, empty `database_url`, asserts `RuntimeError`.

### P0-2 — Postgres baseline migration
- **Current behaviour.** `alembic/versions/20260829080000_initial_commutebd.py` covers only CommuteBD tables. `users`, `semesters`, `subjects`, `resources`, `tasks`, `expenses`, `groups`, `group_resources` are defined in `app/database/models.py` but never committed as an Alembic revision.
- **Problem.** Schema drift between ORM and DB; first deploy onto a fresh Postgres will fail.
- **Target behaviour.** Operator runs `alembic revision --autogenerate -m "initial-mirror-tables"` against an empty Postgres with the ORM imported, commits the result, runs `alembic upgrade head`.
- **Files.** new `backend/alembic/versions/2026XXXX_initial_mirror_tables.py`.
- **DB.** yes — operator step.
- **API.** none.
- **Risk.** low if autogenerate is reviewed by hand; medium if autogenerate picks up unwanted drops.
- **Test.** `alembic upgrade head` against a throwaway Postgres in CI.

---

## P1 — Broken behaviour

### P1-1 — Task reminder reschedule / cancel
- **Current behaviour.** `notification_service.dart` schedules a notification at the task's `dueAt`. Editing a task does **not** reschedule; deleting a task does **not** cancel.
- **Problem.** Stale reminders fire after edits; reminders fire for tasks the user already deleted.
- **Target behaviour.** On task PATCH with a new `dueAt`, cancel the previous notification and schedule a new one. On task DELETE, cancel. Persist the notification ID on the task document so we can target it.
- **Files.** `flutter_app/lib/services/notification_service.dart`, `flutter_app/lib/screens/tasks/tasks_screen.dart`, `backend/app/routers/study.py` (cancel via `/api/part3/task-reminders/{id}`).
- **DB.** none.
- **API.** `PATCH /api/part3/task-reminders/{id}` already exists — verify and harden.
- **Risk.** low. Notification IDs are unique per call.
- **Test.** integration test: create task → schedule → edit due time → assert only one upcoming notification.

### P1-2 — Material replace end-to-end
- **Current behaviour.** `/api/materials/{id}/replace` exists; unclear whether the UI surface is wired.
- **Problem.** Brief calls out material replace; current upload flow creates a new material instead of replacing in place.
- **Target behaviour.** Material detail screen has a "Replace file" action → uploads new bytes via signed URL → backend updates `storagePath` and `sizeBytes` (does **not** create a new document).
- **Files.** `flutter_app/lib/screens/materials/material_detail_screen.dart`, `flutter_app/lib/screens/materials/material_upload_screen.dart` (`mode: replace`), `backend/app/routers/materials.py` (verify `replace` handler).
- **DB.** none (Firestore `materials/{id}.storagePath` updated).
- **API.** `PATCH /api/materials/{id}/replace`.
- **Risk.** low — Storage object replacement is idempotent.
- **Test.** unit test of `replace` handler with a mocked storage client.

### P1-3 — AI doc upload wired into the chat surface
- **Current behaviour.** `POST /api/ai/upload` exists; the chat screen has no "Attach" button.
- **Problem.** Users cannot upload a PDF / image and ask Gemini about it.
- **Target behaviour.** `ai_assistant_screen.dart` gains an `attach` button that opens `file_picker`, uploads via `/api/ai/upload`, then includes the returned `storagePath` in the next `chat` request. Backend `ai_service.py` includes the file in the Gemini call (multimodal).
- **Files.** `flutter_app/lib/screens/study/ai_assistant_screen.dart`, `flutter_app/lib/services/ai_service.dart`, `backend/app/services/ai_service.py`.
- **DB.** none.
- **API.** `POST /api/ai/upload` (verify), `POST /api/ai/chat` (accept `attachmentStoragePath`).
- **Risk.** medium — Gemini multimodal token cost. Add an explicit cap on attachment bytes.
- **Test.** upload fixture PDF → chat with reference → assert reply cites it.

### P1-4 — Prescription OCR explicit confirmation
- **Current behaviour.** OCR returns parsed fields; unclear whether the user must tap "Confirm" before the medicine is created.
- **Problem.** Risk of "phantom medicine" creation before the user reviews.
- **Target behaviour.** After OCR, screen renders the parsed fields with an editable form. Only when the user taps "Create medicine" does `POST /api/prescriptions/{id}/confirm` fire, which writes the `medicines/{medId}` doc + scheduled doses. Until then, only the OCR result is cached.
- **Files.** `flutter_app/lib/screens/life/medicine_ocr_screen.dart`, `backend/app/routers/prescriptions.py`.
- **DB.** none.
- **API.** `POST /api/prescriptions/{id}/confirm` (verify).
- **Risk.** low — idempotent on `prescriptionId`.
- **Test.** OCR fixture → assert no medicine created until confirm.

### P1-5 — Account delete cleans Postgres
- **Current behaviour.** `DELETE /api/account/delete` cleans Firestore + Storage; Postgres cleanup of `fare_reports` is unverified.
- **Problem.** Orphaned rows remain in `fare_reports` after account deletion.
- **Target behaviour.** Backend delete handler runs `DELETE FROM fare_reports WHERE owner_uid = :uid`; mirrored tables get the same treatment. Verify cascade.
- **Files.** `backend/app/routers/account.py` (or service module), `backend/app/database/models.py` (verify FK `fare_reports.owner_uid` cascade).
- **DB.** yes — explicit cleanup + FK.
- **API.** `DELETE /api/account/delete`.
- **Risk.** medium — if cascade is wrong, accidental deletes elsewhere.
- **Test.** integration test: create user + reports → delete → assert zero rows.

---

## P2 — Required by the brief

### P2-1 — Material 3 `NavigationBar` (no glass blur)
- **Current behaviour.** `_BentoFloatingNav` with `BackdropFilter(sigmaX:18,sigmaY:18)` and a 30 px radius pill.
- **Problem.** Violates the brief's flat-UI rule.
- **Target behaviour.** M3 `NavigationBar` (height 80, indicator purple, label + icon, no blur, no pill). Move the blur style to **bento cards** if desired for visual interest.
- **Files.** `flutter_app/lib/screens/home/home_shell.dart`, `flutter_app/lib/core/theme.dart` (NavigationBar tokens).
- **DB.** none.
- **API.** none.
- **Risk.** low.
- **Test.** visual QA, light + dark.

### P2-2 — Bottom-nav structure Home | Study | Life | Community | Profile
- **Current behaviour.** Five tabs: Home, Study, AI, Life, Profile.
- **Problem.** Brief requires Community; AI should be reachable from Study or Home only, not in bottom nav.
- **Target behaviour.** Remove AI from bottom nav. Add Community (new hub). Keep Home / Study / Life / Profile. AI is launched from the Study dashboard (and Home via quick-action).
- **Files.** `flutter_app/lib/screens/home/home_shell.dart`, `flutter_app/lib/screens/community/*` (new), `flutter_app/lib/screens/study/dashboard.dart` (add AI quick action).
- **DB.** none.
- **API.** none (Community is Firestore-backed).
- **Risk.** low.
- **Test.** smoke test of each tab.

### P2-3 — Community hub
- **Current behaviour.** No `screens/community/` folder; only a "Community Library / Browse Resources" promo block was removed per `ARCHITECTURE.md`.
- **Problem.** Brief requires a Campus Community hub in the bottom nav.
- **Target behaviour.** New `screens/community/campus_community_screen.dart` shows: top contributors, latest notes, popular materials, study-group discovery. Backed by Firestore aggregations (`group_resources`, `materials`).
- **Files.** new `flutter_app/lib/screens/community/*`, new widgets in `flutter_app/lib/widgets/community/*`.
- **DB.** Firestore only.
- **API.** none required — Firestore aggregations.
- **Risk.** medium — community features can spiral.
- **Test.** smoke + role gating.

### P2-4 — Dark mode parity
- **Current behaviour.** `EkTheme.dark()` exists but is a scaffold; many screens hardcode `EkColors.card` / `EkColors.text`.
- **Problem.** Brief requires full light/dark parity.
- **Target behaviour.** Replace every hardcoded colour with a `Theme.of(context).colorScheme.*` or `EkColors.*` token that resolves to light + dark variants. Visual QA per screen.
- **Files.** all screens + widgets; `flutter_app/lib/core/theme.dart` (extend dark tokens); `flutter_app/lib/core/design_tokens.dart`.
- **DB.** none.
- **API.** none.
- **Risk.** medium — easy to miss a screen.
- **Test.** golden test per screen at light + dark.

### P2-5 — Firestore rules role gates
- **Current behaviour.** `firebase/firestore.rules` enforces owner scope; unclear whether role gates are present on study-only collections.
- **Problem.** A `general` user could write to `semesters` / `subjects` / `tasks` / `notes` if rules are too permissive.
- **Target behaviour.** Rules deny writes for `request.auth.token.role != 'student'` to study-keyed collections (`semesters`, `subjects`, `tasks`, `notes`, `materials`, `ai_conversations`).
- **Files.** `firebase/firestore.rules`.
- **DB.** none.
- **API.** none.
- **Risk.** low.
- **Test.** rules emulator test for `general` user attempting to write to `tasks`.

### P2-6 — Expense consolidation (single surface)
- **Current behaviour.** Two read surfaces — `expense_tracker_screen` + `monthly_money_screen` (in Study).
- **Problem.** Two views, two code paths; risk of divergence.
- **Target behaviour.** Decide: keep Expense as a Life-only hub and remove the Study-side `monthly_money_screen`. Or vice versa. **Recommendation:** keep Expense in Life only; Study `monthly_money` removed or relabelled to "Study Budget" with non-financial data.
- **Files.** `flutter_app/lib/screens/life/expense_tracker_screen.dart` (canonical), `flutter_app/lib/screens/study/monthly_money_screen.dart` (deprecate or relabel).
- **DB.** none.
- **API.** none.
- **Risk.** low.
- **Test.** smoke test of Life → Expense flow.

---

## P3 — UX polish

| ID | Change | Files |
|---|---|---|
| P3-1 | Bangla parity audit (every visible string has a `bn` translation; QA pass) | `flutter_app/lib/core/language.dart` + every screen |
| P3-2 | Remove brutalist legacy widgets once bento is the only design language | `flutter_app/lib/screens/home/widgets/brutalist.dart` (delete), update imports |
| P3-3 | Notes: autosave indicator + markdown preview + subject-suggest | `note_editor_screen.dart`, `notes_screen.dart` |
| P3-4 | Archived-semester toggle: archived semester's tasks are hidden from dashboard | `dashboard_view.dart`, `tasks_screen.dart`, `academic_structure_screen.dart` |
| P3-5 | BazarBuddy purchase → auto-create expense (with deterministic ID) | `bazar_buddy_screen.dart`, `services/bazar_buddy_service.dart` |
| P3-6 | Budget plan-cap (per-month spend limit + alert) | `expense_tracker_screen.dart`, `services/financial_service.dart` |
| P3-7 | ML fare model activation logging + cold-start telemetry | `services/commute/ml_fare.py` |
| P3-8 | Study stats backend aggregation (instead of client-only) | `services/study_service.dart`, `routers/study.py` |

---

## P4 — Optional / deferred

| ID | Change | Trigger |
|---|---|---|
| P4-1 | PostGIS `geometry` columns + GIST index | when `places` > 100k rows |
| P4-2 | Universal search server-side (Firestore + Postgres hybrid) | search latency > 200 ms |
| P4-3 | Composite indexes on `places (city, lat, lng)` and `fare_reports (owner_uid, created_at)` | query planner confirms need |

---

## Cross-cutting deliverables

### Error envelope centralization
- Normalize on `{ "detail": str, "code": str }` everywhere.
- Wrap each router with `app/core/error_handlers.py` to catch unhandled exceptions and return the envelope.

### Performance audit
- Profile the app launch on Android (cold start to home shell).
- Profile the CommuteBD route solve end-to-end (search → nearest → route → report).

### Tests
- Re-run all 57 tests after each P0/P1/P2 change.
- Add tests for every new endpoint and every UX change that introduces branching.

### Responsive check
- Tablet layout (sw600): two-column bento.
- Phone layout (default): single column.

### Release build
- Operator-only. `flutter build appbundle --release` after every P2 lands.

---

## Dependencies between changes

```text
P0-2 (baseline migration) ─┐
P0-1 (fail-fast)           │   ─── Phase 4: stabilize
                            │
P1-1 (task reminders) ────────── Phase 5
P1-2 (material replace) ────────── Phase 5
P1-3 (AI doc upload) ──────────── Phase 5
P1-4 (prescription confirm) ───── Phase 5
P1-5 (account delete) ─────────── Phase 5
                            │
P2-1 (NavigationBar) ─┐
P2-2 (5-tab structure)┼───── Phase 6: UX redesign
P2-3 (Community hub)  ─┘
                            │
P2-4 (dark mode) ──────────── Phase 7
P2-5 (Firestore rules) ────── Phase 7
P2-6 (expense consolidation) Phase 7
                            │
P3-* ──────────────────────── Phase 8+
P4-* ──────────────────────── defer
                            │
Cross-cutting ─────────────── Phases 40-47
Closing docs ──────────────── Phase 48
```
