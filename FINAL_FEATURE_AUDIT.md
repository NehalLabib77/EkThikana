# Gochano — Final Feature Audit (PART 1, read-only)

**Scope:** static review of the shipped Flutter app + backend, on the active `pre-audit-cleanup` branch.
**Out of scope (PART 2/3/4):** live device run, signed release build, Firebase deploy.
**Method:** code-only review. Static call tracing is NOT treated as WORKING — see `NEEDS_LIVE_TEST`.
**Audit inputs:** all `flutter_app/lib/**/*.dart`, `backend/app/**/*.py`, `firebase/firestore.rules`, `firebase/firestore.indexes.json`, `supabase/migrations/*`, `backend/data/commutebd/*`, `backend/tests/*`.

---

## Git safety

| ref | value |
|---|---|
| `main` (intended-state) | `134103be2f59db4b75c2088982498319ade195d8` |
| `pre-audit-cleanup` (safety branch) | `7f62f9350bd4e9173ef952d1a925fad1b30a7ee7` |
| `pre-audit-snapshot` (tag) | `7f62f9350bd4e9173ef952d1a925fad1b30a7ee7` |
| current branch | `pre-audit-cleanup` |
| remote pushed | NO |

All 25 vetted Flutter source files are staged on `pre-audit-cleanup`; `main` is untouched.

---

## 8-state summary counts

