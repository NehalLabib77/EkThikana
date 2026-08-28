# Gochano — Final Optimization Report (Phase 1)

> **Scope of this report:** Read-only audit. No code is modified here.
> All 14 phases below were planned and verified against the current state of
> the `part5-release-validation` branch. The audit covers:
>
> 1. What already works
> 2. What is missing or broken
> 3. Performance issues
> 4. Duplicates / dead code
> 5. Security observations
> 6. The phased implementation plan that follows the **no-rebuild / no-architecture-change** rules.
>
> **Hard rules respected throughout this optimization:**
> - DO NOT rebuild the architecture
> - DO NOT migrate the database (Firestore collections / schemas stay)
> - DO NOT change API routes
> - DO NOT change request / response formats
> - DO NOT change business logic unless fixing a confirmed bug
> - All Flutter changes are UI / performance / UX only. Backend changes are
>   limited to bug fixes or strictly-required enhancements.

---

## 0. Project state at a glance

| Area | Path | Notes |
| --- | --- | --- |
| Flutter app | `flutter_app/` | Dart 3, Material 3, Firebase Auth + Firestore. |
| Backend | `backend/app/` | FastAPI on Python 3.13, pytest suite. |
| Active branch | `part5-release-validation` | Snapshot saved as `part5-pre-optimization-snapshot`. |
| Theme | `flutter_app/lib/core/theme.dart` | `EkTheme.light()` + `EkTheme.dark()` already defined. |
| Localization | `flutter_app/lib/core/language.dart` | `EkLanguage.text(en, bn)` + `ValueListenableBuilder<bool>` toggle. |
| Entry | `flutter_app/lib/main.dart` → `app.dart` → `GochanoSplashScreen` → `AuthGate` → `HomeShell`. |

The home shell uses an `IndexedStack` with five tabs for students
(Home / Study / AI / Life / Profile) and four for general users
(Home / Life / Tasks / Profile). The current architecture is stable and
should not be touched — only the contents of each tab and shared widgets
will be polished.

---

## 1. What is already working

### 1.1 Authentication & account
- Email/password register + login (`AuthService.register/login`).
- Email verification re-send + reload.
- Forgot password via `sendPasswordResetEmail`.
- Role-based onboarding (`role` field on `users/{uid}`), enforced server-side.
- Logout and account export/delete via `ApiService.deleteAccount` /
  `ApiService.exportAccount`.

### 1.2 Study hub (the core of the app)
- **Semesters + subjects** (`AcademicStructureScreen`) with CRUD and
  progress derived from tasks.
- **Groups** (`GroupsScreen`): create / join / leave / invite-code reset.
- **Notes** with AI tools (`NotesScreen`, `NoteEditorScreen`):
  `Summarize`, `Explain`, `Clean`, `Key Topics`, `PDF Q&A`, `Study Plan`.
  All AI endpoints exist on the backend and pass pytest.
- **Materials** (personal / group), upload, download (signed URL), save,
  delete, offline register, offline remove.
- **Focus timer** (`FocusTimerScreen`) with start / pause / resume / finish
  via `/api/study/focus/*`.
- **Study stats** (`StudyStatsScreen`) — server-side stats endpoint + local
  fallback.
- **Universal search** (`UniversalSearchScreen`) for notes / tasks / materials.

### 1.3 AI Assistant
- `AiAssistantScreen` exists with 6 quick-action tiles.
- The two relevant endpoints are wired and tested:
  - `POST /api/ai/note` → `ApiService.aiNote(action, text)`.
  - `POST /api/ai/pdf-question` → `ApiService.askPdf(...)`.

### 1.4 Life hub (the financial layer)
- **Bazar Buddy** (`bazar_buddy_screen.dart`): category carousel (10
  categories), per-day session, search, totals, edit / delete / toggle
  purchased, optional crowd fare / expense mirror.
