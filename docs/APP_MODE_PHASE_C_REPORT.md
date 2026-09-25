# Gochano App Mode Switching — Phase C Verification Report

> **Feature**: App Mode Switching — Phase C (Dynamic Shell & Navigation Adapter)  
> **Status**: Completed & Verified  
> **Date**: 2026-09-25  
> **Author**: Google DeepMind / Antigravity Agent  

---

## 1. Files Changed

1. **`flutter_app/lib/core/settings/gochano_app_mode.dart`** (MODIFIED)
   - Added `isDiscovered()` and `markDiscovered()` helper methods backed by local `SharedPreferences` with storage key `gochano.appMode.discovered`.
   - Allows lightweight, non-blocking discovery tracking for the new Study vs Utility modes without adding backend dependencies.

2. **`flutter_app/lib/features/shell/presentation/gochano_shell.dart`** (MODIFIED)
   - Replaced static 5-destination list with dynamic navigation adapter reacting directly to `GochanoAppModePreferences.current`.
   - Integrated automatic index-reset safety on mode switch (`_index = 0` / Today) preventing any `RangeError` (e.g. switching from Study index 4 to Utility mode which has 4 items, indices 0..3).
   - Implemented `_buildDestinations(mode)` for:
     - **Study Mode**: `Today | Workspace | Plan | Community | Profile` (5 items)
     - **Utility Mode**: `Today | Commute | Money | Profile` (4 items)
     - **General Accounts**: `Home | Life | Tasks | Profile` (4 items)
   - Implemented `_buildPages(mode)` with `IndexedStack` preserving state across destination switching within the active mode.
   - Preserved `StudyScreen` in the codebase for canonical deep linking and legacy routes.
   - Added `pagesBuilder` hook on `GochanoShell` to enable isolated widget testing without invoking live uninitialized native Firebase channels.
   - Added `_handleDestinationFromHome` compatibility router to cleanly translate legacy callbacks (e.g., tasks "See All", commute/money card taps) to their correct destinations or canonical pushed routes.
   - Added lightweight post-frame discovery SnackBar with direct action to open `showAppModeSelectorSheet(context)`.

3. **`flutter_app/test/shell_dynamic_navigation_test.dart`** (NEW)
   - 8 comprehensive widget test cases validating destination counts, labels, mode-switching index reset, Profile tab anchoring, repeated switching stability, narrow-device (320dp) Bangla rendering, and discovery notice interactions.

---

## 2. Existing Shell Architecture Found

Prior to Phase C, `GochanoShell` had:
- A fixed bottom navigation bar: `Today | Study | Commute | Money | Profile` for student accounts.
- `HomeScreen` mounted at index 0, followed by `StudyScreen` (which contained tab bars for Workspace, Plan, Community), `CommuteScreen`, `ExpenseScreen`, and `ProfileScreen`.
- Navigation state persisted using `IndexedStack`.
- Callbacks from `HomeScreen` invoked `_select(int index)` with hardcoded index numbers (`1` for Study, `2` for Commute, `3` for Money).

---

## 3. Mode-Listening Implementation

`GochanoShell` subscribes directly to `GochanoAppModePreferences.current` inside `initState`:
```dart
GochanoAppModePreferences.current.addListener(_onAppModeChange);
```
And cleans up the listener in `dispose()`:
```dart
GochanoAppModePreferences.current.removeListener(_onAppModeChange);
```
No external state management frameworks (Provider, Riverpod, Bloc, GetX) were introduced. The implementation follows the established lightweight `ValueNotifier` pattern of `GochanoLanguage` and `GochanoAppearance`.

---

## 4. Study Mode Destination Mapping

When `GochanoAppModePreferences.current.value == GochanoAppMode.study`:
- Destinations (5):
  1. `Today` (`Icons.home_outlined` / `Icons.home_rounded`)
  2. `Workspace` (`Icons.menu_book_outlined` / `Icons.menu_book_rounded`)
  3. `Plan` (`Icons.calendar_today_outlined` / `Icons.calendar_today_rounded`)
  4. `Community` (`Icons.people_outline_rounded` / `Icons.people_rounded`)
  5. `Profile` (`Icons.person_outline_rounded` / `Icons.person_rounded`)
- Page Stack (5):
  1. `HomeScreen`
  2. `WorkspaceView`
  3. `PlanView`
  4. `CommunityView`
  5. `ProfileScreen`

---

## 5. Utility Mode Destination Mapping

When `GochanoAppModePreferences.current.value == GochanoAppMode.utility`:
- Destinations (4):
  1. `Today` (`Icons.home_outlined` / `Icons.home_rounded`)
  2. `Commute` (`Icons.directions_transit_outlined` / `Icons.directions_transit_rounded`)
  3. `Money` (`Icons.account_balance_wallet_outlined` / `Icons.account_balance_wallet_rounded`)
  4. `Profile` (`Icons.person_outline_rounded` / `Icons.person_rounded`)
- Page Stack (4):
  1. `HomeScreen`
  2. `CommuteScreen`
  3. `ExpenseScreen`
  4. `ProfileScreen`

