# Gochano App Mode Switching — Phase E Implementation Report

**Status:** Complete
**Date:** 2026-09-26
**Auditor:** Pair Programming Agent

---

## 1. Files Changed
- `lib/features/shell/presentation/quick_add_sheet.dart` (Mode filtering logic, dynamic action list composition)
- `test/quick_add_mode_filtering_test.dart` (New focused Phase E test suite, 13 test cases)
- `docs/APP_MODE_PHASE_E_REPORT.md` (This documentation report)

*Note: No changes to `gochano_shell.dart`, `home_screen.dart`, backend, Firestore rules, or data services were required.*

---

## 2. Existing Quick Add Architecture Discovered
- `QuickAddAction` is an enum defining 6 canonical actions: `task`, `assignment`, `expense`, `medicine`, `planTrip`, `note`, with a backward-compatibility alias `trip = QuickAddAction.planTrip`.
- `QuickAddSheet` is a pure UI bottom sheet coordinator without database persistence, auth logic, or direct service invocation.
- `showQuickAddSheet(context)` opens the modal sheet and returns the selected `QuickAddAction?`.
- `launchQuickAddAction(context, action)` receives the selected action and dispatches to canonical creation flows (`showAddTaskSheet`, `showAddExpenseSheet`, `MedicineFormScreen`, `showPlanTripSheet`, `NoteEditorScreen`).
- In `GochanoShell`, only student accounts (`_isStudent`) show the Universal Quick Add FAB.
- Prior regression tests (`universal_quick_add_test.dart` and `physical_defects_regression_test.dart`) enforce strict architecture purity guards and verify that `QuickAddSheet` renders smoothly under 320dp and 2.0x font scaling.

---

## 3. Study Mode Visible Action List
When `GochanoAppModePreferences.current.value == GochanoAppMode.study`:
Exactly 3 primary actions are surfaced:
1. **Task** (`QuickAddAction.task`) — `_QuickAddCard` with icon `Icons.check_circle_outline_rounded`, title: 'Task' / 'কাজ'
2. **Assignment** (`QuickAddAction.assignment`) — `_QuickAddCard` with icon `Icons.assignment_outlined`, title: 'Assignment' / 'অ্যাসাইনমেন্ট'
3. **Note** (`QuickAddAction.note`) — `_QuickAddCard` with icon `Icons.edit_note_rounded`, title: 'Note' / 'নোট'

Excluded from Study Mode:
- Expense (hidden)
- Plan Trip (hidden)
- Medicine (hidden)

---

## 4. Utility Mode Visible Action List
When `GochanoAppModePreferences.current.value == GochanoAppMode.utility`:
Exactly 2 primary actions are surfaced:
1. **Expense** (`QuickAddAction.expense`) — `_QuickAddCard` with icon `Icons.account_balance_wallet_outlined`, title: 'Expense' / 'খরচ'
2. **Plan Trip** (`QuickAddAction.planTrip`) — `_QuickAddCard` with icon `Icons.departure_board_rounded`, title: 'Plan Trip' / 'যাত্রা পরিকল্পনা'

Excluded from Utility Mode:
- Task (hidden)
- Assignment (hidden)
- Note (hidden)
- Medicine (hidden)

---

## 5. Hidden-But-Preserved Actions
- **Medicine** (`QuickAddAction.medicine`), **Expense** (`QuickAddAction.expense`), **Plan Trip** (`QuickAddAction.planTrip`), **Task** (`QuickAddAction.task`), **Assignment** (`QuickAddAction.assignment`), and **Note** (`QuickAddAction.note`) remain fully defined in `QuickAddAction`.
- None of the action handlers or routes were deleted from the application.
- Filtering is implemented strictly at the presentation layer.

---

## 6. Dispatcher Preservation
In `launchQuickAddAction(...)`:
- All 6 cases (`task`, `assignment`, `expense`, `medicine`, `planTrip`, `note`) remain completely implemented and intact.
- Even when Medicine is hidden from the primary mode-filtered sheet, `launchQuickAddAction(context, QuickAddAction.medicine)` remains functional for deep links, notifications, shortcuts, and direct screen routes.

---

## 7. General / Non-Student Behavior
- When `QuickAddSheet` is rendered without a specific mode (`mode == null`), such as in unconstrained or general-role views:
  - All 6 canonical actions (Task, Assignment, Expense, Medicine, Plan Trip, Note) are rendered in their standard 2-column grid.
  - Existing regression tests in `test/physical_defects_regression_test.dart` and `test/universal_quick_add_test.dart` remain 100% compliant.

---

