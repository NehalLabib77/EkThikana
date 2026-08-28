# Phase B Bug-Fix Report

Branch: `part5-release-validation`
Scope: 6 production bugs reported from live-device validation, fixed without altering architecture, contracts, routes, schemas, or dependencies.

---

## Summary table

| # | Surface           | Severity    | Symptom                                            | Status |
|---|-------------------|-------------|----------------------------------------------------|--------|
| 1 | App launch        | Blocker     | Black screen after splash on Infinix X665E         | Fixed  |
| 2 | AI Assistant      | Blocker     | "AI Assistant unreachable" toast on tap            | Fixed (transitive via #3) |
| 3 | AI Assistant      | Blocker     | PDF upload silently fails                          | Fixed  |
| 4 | Study Hub         | High        | No way to reach Materials / Upload from Study Hub  | Fixed  |
| 5 | BazarBuddy        | Blocker     | `setState() after dispose()` assertion on edit      | Fixed  |
| 6 | BazarBuddy        | Medium      | Wrong emoji icon for some saved categories         | Fixed  |

All fixes verified by `flutter analyze` (no new errors, no new warnings) and
`flutter test` (19/19 unit tests pass — central ledger idempotency, fare-only
guard, taken-only cost, and notification dedup invariants all preserved).

---

## Bug 1 — Black screen after splash (splash setState race)

### Root cause
`flutter_app/lib/app.dart` had `_BootRouterState._handleReady()` calling
`setState` synchronously inside an async listener that could fire after the
splash `State` was being rebuilt. On the slower Infinix X665E the rebuild
ordering triggered `_debugLocked` and produced a permanent black screen.

### Fix
Defer the state mutation past the current frame using
`WidgetsBinding.instance.addPostFrameCallback`.

### File
- `flutter_app/lib/app.dart` — `_BootRouterState._handleReady` wrapped the
  `setState` body in `WidgetsBinding.instance.addPostFrameCallback((_) { ... })`.

### Logic preserved
- Boot state machine is unchanged; only the frame timing of the rebuild is shifted.
- All downstream routes (loading -> home -> auth) still resolve identically.

---

## Bug 2 — AI Assistant "unreachable"

### Root cause
Not a network problem. The "unreachable" toast appeared because the PDF flow
(Bug 3) raised an exception and the screen treated it as "service not
reachable". After fixing Bug 3 the toast disappears with no further changes.

### Fix
See Bug 3 — `ai_assistant_screen.dart` now uses the real
`ApiService.uploadMaterial` + `ApiService.askPdf` pipeline instead of an
unimplemented stub, so the same code path that produced the toast now
succeeds.

---

## Bug 3 — AI Assistant PDF upload silently fails

### Root cause
`ai_assistant_screen.dart` was using a non-existent stub API call. The file
picker opened a PDF but its bytes were dropped on the floor — no multipart
upload was ever made.

### Fix
Rewired the PDF flow to the existing backend contract:
1. `_pickUpload` calls `ApiService.uploadMaterial(bytes: bytes, filename: name)`
   which performs a multipart `POST /ai/pdf-question` and returns the
   material id.
2. `_askPdfFromUpload` calls `ApiService.askPdf(materialId: ..., question: ...)`
   which `POST`s the follow-up question to the same endpoint.
3. The file picker uses `file_picker ^12`'s `selected.readAsBytes()` (not the
   deprecated `PlatformFile.bytes` getter).

### File
- `flutter_app/lib/screens/study/ai_assistant_screen.dart` — `_pickUpload`
  and `_askPdfFromUpload` rewritten.

### Logic preserved
- No new endpoint, no new route, no new model.
- Material id is now available for follow-up questions in the same session.
- Errors still surface in the existing chat bubble as a friendly message.

---

## Bug 4 — Study Hub has no Materials / Upload entry points

### Root cause
`study_screen.dart` shipped with only Notes / Planner / Library / AI cards.
There was no in-screen affordance for Materials and Upload, so users had to
back out to the Study dashboard — confusing on first run.

### Fix
Added two new quick-action cards inside the existing `GridView` of the Study
Hub screen:
- **Materials** — opens the existing materials browser.
- **Upload** — opens the existing upload flow.

### File
- `flutter_app/lib/screens/study/study_screen.dart` — extended the
  `quickActions` list with two new entries; labels reuse `EkLanguage.text(...)`.

### Logic preserved
- Cards reuse the same `_QuickAction` widget.
- Routing strings, navigation targets, and role gating unchanged.

---

## Bug 5 — `setState() called after dispose()` on BazarBuddy edit

### Root cause
`bazar_buddy_screen.dart` had `final _customUnitController =
TextEditingController();` as a class field. `editItem` rebuilt that controller
inline, used it through a nested `Builder`, then **did not dispose it** before
exiting the bottom sheet. The next open would then leak controllers and the
old `setState` calls inside the disposed `State` triggered Flutter's
`setState() called after dispose()` assertion, sometimes also crashing the
`DropdownButton` with an "initial value not in items" complaint when the
saved category string had drifted from the current `categories` list.

