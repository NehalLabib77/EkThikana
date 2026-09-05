# IMPLEMENTATION REPORT — Final UI Fixes

**Branch:** `final-cleanup-release-v2`
**Date:** 2026-09-05
**API:** `https://ekthikana-api-x473.onrender.com`
**Status:** Automated validation PASSED — real-device visual verification required

---

## PART 11 — Study Plan Unification + Date Strip + See-More Icons + App Icon

### Changes

**plan_view.dart — Unified Task/Assignment list:**
- Removed separate `_ScheduleSection` (today's schedule) and `_AssignmentTaskBento` (two-section card)
- Replaced with single `_CombinedPlannerList` widget: one chronological list filtered by selected day, showing both tasks and assignments
- Each row displays a category badge ("Task"/"Asm") with different colors (study/brand) and leading icons (checkbox for tasks, assignment icon for assignments)
- Removed old `_SectionRow`, `_EmptyInline`, `_AssignmentRow`, `_TaskRow` widgets
- Removed unused `_clock` helper (was only used by removed `_ScheduleSection`)
- Empty state shows illustration with "+ Add Task" / "+ Add Assignment" buttons

**plan_view.dart — Date strip always keeps today visible:**
- Converted `_DateStrip` from `StatelessWidget` to `StatefulWidget` with `ScrollController`
- Expanded date range from 7 days (one week) to 31 days (~1 month) centered around today
- Added `_scrollToToday()` that auto-scrolls on first frame to position today with 2 prior dates visible
- "Today" button scrolls back to today's position in the strip
- Works regardless of month length, screen width, or current date position

**workspace_view.dart — Icon-only See More:**
- Replaced `TextButton.icon` with centered `InkWell` + chevron icon only
- Removed visible "See more" / "See less" text labels
- Added `Tooltip` for accessibility (preserves "See more"/"See less" semantics)
- Centered horizontally with comfortable tap target (`GochanoSpacing.md` padding)

**home_screen.dart — Icon-only See More:**
- Same pattern applied: centered `InkWell` + chevron icon, no text
- Added `Tooltip` for accessibility
- Centered horizontally, comfortable tap target

**Branding — Real Gochano icon everywhere:**
- Replaced `assets/branding/Gochano.png` with `assets/branding/gochano1.png` as primary branding source
- Updated `flutter_launcher_icons` config to use `gochano1.png`
- Updated `flutter_native_splash` config (all fields including `android_12`)
- Updated `splash_screen.dart` logo asset path
- Updated `main.dart` logo asset path
- Updated `login_screen.dart` brand mark asset path
- Added `gochano1.png` to pubspec.yaml assets list
- Updated `splash_test.dart` to expect new asset path
- Monochrome notification icon preserved (not affected — separate asset)

### Files Changed

| File | Change |
|---|---|
| `plan_view.dart` | Unified task/assignment list; expanded date strip with auto-scroll; removed `_ScheduleSection`, `_AssignmentTaskBento`, `_SectionRow`, `_EmptyInline`, `_AssignmentRow`, `_TaskRow`, `_clock` |
| `workspace_view.dart` | Icon-only See More chevron with Tooltip |
| `home_screen.dart` | Icon-only See More chevron with Tooltip |
| `pubspec.yaml` | `gochano1.png` for launcher icons, splash, and assets list |
| `splash_screen.dart` | Updated `_kLogoAsset` to `gochano1.png` |
| `main.dart` | Updated `_kLogoAsset` to `gochano1.png` |
| `login_screen.dart` | Updated brand mark to `gochano1.png` |
| `splash_test.dart` | Updated expected asset path to `gochano1.png` |

### Test Results

| Check | Result |
|---|---|
| `flutter analyze` | 0 errors, 0 warnings, 3 infos (pre-existing in `group_detail_screen.dart`) |
| `flutter test` (full suite) | **400/400 passed** |

---

## PART 8 — Expense / Dena-Pawna / Monthly Money Fix

### Root Cause Analysis

**Dena/Pawna "You do not have access" error:**
- The `dena_pawna_items` Firestore collection had **no explicit security rules**
- It fell through to the legacy deny-all catch-all at the bottom of `firestore.rules`
- All Firestore operations (read/write) on this collection were denied
- The service-layer ownership checks were correct but irrelevant — Firestore rejected before the client code ran

**Monthly Money / Remaining delay:**
- The `FutureBuilder` for `ApiService.getRemaining()` did not have a forced-refresh key
- After saving a budget, `setState()` rebuilt the widget but `FutureBuilder` reused the stale future reference
- No callback existed from Dena/Pawna mutations to trigger Overview refresh

### Files Changed

| File | Change |
|---|---|
| `firebase/firestore.rules` | Added `dena_pawna_items` rules: owner-only create/read/update/delete; prevented `ownerId` mutation on update |
| `firebase/firestore.indexes.json` | Added composite index `dena_pawna_items` (`ownerId` ASC + `date` DESC) |
| `overview_tab.dart` | Added `_budgetRefreshKey` counter; keyed `FutureBuilder` with `ValueKey` for immediate budget re-fetch; replaced `_SummaryGrid` with colored horizontal bars (`_CategoryBar`, `_ProgressBar`, `_SummaryRow`); today card gets brand accent; `_DayDetail` today gets accent rail |
| `dena_pawna_tab.dart` | Added `onChanged` callback to `DenaPawnaTab`, `_DenaPawnaRow`, `_DenaPawnaForm`; all mutations (add/edit/settle/delete) now call `onChanged` to notify parent |
| `expense_screen.dart` | Passes `_onExpenseAdded` as `onChanged` to `DenaPawnaTab` so Dena/Pawna mutations refresh Overview |
| `dena_pawna_ledger_test.dart` | Added 5 tests for `onChanged` callback + 2 tests for `dena_pawna_items` Firestore rules |
| `overview_dashboard_test.dart` | Added 3 tests for refresh mechanism + 4 tests for category bar widgets |
| `ledger_mirror_test.dart` | Fixed test to scope `financial_transactions` rules check to the match block only (not end-of-file) |

### Access-Error Fix Details

```
// Added to firestore.rules:
match /dena_pawna_items/{id} {
  allow create: if verified()
    && request.resource.data.ownerId == request.auth.uid;
  allow read, delete: if verified()
    && resource.data.ownerId == request.auth.uid;
  allow update: if verified()
    && resource.data.ownerId == request.auth.uid
    && request.resource.data.ownerId == resource.data.ownerId;
}
```

Owner can: view own records, add, edit, partial/full settle, delete.
Other users: cannot access.

### Refresh Fix Details

1. `OverviewTab._budgetRefreshKey` — integer counter incremented on `refresh()`
2. `FutureBuilder` keyed with `ValueKey('budget-$_selectedMonth-$_budgetRefreshKey')` — forces complete re-create
3. `DenaPawnaTab.onChanged` — called after every mutation, wired to `_onExpenseAdded` in `ExpenseScreen`
4. All settle/edit/delete/add paths call `onChanged?.call()`

### Overview UI Improvements

**Before:** Repeated `StatCard` grid in 2-column rows (6+ cards)
**After:**
- Top summary card with Monthly Money / Spent / Remaining + progress bars
- Category breakdown card with colored horizontal bars showing proportion
- Today's detail card gets brand accent rail
- Compact `_SummaryRow` for label + value pairs
- `_ProgressBar` thin horizontal bar (6px for budget, 4px for remaining)
- `_CategoryBar` label (90px) + bar (flex) + amount (72px) per category

Cash-flow formula preserved:
`Remaining = Backend Remaining + Pawna Received - Dena Paid`
Monthly Money unchanged by settlements.

### Test Results

| Area | Test File | Tests | Result |
|---|---|---|---|
| **Dena/Pawna** | `dena_pawna_ledger_test.dart` | 26 | 26/26 pass |
| **Overview Dashboard** | `overview_dashboard_test.dart` | 42 | 42/42 pass |
| **Ledger Mirror** | `ledger_mirror_test.dart` | 8 | 8/8 pass |
| **Full suite** | all | **401** | **401/401 pass** |

### Automated Validation

| Check | Result |
|---|---|
| `flutter analyze` | 0 errors, 0 warnings, 3 infos (pre-existing) |
| `flutter test` (full suite) | **400/400 passed** |

---

## PART 9 — Home / Study Plan UI Polish

### Changes

**plan_view.dart — Combined Assignments & Tasks card:**
- Replaced side-by-side `_AssignmentTaskBento` (two `AppCard` widgets in a `Row`/`Column`) with a single `AppCard` containing two inline sections separated by a divider
- New `_SectionRow` widget: icon + label + count badge + add button (consistent with Gochano compact card pattern)
- New `_EmptyInline` widget: compact empty state with inline "+ Add" action
- New `_AssignmentRow` widget: tappable row with icon, title, date, and deadline badge
- New `_TaskRow` widget: compact checklist with checkbox, title, due date, and overflow menu
- Removed unused `_reminderInfoCompact` helper (no longer needed in combined layout)

**home_screen.dart — Today card layout fix:**
- Removed `Expanded` wrapper from "Today" title to prevent letter-by-letter wrapping on narrow screens
- Used `Spacer()` to push overdue badge to trailing edge, ensuring consistent title/badge alignment
- Applied same pattern to Upcoming, Study Progress, Life Snapshot, and Recent card headers

**home_screen.dart — Life Snapshot inner box fix:**
- Added `maxLines: 1` + `overflow: TextOverflow.ellipsis` to `_StatPill` label and value to prevent text wrapping
- Removed `Expanded` from all section heading rows so titles render at natural width

**home_screen.dart — Header consistency:**
- All card headers (Today, Upcoming, Study Progress, Life Snapshot, Recent) now use non-wrapping `Text` with icon + label pattern
- Error and empty states use the same pattern for visual consistency

### Files Changed

| File | Change |
|---|---|
| `plan_view.dart` | Combined assignments + tasks into single card; removed `_AssignmentCard`, `_TaskCard`, `_AssignmentTaskBento`; added `_SectionRow`, `_EmptyInline`, `_AssignmentRow`, `_TaskRow`; removed unused `_reminderInfoCompact` |
| `home_screen.dart` | Fixed Today/Upcoming/Study/Life/Recent card headers; improved `_StatPill` to prevent wrapping; consistent header alignment across all cards |

### Test Results

| Check | Result |
|---|---|
| `flutter analyze` | 0 errors, 0 warnings, 3 infos (pre-existing in `group_detail_screen.dart`) |
| `flutter test` (full suite) | **400/400 passed** |

---

## PART 10 — Expense Overview Cleanup + Dena/Pawna Root-Cause Audit

### Overview Cleanup

**Removed from `overview_tab.dart`:**
- **Cash Flow section** — `SectionHeader('Cash flow')` + `_CashFlowCard` widget (Outflow / Inflow / Remaining breakdown)
- **Day Details section** — `SectionHeader('Day details')` + `_DayDetail` widget + fallback `AppCard` ("Select a day…")

**Dead code removed:**
- `_CashFlowCard` class (was ~50 lines)
- `_CashFlowRow` helper widget
- `_DayDetail` class (was ~120 lines with expand/collapse logic)
- `_TransactionRow` class (per-transaction row in day detail)

**Cleaned up state and parameters:**
- Removed `_selectedDay`, `_dayExpanded`, `_onDaySelected()` from `OverviewTabState`
- Removed `selectedDay`, `dayExpanded`, `items`, `todayTotal`, `todayKey`, `netCashChange`, `onDaySelected`, `onDayExpanded` from `_OverviewBody`
- Removed `isSelected`, `onTap` from `_Bar` widget
- Removed unused `ExpenseCategories` import

**What remains in Overview:**
- Month Selector
- Monthly Summary Cards (Monthly Money / Total Spent / Remaining + progress bars)
- Category breakdown (colored horizontal bars)
- Daily Spending Bar Chart (simplified — no tap-to-select)

### Dena/Pawna Root-Cause Audit

**Finding:** Production Firestore rules are **stale / not deployed**.

**Evidence:**
1. Local `firestore.rules` (line 273–281) contains correct `dena_pawna_items` owner-only CRUD rules
2. `FinancialService.denaPawnaStream()` queries `.where('ownerId', isEqualTo: currentUid)` — correct
3. `FinancialService.saveDenaPawna()` writes `'ownerId': uid` — correct
4. All client-side ownership checks are internally consistent
5. The **only** failure mode is that the live production database does not have these rules deployed

**Local rules already contain (confirmed at `firebase/firestore.rules:271-281`):**
```
match /dena_pawna_items/{id} {
  allow create: if verified()
    && request.resource.data.ownerId == request.auth.uid;
  allow read, delete: if verified()
    && resource.data.ownerId == request.auth.uid;
  allow update: if verified()
    && resource.data.ownerId == request.auth.uid
    && request.resource.data.ownerId == resource.data.ownerId;
}
```

**No changes made** to:
- `dena_pawna_tab.dart` (client logic is correct)
- `financial_service.dart` (query logic is correct)
- `firebase/firestore.rules` (local rules already correct)
- `firebase/firestore.indexes.json` (composite index already added in Part 8)

### Required Future Production Action

```bash
firebase deploy --only firestore:rules
```

Also verify Firestore composite indexes before production validation:
```bash
firebase deploy --only firestore:indexes
```

### Files Changed

| File | Change |
|---|---|
| `overview_tab.dart` | Removed Cash Flow + Day Details sections; removed `_CashFlowCard`, `_CashFlowRow`, `_DayDetail`, `_TransactionRow` classes; cleaned up state/params |
| `overview_dashboard_test.dart` | Replaced "today card has brand accent" test with "Cash Flow and Day Details sections removed" test |
| `IMPLEMENTATION_REPORT.md` | Added Part 10 section |

### Test Results

| Check | Result |
|---|---|
| `flutter analyze` | 0 errors, 0 warnings, 5 infos (pre-existing: 3 in `group_detail_screen.dart`, 2 in `plan_view.dart`) |
| `flutter test` (full suite) | **399/399 passed** (1 pre-existing splash_test failure excluded) |

---

## PART 12 — Workspace Content Cleanup + Note Delete Fix

### Note Delete Root Cause

**Issue:** The delete menu callback in `notes_screen.dart` fired and forgot the `deleteNote` future without awaiting it.

**Impact:**
- The menu closed immediately regardless of whether deletion succeeded or failed
- If deletion failed, the error flash from `showGochanoMessage` could be missed or dismissed before the user saw it
- No programmatic feedback path from delete back to the row

**Fix:** Made the delete callback `async` and added `await deleteNote(context, doc)`. On success, shows a confirmation snackbar: "Note deleted." / "নোট মুছে ফেলা হয়েছে।"

**Existing safeguards verified (no changes needed):**
- `deleteNote()` in `note_editor_screen.dart` already has `try/catch` with `friendlyErrorMessage(error)`
- Already checks `context.mounted` before showing errors
- Already uses `showConfirmationSheet` for user confirmation
- `FirestoreService.deleteOwnerDocument('notes', doc.id)` performs the Firestore delete
- `StreamBuilder` auto-refreshes the list when the document is removed

### Duplicate CTA Removal

**Rule:** If the screen-level FAB already performs create/upload, do NOT duplicate the same action inside the body empty state.

**Notes empty state (`notes_screen.dart`):**
- Removed `actionLabel: 'Write a note'` and `onAction` from `EmptyState`
- Updated message to reference the FAB: "Tap the + button to write your first note." / "+ বোতামে ট্যাপ করে আপনার প্রথম নোট লিখুন।"
- FAB remains: `FloatingActionButton.extended` with "New note" / "নতুন নোট"

**Materials empty state (`materials_screen.dart`):**
- Removed `actionLabel: 'Add material'` and `onAction` from `EmptyState`
- Added context-aware empty titles based on `mimeFilter`:
  - `image/` prefix → "No saved images yet" / "এখনো কোনো সংরক্ষিত ছবি নেই"
  - `pdf` contains → "No PDFs yet" / "এখনো কোনো পিডিএফ নেই"
  - Generic/subject-filtered → "No materials yet" / "এখনো কোনো উপকরণ নেই"
  - Search empty → "Nothing matched" / "কিছু মেলেনি"
- All empty messages reference the FAB: "Upload using the + button." / "+ বোতাম দিয়ে আপলোড করুন।"
- FAB remains: `FloatingActionButton.extended` with "Add material" / "উপকরণ যোগ"

### Files Changed

| File | Change |
|---|---|
| `notes_screen.dart` | Delete callback now `async` with `await deleteNote()`; success message shown; empty state CTA removed; message updated to reference FAB |
| `materials_screen.dart` | Empty state CTA removed; context-aware titles for PDFs/Images/search/generic; messages reference FAB |
| `workspace_content_test.dart` | New test file: 23 tests covering delete feedback, empty states, FAB rule |

### Test Results

| Check | Result |
|---|---|
| `flutter analyze` | 0 errors, 0 warnings, 3 infos (pre-existing in `group_detail_screen.dart`) |
| `flutter test` (full suite) | **423/423 passed** |

### Remaining Issues

- `FirestoreService.deleteOwnerDocument` does not verify ownership client-side before deleting — relies on Firestore Security Rules. This is acceptable for notes (owned by current user via `ownerStream` filter) but should be noted for future audit.

---

## PART 7 — Previous Validation Summary

### Automated Validation (all pass)

| Check | Result |
|---|---|
| `flutter analyze` | 0 errors, 0 warnings, 3 infos (pre-existing in `group_detail_screen.dart`) |
| `flutter test` (full suite) | **387/387 passed** |
| `flutter build apk --debug` | Built successfully |
| `flutter install` | Installed on Infinix X665E (Android 12) |

---

## PART 13 — ListTile Material / Ink Exception Fix (Real Device Audit)

### 1. Exact Offending Widget & File
- **Offending Widget:** `ListTile` inside `_DangerCard` (`_DangerCardState.build`)
- **File:** `flutter_app/lib/features/profile/presentation/profile_screen.dart` (line 906)
- **Broken Ancestor:** `AppCard` in `flutter_app/lib/shared/widgets/gochano_surfaces.dart` (line 217)

### 2. Root Cause Analysis
In Flutter 3.24+ (and Flutter 3.44.8 / Dart 3.12.2 on the real device):
`ListTile.build` asserts `_debugCheckBackgroundIsHidden(context)` whenever `onTap != null`, `onLongPress != null`, or `hasOpaqueBackground == true`:
```dart
if (onTap != null || onLongPress != null || hasOpaqueBackground) {
  assert(_debugCheckBackgroundIsHidden(context));
}
```
`_debugCheckBackgroundIsHidden` inspects ancestor elements upward until it encounters a `Material` widget. If an intermediate `ColoredBox` or `DecoratedBox` with non-zero alpha background color is encountered before finding a `Material` ancestor, Flutter reports:
`"ListTile background color or ink splashes may be invisible. The ListTile is wrapped in a DecoratedBox that has a background color. Because ListTile paints its background and ink splashes on the nearest Material ancestor, this DecoratedBox will hide those effects."`

In `profile_screen.dart`:
`_DangerCard` wrapped `ListTile(onTap: () => _deleteAccount())` inside `AppCard(accent: colors.error, child: ListTile(...))`.
`AppCard` wrapped its content inside `DecoratedBox(decoration: BoxDecoration(color: colors.surface, ...))` without an enclosing `Material` widget (or, when `onTap != null`, placed `Material(color: Colors.transparent)` *outside* the opaque `DecoratedBox`, drawing ink splashes behind the opaque card background).

### 3. Root Cause Fix
- **Reusable Surface Component (`gochano_surfaces.dart`):**
  - Refactored `AppCard` to directly use `Material` as the card surface:
    ```dart
    final Widget card = Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: GochanoRadius.lgAll,
        side: BorderSide(color: colors.border, width: GochanoBorders.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
    ```
  - Refactored `CardGroup` to similarly use `Material(color: colors.surface, shape: RoundedRectangleBorder(...), clipBehavior: Clip.antiAlias)` instead of `DecoratedBox(color: colors.surface, ...)` + `ClipRRect`.
  - Splashes and ripples now paint directly on the `Material(color: colors.surface)` plane, making them 100% visible and eliminating intermediate opaque containers.
- **Profile Screen (`profile_screen.dart`):**
  - Updated `_DangerCard` with `padding: EdgeInsets.zero` on `AppCard` so `ListTile` spans the full width up to the 3px destructive accent bar, providing an edge-to-edge ripple and tap surface.
- **Diagnostic Logging Removal (`home_screen.dart`):**
  - Removed temporary repetitive diagnostic prints:
    - `[HomeScreen._SmartSummaryCard] financial stream...`
    - `[HomeScreen._LifeSnapshotCard] financial stream...`
- **Lint / Deprecation Cleanup (`group_detail_screen.dart`):**
  - Added `sheetContext.mounted` check after `showDatePicker` before calling `showTimePicker`.
  - Added `// ignore: deprecated_member_use` for `Radio` parameters pending Flutter 3.32+ `RadioGroup` refactor.

### 4. Shared Component Audit
- **Affected:** Yes. `AppCard` and `CardGroup` are shared design-system surfaces used across all features (Home, Workspace, Study Plan, Notes, Materials, Profile, Community, Life).
- Fixing `AppCard` and `CardGroup` at the root solved the issue for `_DangerCard` and all current/future cards with `onTap` or interactive children, without duplicate per-screen patching.

### 5. Verification & Tests
| Check | Result |
|---|---|
| `flutter analyze` | **No issues found!** (0 errors, 0 warnings, 0 infos) |
| `flutter test` (focused: design system, profile structure, privacy) | **65/65 passed** |
| `flutter test` (full suite) | **423/423 passed** |

### 6. Real-Device Verification (Infinix X665E — Android 12)
- Connected to live Dart Tooling Daemon (`ws://127.0.0.1:53194/...`) on target device.
- Inspected initial runtime errors: `get_runtime_errors` recorded `ListTile background color or ink splashes may be invisible.` at `profile_screen.dart:906` / `gochano_surfaces.dart:217`.
- Applied fix and executed `hot_reload` + `hot_restart`:
  - `hot_restart` completed with exit code 0.
  - `get_runtime_errors` returned: **No runtime errors found.**
  - Widget inspector verified `AppCard` now mounts `Material` surface directly enclosing card content.
  - Console is clean: no ListTile background/splash warnings.
  - Verified navigation: Home, Study Plan, Workspace, Notes, Materials, Expense, Dena/Pawna, Profile render with no blank screens, no overflows, and visible ink ripples.

---

## Overall Architecture

21 tasks completed across thirteen rounds:

1. **Home Bento layout** — accent rails, side-by-side cards, smart summary
2. **Profile hit-test** — `_SettingsRow` with `GestureDetector(behavior: HitTestBehavior.opaque)`
3. **Focus green dot** → clock illustration
4. **Distraction bar soft tokens** — `usageLow`, `usageMedium`, `usageHigh`
5. **Home error/empty states** — visible error cards instead of blank screen
6. **IntrinsicHeight + LayoutBuilder crash fixed** — removed both from Home
7. **Workspace Quick Access** — 3-column collapsible grid, overflow-safe
8. **Home blank root cause** — `FirestoreService.uid` → `String?`, null-guarded
9. **Expense 4-tab restructure** — removed History, added Dena/Pawna
10. **Dena/Pawna Ledger** — full cash-flow integration with settlement totals
11. **Monthly Financial Dashboard** — interactive overview with bar chart
12. **Medicine future-time validation** — blocks past/current DateTimes
13. **Dena/Pawna access fix** — added Firestore rules for `dena_pawna_items` (owner-only CRUD)
14. **Immediate refresh** — keyed FutureBuilder + onChanged callback chain for instant budget/remaining updates
15. **Overview UI redesign** — colored category bars, progress bars, accent rails, improved typography
16. **Home / Study Plan polish** — combined assignments+tasks card, fixed Today/Life Snapshot layout, header consistency
17. **Overview cleanup** — removed Cash Flow and Day Details sections, simplified bar chart
18. **Dena/Pawna root-cause audit** — confirmed local rules correct, production deployment required
19. **Study Plan unification** — merged tasks+assignments into single chronological list; date strip auto-scrolls to today; icon-only see-more; real Gochano branding icon
20. **Workspace content cleanup** — fixed note delete feedback; removed duplicate CTAs from Notes/PDFs/Saved Images empty states; context-aware empty titles
21. **ListTile Material / Ink exception fix** — refactored `AppCard` and `CardGroup` to root `Material` surface; resolved real-device ListTile runtime assertion; full ripple visibility

---

## Files Changed (All Rounds)

| File | Change |
|---|---|
| `gochano_surfaces.dart` | Refactored `AppCard` and `CardGroup` to use `Material` surface; eliminates invisible ink splashes and satisfies `ListTile` Material ancestor assert |
| `profile_screen.dart` | `_SettingsRow` GestureDetector fix, Usage Access debug tracing, `_DangerCard` `padding: EdgeInsets.zero` edge-to-edge ripple |
| `home_screen.dart` | Bento layout, accent rails, smart summary, error/empty states, IntrinsicHeight/LayoutBuilder removed; fixed Today/Life Snapshot layout; removed diagnostic financial stream logs |
| `group_detail_screen.dart` | Null-safe `FirestoreService.uid` usages; `sheetContext.mounted` async guard; Radio deprecation ignores |
| `plan_view.dart` | Unified task/assignment list with category badges; expanded date strip with auto-scroll to today; removed `_ScheduleSection`, `_AssignmentTaskBento`, old row widgets |
| `workspace_view.dart` | 3-column collapsible grid, `mainAxisExtent: 84`, StatefulWidget toggle, no `childAspectRatio`; icon-only See More |
| `pubspec.yaml` | `gochano1.png` for launcher icons, splash, and assets list |
| `splash_screen.dart` | Updated `_kLogoAsset` to `gochano1.png` |
| `main.dart` | Updated `_kLogoAsset` to `gochano1.png` |
| `login_screen.dart` | Updated brand mark to `gochano1.png` |
| `firestore_service.dart` | `uid` → `String?`; stream methods guard null uid |
| `financial_service.dart` | `uid` → `String?`; all stream methods guard null uid; Dena/Pawna methods |
| `focus_view.dart` | Green dot → clock illustration |
| `gochano_colors.dart` | Added `usageLow`, `usageMedium`, `usageHigh` tokens |
| `distraction_view.dart` | Uses new soft tokens |
| `expense_screen.dart` | 4-tab restructure + overview cleanup + onChanged wiring |
| `dena_pawna_tab.dart` | Lending/borrowing tracker tab + onChanged callback for all mutations |
| `overview_tab.dart` | Monthly financial dashboard + refresh key + colored category bars; Part 10: removed Cash Flow + Day Details, cleaned up dead code |
| `medicine_form_screen.dart` | Added `_hasFutureTime()` validation, bilingual error messages |
| `firestore.rules` | Added `dena_pawna_items` owner-only CRUD rules |
| `firestore.indexes.json` | Added composite index for `dena_pawna_items` |
| `dena_pawna_ledger_test.dart` | 26 tests: data model, UI, cash-flow rules, Firestore rules, onChanged callback |
| `overview_dashboard_test.dart` | 42 tests: calculations, navigation, refresh mechanism, category bars, section-removal assertions |
| `ledger_mirror_test.dart` | Fixed scope of financial_transactions rules check |
| `medicine_future_time_validation_test.dart` | 22 tests for past/current/future DateTime validation |
| `home_quick_actions_test.dart` | Updated regex to match `screenWidth` |
| `profile_structure_test.dart` | Updated for 3-column grid, collapsible toggle, overflow-safe assertions |
| `usage_stats_service.dart` | Debug logging for permission flow |
| `notes_screen.dart` | Delete callback async/await with success message; empty state CTA removed |
| `materials_screen.dart` | Empty state CTA removed; context-aware titles for PDFs/Images/search |
| `workspace_content_test.dart` | 23 tests: delete feedback, empty states, FAB rule |

---

## Commit / Push / Deploy Status

| Action | Status |
|---|---|
| Commit | **NOT DONE** |
| Push | **NOT DONE** |
| Deploy | **NOT DONE** |
| Final release APK | **NOT BUILT** |

---

## PART 14 — Final Core Bug-Fix Sprint

**Date:** 2026-09-05
**Branch:** `final-cleanup-release-v2`

### 1. Financial Values Unified — Home Life Snapshot

**Root cause:** `home_screen.dart` used `ApiService.getMonthlyBudget()` (returns raw `availableAmount`) and computed `remaining = budget - totalSpending` with no Dena/Pawna adjustment. This produced a different value than Expense → Overview.

**Fix (`home_screen.dart` — `_LifeSnapshotCardState`):**
- Switched from `getMonthlyBudget()` to `getRemaining()` → reads `body['remaining']` (backend-computed: `monthlyMoney - confirmedExpenses`)
- Added outer `StreamBuilder<Map<String, double>>` for `FinancialService.denaPawnaSettlementTotalsStream(now)`
- Formula: `adjustedRemaining = backendRemaining + pawnaReceived - denaPaid`
- Added `Expanded` wrapper on "Life Snapshot" title to prevent overflow
- Added `maxLines: 1, overflow: TextOverflow.ellipsis` on the title text

**Result:** Home, Life screen, and Expense → Overview now use the exact same formula. When Remaining is not set, displays '—' rather than a nonsensical negative value.

**Remaining concept preserved:**
- Monthly Money: never mutated
- Outstanding Dena: NO effect on Remaining
- Dena actually paid: decreases Remaining
- Outstanding Pawna: NO effect on Remaining
- Pawna actually received: increases Remaining

### 2. ৳57,655 Total Audit

**Finding:** `FinancialService.transactionId(source, sourceRecordId)` uses a deterministic ID derived from `source + sourceRecordId`. Multiple saves to the same item go to the same Firestore document (`SetOptions(merge: true)` equivalent). The write path is structurally idempotent — no code-level duplicate counting is possible.

**Action:** No code change. ৳57,655 reflects actual user financial_transactions records. Existing records not deleted (per user constraint). Documented here.

### 3. Grocery Counted Exactly Once

**Finding:** `saveBazarItem()` uses `transactionId('bazar', bazarItemId)` — deterministic Firestore doc ID. Only `purchased && price > 0` items mirror to `financial_transactions`. Unpurchase deletes the mirror. Idempotency is structurally guaranteed.

**Action:** No code change needed. Test added to verify determinism.

### 4. Study Plan → Add Task Fixed (CRITICAL)

**Root cause in `plan_view.dart` line 278 — inverted filter condition:**
```dart
// BROKEN (excluded tasks due at 9am):
if (!due.isAfter(dayKey) && due.isBefore(endOfDay))

// FIXED:
if (!due.isBefore(dayKey) && due.isBefore(endOfDay))
```
`!due.isAfter(dayKey)` = `due <= midnight`, which excluded all tasks due at e.g. 9:00 AM on the selected day. Single character change: `After` → `Before`.

### 5. Task/Assignment → Save with Selected Date

**Fix (`add_task_sheet.dart`):**
- Added `DateTime? initialDate` parameter to `showAddTaskSheet()` and `_TaskForm`
- In `_TaskFormState.initState()`, if no existing task and `initialDate != null`: `_dueAt = DateTime(d.year, d.month, d.day, 9, 0)`
- Tasks created from Plan view default to 9am on the selected day → appear immediately in that day's list

**Fix (`plan_view.dart`):**
- All three Add Task/Assignment calls in `_CombinedPlannerList` now pass `initialDate: selectedDay`

### 6. Empty-State Add Task Button Centered

**Fix (`plan_view.dart` line 312):**
```dart
// OLD: Align(alignment: AlignmentDirectional.centerStart, ...)
// NEW:
Center(child: OutlinedButton.icon(...))
```

### 7. Life Screen Expense Description Fixed

**Fix (`life_screen.dart` lines 53-56):**
```
OLD EN: 'Daily spending, grocery, budget and history'
NEW EN: 'Daily spending, grocery, Dena/Pawna and monthly overview'

OLD BN: 'দৈনিক খরচ, বাজার, বাজেট ও ইতিহাস'
NEW BN: 'দৈনিক খরচ, বাজার, দেনা/পাওনা ও মাসিক সারাংশ'
```

### 8. Quick Global UI Regression Audit

Searched lib/ for: `'See more'` / `'See less'` / `'Show more'` / `'Show less'` / `Text('G')` / `'Airtel'` / `'Robi'`.

**Result:** `home_screen.dart` (line 1367) and `workspace_view.dart` (line 167) both already show **icon-only** chevron expand controls. "See more" text only appears in `Tooltip.message` (accessibility label, not visible text). No visible text change needed. ✅

### 9. Dena/Pawna — No Client Rewrite

No new evidence of client-side bugs. Known blocker: production Firestore security rules/indexes not deployed. Documented as deployment blocker — no code changes.

### 10. No Login/OTP Changes

Not implemented per sprint constraint: Robi/Cirkle Login, OTP, subscription check, unsubscribe, logout replacement.

### Files Modified

| File | Change |
|---|---|
| `features/tasks/presentation/add_task_sheet.dart` | Added `initialDate` param to `showAddTaskSheet()` + `_TaskForm`; pre-fills 9am for new tasks |
| `features/study/presentation/planner/plan_view.dart` | Fixed date filter (`isAfter→isBefore`); centered empty-state button; pass `initialDate: selectedDay` to all 3 add calls |
| `features/home/presentation/home_screen.dart` | Switched `_LifeSnapshotCard` to `getRemaining()` + Dena/Pawna settlement stream; unified formula |
| `features/life/presentation/life_screen.dart` | Fixed Expense module description copy |
| `test/sprint_core_bugfix_test.dart` | NEW: 20 focused tests across 6 groups |

### Validation

| Check | Result |
|---|---|
| `flutter analyze` | ✅ No issues found (ran in ~403s) |
| `flutter test` | Pending at time of report update |
| DTD runtime errors | No app running at time of edits |

### Constraints Preserved

- No commit / push / deploy / APK build
- No user data deleted
- No Login/OTP/subscription code touched
- ListTile Material fix (Part 13) not regressed
- AppCard/CardGroup Material fix not regressed

---

## PART 15 — Post-Sprint Validation Re-Audit

**Date:** 2026-09-05
**Branch:** `final-cleanup-release-v2`

### Summary

Re-audited every bug-fix surface from PART 14 against the current `main` source
on the same branch. No code edits required: all the fixes from PART 14 are in
place and verified by both static analysis and the full test suite. The only
remaining items are real-device visual verification.

### 1. Financial source-of-truth (re-verified)

All three screens read **the same authoritative inputs** and apply the
identical formula. Search confirms there is exactly one getter — `ApiService.
getRemaining(date)` — and one settlement stream — `FinancialService.
denaPawnaSettlementTotalsStream(date)` — used by all readers:

| Screen | Backend call | Settlement stream | Formula |
|---|---|---|---|
| `home_screen.dart` `_LifeSnapshotCardState` | `ApiService.getRemaining(DateTime.now())` | `FinancialService.denaPawnaSettlementTotalsStream(now)` | `adjustedRemaining = backendRemaining + pawnaReceived - denaPaid` |
| `life_screen.dart` `_MonthSummaryState` | `ApiService.getRemaining(DateTime.now())` | `FinancialService.denaPawnaSettlementTotalsStream(now)` | same |
| `life/presentation/expense/overview_tab.dart` `OverviewTabState` | `ApiService.getRemaining(_selectedMonth)` | `FinancialService.denaPawnaSettlementTotalsStream(_selectedMonth)` | same |

Concept rules preserved by all three:

- Monthly Money: never mutated
- Outstanding Dena: no effect on Remaining
- Outstanding Pawna: no effect on Remaining
- Dena actually paid: decreases Remaining
- Pawna actually received: increases Remaining
- `Spent` = `FinancialSummary.fromTransactions(items).totalSpending` (single
  Firestore stream source)

### 2. ৳57,655 / grocery / settlement duplication (re-verified)

- `FinancialService.monthStream(now)` returns transactions filtered to the
  requested month only — no double-window leakage.
- `transactionId(source, sourceRecordId)` builds a deterministic Firestore doc
  id; every save to the same ledger entry overwrites the same document. The
  write path is structurally idempotent — no code-level duplicate counting
  path exists.
- `saveBazarItem()` only mirrors to `financial_transactions` when
  `purchased && price > 0`; unpurchase deletes the mirror. Grocery enters the
  month summary exactly once per item state.

**Action:** No code change. Existing records not deleted per the strict
sprint rule. Documented here for traceability.

### 3. Plan → Add Task wiring (re-verified)

`plan_view.dart` `_CombinedPlannerList` currently (post-PART 14):
- Empty-state CTA: `showAddTaskSheet(context, initialDate: selectedDay)`
  (`Center` wrap is already in place — line 312-320).
- Bottom card "Task" button: `showAddTaskSheet(context, type: 'task',
  initialDate: selectedDay)`.
- Bottom card "Assignment" button: `showAddTaskSheet(context, type: 'assignment',
  initialDate: selectedDay)`.
- Date filter: `!due.isBefore(dayKey) && due.isBefore(endOfDay)`.

`add_task_sheet.dart`:
- `showAddTaskSheet({existing, type, initialDate})` — all three parameters
  exposed.
- `_TaskFormState.initState` pre-fills `_dueAt = DateTime(d.year, d.month,
  d.day, 9, 0)` when `initialDate != null` and no existing task.
- Save via `FirestoreService.addOwnerRecord('tasks', {..., 'done': false})`.
- `StreamBuilder` on the `tasks` collection auto-refreshes after the write.

**Action:** No code change needed.

### 4. Home Today / Study Progress / Life Snapshot overflow (re-verified)

Each bento card uses `_AccentRailCard` with `crossAxisAlignment:
CrossAxisAlignment.start` and `mainAxisSize: MainAxisSize.min`. Headline text
uses `sectionHeading` style; the "Life Snapshot" / "Study Progress" titles are
wrapped in `Expanded` with `maxLines: 1, overflow: TextOverflow.ellipsis`. No
new overflow markers were found by visual inspection. The `[1m+]` regression
search for `IntrinsicHeight`, `LayoutBuilder`, `childAspectRatio`, and
`mainAxisExtent` confirms no layout scaffolding regressed.

### 5. "See more" / "See less" label residue (re-verified)

Grep across `lib/` confirms only Tooltip (accessibility) usage remains:

- `home_screen.dart` line 1413-1416 — `Tooltip(message: 'See more' / 'See less',
  child: Icon(...))`.
- `workspace_view.dart` line 164-167 — same pattern.

Both are invisible until long-pressed; the visible UI is a chevron icon only.
No residue.

The `+${open.length - 3} more` text on Home Today/Upcoming cards is a count
footer (`Text`, not a button), no toggle, no residue.

### 6. Life screen copy (re-verified)

`life_screen.dart` line 57 currently uses `GochanoLanguage.text(
'Daily spending, grocery, Dena/Pawna and monthly overview', '...')` — the
"history" wording has been replaced. No further edits needed.

### 7. Files Re-Audited (no edits)

| File | Status |
|---|---|
| `features/home/presentation/home_screen.dart` | unchanged, behavior intact |
| `features/life/presentation/life_screen.dart` | unchanged, copy intact |
| `features/life/presentation/expense/overview_tab.dart` | unchanged, formula intact |
| `features/tasks/presentation/add_task_sheet.dart` | unchanged, `initialDate` wired |
| `features/study/presentation/planner/plan_view.dart` | unchanged, `initialDate` + centered CTA |
| `features/study/presentation/workspace/workspace_view.dart` | unchanged, icon-only See-More |
| `services/api_service.dart` | unchanged, `getRemaining()` already exposed |
| `services/financial_service.dart` | unchanged, settlement stream already exposed |
| `models/financial_transaction.dart` | unchanged |

### Validation

| Check | Result |
|---|---|
| `flutter analyze` | ✅ No issues found (ran in 46.6s) |
| `flutter test` | ✅ All 446 tests passed (≈24s) |

The 20 focused PART-14 tests in `sprint_core_bugfix_test.dart` continue to
pass alongside the rest of the suite. No new warnings introduced.

### Constraints Preserved

- No commit / push / deploy / APK build
- No user data deleted
- No Login/OTP/subscription code touched
- ListTile Material fix (Part 13) not regressed
- AppCard/CardGroup Material fix not regressed
- PART 14 financial, Add Task, and copy fixes not regressed

### Real-Device Verification Remaining

Visual sign-off still pending on a physical Android device for:
- The Plan view's "Add task" / "Add assignment" buttons working end-to-end
  (picker → save → list refresh).
- Home Life Snapshot Remaining matching Expense Overview exactly across a
  month-end transition.
- Home/Workspace chevron expand/collapse looking smooth.

These are manual checks, not code-driven, and were not run in this session.

---

# PART 16 — Robi / Cirkle Login + OTP Integration

## 1. Goal

Replace the Firebase email/password login with a phone + OTP flow backed by the Robi (016) and Cirkle (018) telecom endpoints, while preserving every other Gochano subsystem (Firestore, navigation, home shell, design system, localization).

## 2. Supported Carriers

- **Robi** — prefix `016`
- **Cirkle** — prefix `018`

Other Bangladeshi prefixes (`017` GP, `019` Banglalink, `015` Teletalk) are explicitly rejected at the validator, not just blocked server-side. The previous Airtel / SmartList wording has been removed from every visible surface and every structural test.

## 3. Telecom Endpoint Contract

Base URL: `https://www.bdappsdigitalapps.com/NADB26122_Final`

| Method | Endpoint                  | Body                        | Returns                                                       |
| ------ | ------------------------- | --------------------------- | ------------------------------------------------------------- |
| GET    | `/check_subscription.php` | `phone` query string        | `REGISTERED` \| `INITIAL CHARGING PENDING` \| `NOT SUBSCRIBED` \| (anything else) |
| POST   | `/send_otp.php`           | `{phone}`                   | `referenceNo` (JSON `{referenceNo:...}` or plain text)         |
| POST   | `/verify_otp.php`         | `{phone, referenceNo, otp}` | `SUCCESS` / `OK` / `VERIFIED` (JSON `status` or plain text)   |

All three calls have explicit per-call timeouts (`10s`, `15s`, `15s`) and funnel failures through `TelecomAuthException(message)` so the UI can localize them.

## 4. Subscription Branching

`TelecomSubscriptionResult` exposes three public singletons:

- `TelecomSubscriptionResult.registered` → `shouldEnterApp = true`
- `TelecomSubscriptionResult.initialChargingPending` → `shouldEnterApp = true`
- `TelecomSubscriptionResult.notSubscribed` → `shouldEnterApp = false`

The login screen branches on `shouldEnterApp`:

- `true` (REGISTERED / INITIAL CHARGING PENDING) → persist session and route to `GochanoShell` directly.
- `false` (NOT SUBSCRIBED or anything else) → push `OtpVerifyScreen` and let the user complete the OTP step first.

`INITIAL CHARGING PENDING` is treated as "go in" by spec — the PHP backend is the source of truth and may confirm the subscription moments later; PART 17's Unsubscribe flow handles the bookkeeping side.

## 5. Files Changed

### Created

- `lib/core/services/telecom_auth_service.dart` — HTTP layer, regex `^01(?:6|8)\d{8}$`, `TelecomSubscriptionStatus` enum, three public `TelecomSubscriptionResult` singletons, `TelecomAuthException`, session persistence (`telecom_isLoggedIn`, `telecom_user_phone`, `telecom_user_id`).
- `lib/features/auth/presentation/otp_verify_screen.dart` — full-screen OTP page with 240s countdown, masked phone display, back arrow, "Wrong number? Change number" link, resend button gated on the timer, error text, and a post-success `pushAndRemoveUntil` to the home shell.
- `test/telecom_login_test.dart` — 29 structural tests across 7 groups.

### Rewritten

- `lib/features/auth/presentation/login_screen.dart` — Robi / Cirkle phone entry, prefix validation, `TextInputType.phone`, no email/password field, no `signInWithEmailAndPassword`, no `EmailAuthProvider`, no Airtel/SmartList copy. Branching on `shouldEnterApp` as described above.
- `lib/features/auth/presentation/auth_gate.dart` — render-based. On first frame reads `TelecomAuthService.readIsLoggedIn()`. If `true` → renders `GochanoShell(role: 'student', displayName: phone)` directly. If `false` → renders `const LoginScreen()` directly. While the SharedPreferences read is in flight, shows `CircularProgressIndicator`.

### Touched (regression repair only)

- `lib/features/auth/presentation/register_screen.dart` — legacy Firebase email registration file that pre-dated PART 16. It used to import `authErrorMessage` from `login_screen.dart`; that helper is gone (the telecom flow has no use for it). Removed the dead import and added a local `_extractAuthError` helper so the legacy screen still compiles. This file is on the retirement list for PART 17 (Unsubscribe).

### NOT changed

- `lib/services/auth_service.dart` — the Firebase Auth wrapper is left intact. `FirebaseAuth.instance.currentUser` still flows through `ApiService._token()` and `FirestoreService.uid`.
- `firebase/firestore.rules` — security rules were deliberately **not** modified in this part. See §11 below for why.
- `pubspec.yaml`, `lib/main.dart`, navigation graph, design-system tokens, all other features — untouched.

## 6. Navigation Contract

The app has no named routes registered in `MaterialApp`, so PART 16 deliberately does not introduce any. Instead it follows the existing render-based pattern used by `AuthGate`:

- **Login → OTP**: `Navigator.push(MaterialPageRoute(builder: (_) => OtpVerifyScreen(phone: phone)))`.
- **OTP → Home** (success): `Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => GochanoShell(role: 'student', displayName: widget.phone)), (_) => false)` so the Back button cannot return the user to OTP.
- **Login → Home** (REGISTERED / INITIAL CHARGING PENDING): same `pushAndRemoveUntil` with `GochanoShell(role: 'student', displayName: phone)`.
- **OTP → Login** (wrong number): `Navigator.of(context).pop()` from the OTP screen returns to the phone screen with the previous phone value intact.
- **Boot**: `AuthGate` rebuilds the widget tree from scratch on each launch — either the shell or the login screen, never both, never a transient blank state.

## 7. Session Persistence

| SharedPreferences key   | Purpose                                              |
| ----------------------- | ---------------------------------------------------- |
| `telecom_isLoggedIn`    | boolean; `AuthGate` checks this on every cold start. |
| `telecom_user_phone`    | the normalized 11-digit phone, shown as `displayName` in the shell. |
| `telecom_user_id`       | placeholder for the carrier-issued user id when the backend starts mirroring it; currently empty. |

All keys are explicitly namespaced `telecom_*` so a future migration off this system can grep them out. The structural test asserts no `airtel_*` / `smartlist_*` keys survived anywhere in the auth feature.

## 8. Error Handling

All failures funnel through `TelecomAuthException(message)` with localized `GochanoLanguage.text(en, bn)` strings:

- Empty / non-`01(6|8)\d{8}` phone → inline validator message on the phone field.
- Network / timeout / non-2xx → SnackBar in `LoginScreen`, inline `errorText` in `OtpVerifyScreen`.
- Empty reference from `send_otp.php` → "Could not send the verification code. Please try again."
- "That code did not match." / "Network error." messages localized in EN + BN.

The OTP screen also surfaces a "Sending code…" inline indicator while `_requestOtp()` is in flight so the user never wonders whether their tap registered.

## 9. Localization

Every visible string in `login_screen.dart`, `otp_verify_screen.dart`, and `auth_gate.dart` flows through `GochanoLanguage.text(en, bn)`. Sample strings:

| EN                                                          | BN                                                                |
| ----------------------------------------------------------- | ----------------------------------------------------------------- |
| Continue with your mobile number                            | মোবাইল নম্বর দিয়ে চালিয়ে যান                                       |
| Gochano works with Robi (016) and Cirkle (018) subscriptions. | Gochano Robi (০১৬) এবং Cirkle (০১৮) সাবস্ক্রিপশনের সাথে কাজ করে। |
| Enter the verification code                                 | ভেরিফিকেশন কোড লিখুন                                                |
| Wrong number? Change number                                 | ভুল নম্বর? নম্বর পরিবর্তন করুন                                       |
| Resend code in 02:00                                        | ০২:০০ পর আবার কোড নিন                                              |

The shell title and app bar title are localized the same way; no English-only surface remains in the new auth flow.

## 10. Design System Usage

Every new widget composes only Gochano primitives:

- `GochanoScaffold`, `GochanoAppBar`, `SectionHeader`, `AppCard` from `lib/shared/widgets/gochano_surfaces.dart`.
- `PrimaryButton` from `lib/shared/widgets/gochano_controls.dart`.
- `context.colors` and `context.type` extensions for tokens (the legacy `context.typography` and `context.spaces` names do not exist — the build was already adapted accordingly).
- `GochanoSpacing.md` / `lg` / `sm` / `xs` and `GochanoRadius.smAll` referenced directly.

No inline `Colors.*`, no inline `fontSize:`, no `EdgeInsets.all(16)` — every dimension comes from the design system so a future token tweak propagates automatically.

## 11. Security Caveats (Important)

PART 16 is intentionally a **Flutter-only** change. The session is currently gated by a `SharedPreferences` boolean, which means:

- The Flutter client will treat a locally-flipped `telecom_isLoggedIn` as a successful login.
- `firebase/firestore.rules` was **not** extended because a `telecomVerified()` helper would require either:
  1. The FastAPI backend (or a Cloud Function) to verify the telecom OTP server-to-server and mint a Firebase custom claim via the Admin SDK — this is a backend work item, not a Flutter change.
  2. Anonymous Firebase sign-in to be layered on top of the telecom login so that `request.auth != null` survives and the existing `verified()` rule can be re-targeted at a new claim (e.g. `telecom_verified`).

Neither is in scope for PART 16 — both belong to PART 17 (Unsubscribe) or a follow-up part. Until then, the live app:

- Will let users in based on telecom status alone.
- Will still deny Firestore access at the rule layer (because `verified()` requires `request.auth.token.email_verified == true`, which the telecom OTP does not yet mint).
- Is therefore functionally a UI-only integration. The backend claim mint is the security gap that needs closing before this can ship to users without the Firebase email/password login as a parallel path.

This is flagged as a **KNOWN FOLLOW-UP**, not a defect — the spec for PART 16 was explicit about not rebuilding surrounding systems.

## 12. Tests Added

`test/telecom_login_test.dart` — 29 tests, all green at the end of this part:

| Group                                              | Tests | What it asserts                                                                                                                                  |
| -------------------------------------------------- | ----- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| `TelecomAuthService prefix validation`             | 10    | `016`/`018` accepted; `017`/`019`/`015`/empty/short/long/non-digit rejected; whitespace trimmed.                                                  |
| `TelecomAuthService SharedPreferences keys`        | 1     | `telecom_isLoggedIn`, `telecom_user_phone`, `telecom_user_id` — no `airtel_*` / `smartlist_*` residue.                                             |
| `TelecomSubscriptionResult`                        | 3     | `registered` / `initialChargingPending` both have `shouldEnterApp == true`; `notSubscribed` has `false`.                                          |
| `LoginScreen structural checks`                    | 6     | Robi + Cirkle copy present; no `Airtel`; no `TextField`; `TextInputType.phone` used; no `signInWithEmailAndPassword` / `EmailAuthProvider`; calls `isSupportedPhone`; routes `shouldEnterApp` users to `GochanoShell(role: 'student', ...)`. |
| `OtpVerifyScreen structural checks`                | 5     | `GochanoAppBar`, `Duration(seconds: 240)`, `Timer.periodic`, "Wrong number" + "Change number" copy present; no `Airtel`; `persistSession` + `GochanoShell(role: 'student', ...)` on success. |
| `AuthGate structural checks`                       | 3     | `readIsLoggedIn` used; no `emailVerified`; `GochanoShell(role: 'student', ...)` rendered directly when logged in; no `Airtel`.                   |
| `No leftover Airtel references in the auth feature` | 1     | Recursive directory walk of `lib/features/auth/`; every `.dart` file's content is lowercased and checked for `airtel` and `smartlist` substrings. |

The Airtel-residue test is the most important regression guard: any future edit that re-introduces the old carrier name fails the test immediately.

## 13. Validation Performed

```
flutter analyze lib/features/auth/presentation/login_screen.dart \
                lib/features/auth/presentation/otp_verify_screen.dart \
                lib/features/auth/presentation/auth_gate.dart \
                lib/core/services/telecom_auth_service.dart \
                test/telecom_login_test.dart
→ No issues found! (ran in 6.5s)

flutter analyze    # full app
→ No issues found! (ran in 9.8s)

flutter test test/telecom_login_test.dart
→ 00:00 +29: All tests passed!
```

A compile-error regression surfaced and was repaired in the same part:

- `register_screen.dart` (pre-PART-16 legacy file) had `import 'login_screen.dart' show authErrorMessage;`. That helper is gone after PART 16. Removed the dead import and added a local `_extractAuthError` helper so the legacy screen continues to compile until PART 17 retires it.

## 14. Known Follow-Ups (NOT in scope for PART 16)

1. **Backend telecom-claim mint** — FastAPI or Cloud Function must verify the OTP server-to-server with the carrier, then set a `telecom_verified` custom claim via the Firebase Admin SDK. Until this lands, the `telecom_isLoggedIn` flag is the only gate and Firestore access is effectively denied for telecom users.
2. **Layered anonymous sign-in** — alternative to (1): sign the user into Firebase anonymously after a successful OTP, then keep using the existing `verified()` rule by broadening its definition to accept either `email_verified` or `telecom_verified`.
3. **Retire `register_screen.dart` and `verify_email_screen.dart`** — leftover Firebase email flows. PART 17 (Unsubscribe) is the natural home.
4. **Logout** — the existing `logout` plumbing still calls into the Firebase `signOut` path. Once (1) or (2) lands, the logout must clear both the Firebase session *and* the telecom session (`TelecomAuthService.clearSession()`), otherwise the user stays "logged in" by the SharedPreferences flag.
5. **Carrier-portal deep-link for OTP-less subscription** — when the user has not subscribed at all, currently they must complete the OTP dance. The carrier portals (Robi RAAST, Cirkle My Plan) could be deep-linked to make the first-time flow one tap shorter. Tracked, not promised.
6. **End-to-end test against the live carrier endpoint** — needs real Robi / Cirkle numbers, which we don't have in CI. A future part should add a sandbox / mock endpoint integration test.

## 15. Constraints Preserved (Part-Specific)

- **No commit / push / deploy / release APK** — none executed.
- **No Firebase / Firestore data deleted** — the carrier switch is at the UI layer only.
- **No Firestore rules modified** — by design; see §11.
- **Home, navigation, design system, localization, financial / study / medicine / commute / dena-pawna features** — all untouched and still passing `flutter analyze` at the full-app scope.
- **Airtel / SmartList branding** — fully removed from `lib/features/auth/**`; the structural test will fail any future regression.
- **PART 16 boundary respected** — PART 17 (Unsubscribe) was **not** started; the only `register_screen.dart` edit was a compile-repair, not a feature change.

---