## 8. Localization Behavior
- Reuses `GochanoLanguage.text(...)` and Bengali translations:
  - Task: 'Task' / 'কাজ'
  - Assignment: 'Assignment' / 'অ্যাসাইনমেন্ট'
  - Note: 'Note' / 'নোট'
  - Expense: 'Expense' / 'খরচ'
  - Plan Trip: 'Plan Trip' / 'যাত্রা পরিকল্পনা'
  - Medicine: 'Medicine' / 'ওষুধ'
- Labels wrap and fit without truncation or overflow in both English and Bengali.

---

## 9. Responsive Layout Behavior
- Evaluated on 320dp, 360dp, and with 2.0x font scaling:
  - Study Mode: Row 1 has Task + Assignment; Row 2 has full-width Note.
  - Utility Mode: Row 1 has Expense + Plan Trip.
  - No `RenderFlex` overflow on narrow viewports (320dp width).

---

## 10. Mode Switching Behavior
- `showQuickAddSheet(context)` dynamically inspects `GochanoAppModePreferences.current.value` on every invocation.
- If the user switches modes (e.g., Study -> Utility) in Profile Settings and returns to Today, tapping the Quick Add FAB immediately displays the updated mode's action set.
- Switching back immediately restores the previous set without any stale cached action state.

---

## 11. Action-Launch Verification
- Tapping Task dispatches `QuickAddAction.task` -> opens `showAddTaskSheet(type: 'task')`.
- Tapping Assignment dispatches `QuickAddAction.assignment` -> opens `showAddTaskSheet(type: 'assignment')`.
- Tapping Note dispatches `QuickAddAction.note` -> opens `NoteEditorScreen()`.
- Tapping Expense dispatches `QuickAddAction.expense` -> opens `showAddExpenseSheet()`.
- Tapping Plan Trip dispatches `QuickAddAction.planTrip` -> opens `showPlanTripSheet()`.
- Sheet closes via `Navigator.pop(action)` prior to launcher execution.

---

## 12. Tests Added
`test/quick_add_mode_filtering_test.dart` added covering 13 test scenarios:
1. Study Mode shows exactly Task, Assignment, Note
2. Study Mode returns canonical `QuickAddAction` on tap
3. Utility Mode shows exactly Expense, Plan Trip
4. Utility Mode returns canonical `QuickAddAction` on tap
5. General / non-student role (`mode == null`) shows all 6 canonical actions
6. `showQuickAddSheet` dynamically reflects active preference mode across switches
7. Repeated mode switching has no stale cached action list
8. Study Mode 320dp responsive layout verification
9. Utility Mode 320dp responsive layout verification
10. 2.0x font scaling without overflow
11. Bangla localization in Study Mode without overflow
12. Bangla localization in Utility Mode without overflow
13. Canonical action dispatch preservation for all 6 actions

---

## 13. Phase A Regression Result
- `test/app_mode_test.dart`: **PASS** (100% passing)

---

## 14. Phase B Regression Result
- `test/profile_app_mode_selector_test.dart`: **PASS** (100% passing)

---

## 15. Phase C Regression Result
- `test/shell_dynamic_navigation_test.dart`: **PASS** (10/10 tests passing)

---

## 16. Phase D Regression Result
- `test/home_rebuild_test.dart`: **PASS**
- `test/home_mode_filtering_test.dart`: **PASS** (9/9 tests passing)
- `test/home_today_overdue_test.dart`: **PASS**

---

## 17. Phase E Test Result
- `test/quick_add_mode_filtering_test.dart`: **PASS** (13/13 tests passing)
- `test/physical_defects_regression_test.dart`: **PASS** (28/28 tests passing)
- Combined full regression suite: **114/114 tests passing**

---

## 18. Flutter Analyze Result
```
Analyzing lib...
No issues found! (ran in 127.8s)
Exit Code: 0
```

---

## 19. Git Diff Check Result
```
git diff --check
Exit Code: 0 (No whitespace errors, clean line endings)
```

`git diff --stat`:
```
lib/features/shell/presentation/quick_add_sheet.dart | 219 ++++++++++++---------
1 file changed, 123 insertions(+), 96 deletions(-)
```

---

## 20. APK Build Result
```
Running Gradle task 'assembleDebug'...                            298.7s
√ Built build\app\outputs\flutter-apk\app-debug.apk
Exit Code: 0
```

---

## 21. Remaining Issues / Deferred Work
- None for Phase E. All Phase E requirements have been implemented and verified.
- Phase F (Final Hardening) remains deferred for subsequent phase.

---

PHASE E: PASS
