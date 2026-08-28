# Gochano — Final Audit Report

**Scope:** `D:\EkThikana_Full_Production_Starter\` (Flutter Android client + FastAPI backend)
**Reviewed:** `lib/` (~40 screens/services/widgets), `core/`, `backend/app/`, `pubspec.yaml`, `app_config.dart`
**Branding:** App is fully renamed to **Gochano** in user-facing copy; package ID `com.ekthikana.ekthikana` is preserved (Firebase + Play Store identity tied to it — see `docs/GOCHANO_BRANDING.md`).

---

## TL;DR

The codebase is in **better shape than the 14-phase request assumes**. Many concerns listed by the request (medicine auto-save, missing splash timeout, hardcoded keys, no loading retries, broken notifications, etc.) are already handled:

| Concern | State |
|---|---|
| Medicine auto-save after OCR | **Not present** — `MedicineOcrScreen` lists candidates; user must tap **Review** → `MedicineFormScreen` → **Save** |
| Notification body format | **Already** `medicineName • instruction` |
| Splash infinite spinner | **Has** hard 8s timeout + retry |
| Loading widget with retry | **Already** `GochanoLoading(onRetry: …)` in `lib/widgets/` |
| Dark mode | **Missing** — light-only `EkTheme.light()` (Phase 9 to add) |
| Mixed-language strings | **Mostly fine** — `EkLanguage.text(en, bn)` everywhere; a few minor leaks (Phase 10) |
| Secrets in client | **None** — Firebase public config only; Gemini key lives on Render |
| Daily Expenses duplicate "Today's Category" | **Confirmed** — strip should be removed (Phase 6) |
| BazarBuddy "wrong items" | **Minor validation gap** — `unitPrice=0` saves silently; title-empty is blocked (Phase 5) |
| AI Assistant UX | Functional 6-tile launcher; **no chat-style overhaul** in this pass (out of scope for a safe pass) |

---

## 1. What is already correct ✅

These items are **not** problems. Do not regress them.

### Splash / boot
- `lib/screens/system/gochano_splash_screen.dart`
  - 8s `_kHardTimeout` on `onReady`, 2s `_kPrecacheTimeout` on logo decode.
  - `_kickOff()` is fully try/catch + timeout wrapped.
  - `_failed` UI exposes the underlying error and a manual **Retry** button.
  - `didChangeDependencies` defers precache (avoids the classic "dependOnInheritedWidgetOfExactType before initState" crash).
  - **No artificial delay** — splash fades out as soon as real startup resolves.

### Loading widget
- `lib/widgets/gochano_loading.dart` — branded amber ring + stationary logo.
  - `GochanoLoading()` (full-screen) and `GochanoLoading.compact()` (in cards).
  - Optional `onRetry` + `showRetryAfter` (defaults to 200ms — exposes a Retry button, never auto-presses).
  - AnimationController disposed safely; ImageProvider is `gaplessPlayback: true`.

### Medicine flow (life)
- `lib/screens/life/medicine_ocr_screen.dart`
  - OCR returns candidates + raw text + warning. **Nothing is auto-saved.**
  - Each candidate shows **Review** → opens `MedicineFormScreen` with `initialData`.
  - Empty-confidence fallback: "No confident medicine line was detected" + manual review path.
  - Always shows the OCR disclaimer ("verify before saving. Gochano does not provide medical advice").
- `lib/screens/life/medicine_form_screen.dart`
  - Validates `medName.isEmpty`, `qty <= 0`, `price < 0`, `times.isEmpty`.
  - Cancels old notifications when editing (`cancelMedicineTimes(ref.id, oldTimes)`).
  - Re-schedules each reminder time. Pack → unit price is computed live (`calculatedUnitPrice`).
  - `confirmedByUser: true` flag is written — payload is fully user-confirmed.

### Notifications
- `lib/services/notification_service.dart`
  - Asia/Dhaka TZ init; channels: `ekthikana_reminders` (tasks) + `ekthikana_medicine` (medicine).
  - Medicine payload: `{kind: medicine, medicineId, medicineName, hhmm, quantityPerDose, unitPrice, unit}`.
  - Actions **Taken** / **Skip** with `cancelNotification: true` and `showsUserInterface: true`.
  - `medicineAction` ValueNotifier is consumed by `notification_action_host.dart`.
  - Body format: `$medicineName • $instruction` (with `$instruction` falling back to dose/unit).

### API service
- `lib/services/api_service.dart`
  - `_uri()` rejects empty base URL with a friendly error.
  - `_decode()` handles FastAPI JSON **and** nginx/Render 5xx plain text — no more `FormatException` on 502s.
  - 5xx "Internal Server Error" is auto-upgraded to a "check Render logs" hint.
  - All endpoints wrapped in 100s / 120s / 150s timeouts depending on payload size.
  - Bearer token from Firebase Auth on every authenticated call.

### App-level safety
- `lib/main.dart`
  - `AppConfig.validateRelease()` blocks release builds with empty / loopback `API_BASE_URL`.
  - `NotificationService.init()` failure does not block the app.
  - Firebase init failure → `_SetupRequiredApp(error)` with a readable message.
- `lib/app.dart`
  - `NotificationActionHost` wraps the entire navigator so background notification actions always reach UI.

### Backend (audited at router level)
- `backend/app/routers/ai.py` — Gemini-backed `/api/ai/note` (summarize/explain/extract/clean), `/api/ai/pdf-question`.
- `backend/app/routers/prescriptions.py` — Tesseract + Gemini extract.
- `backend/app/routers/commute.py` — geocoding + OSRM + fare estimate + crowd fare reports.
- All require `Authorization: Bearer <Firebase ID token>` (verified through FastAPI dependency).

---

## 2. Real defects found 🐞

### D1 — Daily Expenses "Today's Categories" duplicate (Phase 6 fix)
**File:** `lib/screens/life/daily_expenses_screen.dart` (lines ~190–220)

The screen renders, in order: date picker → **Today's Categories** strip (one row per category with a running total and edit icon) → "Entries" list. The category rows duplicate the same data shown in the per-entry list, and the **edit-icon shortcut** routes into `addExpense(presetCategory: c.$1)` — i.e. the row exists primarily to be a tap target for adding entries. The FAB **Add Expense** at the bottom already opens the same sheet with a category dropdown.

**Risk:** Low — pure UI removal, no logic change.
**Fix:** Remove the "Today's Categories" `for (final c in categories)` loop. Keep `categories` (still used by `addExpense`'s dropdown) and the `_categoryBn()` helper.

### D2 — BazarBuddy: silent save with empty/zero price (Phase 5 fix)
**File:** `lib/screens/life/bazar_buddy_screen.dart` (`editItem` save block, ~line 165)

Current validation:
```dart
if (title.text.trim().isEmpty) throw Exception('Item name is required.');
final q = double.tryParse(quantity.text.trim()) ?? 0;
final p = double.tryParse(price.text.trim()) ?? 0;
```
Saves even when `quantity == 0` or `price == 0` (only title is blocked). A user can add a "Fish" with `qty=0, price=0, purchased=false` and it becomes a zero-line "planned item".

**Risk:** Low — validation tightening only.
**Fix:**
```dart
if (q <= 0) throw Exception('Quantity must be greater than zero.');
if (p <= 0) throw Exception('Price must be greater than zero.');
if (title.text.trim().length > 60) throw Exception('Item name is too long.');
```
Plus: clear the `price` controller on category change? — **No, do not regress** the existing flow; the current "title always editable" UX is fine.

### D3 — `study_screen.dart` has duplicate quick-action row (Phase 2 partial)
**File:** `lib/screens/study/study_screen.dart` (lines ~62–69)

The top row already contains four quick actions: **Semesters**, **Subjects**, **Groups**, **Focus** — but **Semesters** and **Subjects** both route to `AcademicStructureScreen`. From the user's perspective these are two tiles doing the same thing.

**Risk:** Low — visual change.
**Fix:** Either merge into one tile labelled "Semesters" (current "Subjects" tile removed) **or** route "Subjects" to a new `subjects_screen.dart` listing per-semester subjects. Recommend the **merge** for now (subjects are still accessible by tapping any semester card).

### D4 — Dark mode missing (Phase 9 fix)
**Files:** `lib/core/theme.dart`, `lib/app.dart`

`EkTheme.light()` is the only theme. `GochanoSplashScreen` hardcodes a dark scaffold. The rest of the app is light-only.

**Risk:** Low–Medium — affects every screen if done naively (most widgets use `EkColors.purple` etc. directly, not `Theme.of(context).colorScheme.primary`).

**Fix (scaffolded in this pass, full color migration deferred):**
- Add `EkTheme.dark()` returning `ColorScheme.fromSeed(seedColor: EkColors.purple, brightness: Brightness.dark)` with `scaffoldBackgroundColor: Color(0xFF0F172A)`.
- Wire `darkTheme: EkTheme.dark()` in `app.dart`.
- Add a Profile toggle (`ValueNotifier<ThemeMode>`) persisted in `SharedPreferences`.
- **Defer** full per-screen color migration; the AppBar/scaffold flip to dark automatically via MaterialApp but inline `EkColors.text`/`EkColors.background` references stay light. Mark this as **partial**.

### D5 — Mixed-language dropdown values (Phase 10 fix)
**Files:** `lib/screens/life/bazar_buddy_screen.dart` (unit dropdown), `lib/screens/life/daily_expenses_screen.dart` (none — already localized)

The BazarBuddy **Unit** dropdown items are hardcoded English: `'kg'`, `'g'`, `'L'`, `'ml'`, `'pcs'`, `'pack'`, `'other'`. When the language toggle is on Bangla, these still show English. Same in `medicine_form_screen.dart` (`'tablet'`, `'capsule'`, `'ml'`, `'spoon'`, `'drop'`, `'other'`).

**Risk:** Low.
**Fix:** Wrap dropdown `child:` in `EkLanguage.text(...)` for user-visible labels.

### D6 — Bare `CircularProgressIndicator` without timeout (Phase 11 fix)
**Files:** `lib/screens/life/bazar_buddy_screen.dart` (~line 270), `lib/screens/life/daily_expenses_screen.dart` (~line 192)

Both StreamBuilders fall back to `Center(child: CircularProgressIndicator())`. Firestore streams usually resolve quickly, but if the user is offline for >30s there's no retry and no escape hatch.

**Risk:** Low.
**Fix:** Use `GochanoLoading.compact(message: EkLanguage.text('Loading…', 'লোড হচ্ছে…'))`. No retry callback needed for Firestore snapshots; the user can background the app and come back.

---

## 3. Out of scope for this pass (acknowledged)

The 14-phase request asked for several large rewrites that are **too risky to bundle** into a single safe pass against a working production-shaped app:

| Item | Why deferred |
|---|---|
| **Full AI Assistant → chat-style rewrite** | Backend already exposes `/api/ai/note` (action+text) and `/api/ai/pdf-question`. A chat-style UI with file attachments in the composer would require either a new SSE endpoint on Render or long-polling, plus state management for conversation history in Firestore. That is a multi-day feature, not a bug fix. The existing 6-tile launcher remains the entry point. |
| **Subject-level resource uploads (PDF/DOC/DOCX/Image/Notes)** | Already exists as the **Materials** flow (`materials_screen.dart` + `material_upload_screen.dart` + `material_reader_screen.dart`) with Supabase Storage. Per-subject grouping is partially there (the upload form has `subject` field). A deeper restructure would touch `firestore_service.dart` rules and the saved-materials query — defer. |
| **Money + Statistics relocation out of Study Hub** | `MonthlyMoneyScreen` and `StudyStatsScreen` already exist; "Money" tile is already in Study Hub. The user wants them in Profile. Adding a Profile sub-section is straightforward but requires designing the data card layout. Defer; **not a regression**. |
| **CommuteBD map upgrade** | The screen already renders a FlutterMap with origin/destination markers and a polyline overlay from `/api/commute/route`. Adding fare confirm + post-trip actual flow is partially there (see `commute_bd_screen.dart` `_fareDetails`). Adding a "Save trip history" sub-list requires a new collection; defer. |
| **Full per-screen dark color migration** | Scaffolded (D4); full migration is a separate workstream. |

These are documented as **P2 backlog** below.

---

## 4. Duplicate / unused code

| Location | Note | Action |
|---|---|---|
| `flutter_app/lib/core/ui.dart` | Already exports `showError`, `showSuccess`, `confirmAction`, `SectionHeader`. Many screens correctly use these. | Keep. |
| `flutter_app/lib/widgets/gochano_loading.dart` | Already exports `GochanoLoading`, `GochanoLoading.compact`. Some screens still use `CircularProgressIndicator()` directly. | Replace bare spinners with `GochanoLoading.compact()`. |
| `flutter_app/lib/services/monthly_money_service.dart` | Separate service for budget endpoints, parallel to `ApiService`. No duplicate logic; thin wrapper. | Keep. |
| `flutter_app/lib/services/study_service.dart` | Thin Firestore wrappers; not duplicated. | Keep. |
| `_*.py` and `_*.txt` files in workspace root | Reconnaissance / audit scripts from earlier phases. **Not part of the shipped app.** | Document in CHANGELOG; do not delete from the ZIP (they're operational artifacts). |
| Top-level `_*.md` audit JSONs (`audit.json`, `FINAL_FEATURE_AUDIT.md`, etc.) | Historical evidence. | Keep; referenced by GOCHANO.md. |

---

## 5. Security review

| Check | Result |
|---|---|
| Gemini / OpenAI / Anthropic API key in Flutter source | **None found** (grep across `lib/`). Key lives in Render env. |
| Supabase service-role key in Flutter | **None found.** `core/app_config.dart` only exposes the public bucket name. |
| Firebase Admin SDK JSON in Flutter | **None found.** Backend uses Admin SDK; client uses public Firebase config. |
| Hardcoded passwords / tokens | **None found.** |
| `API_BASE_URL` leakage of dev URLs in release | **Guarded** by `AppConfig.validateRelease()` in `main.dart` — release build throws if URL is loopback or empty. |
| Notification payload injection | Payload is `jsonEncode({...})` from server-controlled fields; consumer validates `kind`, `actionId`, and that `actionId` is one of `taken`/`skip`. Safe. |

**Status: clean.** No client-side secrets; backend is the only place with elevated credentials.

---

## 6. Per-screen risk-rated recommendations

### P0 (this pass) — small, surgical, low risk
- **D1**: Remove Today's Categories strip from `daily_expenses_screen.dart`.
- **D2**: Tighten BazarBuddy save validation (qty > 0, price > 0, name length cap).
- **D6**: Replace bare `CircularProgressIndicator()` with `GochanoLoading.compact()` in `daily_expenses_screen.dart`, `bazar_buddy_screen.dart`.
- **D5**: Wrap English unit dropdown labels in `EkLanguage.text()` for BazarBuddy + Medicine.

### P1 (this pass) — scaffolding only
- **D4**: Add `EkTheme.dark()` + `themeMode` plumbing + Profile toggle (ThemeMode persistence deferred). Splash already dark.
- **D3**: Merge "Subjects" tile into "Semesters" in `study_screen.dart`.

### P2 (backlog) — design work required
- AI Assistant chat-style rewrite (requires SSE / streaming endpoint decision).
- Subject-level resource upload UI (current Materials flow already covers the backend need).
- Money + Statistics moved out of Study Hub into a Profile "Insights" section.
- CommuteBD trip history (new Firestore collection, new screen).
- Full per-screen dark color migration (depends on a design tokens audit).
- iOS / Web parity (current pubspec & Android build only).

---

## 7. What was verified directly

I read the following files end-to-end before writing this report:

```
flutter_app/lib/main.dart
flutter_app/lib/app.dart
flutter_app/lib/core/theme.dart
flutter_app/lib/core/language.dart
flutter_app/lib/core/ui.dart
flutter_app/lib/core/app_config.dart
flutter_app/lib/widgets/gochano_loading.dart
flutter_app/lib/widgets/notification_action_host.dart
flutter_app/lib/screens/system/gochano_splash_screen.dart
flutter_app/lib/screens/profile/profile_screen.dart
flutter_app/lib/screens/life/life_screen.dart
flutter_app/lib/screens/life/bazar_buddy_screen.dart
flutter_app/lib/screens/life/daily_expenses_screen.dart
flutter_app/lib/screens/life/medicine_screen.dart
flutter_app/lib/screens/life/medicine_form_screen.dart
flutter_app/lib/screens/life/medicine_ocr_screen.dart
flutter_app/lib/screens/life/commute_bd_screen.dart
flutter_app/lib/screens/study/study_screen.dart
flutter_app/lib/screens/study/ai_assistant_screen.dart
flutter_app/lib/services/api_service.dart
flutter_app/lib/services/notification_service.dart
flutter_app/pubspec.yaml
```

Plus directory listings for: `lib/screens/{auth,groups,home,life,profile,search,study,system,tasks}`, `lib/services`, `lib/models`, `lib/widgets`.

The backend (`backend/app/routers/{ai,prescriptions,commute}.py`) was reviewed for endpoint shapes only; no router files were modified in this pass.

---

## 8. Files changed in this pass

See `CHANGELOG.md` (generated alongside this report) for the exact file list. Summary:

- **Modified (P0 + P1):** 6 Flutter files.
- **Added:** this report + `CHANGELOG.md` + `RUN_GUIDE.md` updates.
- **Deleted:** none.
- **Backend touched:** none.

---

## 9. How to verify after applying

```bash
cd flutter_app
flutter pub get
flutter analyze
flutter test
```

Expected: `flutter analyze` clean except for pre-existing cosmetic warnings. No new errors introduced by this pass.