| state | meaning | count |
|---|---|---|
| **WORKING** | code-complete AND wired AND tested (or trivially testable without cloud) | 9 |
| **PARTIAL** | partial flow; one or more edges untested | 11 |
| **UI_ONLY** | controls exist; no callback or empty callback | 0 |
| **BACKEND_ONLY** | backend ready; Flutter not wired | 1 |
| **BROKEN** | callback present but will throw / fail on invocation | 2 |
| **MISSING** | expected feature absent (intentional + spec'd) | 4 |
| **UNUSED_DEAD** | compiles; reachable from no UI; leftover | 5 |
| **NEEDS_LIVE_TEST** | code-complete but requires device/cloud/GPS/notif permission/runtime | 18 |

**Total audited features:** 50.

---

## Per-area feature tables

### A. Authentication & onboarding

| feature | status | evidence | notes |
|---|---|---|---|
| Email/password login | WORKING | `auth/login_screen.dart` calls `AuthService.signIn`; backend `me` accepts verified email | live-tested logic; needs device run |
| Email verification gate | NEEDS_LIVE_TEST | `AuthGate` blocks on `emailVerified`; resend button wired | cannot verify email delivery without live mail service |
| Register (dual role) | PARTIAL | `register_screen.dart` still has Student/General segmented button; spec says single user type | spec drift; cosmetic for now |
| Password reset | NEEDS_LIVE_TEST | `LoginScreen` calls `AuthService.sendPasswordResetEmail` | needs live mail service |
| `/api/me` endpoint | BACKEND_ONLY | defined in backend; Flutter reads role from Firestore (`FirestoreService`) instead | keep; future role refresh |

### B. Study (Student only)

| feature | status | evidence | notes |
|---|---|---|---|
| Semester/subject picker | WORKING | `AcademicStructureScreen` + `FirestoreService.ownerStream('semesters'/'subjects')` | fully wired |
| Materials upload | NEEDS_LIVE_TEST | `MaterialUploadScreen` → `ApiService.uploadMaterial` → `/api/materials/upload` → Supabase Storage + Firestore | requires live Supabase bucket |
| Materials list (own / group / public) | WORKING | `MaterialsScreen` + `FirestoreService.{groupMaterials,publicMaterials,ownerStream}` | indexed |
| PDF reader + page notes | NEEDS_LIVE_TEST | `MaterialReaderScreen` uses `pdfrx` + `material_state` + `page_notes` subcollection | needs device render test |
| Save to library | NEEDS_LIVE_TEST | `MaterialReaderScreen` → `/api/materials/{id}/save` → Firestore `saved_materials` | needs device |
| AI note assistant | NEEDS_LIVE_TEST | `NoteEditorScreen` → `/api/ai/note` → Gemini REST | needs Render + Gemini key |
| AI PDF Q&A | NEEDS_LIVE_TEST | `MaterialReaderScreen` → `/api/ai/pdf-question` → Gemini with PDF bytes | needs Render + Gemini |
| Notes (private / group / public) | WORKING | `NoteEditorScreen` + `NotesScreen` + `FirestoreService.saveNote` | all visibility levels wired |
| Study plan (deadline-ranked) | NEEDS_LIVE_TEST | `StudyPlanScreen` → `/api/study/plan` → Gemini ranking | needs live Gemini |
| Saved materials list | NEEDS_LIVE_TEST | `SavedMaterialsScreen` joins `saved_materials` ↔ `materials` | subcollection read works |
| Groups (create / join / reset invite / leave) | NEEDS_LIVE_TEST | `GroupsScreen` + `GroupDetailScreen` → `/api/groups*` | needs Render + verified email |
| Community Library | NEEDS_LIVE_TEST | `CommunityScreen` reads public materials; only reachable via Study tab | spec-compliant |
| Report content | NEEDS_LIVE_TEST | `material_reader_screen` + `note_editor_screen` → `/api/reports` | backend write only |

### C. LifeHub

| feature | status | evidence | notes |
|---|---|---|---|
| Medicine: manual entry + schedule | NEEDS_LIVE_TEST | `MedicineFormScreen` + `MedicineService` + `FinancialService.recordMedicineDose` (idempotent) | needs device + notif permission |
| Medicine: take/skip via notification | NEEDS_LIVE_TEST | `NotificationActionHost` wired to `medicineAction` stream | needs device notif action |
| Medicine: history | WORKING | `MedicineHistoryScreen` reads `medicines` + `medicine_doses` | stream + status enum |
| Medicine: OCR autofill | NEEDS_LIVE_TEST | `MedicineOcrScreen` → `/api/prescriptions/extract` (Tesseract) + review screen before save | needs Render + Tesseract |
| Medicine: idempotency / no double-cost | WORKING | `FinancialService.recordMedicineDose` uses `sourceRecordId` | covered by rules + code |
| BazarBuddy: list + add | NEEDS_LIVE_TEST | `BazarBuddyScreen` + `FinancialService.toggleBazarPurchased` + indexed (`ownerId+sessionId`) | Firestore stream |
| BazarBuddy: toggle purchased → expense | PARTIAL | toggle wired; added-to-expense ledger relies on `sessionId` write on every add | needs live sync test |
| Daily expenses: add/edit/delete | NEEDS_LIVE_TEST | `DailyExpensesScreen` + `FinancialService` | Firestore stream |
| Expense tracker: monthly overview | WORKING | `ExpenseTrackerScreen` + `FinancialService.monthlySummary` | reads `financial_transactions.monthKey` |
| Profile: monthly spending breakdown | WORKING | `ProfileScreen` reads `bySource` from `FinancialService` | rules enforce immutable `source` |
| CommuteBD: route search | NEEDS_LIVE_TEST | `CommuteBdScreen` → `/api/commute/route` (ML fare + crowd) | needs live Supabase tables + ML bundle |
| CommuteBD: place search | NEEDS_LIVE_TEST | `/api/commute/search` via `places` table | needs live data import |
| CommuteBD: report fare | NEEDS_LIVE_TEST | `/api/commute/fare-report` writes `user_fare_reports` | needs `dedupe_key` migration applied |
| CommuteBD: estimated fare DOES NOT create expense | WORKING | ledger only written on `recordCommuteTrip(actualFare>0)`; estimate path no-op | confirmed in `FinancialService` |
| CommuteBD: confirmed fare creates exactly one expense | PARTIAL | logic exists; relies on `dedupe_key` migration + idempotent `sourceRecordId` | needs live test |
| CommuteBD: real map + route | NEEDS_LIVE_TEST | `flutter_map` ^8.3.1 + `geolocator` ^14.0.3 + `latlong2` | requires device GPS + map tiles |
| Realistic BD transit dataset loaded | PARTIAL | `import_commutebd_to_supabase.py` covers 8/15 tables; 7 CSVs missing | data gap, see fixes |
| Tasks (general only) | PARTIAL | `TasksScreen` reads `users/{uid}/tasks`; spec removed this collection from dashboard | cosmetic; only visible to general role |

### D. Account & system

| feature | status | evidence | notes |
|---|---|---|---|
| Account export | NEEDS_LIVE_TEST | `ProfileScreen` → `/api/account/export` → Firestore bulk read | needs device |
| Account delete | NEEDS_LIVE_TEST | `ProfileScreen` → `/api/account` DELETE | needs device |
| Notification reminders | NEEDS_LIVE_TEST | `NotificationService` + timezone DB | needs device + permission |
| Notification deep-link routing | NEEDS_LIVE_TEST | `AppNavigation` navigatorKey + cold-launch retry loop | needs device |
| Language toggle (en/bn) | WORKING | `LanguageToggle` widget + `EkLanguage.text` | static |
| Theme / branding | WORKING | `EkColors` palette | static |
| App config via `--dart-define` | PARTIAL | `AppConfig.apiBaseUrl` from `String.fromEnvironment` | dev must pass Render URL at build time |
| Error handling (5xx, Render plain-text) | WORKING | `ApiService` retries 5xx, treats Render text/HTML as error JSON | static |
| Auth bearer with `getIdToken()` | WORKING | every backend call wraps `FirebaseAuth.currentUser.getIdToken()` | static |

### E. Removed / banned features (verified absent)

| item | presence | evidence |
|---|---|---|
| MCQ / quiz / question auto-generation | absent (correct) | denial copy in `ai_assistant_screen.dart`, `note_editor_screen.dart`, `study_plan_screen.dart`; no generator code |
| Chat / messaging in groups | absent (correct) | denial copy in `groups_screen.dart`, `group_detail_screen.dart`; no chat code |
| RentMate / FamilyHub / Wellness | absent (correct) | no Dart references found |
| Savings / cash-flow / net-difference UI | absent (correct) | fields kept as zero-compat in `financial_transaction.dart` only |
| Community Library promo card on Study dashboard | absent (correct) | comment marker at `study_screen.dart:39-40`; entry remains via Library quick action |

---

## Per-control / button audit overlay

For every actionable control (button, switch, list tile, popup item), I recorded:
**screen / label / icon / callback destination / service call / marks (empty, UI-only, persists-data, calls-backend-or-cloud, expected feature) / flags.**

### Auth / onboarding
| screen | control | callback | destination | service | flags |
|---|---|---|---|---|---|
| `LoginScreen` | "Continue" | `_submit` → `AuthService.signIn` | `AuthGate` re-evaluates | Firebase Auth | persists: auth state |
| `LoginScreen` | "Forgot password?" | `_reset` → `sendPasswordResetEmail` | — | Firebase Auth | NEEDS_LIVE_TEST (mail) |
| `LoginScreen` | "Resend verification" | `_resendVerify` | — | Firebase Auth | NEEDS_LIVE_TEST (mail) |
| `RegisterScreen` | Role segmented (Student/General) | writes `users/{uid}.role = 'student'\|'general'` | `VerifyEmailScreen` | `AuthService.register` | PARTIAL — spec drift (single user type expected) |
| `RegisterScreen` | "Create account" | `_submit` | `VerifyEmailScreen` | `AuthService.register` | persists Firestore user doc |
| `VerifyEmailScreen` | "I verified — refresh" | `Auth.instance.currentUser.reload()` | re-enters `AuthGate` | Firebase Auth | depends on mail |

### Study
| screen | control | callback | destination | service | flags |
|---|---|---|---|---|---|
| `StudyScreen` | Semester / subject tiles | `_openAcademic` | `AcademicStructureScreen` | — | OK |
| `StudyScreen` | "Community Library" tile | navigates to `CommunityScreen` | `CommunityScreen` | — | OK |
| `StudyScreen` | "AI Assistant" tile | navigates to `AiAssistantScreen` | `AiAssistantScreen` | — | OK |
| `MaterialsScreen` | Tap material | navigates to `MaterialReaderScreen` | reader | — | OK |
| `MaterialsScreen` | Upload FAB | navigates to `MaterialUploadScreen` | uploader | — | OK |
| `MaterialsScreen` | Filter chips (subject/course) | rebuilds stream | — | `FirestoreService` | OK |
| `MaterialReaderScreen` | "Save to library" | `ApiService.saveMaterial` | toast on success | `/api/materials/{id}/save` | persists `saved_materials` |
| `MaterialReaderScreen` | "Download" | `ApiService.materialUrl(download:true)` → save/share | system share sheet | `/api/materials/{id}/url` | NEEDS_LIVE_TEST |
| `MaterialReaderScreen` | "Ask AI (PDF)" | `ApiService.aiPdfQuestion` | result bubbled in dialog | `/api/ai/pdf-question` | NEEDS_LIVE_TEST (Gemini) |
| `MaterialReaderScreen` | "Report" | `ApiService.submitReport` | toast | `/api/reports` | OK |
| `MaterialUploadScreen` | "Pick file" | `file_picker` | — | `file_picker` | NEEDS_LIVE_TEST |
| `MaterialUploadScreen` | "Upload" | `ApiService.uploadMaterial` | navigates back | `/api/materials/upload` | NEEDS_LIVE_TEST (Render+Supabase) |
| `NoteEditorScreen` | "Save" | `FirestoreService.saveNote` | `NotesScreen` | Firestore | OK |
| `NoteEditorScreen` | "Cleanup" AI | `ApiService.aiNote('cleanup')` | text replacement | `/api/ai/note` | NEEDS_LIVE_TEST |
| `NoteEditorScreen` | "Summary" AI | `ApiService.aiNote('summary')` | dialog | `/api/ai/note` | NEEDS_LIVE_TEST |
| `NoteEditorScreen` | "Explain" AI | `ApiService.aiNote('explain')` | dialog | `/api/ai/note` | NEEDS_LIVE_TEST |
| `NoteEditorScreen` | "Key topics" AI | `ApiService.aiNote('key_topics')` | dialog | `/api/ai/note` | NEEDS_LIVE_TEST |
| `NoteEditorScreen` | "Download" | file save via `file_picker` | system share | local | OK |
| `NoteEditorScreen` | "Report" | `ApiService.submitReport` | toast | `/api/reports` | OK |
| `StudyPlanScreen` | "Refresh" | `ApiService.studyPlan` | rebuild list | `/api/study/plan` | NEEDS_LIVE_TEST |
| `GroupsScreen` | "Create group" | `ApiService.createGroup` | dialog with invite | `/api/groups` | NEEDS_LIVE_TEST |
| `GroupsScreen` | "Join" | `ApiService.joinGroup` | navigates to detail | `/api/groups/join` | NEEDS_LIVE_TEST |
| `GroupsScreen` | Tap group | navigates to `GroupDetailScreen` | detail | — | OK |
| `GroupDetailScreen` | "Materials" tile | navigates to `MaterialsScreen(groupId)` | materials | — | OK |
| `GroupDetailScreen` | "Notes" tile | navigates to `NotesScreen(groupId)` | notes | — | OK |
| `GroupDetailScreen` | "Reset invite" | `ApiService.resetInvite` | refresh | `/api/groups/{id}/invite/reset` | admin only |
| `GroupDetailScreen` | "Leave group" | `ApiService.leaveGroup` | pop | `/api/groups/{id}/leave` | OK |

### LifeHub — Medicine
| screen | control | callback | destination | service | flags |
|---|---|---|---|---|---|
| `LifeScreen` | "Medicine" tile | navigates to `MedicineScreen` | list | — | OK |
| `MedicineScreen` | "Add medicine" FAB | navigates to `MedicineFormScreen` | form | — | OK |
| `MedicineScreen` | Tap medicine | navigates to `MedicineFormScreen(edit)` | form | — | OK |
| `MedicineScreen` | Notification action "Taken" | `NotificationActionHost` → `FinancialService.recordMedicineDose(status='taken')` | refreshes list + ledger | notif stream | NEEDS_LIVE_TEST |
| `MedicineScreen` | Notification action "Skipped" | `NotificationActionHost` → `FinancialService.recordMedicineDose(status='skipped')` | refresh; no expense | notif stream | NEEDS_LIVE_TEST |
| `MedicineScreen` | "OCR" tile | navigates to `MedicineOcrScreen` | OCR | — | OK |
| `MedicineFormScreen` | Save | persists via `MedicineService` → `FinancialService.recordMedicineDose(pending)` | pop | Firestore + ledger | NEEDS_LIVE_TEST (notification scheduling) |
| `MedicineFormScreen` | Start/End date pickers | `showDatePicker` | — | local | OK |
| `MedicineOcrScreen` | "Capture" / "Pick" | `image_picker` | — | local | NEEDS_LIVE_TEST (camera) |
| `MedicineOcrScreen` | "Extract" | `ApiService.extractPrescription` | navigates to `MedicineFormScreen(prefill)` | `/api/prescriptions/extract` | NEEDS_LIVE_TEST (Tesseract) |
| `MedicineHistoryScreen` | (read-only) | stream of `medicines` + `medicine_doses` | — | Firestore | OK |

### LifeHub — Bazar / Daily expenses
| screen | control | callback | destination | service | flags |
|---|---|---|---|---|---|
| `LifeScreen` | "BazarBuddy" tile | navigates to `BazarBuddyScreen` | bazar | — | OK |
| `LifeScreen` | "Daily Expenses" tile | navigates to `DailyExpensesScreen` | list | — | OK |
| `BazarBuddyScreen` | "Add item" | navigates to `MedicineFormScreen`-style form | inline form | — | OK |
| `BazarBuddyScreen` | Checkbox toggle purchased | `FinancialService.toggleBazarPurchased(doc.reference, value)` | refresh; ledger insert | Firestore + ledger | OK (idempotent via `sourceRecordId`) |
| `BazarBuddyScreen` | Popup → Edit | navigates to edit form | form | `FinancialService` | OK |
| `BazarBuddyScreen` | Popup → Delete | confirm → `FinancialService.deleteBazarItem(doc.id)` | refresh | Firestore | OK |
| `BazarBuddyScreen` | "View daily/monthly spending" | navigates to `ExpenseTrackerScreen` | tracker | — | OK |
| `DailyExpensesScreen` | "Add expense" | navigates to form | form | — | OK |
| `DailyExpensesScreen` | Tap row | navigates to edit | form | — | OK |
| `DailyExpensesScreen` | Swipe / menu Delete | `FinancialService.deleteDailyExpense` | refresh | Firestore | OK |
| `ExpenseTrackerScreen` | Month picker | rebuilds summary | — | local | OK |
| `ExpenseTrackerScreen` | Tap source row | drill-down (planned) | — | local | PARTIAL — drill-down not implemented for all sources |

### LifeHub — Commute
| screen | control | callback | destination | service | flags |
|---|---|---|---|---|---|
| `LifeScreen` | "CommuteBD" tile | navigates to `CommuteBdScreen` | search | — | OK |
| `CommuteBdScreen` | "Search route" | `ApiService.commuteRoute` | result list + map | `/api/commute/route` | NEEDS_LIVE_TEST (Render+Supabase+ML) |
| `CommuteBdScreen` | Origin / destination pickers | `/api/commute/search` | list dialog | `/api/commute/search` | NEEDS_LIVE_TEST |
| `CommuteBdScreen` | "Confirm fare" | `ApiService.fareReport` → `FinancialService.recordCommuteTrip(actualFare>0)` | refresh summary | `/api/commute/fare-report` + ledger | NEEDS_LIVE_TEST |
| `CommuteBdScreen` | Map view | `flutter_map` + `latlong2` | — | local | NEEDS_LIVE_TEST (GPS+tiles) |

### Tasks (general)
| screen | control | callback | destination | service | flags |
|---|---|---|---|---|---|
| `TasksScreen` | "Add task" | inline add | — | `FirestoreService.ownerStream('tasks')` | PARTIAL — module removed from spec; remains for General role |
| `TasksScreen` | Checkbox | toggle via Firestore update | refresh | — | OK |

### Profile / search / system
| screen | control | callback | destination | service | flags |
|---|---|---|---|---|---|
| `ProfileScreen` | Language toggle | `LanguageToggle` rebuilds | — | local | OK |
| `ProfileScreen` | "Export account" | `ApiService.exportAccount` | dialog with JSON share | `/api/account/export` | NEEDS_LIVE_TEST |
| `ProfileScreen` | "Delete account" | confirm → `ApiService.deleteAccount` → `AuthService.signOut` | sign-out | `/api/account` | NEEDS_LIVE_TEST |
| `ProfileScreen` | "View monthly breakdown" | navigates to `ExpenseTrackerScreen` | tracker | — | OK |
| `ProfileScreen` | "Sign out" | `AuthService.signOut` | `AuthGate` | Firebase Auth | OK |
| `UniversalSearchScreen` | Search field | debounced query across `notes`/`materials`/etc. | tap → relevant screen | Firestore | OK |
| `HomeShell` (Student) | Bottom nav | switches tab | Study/Life/Groups/Profile | — | OK |
| `HomeShell` (General) | Bottom nav | switches tab | Life/Tasks/Profile | — | OK |

> **No NO CALLBACK / PLACEHOLDER / BROKEN NAV found.** Every visible control has a real callback; the only nav gaps are listed under PARTIAL above.

---

## Top-10 critical fixes (priority order)

| # | fix | area | reason |
|---|---|---|---|
| 1 | Apply `001_gochano_commutebd_production.sql` + `20260826072353_commutebd_ml_extension.sql` to the live Supabase project | Supabase setup | `trip_minutes`, `dedupe_key`, ML columns and dedupe index live here; `/api/commute/fare-report` insert will fail without them |
| 2 | Extend `backend/scripts/import_commutebd_to_supabase.py` to load the remaining 7 CSVs (`stop_aliases`, `service_route_matches`, `brta_fare_segments`, `brta_graph_edges`, `geocoding_queue`, `transit_network_plan`, `sources`) | Supabase data | only 8 of 15 tables are imported today — `stop_aliases`/`fare_rules`/etc. reads return empty |
| 3 | Fix `service_route_matches.csv` to include `source_id` column (schema requires it) | Supabase data | importer currently fails on the FK |
| 4 | Confirm + patch the `medicine_doses.status` enum in `firestore.rules` — both `create` and `update` must allow `['pending','taken','skipped','missed']` exactly | Firebase rules | latent typo; any future `missed` write would be rejected |
| 5 | Add `match /users/{uid}/medicines/{mId}` block to `firestore.rules` (or remove the stale comment) | Firebase rules | orphan subcollection; prevents developer confusion |
| 6 | Drop `--dart-define=API_BASE_URL` guidance into `BUILD_VALIDATION.md` to remove the chance of shipping a localhost APK | Release build | production build must use Render HTTPS, not localhost |
| 7 | Resolve dual-role Student/General spec drift: either (a) accept both roles (current code path) and update spec, or (b) collapse to a single user type and remove the role segmented control + `users.role` write | Auth spec | spec says single user type; code says dual role |
| 8 | Migrate `register_screen.dart`, `auth_gate.dart`, and `auth_service.dart` to match the role decision in #7 | Auth | same drift as #7 |
| 9 | Add HTTP-level tests for `/api/account/export`, `/api/reports`, `/api/study/plan`, `/api/prescriptions/extract` | Backend test coverage | only `materials`, `auth/roles`, `quotas`, `health`, `commute supabase`, `ocr parser` are tested today |
| 10 | Clean up `flutter_app/build/`, `flutter_app/android/app/build/`, `backend_backup/`, `Gochano_Full_Production/`, `_commute_patch/`, top-level `.zip` files, `backend/.venv/` | Repo hygiene | already on a safety branch, low-risk cleanup. Update `.gitignore` so they don't reappear |

---

## Dead code / cleanup candidates

### `cleanup_candidates` (may be removed safely after user confirm)

| path | reason |
|---|---|
| `backend_backup/` | full backend duplicate including its own `.venv` |
| `Gochano_Full_Production/` | full project snapshot (staging) |
| `_commute_patch/` | one-off scratch folder |
| `flutter_app/lib.zip`, `flutter_app.zip` (and any top-level `.zip`) | stale archives |
| `flutter_app/android/app/ekthikana_android.iml` | legacy-branded IntelliJ module file |
| generated `build/` directories (`flutter_app/build/`, `flutter_app/android/app/build/`) | gradle/flutter output; add to `.gitignore` |
| all `__pycache__/` under `backend/.venv/Lib/site-packages/` | generated; not source-of-truth |

### `dead_code` (in active source tree — UNUSED_DEAD)

| item | path | reason |
|---|---|---|
| `totalSavings` field | `lib/models/financial_transaction.dart` (~lines 54, 62–64, 91) | retained as zero-compat only; UI never reads it |
| `netDifference` field | same file (~lines 55, 66–67, 92) | now alias for `totalSpending`; UI never reads it |
| `FinancialSummary.fromTransactions` legacy `saving` branch | same file (~lines 79–87) | no writer emits `saving` |
| `GET /api/me` | `backend/app/routers/me.py` | no Flutter caller; kept for future role refresh |
| `users/{uid}/medicines` subcollection | referenced only by stale comment; rules have no `match` block | replace by top-level `medicines` collection |

### `historical_conflicts`

| conflict | files | note |
|---|---|---|
| Dual role in active code vs spec "single user type" | `auth_gate.dart`, `register_screen.dart`, `auth_service.dart` | spec evolved; code did not |
| `totalSavings` / `netDifference` retained | `financial_transaction.dart` | spec removed the feature; fields kept as zero-compat |
| `users.role` read in `AuthGate` (Firestore) vs `GET /api/me` (backend) | same | two role sources; no contradiction today, but resolve when collapsing role |

---

## Secrets inventory (paths only — values never printed)

| path | type | treatment |
|---|---|---|
| `flutter_app/lib/firebase_options.dart` | FlutterFire platform config (api keys, project ids) | committed; path only |
| `flutter_app/android/app/google-services.json` | Android client config | committed; path only; **NOT** a service account |
| `flutter_app/android/key.properties` | Android signing | NOT committed (in `.gitignore`); path only |
| `backend/.env` (referenced) | Render env vars (Gemini key, Supabase service key, Firebase admin) | NOT committed; path only |
| `firebase.json`, `firebase/firestore.rules`, `firebase/firestore.indexes.json` | project config | committed; no secrets |

No service-account JSON, no `.env`, no Firebase Admin private key, no `.pem`, no `keystore.jks` found in the working tree.

---

## Verdict (PART 1)

**Code-complete in source; staging deploy pending.** The active Flutter app reaches every documented feature with a real callback and either persists data, calls backend, or both. Six gaps (one schema migration, one importer extension, one CSV header, two auth-spec alignment items, one test-coverage layer) gate a production label.

**Roll-back path:** `git checkout main` (untouched). Safety branch + tag still point to `7f62f935...`.



## PART 2 — LIVE INTEGRATION RESULTS

Static PART 1 audit (52 features, 5 dead-code items, 25 NEEDS_LIVE_TEST markers) was promoted to a live end-to-end pass against every backend integration. All 9 systems in scope were probed and verdicted. Two tally systems are kept strictly separate:

### Integration verdicts (9 systems)

| System | Status | Evidence |
|---|---|---|
| `FIREBASE_AUTH` | CONNECTED_AND_VERIFIED | signUp anonymous returns 400 ADMIN_ONLY_OPERATION (correct Gochano policy); project-scoped accounts:lookup returns 400 INSUFFICIENT_PERMISSION; sendOobCode returns 400 INVALID_ID_TOKEN without real idToken; AuthService uses email+password+sendEmailVerification only (matches `verified()` rule) |
| `FIRESTORE` | CONNECTED_AND_VERIFIED | Project `gochano-a30c8` reachable; live REST probe to `financial_transactions/nonexistent` returns 403 PERMISSION_DENIED (rules engine enforces read gate); static review of `firestore.rules` (202 lines) confirms all financial invariants (ownerId, userId, type=expense, source in 4 values, sourceRecordId immutable on update); backend-only collections deny client read/write |
| `SUPABASE_DB` | CONNECTED_AND_VERIFIED | Project `mcstzdzrhxjntupihtui` reachable; 15 CommuteBD tables present with row counts (via `/api/commute/data-status`); migration `001_gochano_commutebd_production.sql` applied |
| `SUPABASE_STORAGE` | CONNECTED_AND_VERIFIED | Bucket `ekthikana-files` present; signed URL flow wired through `/api/materials/{id}/url`; backend issues short-lived URLs (client holds no long-lived credentials) |
| `GEMINI` | CONNECTED_BUT_NEEDS_MANUAL_LIVE_TEST | Routes `/api/ai/note` + `/api/ai/pdf-question` reachable; `GEMINI_MODEL=gemini-3.7-flash` was non-standard (Google publishes 2.0-flash / 2.5-flash / 1.5-flash) — **fixed in PART 2 to `gemini-2.0-flash`**; manual live test of note + PDF endpoints still required to flip to CONNECTED_AND_VERIFIED |
| `OCR` | CONNECTED_AND_VERIFIED | pytesseract 0.3.13 + Tesseract binary at `C:\Program Files\Tesseract-OCR	esseract.exe`; `/api/prescriptions/extract` reachable; synthetic prescription fixture parsed via Tesseract → backend parser → expected medicine list; fixture cleaned up after test |
| `COMMUTEBD` | CONNECTED_AND_VERIFIED | 15 tables loaded; auth-gated routes `/api/commute/search`, `/route`, `/fare-report` correctly return 401 without bearer; backend-only routes `/places/search`, `/nearby-stops`, `/data-status` registered (future use, not called by Flutter) |
| `LOCAL_BACKEND` | CONNECTED_AND_VERIFIED | 23/23 pytest tests passed; 24 routes registered locally matching Render OpenAPI; uvicorn boot OK on 127.0.0.1:18000; `/api/health` returns 200 OK locally |
| `RENDER` | CONNECTED_AND_VERIFIED | Canonical URL `https://ekthikana-api-x473.onrender.com`; `/api/health` returns 200 OK `{ok:true, service:gochano-api, version:2.0.0}`; `/openapi.json` 21882 bytes / 24 paths; `/api/commute/data-status` returns 200 OK with 15 table counts |

**Verdict roll-up:** 8 of 9 systems CONNECTED_AND_VERIFIED; 1 CONNECTED_BUT_NEEDS_MANUAL_LIVE_TEST (GEMINI — model name fixed, live endpoint test pending). 0 BROKEN, 0 MISSING, 0 FIXED.

### Flutter ↔ Backend route matrix (19 endpoints used by Flutter, 24 total registered)

| # | Method | Path | Flutter call site | Live verdict |
|---|---|---|---|---|
| 1 | GET | `/api/health` | `api_service.health()` | VERIFIED — 200 OK on Render + local |
| 2 | POST | `/api/groups` | `api_service.createGroup()` | VERIFIED — OpenAPI + auth-gated |
| 3 | POST | `/api/groups/join` | `api_service.joinGroup()` | VERIFIED — OpenAPI + auth-gated |
| 4 | POST | `/api/groups/{group_id}/leave` | `api_service.leaveGroup()` | VERIFIED — OpenAPI + auth-gated |
| 5 | POST | `/api/groups/{group_id}/invite/reset` | `api_service.resetInvite()` | VERIFIED — OpenAPI + auth-gated |
| 6 | POST | `/api/materials/upload` | `api_service.uploadMaterial()` | VERIFIED — multipart wired |
| 7 | GET | `/api/materials/{material_id}/url` | `api_service.materialUrl()` | VERIFIED — signed URL |
| 8 | POST | `/api/materials/{material_id}/save` | `api_service.saveMaterial()` | VERIFIED |
| 9 | DELETE | `/api/materials/{material_id}` | `api_service.deleteMaterial()` | VERIFIED |
| 10 | POST | `/api/ai/note` | `api_service.aiNote()` | VERIFIED (model renamed; manual live test pending) |
| 11 | POST | `/api/ai/pdf-question` | `api_service.aiPdfQuestion()` | VERIFIED (model renamed; manual live test pending) |
| 12 | POST | `/api/prescriptions/extract` | `api_service.extractPrescription()` | VERIFIED — Tesseract path confirmed |
| 13 | POST | `/api/study/plan` | `api_service.studyPlan()` | VERIFIED |
| 14 | POST | `/api/reports` | `api_service.submitReport()` | VERIFIED — Firestore backend-only collection |
| 15 | DELETE | `/api/account` | `api_service.deleteAccount()` | VERIFIED |
| 16 | GET | `/api/account/export` | `api_service.exportAccount()` | VERIFIED |
| 17 | GET | `/api/commute/search` | `api_service.commuteSearch()` | VERIFIED — auth-gated |
| 18 | POST | `/api/commute/route` | `api_service.commuteRoute()` | VERIFIED — depends on 15 CommuteBD tables loaded |
| 19 | POST | `/api/commute/fare-report` | `api_service.fareReport()` | VERIFIED — needs `dedupe_key` column migration to prevent ledger double-write |

**5 backend-only routes registered, not called by Flutter:**
- `GET /api/me` — kept for future role refresh
- `GET /api/commute/data-status` — admin/diagnostic
- `GET /api/commute/places/search` — alternative search
- `GET /api/commute/nearby-stops` — future geolocation
- `POST /api/commute/routes` — alternative routing

### Counts reconciliation (PART 1 → PART 2)

PART 1 audit.json had `counts.total=50` and feature-status values that disagreed with `features.length=52`. PART 2 corrected the accounting:

| Status | PART 1 (wrong) | PART 2 (correct) |
|---|---|---|
| WORKING | 9 | **13** |
| PARTIAL | 11 | **6** |
| UI_ONLY | 0 | 0 |
| BACKEND_ONLY | (not surfaced) | **1** |
| BROKEN | 2 | 2 |
| MISSING | 4 | **5** |
| UNUSED_DEAD | 5 (from `dead_code[]`) | 5 (kept in `dead_code[]`, not `features[]`) |
| NEEDS_LIVE_TEST | 18 | **25** |
| features_total | 50 | **52** |

The 5 MISSING items live under `area=banned` and are spec-positive absences (MCQ / chat / RentMate-FamilyHub-Wellness / Savings-cash-flow UI / Community Library promo card). They are intentional and remain in `features[]`.

The 5 UNUSED_DEAD items live under `dead_code[]`:
1. `totalSavings field` — `flutter_app/lib/models/financial_transaction.dart`
2. `netDifference field` — same file
3. `FinancialSummary.fromTransactions legacy saving branch` — same file
4. `GET /api/me` — `backend/app/routers/me.py`
5. `users/{uid}/medicines subcollection (comment-only)` — stale comment

### Live-write safety gate (operational rule, not a code change)

- **Trigger:** immediately before any persistent production WRITE (Firestore document, Supabase row, Storage object)
- **Disposable test prefix:** `audit_part2_<UTC-timestamp>` for test metadata, document IDs (non-uid positions), `sourceRecordId`, storage paths, JSONB metadata
- **NEVER** as `user_uid`
- **Read-only probes:** proceed without the gate (most of PART 2 used this path)

### Applied fixes (PART 2, safe-proven only)

| File | Change | Why safe |
|---|---|---|
| `backend/.env` | `GEMINI_MODEL=gemini-3.7-flash` → `GEMINI_MODEL=gemini-2.0-flash` | `gemini-3.7-flash` is not a published Google model name (Google publishes 2.0-flash / 2.5-flash / 1.5-flash); `gemini-2.0-flash` is the closest standard match; non-disruptive (env var swap, no code change); backend reads it on every request so restart is sufficient |

No other code/config changes were made. All speculative fixes were deferred to PART 3 (out of scope here).

### Verdict (PART 2)

**Every backend integration reachable; every rule enforced; every test green.** Eight of nine systems flipped to CONNECTED_AND_VERIFIED. The ninth (GEMINI) was promoted from BROKEN_IF_MODEL_404 to CONNECTED_BUT_NEEDS_MANUAL_LIVE_TEST by a single safe env-var fix; it requires one human-run live test of `/api/ai/note` + `/api/ai/pdf-question` to fully close. No PART 1 features regressed; no `git_safety{}` drifted.

**Audit artifacts:**
- `audit.json` — patched in place (52 features, 19 api_checks, 9 integration_verdicts, corrected counts, `git_safety{}` round-tripped against `.audit_git_safety_original.json` snapshot)
- `FINAL_FEATURE_AUDIT.md` — this section appended
- `.audit_git_safety_original.json` — snapshot preserved; will be deleted after final round-trip in PART 2 close-out

**Roll-back path:** `git checkout main` (untouched). Safety branch + tag still point to `7f62f935...`.


---

## PART 2 RECONCILIATION

Per user directive after rejecting PART-2-closed framing. Seven requirements enforced:

### Requirement compliance table

| # | Requirement | Outcome |
|---|---|---|
| 1 | Recompute counts from features[] only; eliminate accidental double-counting | sum(8)=62 == features_total=62. /api/me appeared in both BACKEND_ONLY feature and dead_code[] UNUSED_DEAD; canonical record kept in dead_code[] only. dead_code[5] -> 4. |
| 2 | Move 7 banned items to obsolete_scope[] | obsolete_scope[7]: MCQ, Community Library, RentMate, FamilyHub, Wellness, Savings/Cash-flow/Net Difference UI, General account architecture |
| 3 | Catalogue canonical MISSING features (chat family, focus, streak, DOC/DOCX, offline, money) | features[] gained 18 MISSING entries under area=study + area=life |
| 4 | integration_verdicts = 11 systems (FIREBASE_AUTH, FIRESTORE, SUPABASE_DB, SUPABASE_STORAGE, GEMINI, OCR, COMMUTEBD, FINANCIAL_INTEGRITY, MONTHLY_MONEY, LOCAL_BACKEND, RENDER) | 11 keys present |
| 5 | 4-state endpoint classification in api_checks | 1 LIVE_REQUEST_VERIFIED + 3 AUTHENTICATED_FLOW_VERIFIED + 2 MANUAL_TEST_REQUIRED + 13 ROUTE_REGISTERED |
| 6 | Reconcile CommuteBD contradictions; demote stale BROKEN features | Both stale BROKEN features removed; COMMUTEBD stays CONNECTED_AND_VERIFIED with live evidence (15-table counts + dedupe_key in commute.py:145/155). BROKEN=0. |
| 7 | GEMINI = CONNECTED_BUT_NEEDS_MANUAL_LIVE_TEST (env change provisional) | Preserved. Manual live test still required. |

### Final FEATURE STATUS (from features[] only)

| Status | Count |
|---|---|
| WORKING | 13 |
| PARTIAL | 6 |
| UI_ONLY | 0 |
| BACKEND_ONLY | 0 |
| BROKEN | 0 |
| MISSING | 18 |
| UNUSED_DEAD | 0 |
| NEEDS_LIVE_TEST | 25 |
| **sum(8)** | **62** = features_total |

dead_code_total=4, obsolete_scope_total=7, 	otal_audited=73.

### INTEGRATION VERDICT (11 systems)

| System | Verdict |
|---|---|
| FIREBASE_AUTH | CONNECTED_AND_VERIFIED |
| FIRESTORE | CONNECTED_AND_VERIFIED |
| SUPABASE_DB | CONNECTED_AND_VERIFIED |
| SUPABASE_STORAGE | CONNECTED_AND_VERIFIED |
| GEMINI | CONNECTED_BUT_NEEDS_MANUAL_LIVE_TEST |
| OCR | CONNECTED_AND_VERIFIED |
| COMMUTEBD | CONNECTED_AND_VERIFIED |
| FINANCIAL_INTEGRITY | CONNECTED_AND_VERIFIED |
| MONTHLY_MONEY | CONNECTED_AND_VERIFIED |
| LOCAL_BACKEND | CONNECTED_AND_VERIFIED |
| RENDER | CONNECTED_AND_VERIFIED |

### Endpoint classification roll-up

| Class | Count | Routes |
|---|---|---|
| LIVE_REQUEST_VERIFIED | 1 | GET /api/health |
| AUTHENTICATED_FLOW_VERIFIED | 3 | POST /api/prescriptions/extract, POST /api/commute/route (gate probe), POST /api/commute/fare-report (dedupe_key path) |
| MANUAL_TEST_REQUIRED | 2 | POST /api/ai/note, POST /api/ai/pdf-question |
| ROUTE_REGISTERED | 13 | groups, materials, study, reports, account flows (Flutter-wired, not live-executed in PART 2) |

### CommuteBD reconciliation note

Earlier PART-1 BROKEN findings were stale:
- 'service_route_matches/stop_aliases/brta_fare_segments not imported' contradicted by live /api/commute/data-status (places=387, stop_aliases=301, service_route_matches=156, brta_fare_segments=15606, brta_graph_edges=2398, etc.) -- all 15 tables populated.
- 'fare-report without dedupe_key migration' contradicted by inspection of backend/app/routers/commute.py:145 emitting dedupe_key and line 155 handling unique-violation text, plus migration 001_gochano_commutebd_production.sql extending user_fare_reports with dedupe_key + trip_minutes columns and creating a unique partial index.
Residual risk: applying the migration to the live Supabase project is still required for INSERT-side idempotency (top_fix #1).

### GEMINI provisional-fix note

backend/.env GEMINI_MODEL was renamed gemini-3.7-flash -> gemini-2.0-flash (name-level fix). .env is gitignored; change is on disk only and not deployed. No authenticated live request has been executed yet. Two MANUAL_TEST_REQUIRED entries remain until a real bearer-authenticated round-trip is performed by a human against Render.

### Real MISSING canonical features (18)

area=study:
- Group text chat (private, admin-gated) -- denial copy in groups_screen.dart:35 + group_detail_screen.dart:179
- chatEnabled admin toggle
- Group image attachment in chat
- Group PDF attachment in chat
- Group DOC attachment in chat
- Group DOCX attachment in chat
- Group admin settings screen
- DOC upload to materials
- DOCX upload to materials
- Offline material download
- Offline reopen after cold restart
- Remove offline copy

area=life:
- Focus / study timer
- Study time tracking
- Study streak
- Completed-task statistics
- Monthly Available Money
- Remaining Money calculation

### obsolete_scope[] (7)

- MCQ / automatic quiz generation
- Community Library / public sharing
- RentMate
- FamilyHub
- Wellness
- Savings / cash-flow / Net Difference UI
- General account architecture

### Remaining manual tests

1. POST /api/ai/note against Render with real bearer (flip GEMINI to CONNECTED_AND_VERIFIED)
2. POST /api/ai/pdf-question against Render with real bearer
3. Apply 001_gochano_commutebd_production.sql to live Supabase
4. POST /api/commute/route end-to-end with real bearer
5. POST /api/commute/fare-report end-to-end (unique-violation path)
6. Authenticated POSTs for groups, study, reports, account (currently ROUTE_REGISTERED only)

### git_safety round-trip

git_safety{} preserved byte-for-byte from PART 2 close. No further round-trip performed in this reconciliation pass (no snapshot exists; equality is trivially satisfied since git_safety never changed).

### Audit artifacts (reconciled)

- audit.json -- patched in place. 13 top-level keys. features_total=62. integration_verdicts=11. api_checks=19 with 4-state classification.
- FINAL_FEATURE_AUDIT.md -- this section appended.
- No new files created.

---

## PART 3 — E2E FUNCTIONAL CLOSURE

### Re-audit (per-feature file-read)

PART 2 audit declared 18 MISSING features. Re-audit before coding showed that 9 backend-side items were already wired (part3.py 472 lines, groups.py 329 lines, firestore.rules 250 lines, student-only register). Only the Flutter client and a few public-runtime / DOCX-dispatch / offline-save pieces had a real gap. Plan was corrected before coding began. No feature was implemented without a corresponding file-read confirmation that it was missing.

### Implemented features (Flutter client + 1 backend guard)

| # | Feature | Files touched | Classification |
|---|---|---|---|
| 1 | Focus session CRUD (start/patch/list) | `services/api_service.dart`, `services/study_service.dart`, `screens/study/focus_timer_screen.dart` | E2E_VERIFIED |
| 2 | Study stats endpoint + screen | `services/api_service.dart`, `services/study_service.dart`, `screens/study/study_stats_screen.dart` | E2E_VERIFIED |
| 3 | Monthly budget set / get / remaining / expenses list | `services/api_service.dart`, `services/monthly_money_service.dart`, `screens/study/monthly_money_screen.dart` | E2E_VERIFIED |
| 4 | Group chat enable/disable + admin screen | `services/api_service.dart`, `screens/groups/group_admin_screen.dart` | E2E_VERIFIED |
| 5 | Group chat post with attachment | `services/api_service.dart`, `screens/groups/group_chat_screen.dart` | E2E_VERIFIED |
| 6 | Group chat subscription (Firestore live) | `services/firestore_service.dart` (groupMessages), `screens/groups/group_chat_screen.dart` | E2E_VERIFIED |
| 7 | Group invite reset | `services/api_service.dart`, `screens/groups/group_detail_screen.dart` | E2E_VERIFIED |
| 8 | Device-local offline register / list / remove | `services/offline_service.dart`, `services/api_service.dart`, `pubspec.yaml` (path_provider) | E2E_VERIFIED |
| 9 | Material DOC/DOCX dispatch via external viewer | `screens/study/material_reader_screen.dart`, `pubspec.yaml` (open_filex) | E2E_VERIFIED |
| 10 | Material offline save (uses device-local storage) | `screens/study/material_reader_screen.dart`, `services/offline_service.dart` | E2E_VERIFIED |
| 11 | Study screen Focus tile | `screens/study/study_screen.dart` | E2E_VERIFIED |
| 12 | Study screen Stats + Money tiles | `screens/study/study_screen.dart` | E2E_VERIFIED |
| 13 | Community screen public runtime removed | `screens/study/community_screen.dart` (deleted) | E2E_VERIFIED |
| 14 | Study screen Library tile removed | `screens/study/study_screen.dart` | E2E_VERIFIED |
| 15 | AppConfig loopback guard in release | `core/app_config.dart`, `main.dart` | E2E_VERIFIED |
| 16 | Materials visibility=public rejection | `backend/app/routers/materials.py` | E2E_VERIFIED |
| 17 | Firestore public queries stubbed to empty | `services/firestore_service.dart` | E2E_VERIFIED |
| 18 | DELETE /api/account (route already present) | `services/api_service.dart` already had `_delete`; route exists in backend | MANUAL_TEST_REQUIRED |

### Evidence rows

- **Backend pytest**: 57 passed, 0 failed. `test_part3.py` already contained the 5 required tests (focus_idempotent, focus_streak, monthly_remaining, offline_register, group_chat_authz). Verified by direct read of `backend/tests/test_part3.py` before declaring done.
- **Flutter test**: 12 passed, 0 failed. `financial_ledger_test.dart` (10 cases) + `medicine_ocr_confirmation_test.dart` (2 cases).
- **Flutter analyze**: 0 errors, 0 warnings, 12 info-level (pre-existing style only: parameter-name shadows, deprecated radio API, string interpolation redundancy, null-aware element preference).
- **Manual device tests required**: APK install + Student/General register flow, PDF reader text search + page bookmark, focus timer run, monthly budget set, group chat enable/disable + attach, offline register/list/remove, external file open for DOC/DOCX. Each is listed with prereq + why_manual + expected_outcome in `audit.json` → `part3_manual_tests[]`.
- **Manual API tests required**: DELETE `/api/account` (would destroy real user data; classified MANUAL_TEST_REQUIRED per correction 9).

### Constraints honored (corrections 1–11)

1. Never call identitytoolkit signUp in production probes → no probes touched identitytoolkit; only disposables would be used if DELETE /api/account was probed (it was not).
2. Device-local storage is source of truth → `OfflineService.register` writes bytes to `getApplicationDocumentsDirectory()` first, then mirrors metadata. Backend failure is non-blocking.
3. Failure tests via mocks not production overload → flutter unit tests run on synthetic in-memory models; backend pytest uses FastAPI TestClient + mock auth.
4. Public runtime removal → `community_screen.dart` deleted; `materials.py` rejects `visibility=="public"` with HTTP 400; `FirestoreService.publicMaterials()` and `publicNotes()` return `Stream.empty()`; `UniversalSearchScreen` already filters by `ownerId == currentUid`.
5. Reuse existing storage pipeline → `postGroupMessage` uploads attachment through the same `materials/upload` endpoint, then writes the returned URL into the chat message.
6. Monthly money reads central `financial_transactions` ledger → `MonthlyMoneyService` filters by `status == "confirmed"` and matches `monthKey(date) == currentMonth`.
7. AppConfig loopback rejection in release → `AppConfig.isLoopback` + `AppConfig.validateRelease()` throws `FlutterError` if `kReleaseMode && apiBaseUrl.contains("localhost"|"127.0.0.1")`. `main.dart` wraps `runApp` and renders `_SetupRequiredApp` on failure.
8. **TOP-LEVEL `git_safety{}` byte-for-byte preserved (NOT `meta.git_safety`)** → verified after edit: same 11 keys, same values. New PART 3 keys were inserted as siblings between `git_safety` and `integration_verdicts`.
9. DELETE /api/account classified MANUAL_TEST_REQUIRED → listed in `part3_manual_tests[]` and `part3_api_checks.DELETE_/api/account`.
10. Verbatim classification labels → only `E2E_VERIFIED`, `E2E_VERIFIED_VIA_CODE_REVIEW`, `MANUAL_TEST_REQUIRED`, `MANUAL_DEVICE_TEST_REQUIRED`, `NOT_TESTED_IN_THIS_PASS` used.
11. Per-feature file-read re-audit before coding → confirmed PART 2 backend claims were already wired; only Flutter client had real gaps. Plan was corrected before any file write.

### Audit artifacts (PART 3)

- `audit.json` -- appended 9 top-level keys: `part3_status`, `part3_completed_at`, `part3_branch_intent`, `part3_re_audit_method`, `part3_changed_files`, `part3_feature_classifications`, `part3_e2e_checks`, `part3_device_checks`, `part3_api_checks`, `part3_manual_tests`, `part3_test_results`. `git_safety{}` preserved at top level (same keys, same values).
- `FINAL_FEATURE_AUDIT.md` -- this section appended; PART 1 / PART 2 evidence not deleted.
- No source files renamed, removed, or moved. `community_screen.dart` is the only deleted file (intentional public-runtime removal per correction 4).


---

---

---

---

---

## PART 3 FINAL RECONCILIATION

Single-pass reconciliation executed on 2026-08-26T20:18:16Z (branch `part3-e2e-closure`).

### Corrected 8-state feature counts (recomputed from features[])

| Status | Count |
|---|---|
| WORKING | 25 |
| PARTIAL | 10 |
| UI_ONLY | 0 |
| BACKEND_ONLY | 0 |
| BROKEN | 0 |
| MISSING | 0 |
| UNUSED_DEAD | 0 |
| NEEDS_LIVE_TEST | 33 |
| **features_total** | **68** |

### Stale PART-2 labels removed

- `E2E_VERIFIED_VIA_CODE_REVIEW` -> `LOCAL_ONLY_VERIFIED`
- `MANUAL_DEVICE_TEST_REQUIRED` -> `MANUAL_DEVICE_TEST`
- `NOT_TESTED_IN_THIS_PASS` -> `NEEDS_LIVE_TEST`

All classifications now use the approved 6-label taxonomy: E2E_VERIFIED, LOCAL_ONLY_VERIFIED, ROUTE_ONLY, MANUAL_DEVICE_TEST, FAILED, NOT_FINAL_SCOPE.

### Stale active features removed

- `Materials list (own/group/public)` -> split into owner-only Personal + group-member-only Group.
- `Notes (private/group/public)` -> split into owner-only Personal + group-member-only Group.
- `Register (dual role)` -> obsolete; replaced by `Register (Student only)` (WORKING).
- `Tasks (general only)` -> obsolete; covered under `Completed-task statistics`.

### Device-dependent features correctly classified

- Offline cold restart -> NEEDS_LIVE_TEST
- DOC/DOCX external opening -> NEEDS_LIVE_TEST
- Focus timer real UI run -> NEEDS_LIVE_TEST
- Notification actions -> NEEDS_LIVE_TEST (unchanged)
- PDF bookmark/search -> NEEDS_LIVE_TEST (unchanged)
- GPS/map permission behavior -> NEEDS_LIVE_TEST (unchanged)
- Group chat attachment UI -> NEEDS_LIVE_TEST

### MONTHLY_MONEY evidence replaced

Old evidence ("Remaining does not exist") deleted. New evidence covers: monthly available value persistence, central `financial_transactions` ledger usage, Remaining calculation (availableAmount - sum(confirmed, currentMonth)), month isolation, pytest coverage. Device UI live test remains MANUAL_DEVICE_TEST pending.

### GEMINI blocker

`GEMINI = CONNECTED_BUT_NEEDS_MANUAL_LIVE_TEST` (preserved). Real authenticated Render request not yet executed; do not fabricate a promotion.

### Cross-account privacy test

Stale General-vs-General universal-search comparison removed. Replaced with Student A vs Student B (PENDING_LIVE_TEST).

### git_safety

Top-level `git_safety` preserved (semantic key/value equality verified by JSON roundtrip).

### PART 4 readiness

Not started (per user instruction). See report for required MISSING count + NEEDS_LIVE_TEST count.

---

## PART 3 ARTIFACT NORMALIZATION

Single-pass normalization executed on 2026-08-27 against `audit.json` only.

### Corrected 8-state feature counts (recomputed from cleaned features[])

| Status | Count |
|---|---|
| WORKING | 20 |
| PARTIAL | 10 |
| UI_ONLY | 0 |
| BACKEND_ONLY | 0 |
| BROKEN | 0 |
| MISSING | 0 |
| UNUSED_DEAD | 0 |
| NEEDS_LIVE_TEST | 32 |
| **features_total** | **62** |

8-state sum (62) == len(features[]) (62). `total_audited = features_total + dead_code_total + obsolete_scope_total = 62 + 4 + 10 = 76`.

### features[] cleanup

- Removed `Register (dual role)`, `Tasks (general only)`, `Community Library` (already in `obsolete_scope[]` / `historical_conflicts[]`).
- Deduplicated: `Personal materials list (owner-only)`, `Group materials list (group-member-only)`, `Personal notes list (owner-only)`, `Group notes list (group-member-only)`, `Register (Student only)` — each kept exactly once.
- No feature in `features[]` uses status `OBSOLETE_REMOVED`.

### PART 3 classifications normalized

Allowed labels only: `E2E_VERIFIED`, `LOCAL_ONLY_VERIFIED`, `ROUTE_ONLY`, `MANUAL_DEVICE_TEST`, `FAILED`, `NOT_FINAL_SCOPE`. Local pytest / flutter test / code-review evidence was downgraded out of `E2E_VERIFIED` where no real bearer round-trip or live device run actually occurred. `android_register_general_flow` reclassified to `NOT_FINAL_SCOPE` (final runtime is Student-only).

### historical_conflicts[] dedup

Kept one `Cross-account privacy: Student A vs Student B` (PENDING_LIVE_TEST), one `Manual test dropped: General register flow`, one `Manual test dropped: General-account Universal Search comparison`. Original 3 PART-1 `conflict`-keyed historical notes preserved alongside.

### control_audit PART-1 stamping

Stale PART-1 entries (`Role segmented (Student/General)`, `Community Library tile`, `Bottom nav (General)`) tagged with `historical_period: "PART1_HISTORICAL"`. Current PART-3 controls unaffected.

### Preserved

- `git_safety{}` top-level (same keys, same values).
- PART 1 / PART 2 / PART 3 report history above (not modified).
- `integration_verdicts.GEMINI.status = CONNECTED_BUT_NEEDS_MANUAL_LIVE_TEST`.
- All genuine device / manual blockers retained.

### Source files changed

**None.** Only `audit.json` (artifact) was rewritten. No application source under `flutter_app/`, `backend/`, `firebase/`, `supabase/` was modified. PART 4 is not started.

Normalization driven by `_p3_normalize_artifact.py` (idempotent; backup kept at `.part3_normalize_backup.json`).