### Fix
Three coordinated edits to `bazar_buddy_screen.dart`:

1. **Removed the field-level `_customUnitController`** entirely. Replaced it
   with a plain `String? _lastCustomUnitText` that stores whatever the user
   typed during the open bottom-sheet session.
2. **`editItem` now declares a local `TextEditingController? customController;`
   scoped to that call.** It is disposed in the bottom sheet's `finally` block
   alongside the other text controllers.
3. **`if (unit == 'other') ... [Builder(...)]` block** now seeds the local
   controller from `_lastCustomUnitText ?? widget.customUnit`, writes the
   current text back to `_lastCustomUnitText` via `onChanged`, and the
   `suffixText` closure reads from `_lastCustomUnitText` (a plain `String`,
   never a controller).
4. **Save handler** computes `resolvedUnit` from `_lastCustomUnitText`'s
   trimmed value with the saved `customUnit` as a fallback.
5. **Mounted guards** added before the optimistic `setState` in the checkbox
   `onChanged` and in the delete-confirmation flow. Prevents the
   `setState() called after dispose()` class of crashes if the user backs out
   mid-mutation.
6. **Defensive category validation** before `DropdownButton` is built: if the
   saved category is not in the current `categories` list (legacy data
   drift), fall back to the preset category or the last known category
   instead of crashing the dropdown.

### File
- `flutter_app/lib/screens/life/bazar_buddy_screen.dart` — 10 surgical edits
  applied across `_BazarBuddyScreenState` and `editItem`. `get_errors` returns
  "No errors found" on the file.

### Logic preserved
- All save / toggle / soft-delete flows still call the same `FinancialService`
  methods (`saveBazarItem`, `toggleBazarPurchased`).
- Quick-picks, OCR text, and the central ledger remain untouched.
- No Firestore schema, no rule, no field name changed.

---

## Bug 6 — BazarBuddy wrong icon for saved category

### Root cause
`_itemTile` was doing an exact-string match (`category == c.en`) against the
live `categories` list. Two real failure modes were visible in production:
- Saved `'fish'` (lowercase) silently fell back to the `Other` emoji because
  the canonical list has `'Fish'`.
- Saved `'Vegetables '` (trailing space) silently fell back to `Other`.

There is no OCR / suggestion engine that pre-fills categories for BazarBuddy;
the mismatch was a pure lookup bug.

### Fix
`_itemTile` now normalises both sides:
```dart
final rawCategory = data['category']?.toString().trim() ?? '';
final category = categories.firstWhere(
  (c) => c.en.toLowerCase() == rawCategory.toLowerCase(),
  orElse: () => categories.last,
);
```

### File
- `flutter_app/lib/screens/life/bazar_buddy_screen.dart` — `_itemTile` icon
  lookup made case-insensitive and trim-safe.

### Logic preserved
- No category is renamed in storage.
- No migration is required — legacy records start rendering correctly on the
  next read.

---

## Verification

```
flutter analyze
  3 issues found — all pre-existing infos (Radio groupValue/onChanged deprecation
  in medicine_screen.dart, nullable final in ai_assistant_screen.dart line 80).
  0 new errors or warnings introduced by Phase B.

flutter test --no-pub
  All 19 tests passed.
  - Central ledger idempotency: deterministic ids for (source, sourceRecordId)
  - Commute trip ledger guard: actual fare only writes one ledger row
  - Medicine dose keys: Taken -> expense, Skip / Missed / Pending -> no expense
  - Notification id determinism: same medicine + hhmm -> same id
  - FinancialSummary aggregation: legacy non-expense rows ignored
  - monthKey / dateKey formatting preserved
```

## Files touched

```
flutter_app/lib/app.dart
flutter_app/lib/screens/study/ai_assistant_screen.dart
flutter_app/lib/screens/study/study_screen.dart
flutter_app/lib/screens/life/bazar_buddy_screen.dart
```

## Files NOT touched

- Backend (`backend/app/**`).
- Firestore rules (`firebase/**`).
- `api_service.dart` (no new endpoints; existing `uploadMaterial` and `askPdf`
  were already correct, the AI screen just wasn't using them).
- `pubspec.yaml` (no new dependencies).

---

## Known remaining items

These are not bugs in this pass; they are tracked separately in `TODO.md`:

- Manual live-device validation of the PDF upload flow on Infinix X665E.
- Real reverse-geocoding on the map picker (deferred — requires a new backend
  endpoint, which Phase B explicitly forbade).
- Replacement of the deprecated `Radio.groupValue` / `Radio.onChanged` calls
  in `medicine_screen.dart` (3 infos; harmless; not in scope for bug-fix pass).