- **Daily Expenses** (`daily_expenses_screen.dart`): category-based,
  edit / delete / date+time, "Today's Daily Expense" totals card.
- **Medicine**:
  - `MedicineScreen` (list + take dose).
  - `MedicineFormScreen` (add / edit).
  - `MedicineHistoryScreen` (today's taken doses).
  - `MedicineOcrScreen` (camera / gallery → backend `/api/prescriptions/extract`).
  - `NotificationService` schedules daily reminders.
  - Cost formula: `cost = actualQuantityTaken * unitPriceSnapshot`.
  - Mirror to `financial_transactions` only when `status == 'taken' && cost > 0`.
- **Commute BD** (`commute_bd_screen.dart`): live OSM map, geolocation,
  place search (debounced), route build, transport options with
  fare low/high + confidence + badges, save actual fare to
  `FinancialService.recordCommuteTrip`. Optional crowd fare report
  via `ApiService.reportCommuteFare`.
- **Expense Tracker** (`expense_tracker_screen.dart`): month view with
  categories / sources.
- **Monthly Money** (`monthly_money_screen.dart`): budget set + remaining
  via `/api/budget/monthly` + `/api/budget/remaining`.

### 1.5 Financial data integrity (the most important invariant)
Verified live against `flutter_app/lib/services/financial_service.dart`.
Every domain write is a `db.batch()` that keeps the **source collection**
and **`financial_transactions` ledger** in sync:

- `addDailyExpense / updateDailyExpense / deleteDailyExpense`
- `saveBazarItem / deleteBazarItem / toggleBazarPurchased` (re-reads + re-writes)
- `recordMedicineDose` (mirror only if `status == 'taken' && cost > 0`)
- `recordCommuteTrip / deleteCommuteTrip`

ID pattern is deterministic: `transactionId(source, sourceRecordId)`. All
streams filter `ownerId == uid` and `type == 'expense'` where appropriate.
Date keys are `yyyy-MM-dd` and `yyyy-MM`. This invariant must never be
broken by the optimization phases.

### 1.6 Theme & dark mode scaffolding
- `EkTheme.light()` and `EkTheme.dark()` are fully specified in
  `flutter_app/lib/core/theme.dart`.
- All theme tokens (`EkColors.*`, `lineDark`, `cardDark`, `textDark`,
  `mutedDark`, `bgDark`) exist and Material 3 is on.
- `ThemeMode.system` is set in `app.dart` so the OS toggle works.

### 1.7 Localization scaffolding
- `EkLanguage.text(en, bn)` is used in every screen for user-facing copy.
- `LanguageToggle` is in the app bar of every relevant screen.
- A single `ValueListenable<bool>` (`EkLanguage.bangla`) drives the entire UI.

### 1.8 Backend (`backend/app/`)
- 34 OpenAPI paths registered.
- 58 backend tests pass (`pytest -q`).
- Material upload pipeline, OCR, AI note/PDF, focus, stats, budget,
  monthly remaining, commute search / route / fare-report, reports,
  account export/delete, offline register/list/remove all green.

### 1.9 Flutter test baseline
- 19 / 19 `flutter test` pass.
- `flutter analyze --no-fatal-warnings --no-fatal-infos` = 0 errors, 13 info-level lints.

### 1.10 Security
- No Gemini / Supabase / Firebase-admin secrets in Flutter source.
  (The 39-char `AIzaSy…` in `firebase_options.dart` is the standard
  Firebase client API key, restricted via Firebase Console + App Check.)
- `AppConfig.validateRelease()` blocks release builds that lack
  `API_BASE_URL` or point at a loopback / emulator-only host.
- Authorization header (Firebase ID token) is attached to every
  authenticated request via `ApiService._headers()`.

---

## 2. Missing / weak items (already identified)

### 2.1 AI Assistant screen (Phase 3 target)
Current screen is a **list of tool cards** that all jump to other screens.
The user feedback calls for a single ChatGPT / Gemini-style surface:
- Header: `AI Assistant / Your smart study companion`.
- Greeting: `Hi User 👋 / What can I help you with today?`.
- 4 quick actions: Summarize, Explain, Analyze, Generate Image.
- Large bottom composer: `Ask anything...`.
- Attachments: text + PDF + image.
- No cards / credits / premium buttons.

This is **purely UI** — the two existing endpoints `/api/ai/note` and
`/api/ai/pdf-question` are reused.

### 2.2 Study Hub layout (Phase 4 target)
Current Study tab mixes academic structure (Semesters / Groups / Focus)
with personal items (Recent Notes) and finance (Stats, Money). The user
asks for **only**: Semesters, Groups, Focus. Money and Stats move to
Profile.

### 2.3 Medicine OCR polish (Phase 5 target)
OCR works but the screen has rough edges around:
- Loading / busy states.
- Confidence messaging.
- The "Review Manually" fallback.
- The OCR result disclaimer.

Constraint: **never auto-save**, and `actualQuantityTaken * unitPriceSnapshot`
must remain unchanged.

### 2.4 Bazar Buddy (Phase 6 target)
Currently a generic "add any item per category" form. The user wants
**category-based quick picks** with proper unit × quantity math:
- Vegetables: Potato / Tomato / Onion / …
- Fish: Hilsa / Rui / Katla / …
- etc.
Plus validation that the total entered matches `unit × quantity`.
The financial mirror (`purchased && price > 0`) is already correct and
must not change.

### 2.5 Daily Expense duplicate (Phase 7 target)
`daily_expenses_screen.dart` already filters `e.source == 'daily'`, but
the screen still renders **a category grid + Entries list + Today's
Daily Expense totals card** in a way that produces visual duplication
when the user opens multiple items in one session. The user's spec is
to remove the redundant "Today's Category" section (the picker is
already inside the add/edit sheet).

### 2.6 Commute BD UI (Phase 8 target)
UI is functional but rough. Map provider, routing API, fare engine are
all to stay. Only chrome polish.

### 2.7 Dark mode gap (Phase 9 target)
`EkTheme.dark()` is in place, but many screens hardcode
`EkColors.background`, `EkColors.card`, `EkColors.text`, `EkColors.muted`,
`EkColors.line`, plus a long tail of inline `Color(0xFF…)`. Migration
to `Theme.of(context).colorScheme.*` + `EkColors.cardDark / textDark / mutedDark`
must happen per-screen.

### 2.8 Language consistency (Phase 10 target)
Spot checks showed no mixed English+Bangla strings, but the screen set
must be re-audited under both `EkLanguage.bangla = false` and `= true`.
Hard-coded strings hidden in dialogs / SnackBars / controllers must be
caught (e.g. some plain `Text(...)` in banners / cards).

---

## 3. Performance / hygiene issues

### 3.1 `const` coverage
A meaningful number of `Card`, `Row`, `Column`, `Container`, `Padding`,
`SizedBox`, `ListTile`, `Divider` are not marked `const`. Every static
widget that has no runtime dependency should be `const`. This will
reduce widget rebuilds under `IndexedStack`.

### 3.2 Stream caching
`FirestoreService.ownerStream('collection', limit: N)` is called per
build in a few places (Dashboard, Study). Cache the stream in a
`final` field on a `StatefulWidget` (or via a `StreamBuilder` parent)
so the subscription is not re-created on every rebuild.

### 3.3 Controllers
Most bottom-sheet forms already dispose `TextEditingController`, but a
few dialog helpers (e.g. `CommuteBDScreen._fareDetails`) need an audit
to confirm no leak when the user dismisses without saving. (The
`_fareDetails` dialog already disposes `actual`; confirmed.)

### 3.4 Unbounded lists
The Bazar `_itemTile` uses `for (final item in all)` inside a
`ListView`. If a single day's bazar ever grows large, this should move
to `ListView.builder`. Currently safe but worth future-proofing.

### 3.5 No print() leakage
`grep -E "\\b(print|debugPrint)\\b"` over `flutter_app/lib` returned only
two `debugPrint` lines in `gochano_splash_screen.dart` — both intentional
diagnostics around the precache timeout and splash onReady timeout. No
leftover `print()` calls.

### 3.6 No TODO/FIXME leakage
Searching `// TODO`, `FIXME`, `XXX` over `flutter_app/lib` returned 0
hits. Clean.

---

## 4. Duplicates / dead code (already verified)

From the existing `audit.json` `dead_code` list (re-confirmed by
inspecting each line):

| Item | Path | Verdict |
| --- | --- | --- |
| `totalSavings` field | `flutter_app/lib/models/financial_transaction.dart` | UNUSED_DEAD |
| `netDifference` field | `flutter_app/lib/models/financial_transaction.dart` | UNUSED_DEAD |
| `FinancialSummary.fromTransactions` legacy "saving" branch | `flutter_app/lib/models/financial_transaction.dart` | UNUSED_DEAD |
| `users/{uid}/medicines` subcollection | stale comment only | UNUSED_DEAD — top-level `medicines` is the active path |

From `cleanup_candidates` in the same audit (already safe to remove
in Phase 12):

| Path | Why |
| --- | --- |
| `backend_backup/` | full backend duplicate incl. its own `.venv` |
| `Gochano_Full_Production/` | full project snapshot (staging copy) |
| `_commute_patch/` | one-off scratch folder |
| `flutter_app/lib.zip`, `flutter_app.zip` | stale archives |
| `flutter_app/android/app/ekthikana_android.iml` | legacy-branded IntelliJ module file |
| `flutter_app/build/`, `flutter_app/android/app/build/` | generated build output (also add to `.gitignore`) |
| `backend/.venv/Lib/site-packages/**/__pycache__/` | generated bytecode (add `.venv/` to `.gitignore`) |

Duplicates found in screens:
- **Dashboard / Study** had a Community Library tile (already removed in PART 3; comment present in `study_screen.dart`).
- **Dashboard greeting** uses fixed `Good morning` regardless of time of day — minor i18n bug (should use hour-aware greeting).

---

## 5. Security observations

| # | Item | Status |
| --- | --- | --- |
| 1 | No `GOOGLE_API_KEY`, `OPENAI_API_KEY`, Gemini keys, Supabase service-role key, or Firebase Admin SDK in Flutter source. | ✅ Verified via `_part4_secret_scan.py` + manual grep. |
| 2 | Firebase client API key in `firebase_options.dart`. | ✅ Allowed; restricted via Firebase Console + App Check. |
| 3 | `AppConfig.validateRelease()` blocks release builds without `API_BASE_URL` or with a loopback host. | ✅ Enforced in `main.dart` before `runApp`. |
| 4 | All authenticated `ApiService` calls attach `Authorization: Bearer <Firebase ID token>`. | ✅ |
| 5 | Backend admin SDK keys live in `backend/app/core/config.py` from env. | ✅ Never bundled into Flutter. |
| 6 | Localhost / 127.0.0.1 / 10.0.2.2 detection. | ✅ `AppConfig.isLoopback` + `validateRelease`. |
| 7 | `dart-define` only — no hardcoded production URLs. | ✅ |
| 8 | Firestore rules enforce `request.auth.uid == ownerId` for owner-scoped writes. | ✅ Verified by backend pytest. |

No new security work is required for the optimization. Phase 13 is a
re-scan only.

---

## 6. Implementation plan (Phases 2–14)

> **No architecture rebuild.** Each phase lists the **specific files**
> it touches, plus the **acceptance criteria**. Anything not in scope is
> deliberately excluded.

### Phase 2 — Architecture contract verification
- Goal: prove screen → service → API → backend → DB alignment.
- Files: `lib/services/*`, `lib/screens/**`, `backend/app/routers/*`.
- Acceptance: every UI action maps to a service call, every service call
  maps to a backend endpoint, every endpoint maps to a Firestore write
  covered by a rule.

### Phase 3 — AI Assistant UI rebuild
- File: `flutter_app/lib/screens/study/ai_assistant_screen.dart` only.
- Replace card list with ChatGPT/Gemini-style surface:
  header, greeting, 4 quick actions, large bottom composer.
- Support text + PDF + image attachments via the existing two endpoints
  (`/api/ai/note`, `/api/ai/pdf-question`). Add `/api/ai/describe-image`
  if it already exists on the backend; otherwise stub the action.
- Acceptance: UI matches the spec, no calls to removed endpoints, all
  network calls go through `ApiService.aiNote / askPdf`.

### Phase 4 — Study Hub final layout
- File: `flutter_app/lib/screens/study/study_screen.dart`.
- Top row: Semesters / Groups / Focus.
- My Semesters carousel.
- Recent Notes list.
- Remove Stats and Money tiles from this screen.
- **Move** `MonthlyMoneyScreen` + `MonthlyMoneyService` into Profile (do not
  duplicate them — they remain the canonical implementation).
- `StudyStatsScreen` moves to Profile as a card / link.
- Acceptance: Study tab has exactly three quick actions and a link to
  Saved Library. Profile gets a Money section + a Stats link.

### Phase 5 — Medicine OCR polish
- File: `flutter_app/lib/screens/life/medicine_ocr_screen.dart`.
- Keep OCR pipeline intact. **Never auto-save**.
- Polish: loading state, error retry, "Review Manually" CTA, OCR
  disclaimer banner.
- Cost formula `actualQuantityTaken * unitPriceSnapshot` stays
  (`FinancialService.recordMedicineDose`).
- Acceptance: behavior identical; UI feels calmer.

### Phase 6 — Bazar Buddy category quick picks
- File: `flutter_app/lib/screens/life/bazar_buddy_screen.dart`.
- Per-category quick picks (Vegetables: Potato / Tomato / Onion / …; Fish:
  Hilsa / Rui / Katla / …). Tapping a quick pick prefills the bottom sheet.
- Validate `total = unit × quantity` (warn if mismatch, allow override).
- Mirror to `financial_transactions` only on `purchased && price > 0`
  (already enforced in `FinancialService.saveBazarItem`).
- Acceptance: each category has 3+ picks, validation runs, ledger
  integrity is unchanged.

### Phase 7 — Daily Expense: remove duplicate section
- File: `flutter_app/lib/screens/life/daily_expenses_screen.dart`.
- Drop the redundant "Today's Category" grid (already lives inside the
  bottom sheet). Keep Entries list + totals card + Add / Open Financial
  Dashboard buttons.
- `addDailyExpense / updateDailyExpense / deleteDailyExpense` semantics
  stay intact.
- Acceptance: no duplicate category picker.

### Phase 8 — Commute BD UI polish
- File: `flutter_app/lib/screens/life/commute_bd_screen.dart`.
- Map provider, routing API, fare engine all unchanged.
- Polish: map attribution, recenter button, transport options card
  density, error banners.
- `recordCommuteTrip / deleteCommuteTrip` unchanged.
- Acceptance: visuals feel native; no backend changes.

### Phase 9 — Dark mode pass
- Files: every screen under `flutter_app/lib/screens/**`.
- Replace hardcoded `EkColors.background/card/text/muted/line` and
  inline `Color(0xFF…)` with `Theme.of(context).colorScheme.*` or
  `EkColors.cardDark / textDark / mutedDark / lineDark`.
- Acceptance: `ThemeMode.dark` renders every screen without white
  flashes or unreadable text.

### Phase 10 — Language audit
- Files: every screen + widget under `flutter_app/lib/`.
- Every visible string must come from `EkLanguage.text(en, bn)` or be
  pure data (numbers, names). No mixed-script literals.
- Acceptance: toggling Bangla flips **all** strings, including in dialogs,
  SnackBars, banners, empty states, and error fallbacks.

### Phase 11 — Performance
- Files: every screen + widget.
- Add `const` where possible.
- Cache `FirestoreService.ownerStream` subscriptions in state fields.
- Dispose all `TextEditingController`, `Timer`, `MapController`.
- Avoid `setState` in `build`.
- Acceptance: `flutter analyze` clean; `flutter test` 19/19; scroll perf
  visibly smoother on the 4 main tabs.

### Phase 12 — Cleanup
- Remove dead code listed in §4 (model fields + the saving branch in
  `FinancialSummary.fromTransactions`).
- Remove the four cleanup candidate folders / files / build outputs.
- Update `.gitignore` to exclude `build/`, `.venv/`, `__pycache__/`.
- Remove unused imports flagged by `flutter analyze`.
- Acceptance: repo is smaller; `flutter analyze` still clean.

### Phase 13 — Security re-scan
- Re-run `_part4_secret_scan.py` + manual grep for `BEGIN PRIVATE KEY`,
  `sbp_`, `storePassword=`, `GOOGLE_API_KEY`, `OPENAI_API_KEY` over
  `flutter_app/lib`, `flutter_app/android/app/src/main`,
  `flutter_app/assets`, `backend/app`, `firebase`, `supabase/migrations`.
- Confirm 0 hits outside `firebase_options.dart`'s `AIzaSy…` string.
- Acceptance: identical to PART 5 result (0 new hits).

### Phase 14 — Final test sweep
- Frontend:
  - `flutter clean && flutter pub get`
  - `flutter analyze --no-fatal-warnings --no-fatal-infos` → 0 errors.
  - `flutter test` → 19 / 19 + any new tests added.
- Backend:
  - `pip install -r backend/requirements.txt`
  - `pytest -q` from `backend/` → 58 / 58 (or more if Phase 2 added tests).
  - `uvicorn app.main:app --reload` smoke.
- Acceptance: green across the board. PR description links to this
  report and lists every file changed.

---

## 7. Risk register

| Risk | Mitigation |
| --- | --- |
| Breaking the source ↔ financial_transactions mirror pattern | Phase 11 has a dedicated **ledger invariant check**: every write to a domain collection must be accompanied by a matching write to `financial_transactions` (verified by reading `financial_service.dart`). No phase is allowed to change cost formulas. |
| Breaking dark mode by introducing new inline colors | Phase 9 includes a grep audit before sign-off. New `Color(0xFF…)` literals require a code-review note. |
| Phases 3 / 4 accidentally changing navigation routes | All `Navigator.push` targets are existing routes — no new routes added. |
| Removing dead model fields breaks a transitive call | Phase 12 only deletes fields after grep over `lib/`, `test/`, and `backend/` confirms zero readers. |
| Splash regression during cleanup | `_BootRouter` and `GochanoSplashScreen` are off-limits. |

---

## 8. Out of scope

- Database migration (Firestore collections / schemas are frozen).
- API route changes (`/api/...` paths and request bodies are frozen).
- Adding new backend endpoints unless strictly required for a spec item.
- Material migration to a new design system.
- Switching off `pdfrx` / `flutter_map` / `geolocator`.
- Renaming the project (still Gochano / EkThikana).

---

## 9. Sign-off checklist (for after Phases 2–14 complete)

- [ ] All 14 phases done with per-phase acceptance criteria met.
- [ ] `flutter analyze` clean, `flutter test` green.
- [ ] Backend `pytest` green.
- [ ] Source ↔ `financial_transactions` mirror still intact.
- [ ] Dark mode visually verified on every screen.
- [ ] Language toggle visually verified on every screen.
- [ ] `git diff part5-pre-optimization-snapshot..HEAD` reviewed for unintended file moves.
- [ ] No new secrets introduced.

— End of Phase 1 report —