---

## 6. General Account Handling

Accounts with role != `'student'` continue to show:
- `Home | Life | Tasks | Profile` (4 destinations)
- Preserving existing production security restrictions (`require_student`).

---

## 7. Profile Tab Anchoring

`ProfileScreen` is guaranteed to be the final destination in all modes:
- In Study Mode: Index 4 (out of 0..4).
- In Utility Mode: Index 3 (out of 0..3).
- In General Mode: Index 3 (out of 0..3).
Tests explicitly assert that `navBar.destinations.last.label == 'Profile'`.

---

## 8. Mode Switch Index-Reset Safety

When a user switches modes:
```dart
void _onAppModeChange() {
  if (mounted) {
    setState(() {
      _index = 0; // Safely reset to Today/Home to prevent out-of-range errors
    });
  }
}
```
Furthermore, `_index.clamp(0, destinations.length - 1)` is used as a safety rail in `build()`. This guarantees that if a user is on Profile (index 4) in Study Mode and switches to Utility Mode (max index 3), no `RangeError` is possible.

---

## 9. Backward Compatibility & Deep Linking

- `StudyScreen` remains in `lib/features/study/presentation/study_screen.dart` without deletion for legacy routes and deep link dispatchers.
- `_handleDestinationFromHome`: Legacy index-based navigation requests from `HomeScreen` cards are translated appropriately:
  - If in Study Mode and index 2 (Commute) or 3 (Money) is tapped from Home, it pushes `CommuteScreen` or `ExpenseScreen` onto the Navigator stack.
  - If in Utility Mode and index 1 (Study) is tapped from Home, it pushes `WorkspaceView`.

---

## 10. One-Time Mode Discovery

- Backed by `GochanoAppModePreferences.isDiscovered()` and `markDiscovered()`.
- Shown on first load after bootstrap using a floating SnackBar with action `Explore` that opens `showAppModeSelectorSheet(context)`.
- Non-blocking and dismissible.

---

## 11. Localization Verification

Both English and Bangla labels are supported:
- **Study Mode**:
  - `Today` / `আজ`
  - `Workspace` / `ওয়ার্কস্পেস`
  - `Plan` / `পরিকল্পনা`
  - `Community` / `কমিউনিটি`
  - `Profile` / `প্রোফাইল`
- **Utility Mode**:
  - `Today` / `আজ`
  - `Commute` / `যাতায়াত`
  - `Money` / `টাকা`
  - `Profile` / `প্রোফাইল`
Verified with physical size constrained to 320dp width without text clipping or overflow.

---

## 12. Dart Format Result

Executed `dart format lib/features/shell/presentation/gochano_shell.dart lib/core/settings/gochano_app_mode.dart test/shell_dynamic_navigation_test.dart`.
All files formatted cleanly.

---

## 13. Test Suite Executed

Test File: `flutter_app/test/shell_dynamic_navigation_test.dart`
8/8 test cases passed:
1. `renders Study Mode 5 destinations by default`
2. `renders Utility Mode 4 destinations when active`
3. `switching Study -> Utility resets selection to index 0 and avoids RangeError`
4. `switching Utility -> Study resets selection to index 0`
5. `repeated mode switching is stable without leaked errors`
6. `Profile is the final destination in both modes`
7. `Bangla labels render correctly without overflow on narrow width (320dp)`
8. `One-time discovery banner shows when undiscovered, and can be dismissed/marked`

---

## 14. Phase A Regression Result

Command: `flutter test test/app_mode_test.dart`
- **Result**: **12/12 passed** (100% PASS).

---

## 15. Phase B Regression Result

Command: `flutter test test/profile_app_mode_selector_test.dart`
- **Result**: **7/7 passed** (100% PASS).

---

## 16. Phase C Test Result

Command: `flutter test test/shell_dynamic_navigation_test.dart`
- **Result**: **8/8 passed** (100% PASS).
- Combined all App Mode suites (`app_mode_test.dart`, `profile_app_mode_selector_test.dart`, `shell_dynamic_navigation_test.dart`): **27/27 passed**.

---

## 17. Flutter Analyze Result

Command: `flutter analyze lib/features/shell/presentation/gochano_shell.dart lib/core/settings/gochano_app_mode.dart test/shell_dynamic_navigation_test.dart`
- **Result**: **No issues found!** (0 errors, 0 warnings, 0 lints).

---

## 18. APK Build Result

Command: `flutter build apk --debug`
- **Result**: **SUCCESS**
  `Built build\app\outputs\flutter-apk\app-debug.apk` (built in 111.0s).

---

## 19. Git Diff Check Result

- `git diff --check`: Clean (0 whitespace errors).
- Clean separation of concerns with 0 changes to backend, Firestore rules, or models.

---

## 20. Remaining Risk or Deferred Issues

- `HomeScreen` content filtering is intentionally untouched (deferred to Phase D).
- `quick_add_sheet.dart` filtering is intentionally untouched (deferred to Phase E).
- No blocking issues or architecture risks identified.

---

## Conclusion

PHASE C: PASS
