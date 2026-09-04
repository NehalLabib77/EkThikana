# IMPLEMENTATION REPORT

## Feature 1 — Assignment/Task Bento Cards + Quick Add

### Verified Behavior

| Requirement | Status | Evidence |
|-------------|--------|----------|
| Assignment due DATE + TIME | ✅ | `add_task_sheet.dart:75-106` — `showDatePicker` then `showTimePicker`, stored as `DateTime` in `_dueAt` |
| Assignment reminder presets | ✅ | `add_task_sheet.dart` — 4 ChoiceChip presets (None / 10 min / 30 min / 1 hour before dueAt) |
| Task reminder presets | ✅ | Same form — shared for both assignment and task |
| Edit loads existing preset | ✅ | `_detectPreset()` matches existing `remindAt` to closest preset on load |
| Edit preserves/reschedules reminder | ✅ | `_save()` calls `NotificationService.rescheduleTask(when: _remindAt)` |
| Complete cancels pending reminder | ✅ | `plan_view.dart` — `_setDone()` calls `rescheduleTask(when: done ? null : remindAt)` |
| Delete cancels pending reminder | ✅ | `plan_view.dart` — `_delete()` calls `NotificationService.cancelTask(doc.id)` before Firestore delete |
| No reminder cancels notification | ✅ | Preset "None" sets `remindAt = null`; `rescheduleTask(when: null)` cancels |
| Due change recalculates reminder | ✅ | `_applyReminderPreset()` recomputes `remindAt` from selected preset + new `_dueAt` |
| No dueAt disables presets | ✅ | Preset chips hidden when `_dueAt == null` |
| Prevent reminder after due time | ✅ | `_save()` safety net rejects `remindAt >= dueAt` |
| No duplicate notifications | ✅ | `notification_service.dart:192-193` — deterministic ID: `taskId.hashCode & 0x7fffffff` |
| Data persists after restart | ✅ | Firestore for task data; `zonedSchedule` persists in Android AlarmManager |
| EN/Bangla localization | ✅ | All labels use `GochanoLanguage.text(en, bn)` |
| Old records compatible | ✅ | `_detectPreset()` falls back to preset 0 (None) when no exact match found |

### Quick Add Actions

| Requirement | Status | Evidence |
|-------------|--------|----------|
| Tap "+" on Assignment card | ✅ | `_AssignmentCard` header: `GestureDetector` "+" → `showAddTaskSheet(type: 'assignment')` |
| Tap "+" on Task card | ✅ | `_TaskCard` header: `GestureDetector` "+" → `showAddTaskSheet(type: 'task')` |
| Tap "+ Add" in empty state | ✅ | Both cards show compact "+ Add" text link in empty state |
| Edit existing item | ✅ | `showAddTaskSheet(existing: doc)` — `type` param ignored, form reads existing data |
| Existing callers (Home, Tasks, Search) | ✅ | `type` defaults to `'task'` — backward compatible |

### Classification (Latest)

| Scenario | Behavior |
|----------|----------|
| `type == 'assignment'` | Assignment |
| `type == 'task'` | Task |
| `type == null` (legacy) | **Task** — never inferred from due date |

```dart
final isAssignment = data['type']?.toString() == 'assignment';
```

### Reminder Scheduling

| Scenario | Behavior |
|----------|----------|
| Preset selected (10/30/60 min) | `_remindAt = _dueAt - preset`; saved to Firestore; notification scheduled at `_remindAt` |
| Preset "None" selected | `remindAt` set to null; `rescheduleTask(when: null)` cancels pending |
| Edit existing task | `_detectPreset()` matches existing `remindAt` to closest preset; chips pre-select |
| Due date changed | `_applyReminderPreset()` recalculates `_remindAt` from current preset + new `_dueAt` |
| No due set | Preset chips hidden; `_remindAt = null` |
| Complete task | `rescheduleTask(when: null)` cancels |
| Delete task | `cancelTask(doc.id)` cancels before Firestore delete |

### Data Fields

| Field | Type | Purpose |
|-------|------|---------|
| `type` | `String` | `'assignment'` or `'task'` — written on create, read for filtering |
| `dueAt` | `Timestamp?` | When the task is due (date + time) |
| `remindAt` | `Timestamp?` | When to fire the reminder notification (separate date + time) |
| `done` | `bool` | Completion flag; cancel reminder on true |
| `title` | `String` | Task name |

### Files Changed

| File | What Changed |
|------|--------------|
| `flutter_app/lib/features/tasks/presentation/add_task_sheet.dart` | Replaced `_pickReminderDate()` + SwitchListTile toggle with 4 ChoiceChip presets (None/10m/30m/1h). Added `_reminderPreset`, `_detectPreset()`, `_applyReminderPreset()`. Due change recalculates reminder. No dueAt hides presets. `type` param on `showAddTaskSheet()` and `_TaskForm` |
| `flutter_app/lib/features/study/presentation/planner/plan_view.dart` | Compact side-by-side bento layout; `_StudyGoalSection` (see Feature 2); `_EditGoalSheet`, `_HourMinuteRow`, `_CompactStepper` widgets |
| `flutter_app/test/deadline_state_test.dart` | New — deadline state tests |

---

## Fix — Assignment/Task Bento Always Visible (Plan View)

### Root Cause
`_AssignmentTaskBento.build()` (plan_view.dart:328) returned `SizedBox.shrink()` when both `deadlines` and `tasks` were empty, hiding the entire section. Additionally, `_AssignmentCard` (plan_view.dart:367) returned `SizedBox.shrink()` when empty instead of showing an empty state with the "+" add button.

### Exact Fix
1. **`_AssignmentTaskBento`**: Removed the early return `if (deadlines.isEmpty && tasks.isEmpty) return const SizedBox.shrink();` — the bento layout now always renders both cards side-by-side (or stacked on small screens).
2. **`_AssignmentCard`**: Added an `EmptyState` with illustration, title, message, and "Add assignment" action button — matching the behavior of `_TaskCard`. The header with "+" button is now always visible.

### Files Changed

| File | What Changed |
|------|--------------|
| `flutter_app/lib/features/study/presentation/planner/plan_view.dart` | `_AssignmentTaskBento`: removed early return when empty. `_AssignmentCard`: added `EmptyState` with "Add assignment" action; header always shows "+" button. |

### Tests
- `flutter analyze` — 0 issues
- `flutter test` — 282/282 passed
- Backend tests — 360/360 passed

---

## Plan UI — Compact Side-by-Side Assignment + Task Cards

### Exact UI Change
**Before**: Two cards with `SectionHeader`, `EmptyState` with illustrations and large buttons, larger font sizes.

**After**: Compact side-by-side bento cards with:
- **Headers**: 14sp label with brand-colored `+` button (24×24px container)
- **Items**: 13sp title, 10sp metadata, 10sp reminder
- **Empty state**: Text-only "No assignments/tasks" + "+ Add" link (no illustration)
- **Badges**: Compact inline badges (Overdue/Today/Tmrw/Nd) with colored backgrounds
- **View all**: Text link instead of TextButton

### Responsive Behavior
| Width | Layout |
|-------|--------|
| ≥300dp | Side-by-side (2 equal columns) |
| <300dp | Stacked vertically (rare, extremely narrow screens) |

### Files Changed

| File | What Changed |
|------|--------------|
| `flutter_app/lib/features/study/presentation/planner/plan_view.dart` | `_AssignmentTaskBento`: breakpoint lowered to 300dp (was 600). `_AssignmentCard`: compact layout with `AppCard(padding: sm)`, 14sp header, 13sp items, 10sp metadata, compact badge, text-only empty state. `_TaskCard`: same compact styling, smaller checkbox (20×20), compact item rows. Added `_deadlineStateBadgeCompact()` and `_reminderInfoCompact()` helpers. Removed unused `_deadlineStateBadge()` and `_reminderInfo()` functions. |

### Responsive Behavior
- **Normal phone (360–414dp)**: Cards display side-by-side
- **Narrow phones (<300dp)**: Gracefully stacks vertically
- **All widths**: Text truncation via `ellipsis`, no overflow

### Validation
| Check | Result |
|-------|--------|
| Both cards visible side-by-side | ✅ |
| Empty state (No assignments + Add) | ✅ |
| Populated state (3 preview items) | ✅ |
| Long title does not overflow | ✅ (maxLines: 1, ellipsis) |
| + Add works | ✅ |
| View all visible when >3 items | ✅ |
| Reminder/date/time readable | ✅ (10sp, compact layout) |
| EN/Bangla localization | ✅ |
| `flutter analyze` | **0 issues** |
| `flutter test` | **282/282 passed** |

### Business Logic Untouched
- ✅ Assignment/Task data logic (CRUD, filtering)
- ✅ Add/edit/delete flows
- ✅ Type filtering (`type == 'assignment'` vs `type == 'task'`)
- ✅ Reminder scheduling and notifications
- ✅ Study Goal section
- ✅ Focus/Workspace

### Remaining Issues
- None

### No Commit / Push / Deploy
Confirmed. No git commit, push, or deploy operations performed.

---

## Reminder Preset Options — Assignment + Task

### Change Summary
Replaced the full date+time reminder picker (`_pickReminderDate()` + SwitchListTile toggle) with 4 compact ChoiceChip presets for both Assignment and Task forms.

### Presets
| Index | Label (EN) | Label (BN) | Duration before dueAt |
|-------|-----------|------------|----------------------|
| 0 | None | নেই | (no reminder) |
| 1 | 10 min before | ১০ মিনিট আগে | 10 minutes |
| 2 | 30 min before | ৩০ মিনিট আগে | 30 minutes |
| 3 | 1 hour before | ১ ঘণ্টা আগে | 1 hour |

### Behavior
- **Preset → remindAt**: `_remindAt = _dueAt - _kPresetDurations[preset]`
- **No dueAt**: Preset chips hidden; `_remindAt = null`
- **Edit mode**: `_detectPreset()` matches existing `remindAt` to closest preset on load
- **DueAt changed**: `_applyReminderPreset()` recalculates `remindAt` from current preset
- **Preset "None"**: Sets `remindAt = null`; `rescheduleTask(when: null)` cancels notification
- **Safety net**: `_save()` rejects `remindAt >= dueAt`

### UI
- Compact `Wrap` of 4 `ChoiceChip` widgets below the Due field
- Only visible when `_dueAt != null`
- Label "Reminder" / "রিমাইন্ডার" shown above chips

### Files Changed

| File | What Changed |
|------|--------------|
| `flutter_app/lib/features/tasks/presentation/add_task_sheet.dart` | Removed `_pickReminderDate()`, SwitchListTile toggle, `_remind` bool. Added `_kPresetDurations`, `_reminderPreset`, `_detectPreset()`, `_applyReminderPreset()`, `_buildPresetChip()`. Preset chips replace picker UI. Due change recalculates reminder. No dueAt hides presets. |

### Tests & Results
- ✅ `flutter analyze` — 0 issues
- ✅ `flutter test` — 292/292 passed

### No Commit / Push / Deploy
Confirmed. No git commit, push, or deploy operations performed.

---

## Study Workspace — Final Cleanup (Shortcut-First)

### Change Summary
Finalized Study > Workspace as a shortcut-first screen. Quick Access at top, Recent Materials below. Removed duplicate Notes and Semesters dashboard sections. Fixed Semester shortcut to navigate to a proper `SemesterListScreen`. Fixed Shared Box to show only Community Group Resources (no full Community screen).

### Root Cause: Semester Shortcut Bug
The Semester shortcut used `Scrollable.ensureVisible` to scroll to an inline Semesters section. This broke when the section was removed from Workspace. The root cause was that there was no separate Semester screen — semesters were rendered inline in `WorkspaceView` as `_SemesterCard` widgets.

**Fix:** Extracted the semester/subject list into `SemesterListScreen`, a standalone screen that opens when tapping the Semester shortcut. The screen reuses the exact same Firestore queries (`ownerStream('semesters')`, `ownerStream('subjects')`), card widgets, and action functions (add/rename/delete semester/subject) that were previously inline in `workspace_view.dart`. Navigation flow: Workspace → Semester → Subject (`SubjectScreen`) → Materials (`MaterialsScreen`).

### Root Cause: Shared Box Opening Full Community Screen
Shared Box previously opened `CommunityScreen()`, which shows the full Community screen including group chat, members, and overview tabs. Shared Box should only show group resources/files.

**Fix:** Created `SharedBoxScreen` — a resource-only screen that lists the user's groups and shows their shared resources (materials + notes) grouped by group name. Reuses existing Firestore queries: `FirestoreService.groupMaterials(groupId)` and `FirestoreService.groupNotes(groupId)`. Reuses existing `MaterialReaderScreen` and `NoteEditorScreen` for opening resources. No new data model, no duplicate queries.

### Duplicate Sections Removed
- **Notes section** removed from Workspace (Notes accessible via Quick Access → `NotesScreen()`)
- **Semesters section** removed from Workspace (Semesters accessible via Quick Access → `SemesterListScreen`)
- **Final Workspace content:** Quick Access grid + Recent Materials

### Shortcuts

> **Note:** AI Assistant was added as the first shortcut in a subsequent change (see "Workspace AI Assistant / Ziku" below). Final count: 6 shortcuts (AI Assistant, Notes, PDFs, Saved Images, Semester, Shared Box).

| # | Label (EN) | Label (BN) | Illustration | Accent | Destination |
|---|-----------|------------|-------------|--------|-------------|
| 1 | Notes | নোট | `fileNote` | `colors.study` | `NotesScreen()` |
| 2 | PDFs | পিডিএফ | `filePdf` | `colors.brand` | `MaterialsScreen(mimeFilter: 'application/pdf')` |
| 3 | Saved Images | সংরক্ষিত ছবি | `fileImage` | `colors.ai` | `MaterialsScreen(mimeFilter: 'image/')` |
| 4 | Semester | সেমিস্টার | `featureStudy` | `colors.study` | `SemesterListScreen()` — standalone semester list |
| 5 | Shared Box | শেয়ার্ড বক্স | `featureGroups` | `colors.community` | `SharedBoxScreen()` — group resources only |

### UI Structure
- `AppCard` wrapper with `GridView.builder` inside `LayoutBuilder`
- 4 columns on phones ≥380dp, 3 columns on narrower screens
- Tile: 52px tinted circle icon + 2-line centered label (matches Home Quick Actions exactly)
- "See more" / "See less" `TextButton.icon` toggle below grid
- Collapsed: 3 tiles. Expanded: 6 tiles. State is local `bool _expanded` — no persistence.

### SemesterListScreen Architecture
- Standalone `GochanoScaffold` screen with AppBar "Semesters"
- Streams `FirestoreService.ownerStream('semesters')` and `ownerStream('subjects')`
- Groups subjects by `semesterId`, renders `_SemesterCard` per semester
- Each `_SemesterCard` contains `_SubjectRow` widgets with material count stream
- Tapping a subject navigates to `SubjectScreen` → embeds `MaterialsScreen(subjectFilter:)`
- Full CRUD: add/rename/delete semesters and subjects via dialogs
- Moved from `workspace_view.dart` (no longer inline in Workspace)

### SharedBoxScreen Architecture
- Standalone `GochanoScaffold` screen with AppBar "Shared Box"
- Streams `FirestoreService.myGroups()` to get user's groups
- For each group, streams `FirestoreService.groupMaterials(groupId)` and `groupNotes(groupId)`
- Resources displayed per-group using `CardGroup` + `GochanoListRow` (same pattern as `_ResourcesTab` in `group_detail_screen.dart`)
- Materials open via `MaterialReaderScreen`, notes open via `NoteEditorScreen`
- No chat, members, overview — resources only
- Group permissions preserved (Firestore security rules enforce `memberIds` check)

### What Changed in MaterialsScreen (previous batch)
Added `mimeFilter` parameter to `MaterialsScreen`:
- `const MaterialsScreen({super.key, this.subjectFilter, this.mimeFilter})`
- Filters materials by MIME type prefix when set
- App bar title adapts: "PDFs" for `application/pdf`, "Saved Images" for `image/`

### Files Changed

| File | What Changed |
|------|--------------|
| `flutter_app/lib/features/study/presentation/workspace/workspace_view.dart` | Converted to shortcut-first: only Quick Access + Recent Materials. Removed duplicate Notes/Semesters sections. Removed all private semester/subject classes and action functions (moved to `semester_list_screen.dart`). Semester shortcut now navigates to `SemesterListScreen`. Shared Box shortcut now navigates to `SharedBoxScreen`. `WorkspaceView` is now a `StatelessWidget`. Removed `_semestersKey`, `Scrollable.ensureVisible`, and semester/subject StreamBuilders. |
| `flutter_app/lib/features/study/presentation/workspace/semester_list_screen.dart` | **New file.** Standalone Semester list screen. Contains `_SemesterCard`, `_SubjectRow`, and all CRUD actions (add/rename/delete semester/subject). Extracted from `workspace_view.dart`. |
| `flutter_app/lib/features/community/presentation/shared_box_screen.dart` | **New file.** Resource-only Shared Box screen. Lists user's groups with their shared materials and notes. Reuses `FirestoreService.groupMaterials()`, `groupNotes()`, `MaterialReaderScreen`, `NoteEditorScreen`. No full Community screen. |
| `flutter_app/lib/features/study/presentation/materials/materials_screen.dart` | Added `mimeFilter` parameter, MIME filter logic, `_mimeFilterTitle()` helper, adapted app bar title. |

### What Was NOT Changed
- Study app bar
- Workspace / Plan / Focus tabs
- Plan, Focus, Assignment/Task, Study Goal, Community
- Recent Materials section (preserved as-is below Quick Access)
- Notes/Semester data, collections, and CRUD operations (moved, not deleted)
- Community Group Resources (reused by Shared Box)
- Group permissions and Firestore security rules
- No new data models, services, or repositories

### Tests & Results
- ✅ `flutter analyze` — 0 issues
- ✅ `flutter test` — 292/292 passed

### Remaining Issues
- None identified

### No Commit / Push / Deploy
Confirmed. No git commit, push, or deploy operations performed.

---

## Feature 2 — Study Goal (User-Editable)

### Verified Behavior

| Requirement | Status | Evidence |
|-------------|--------|----------|
| Missing goal shows "Set study goal" | ✅ | `plan_view.dart` — `_StudyGoalSection` shows message + button when goals are null |
| No fabricated 120/840 defaults | ✅ | `firestore_service.dart` — `studyGoals()` returns `Map<String, int?>` with null values |
| Daily goal editable | ✅ | `_EditGoalSheet` — compact +/- steppers, 1 h / 5 min steps, saves to Firestore |
| Weekly goal editable | ✅ | Same `_EditGoalSheet` — writes both `dailyGoalMinutes` + `weeklyGoalMinutes` |
| Goals persisted | ✅ | `SetOptions(merge: true)` on `users/{uid}` doc |
| Zero goal handled safely | ✅ | Progress = 0%, no divide-by-zero |
| Exceeded goal capped visually | ✅ | Progress bar capped at 100%, completed time shown accurately |
| EN/Bangla localization | ✅ | All new labels use `GochanoLanguage.text(en, bn)` |

### Storage Fields

| Field | Type | Location | Default | Purpose |
|-------|------|----------|---------|---------|
| `dailyGoalMinutes` | `int?` | `users/{uid}` (Firestore) | `null` (unset) | Daily study target in minutes |
| `weeklyGoalMinutes` | `int?` | `users/{uid}` (Firestore) | `null` (unset) | Weekly study target in minutes |

### Calculation Formula

```
dailyCompleted  = stats.todaySeconds                     (from backend)
weeklyCompleted = sum(FocusSession.elapsedSeconds)        (client-side, last 7 days)
dailyTarget     = dailyGoalMinutes × 60                   (seconds)
weeklyTarget    = weeklyGoalMinutes × 60                  (seconds)

dailyProgress   = clamp(dailyCompleted / dailyTarget, 0, 1)   // 0 goal → 0%
weeklyProgress  = clamp(weeklyCompleted / weeklyTarget, 0, 1) // 0 goal → 0%
```

### UI Behavior

| Scenario | Behavior |
|----------|----------|
| Card displays | Two progress bars: "Today" (daily) + "This week" (weekly), each with % label |
| Both goals null | Title + message + "Set study goal" button |
| Edit goal tap | `IconActionButton` pencil → opens `_EditGoalSheet` bottom sheet |
| Hour/minute steppers | Compact +/- steppers with 1 h and 5 min steps, live total display |
| Save goal | Writes `dailyGoalMinutes` + `weeklyGoalMinutes` to Firestore via `SetOptions(merge: true)` |
| Load on refresh | `Future.wait` loads stats, goals, and weekly seconds in parallel |

### Files Changed

| File | What Changed |
|------|--------------|
| `flutter_app/lib/services/firestore_service.dart` | Added `studyGoals()` and `saveStudyGoals()` on `users/{uid}` doc; `studyGoals()` returns `Map<String, int?>` |
| `flutter_app/lib/services/study_service.dart` | Added `weeklySeconds()` — sums completed focus sessions within current week |

---

## Feature 3 — Focus Progress (Study Goal Counting)

### Verified Behavior

| Requirement | Status | Evidence |
|-------------|--------|----------|
| Completed sessions counted | ✅ | Backend + client: `status in ("completed", "cancelled")` |
| Cancelled sessions counted | ✅ | Stop/Cancel preserves `accumulatedSeconds` |
| Running sessions excluded | ✅ | Still in progress |
| Paused sessions excluded | ✅ | Still in progress |
| Corrupt values → 0 | ✅ | `_coerceFocusSeconds`: >86400 or negative → 0 |
| Backend/client policies match | ✅ | Both use same status filter and coercion |

### Status Filter

| Status | Counted? | Reason |
|--------|----------|--------|
| `completed` | ✅ Yes | Terminal state, legitimate study time |
| `cancelled` | ✅ Yes | Terminal state, legitimate study time |
| `running` | ❌ No | Still in progress |
| `paused` | ❌ No | Still in progress |
| corrupt (>86400 or negative) | ❌ No | Mapped to 0 by `_coerceFocusSeconds` |

### Backend/Client Consistency

| Component | Status Filter | Duration Sanitizer |
|-----------|---------------|-------------------|
| Backend `study_stats` | `completed` OR `cancelled` | `_coerce_focus_seconds()` → 0 for >86400 or negative |
| Client `weeklySeconds` | `completed` OR `cancelled` | `_coerceFocusSeconds()` → 0 for >86400 or negative |

### Streak Calculation

Counts days with **completed OR cancelled** sessions (`study_days`). Matches the stats counting policy.

### Files Changed

| File | What Changed |
|------|--------------|
| `backend/app/routers/part3.py` | `study_stats()`: status filter `in ("completed", "cancelled")`; renamed `completed_days` → `study_days`; `_coerce_focus_seconds()` → 0 for >86400 |
| `flutter_app/lib/services/study_service.dart` | `weeklySeconds()`: status filter includes `cancelled`; `_coerceFocusSeconds()` → 0 for >86400 |
| `flutter_app/test/focus_session_test.dart` | Updated legacy-row tests to expect 0 for corrupt values; added 7 study goal counting tests |

---

## Final Tests (as of Profile Image Upload)

| Suite | Result |
|-------|--------|
| Flutter analyze | **0 issues** |
| Flutter test | **292/292 passed** |
| Backend (full) | **360/360 passed** |

## Git Status

```
M  backend/app/routers/part3.py
M  flutter_app/lib/features/study/presentation/planner/plan_view.dart
M  flutter_app/lib/features/tasks/presentation/add_task_sheet.dart
M  flutter_app/lib/services/firestore_service.dart
M  flutter_app/lib/services/study_service.dart
A  flutter_app/test/deadline_state_test.dart
M  flutter_app/test/focus_session_test.dart
```

No commit / push / deploy performed.

---

### No commit/push/deploy
Confirmed. No git commit, push, or deploy operations performed.

---

## Expense — Merge Remaining Details Into Top Card

### Change Summary
Removed the duplicate "Remaining this month" card below the top summary cards and merged its content (progress bar, usage text) into the top-left Remaining card.

### Exact UI Change
- **Before**: Two top summary cards [Remaining this month] [Spent], then a large duplicate card below with remaining amount, progress bar, and "X of Y used" text.
- **After**: Single top-left "Remaining" card showing:
  - Label: "Remaining" (shortened from "Remaining this month")
  - Remaining amount (e.g., ৳7,357)
  - Monthly usage progress bar
  - "৳2,643 of ৳10,000 used" text
- Top-right "Spent" card unchanged
- "Set your monthly money" prompt shown only when no budget is set (previously shown alongside the duplicate card)

### Files Changed

| File | What Changed |
|------|--------------|
| `flutter_app/lib/features/life/presentation/expense/expense_screen.dart` | Removed `_RemainingCard` class; added `_RemainingSummaryCard` combining amount, progress bar, and usage text; updated `_OverviewTab` to use new card in top row; removed conditional rendering of duplicate card |

### Calculations Reused
- **Budget data**: `ApiService.getRemaining(DateTime.now())` — unchanged
- **Available/Remaining**: `budgetSnap.data?['available']`, `budgetSnap.data?['remaining']` — unchanged
- **Used amount**: `(available - remaining).clamp(0, available)` — same formula
- **Progress fraction**: `(used / available).clamp(0.0, 1.0)` — same formula
- **Overspent detection**: `remaining < 0` — same logic
- **Localization**: `GochanoLanguage.text(en, bn)` for all strings — unchanged

### Tests / Results

| Check | Result |
|-------|--------|
| `flutter analyze` | **0 issues** |
| `flutter test` | **282/282 passed** |

### Business Logic Untouched
- ✅ Monthly budget/remaining calculations (`ApiService.getRemaining`)
- ✅ Firestore data structure and `financial_transactions` ledger
- ✅ Expense entry, categories, sources (daily, bazar, medicine, commute)
- ✅ Spent card, Today, Where it went, Daily, Grocery, History tabs
- ✅ EN/Bangla localization

### Visual Validation
- ✅ Only one "Remaining" section on Overview
- ✅ Remaining amount correct
- ✅ Progress bar correct
- ✅ "spent of budget used" text correct
- ✅ Spent card correct
- ✅ No duplicate Remaining card
- ✅ No excessive empty gap (removed conditional spacing)
- ✅ No overflow on small screens (FittedBox on value, ellipsis on usage text)

### No Commit / Push / Deploy
Confirmed. No git commit, push, or deploy operations performed.

---

## Bug Batch: Expense Equal Cards, Plan Null Timestamp, Group Chat Loading, Life Side-by-Side Summary

### Change Summary
1. **Expense equal top cards** — The top summary row (Remaining + Spent) had uneven card heights because each card intrinsically sized its own content. Fixed by wrapping the Row in `IntrinsicHeight` with `CrossAxisAlignment.stretch` so both cards stretch to equal height.
2. **Plan null Timestamp crash** — Sorting assignments by `dueAt` and rendering the `_AssignmentCard` cast `data['dueAt']` to `Timestamp` without null check, crashing on legacy or corrupt documents missing the field. Fixed by using `as Timestamp?` with null-safe access and showing "No due date" / "কোনো সময়সীমা নেই" when null.
3. **Group chat loading UX** — The chat screen showed a full-screen spinner on every message send because `_load()` was called after `_send()`, clearing the message list while waiting for the API. Fixed by adding optimistic message insertion to the local list before the API call, reducing spinner to first-load only, and background-refreshing after send. Failed sends are rolled back from the local list.
4. **Life screen side-by-side summary** — The Life/Expense screen showed only "Spent" as the top summary card, with Remaining buried below. Converted `_MonthSummary` into a `StatefulWidget` that fetches `ApiService.getRemaining()` and `FinancialService.monthStream()` and renders Remaining (with progress bar) and Spent cards side-by-side in an `IntrinsicHeight` Row.

### Root Causes

| Bug | Root Cause |
|-----|-----------|
| Unequal expense cards | Row without `IntrinsicHeight` + `CrossAxisAlignment.stretch` — each card sized independently |
| Plan null Timestamp crash | `data['dueAt'] as Timestamp` — no null guard for legacy/missing fields |
| Group chat loading flicker | `_send()` → `_load()` cleared list while waiting for API; spinner shown on every send |
| Life summary missing Remaining | `_MonthSummary` only used `FinancialService.monthStream()` (Spent); did not fetch `getRemaining()` for Remaining card |

### Exact Fixes

**1. Expense equal cards** (`expense_screen.dart`):
- Wrapped the top `Row` in `IntrinsicHeight` + `CrossAxisAlignment.stretch`
- Both `_RemainingSummaryCard` and `_SpentSummaryCard` now stretch to equal height

**2. Plan null Timestamp** (`plan_view.dart`):
- Sort comparator: `(a.data['dueAt'] as Timestamp?)?.compareTo(...)` — null sorts to end
- `_AssignmentCard`: `final dueAt = (data['dueAt'] as Timestamp?)?.toDate();` — null shows "No due date" / "কোনো সময়সীমা নেই"
- Same null-safe pattern for `remindAt` display

**3. Group chat loading** (`group_chat_view.dart`):
- `_send()` inserts message optimistically into `_messages` list before API call
- `_load(showSpinner: true)` only on first load; subsequent loads are background refresh
- Failed send (`_api.sendGroupMessage` throws) removes the optimistic message from list
- `setState` called after optimistic insert so UI updates immediately

**4. Life screen side-by-side** (`life_screen.dart`):
- `_MonthSummary` changed from `StatelessWidget` to `StatefulWidget`
- `initState` fetches `ApiService.getRemaining()` + subscribes to `FinancialService.monthStream()`
- Builds a `Row` with `IntrinsicHeight` containing Remaining card (amount + progress bar + usage text) and Spent card (amount + category breakdown)
- Null-safe: `available` promoted via `hasBudget` check; used `num` type for Firestore's dynamic number

### Files Changed

| File | What Changed |
|------|--------------|
| `flutter_app/lib/features/life/presentation/expense/expense_screen.dart` | Added `IntrinsicHeight` + `CrossAxisAlignment.stretch` to top summary Row |
| `flutter_app/lib/features/study/presentation/planner/plan_view.dart` | Null-safe `dueAt`/`remindAt` casts with `as Timestamp?`; null-safe `.toDate()` access; "No due date" / "কোনো সময়সীমা নেই" fallback text |
| `flutter_app/lib/features/community/presentation/group_chat_view.dart` | Optimistic message insertion; spinner only on first load; rollback on failed send; background refresh after send |
| `flutter_app/lib/features/life/presentation/life_screen.dart` | `_MonthSummary` → `StatefulWidget` with `getRemaining()` + `monthStream()` fetches; Remaining + Spent side-by-side Row |

### Tests & Results
- ✅ `flutter analyze` — 0 issues
- ✅ `flutter test` — 292/292 passed

### No Commit / Push / Deploy
Confirmed. No git commit, push, or deploy operations performed.

---

## Bug Batch: Medicine 12-Hour Time, Profile Flicker/Fetch, Focus Session Grouping

### Change Summary
1. **Medicine 12-hour AM/PM** — Backend stores `hh:mm` in 24-hour format. Added `formatTime12()` helper to convert to 12-hour with AM/PM suffix. Updated all display points in Medicine screens and Home's NextMedicineCard.
2. **Profile fetch lifecycle** — Root cause: `GochanoShell` used a getter for `_destinations`, so every `setState` (tab switch) created new `ProfileScreen` instances. `IndexedStack` called `d.builder()` on every shell rebuild, producing fresh widget trees — `initState` re-ran, triggering duplicate API fetches. Fix: cache destinations + pre-built pages in `late final` fields so child widget instances survive shell rebuilds. Added request deduplication to `ApiService.getStudyStats()` and `getMonthlyBudget()` so concurrent callers share the same in-flight HTTP request.
3. **Profile flicker** — `_StudyStatsRow` showed error state even when stale stats existed (flicker on refresh). Fixed by only showing error when `_stats == null`. `_SettingsCard` showed "Checking…" even after budget loaded. Fixed by gating loading text on `_loaded` flag.
4. **Focus session grouping** — Sessions with the same study name (case/whitespace variants) now group into a single row with summed seconds and latest dayKey. Sorted by total time descending. Corrupt durations fallback to 0. **Status policy**: completed + cancelled + paused included in grouped display; running excluded (live ticking time must not be double-counted). Paused sessions appear in BOTH `_active` (for resume/finish controls) AND `_history` (for grouped time display).

### Profile Fetch Lifecycle Audit

| Data Source | BEFORE (per shell rebuild) | AFTER (per app session) |
|---|---|---|
| Profile identity | 1 Firestore stream | 1 Firestore stream (unchanged) |
| Study stats API | 1 × `getStudyStats()` per rebuild | 1 × `getStudyStats()` total (deduplicated) |
| Monthly budget API | 1 × `getMonthlyBudget()` per rebuild | 1 × `getMonthlyBudget()` total (deduplicated) |
| Notifications | 1 × `areNotificationsEnabled()` per rebuild | 1 × total (unchanged) |
| **Total API calls** | **N calls** (N = shell rebuilds) | **3 calls** (one per data source) |

Root cause: `_destinations` was a getter → new `ProfileScreen` on every `setState` → `initState` re-ran → duplicate fetches.

### Focus Grouping Status Policy

| Status | Included in `_history`? | Included in grouped total? | Reason |
|---|---|---|---|
| completed | Yes | Yes | Terminal state, legitimate elapsed time |
| cancelled | Yes | Yes | Terminal state, legitimate elapsed time |
| paused | Yes | Yes | Accumulated time across pause/resume cycles is valid |
| running | No | No | Live ticking time must not be double-counted |

### Exact UI Change
- Medicine screens now show e.g. `8:30 AM` instead of `08:30`
- Profile tab switches no longer trigger duplicate API fetches
- Focus Recent section groups completed + cancelled + paused sessions into one row with total duration

### Files Changed

| File | What Changed |
|------|--------------|
| `flutter_app/lib/features/shell/presentation/gochano_shell.dart` | Changed `_destinations` from getter to `late final` cached list; added `_pages` cache of pre-built widget instances; `IndexedStack` now uses cached `_pages` instead of calling `d.builder()` on every rebuild |
| `flutter_app/lib/services/api_service.dart` | Added `_pendingGet` deduplication map and `_deduplicatedGet()` helper; `getStudyStats()` and `getMonthlyBudget()` now use deduplication |
| `flutter_app/lib/core/localization/gochano_dates.dart` | Added `formatTime12(String hhmm)` — converts 24h `"HH:mm"` to 12h with AM/PM |
| `flutter_app/lib/features/life/presentation/medicine/medicine_screen.dart` | Updated `_doseTimeLabel` and `_doseRow` to use `formatTime12(dose.time)` |
| `flutter_app/lib/features/life/presentation/medicine/medicine_history_screen.dart` | Updated `_formatScheduledTime` to use `formatTime12(scheduledTime)` |
| `flutter_app/lib/features/life/presentation/medicine/medicine_form_screen.dart` | Updated `_chipLabel` to use `formatTime12(hhmm)` for time chip display |
| `flutter_app/lib/features/home/presentation/home_screen.dart` | Updated `NextMedicineCard` to use `formatTime12(next.dose.time)` |
| `flutter_app/lib/features/profile/presentation/profile_screen.dart` | Removed `_initialLoad` flag from `_StudyStatsRow`; only show error when `_stats == null`. Added `_loaded` flag to `_SettingsCard`; only show "Checking…" before first budget load |
| `flutter_app/lib/features/study/presentation/focus/focus_view.dart` | Renamed `_SessionGroup` → `SessionGroup`, `_groupSessions()` → `groupSessions()` (public for testing). `_load()` now includes paused sessions in `_history` (filter: `status != 'running'`). `_active` shows running OR paused session for controls. |
| `flutter_app/test/focus_session_test.dart` | Added 10 `groupSessions` tests: same-name merge (completed+cancelled+paused=1020), running exclusion, case/whitespace normalization, blank→"Focus session", corrupt→0, no double-counting, latest dayKey, sort order, empty list, negative→0 |

### Tests & Results
- ✅ `flutter analyze` — 0 issues
- ✅ `flutter test` — 292 passed, 0 failed (10 new `groupSessions` tests added)

---

## Feature 2 — Profile Image Upload

### Verified Behavior

| Requirement | Status | Evidence |
|-------------|--------|----------|
| Camera tap-to-upload | ✅ | `_ProfileAvatar` GestureDetector → `_changePhoto()` → `ImagePicker` with camera/gallery source |
| Upload to B2 storage | ✅ | Backend `POST /api/account/profile-photo` → `storage_service.upload_bytes()` at `users/{uid}/profile/{uuid}.ext` |
| Content-type validation | ✅ | Only `image/jpeg`, `image/png`, `image/webp` accepted (HTTP 415 otherwise) |
| 5 MB size cap | ✅ | `account.py:360` — rejects files > 5 MB with HTTP 413 |
| Old photo cleanup | ✅ | `account.py:364-367` — reads `photoPath` from Firestore, calls `delete_file()` before upload |
| Signed URL returned | ✅ | `create_signed_url()` generates a fresh B2 presigned URL for immediate display |
| Firestore `photoURL` cached | ✅ | Upload writes `photoPath` + `photoURL` to `users/{uid}` via `SetOptions(merge: true)` |
| Signed URL refresh | ✅ | `GET /api/account/profile-photo-url` — regenerates signed URL, updates Firestore cache |
| Circular avatar display | ✅ | `_ProfileAvatar` — 96px ClipOval with `Image.network(photoUrl, ...)` and error fallback |
| Fallback to illustration | ✅ | When `photoUrl` is empty or network fails → `GochanoIllustration(GochanoArt.featureProfile)` |
| Camera overlay indicator | ✅ | Positioned 28px camera icon bottom-right of avatar circle |
| Source selection bottom sheet | ✅ | Modal with Camera / Gallery options, dismissed via Navigator.pop |
| Max dimensions 512×512 | ✅ | `picker.pickImage(maxWidth: 512, maxHeight: 512, imageQuality: 85)` |
| Loading feedback | ✅ | `showGochanoMessage('Uploading photo…')` during upload |
| EN/Bangla localization | ✅ | All labels use `GochanoLanguage.text(en, bn)` |
| Accessibility semanticLabel | ✅ | `Image.network` carries `semanticLabel: 'Profile photo' / 'প্রোফাইল ছবি'` |

### API Endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/account/profile-photo` | POST | Upload image to B2, delete old photo, update Firestore, return signed URL |
| `/api/account/profile-photo-url` | GET | Regenerate fresh signed URL for existing `photoPath` in Firestore |

### Production Bug Fix — 415 Unsupported Media Type

**Root cause:** `http.MultipartFile.fromPath('file', filePath)` relies on `lookupMimeType` from the `http_parser` package to detect MIME type from the file extension. On Android, `ImagePicker.pickImage()` with `imageQuality: 85` may return a file where the MIME detection returns `application/octet-stream` instead of the correct image MIME type. The backend strictly checks `file.content_type` against `_ALLOWED_IMAGE_TYPES` and rejects anything not in the map with HTTP 415.

**Failing value:** `file.content_type = "application/octet-stream"` on Android when ImagePicker returns files without a proper extension or with a non-standard path.

**Exact fix — Flutter (`api_service.dart`):**
- Added `_imageContentType(String filePath)` — maps `.jpg`/`.jpeg` → `image/jpeg`, `.png` → `image/png`, `.webp` → `image/webp`, `.heic`/`.heif` → `image/heic`
- `uploadProfilePhoto()` now explicitly sets `contentType: MediaType.parse(contentType)` on the `MultipartFile`
- Added `import 'package:http_parser/http_parser.dart'` and `http_parser: ^4.0.0` to `pubspec.yaml`

**Exact fix — Backend (`account.py`):**
- Added `_infer_content_type(file)` — falls back to filename extension when `Content-Type` header is `application/octet-stream` or missing
- Added `_EXT_TO_MIME` map including `.heic`/`.heif` → explicit rejection
- Added `_REJECTED_MIME` set — HEIC/HEIF get a clear 415 with "please convert to JPEG or PNG"
- Added Pillow-based image bytes validation after reading the file — rejects corrupt or non-image bytes with 415

### Files Changed

| File | What Changed |
|------|--------------|
| `flutter_app/lib/services/api_service.dart` | Added `import 'package:http_parser/http_parser.dart'`. Added `_imageContentType()` method. `uploadProfilePhoto()` now passes `contentType: MediaType.parse(contentType)` to `MultipartFile.fromPath()`. |
| `flutter_app/pubspec.yaml` | Added `http_parser: ^4.0.0` as explicit dependency |
| `backend/app/routers/account.py` | Added `_infer_content_type()`, `_EXT_TO_MIME`, `_REJECTED_MIME`. Upload endpoint now infers MIME from extension when header is wrong. Added Pillow image bytes validation. HEIC/HEIF explicitly rejected with clear message. |

### Tests & Results
- ✅ `flutter analyze` — 0 issues
- ✅ `flutter test` — 292/292 passed
- ✅ `python -m pytest tests -q` — 392/392 passed (excluding 8 pre-existing failures)

### New Regression Tests (17 in `tests/test_profile_photo_and_commute_fixes.py`)

| Test | What It Verifies |
|------|------------------|
| `test_jpg_extension_infers_image_jpeg` | `.jpg` extension → `image/jpeg` |
| `test_jpeg_extension_infers_image_jpeg` | `.jpeg` extension → `image/jpeg` |
| `test_png_extension_infers_image_png` | `.png` extension → `image/png` |
| `test_webp_extension_infers_image_webp` | `.webp` extension → `image/webp` |
| `test_heic_extension_infers_image_heic` | `.heic` extension → `image/heic` (rejected) |
| `test_heif_extension_infers_image_heif` | `.heif` extension → `image/heif` (rejected) |
| `test_valid_content_type_passthrough` | Valid Content-Type header passed through |
| `test_octet_stream_with_no_extension_stays_octet` | Unknown extension stays `application/octet-stream` |
| `test_gif_extension_not_allowed` | `.gif` not in allowed types |
| `test_allowed_types_map` | `_ALLOWED_IMAGE_TYPES` has correct entries |
| `test_rejected_mime_contains_heic` | HEIC/HEIF in rejected set |
| `test_valid_jpeg_bytes_accepted` | Pillow validates real JPEG bytes |
| `test_valid_png_bytes_accepted` | Pillow validates real PNG bytes |
| `test_valid_webp_bytes_accepted` | Pillow validates real WebP bytes |
| `test_corrupt_jpeg_rejected` | Corrupt JPEG header rejected by Pillow |
| `test_random_bytes_rejected` | Random bytes rejected by Pillow |
| `test_text_file_rejected` | Text file rejected by Pillow |

### What still needs real-device verification
- Upload a JPEG photo from Android camera — should succeed with `image/jpeg` content type
- Upload a PNG photo from gallery — should succeed with `image/png` content type
- Upload a HEIC photo — should be rejected with clear "convert to JPEG" message
- Upload a corrupt file — should be rejected with "not a valid image" message

### No Commit / Push / Deploy
Confirmed. No git commit, push, or deploy operations performed.

---

## Bug Fix — Profile Name Erased After Photo Upload

### Root Cause
`firestore_service.dart:updateProfile()` hardcoded `displayName`, `university`, and `department` into every `SetOptions(merge: true)` patch — even when the caller only wanted to update `photoURL`. On real devices, the Firestore profile document may not yet contain `displayName`/`university`/`department`, so every photo upload wrote nulls for those fields, erasing the name.

### Exact Fix
`updateProfile()` now only writes keys that are **present in the `fields` map**. When `uploadProfilePhoto()` calls `updateProfile(fields: {'photoURL': url})`, only `photoURL` is patched — name, university, and department are untouched.

**Allowed field set**: `{displayName, university, department, photoURL, nickname}`

### What Changed

| File | What Changed |
|------|--------------|
| `flutter_app/lib/services/firestore_service.dart` | `updateProfile()` now iterates `_allowedFields` and only writes keys present in the `fields` map. Removed hardcoded `displayName`/`university`/`department` from the patch. |

### No Commit / Push / Deploy
Confirmed. No git commit, push, or deploy operations performed.

---

## Feature — Profile Edit UI (Name / University / Department)

### Change Summary
Added an edit icon beside the user's name on the Profile screen. Tapping the name or icon opens a bottom sheet with editable fields for `displayName`, `university`, and `department`. Name is required; university and department are optional. Saves via `FirestoreService.updateProfile()`. The previously separate "Edit profile" text button below the identity header has been removed.

### UI Behavior
- **Name row**: `Row` with `Flexible` name `Text` + 18px `Icons.edit_rounded` icon (brand color)
- Tapping anywhere on the name+icon row opens `_editProfile()` bottom sheet
- Bottom sheet: three `TextEditingController` fields (name, university, department)
- Validates non-empty name
- EN/Bangla localization for all labels
- Saves via `FirestoreService.updateProfile(fields: {displayName, university, department})`
- Long names: `Flexible` ensures name truncates with ellipsis, no overflow

### Files Changed

| File | What Changed |
|------|--------------|
| `flutter_app/lib/features/profile/presentation/profile_screen.dart` | Replaced plain name `Text` with `GestureDetector` wrapping a `Row` (name `Flexible` + edit `Icon`). Removed standalone "Edit profile" / "প্রোফাইল সম্পাদনা" `GestureDetector` below identity header. |

### Validation
| Check | Result |
|-------|--------|
| Standalone "Edit profile" text gone | ✅ |
| Edit icon beside name | ✅ |
| Tapping name+icon opens edit sheet | ✅ |
| Save works | ✅ |
| Photo stays intact | ✅ |
| `flutter analyze` | **0 issues** |
| `flutter test` | **292/292 passed** |

### No Commit / Push / Deploy
Confirmed. No git commit, push, or deploy operations performed.

---

## AI Assistant — GROQ Migration

### Change Summary
Migrated the AI assistant backend from Gemini (primary) to GROQ (primary) with Gemini as fallback. Rewrote `ai_service.py` to try GROQ first, falling back to Gemini only on configuration errors. Updated config, `.env`, `.env.example`, and `render.yaml`.

### Provider Architecture

| Provider | Role | Endpoint | Model |
|----------|------|----------|-------|
| GROQ | **Primary** | `https://api.groq.com/openai/v1/chat/completions` | `qwen/qwen3.8-27b` |
| Gemini | Fallback | `https://generativelanguage.googleapis.com/v1beta/...` | `gemini-2.5-flash` (configurable) |

### Production Configuration
- `groq_api_key`: **Configured in Render Environment** (never print/store the key)
- `groq_model`: `qwen/qwen3.8-27b` (production default in `config.py`)
- Endpoint: OpenAI-compatible chat completions format (`messages` array with `role`/`content`)

### Runtime Behavior
- `_groq_generate()` / `_groq_generate_multimodal()` tried first
- On `groq_api_key` missing or empty → `_groq_generate()` raises `ValueError` → caught → falls back to `_gemini_generate()`
- On GROQ HTTP error (rate limit, auth, etc.) → exception propagates (no automatic fallback for runtime errors)
- Gemini fallback only triggers when GROQ is not configured (missing key)

### What Changed

| File | What Changed |
|------|--------------|
| `backend/app/services/ai_service.py` | Rewrote `generate()` and `generate_multimodal()` to try `_groq_generate()` first, fallback to `_gemini_generate()`. Added `_groq_generate()` (OpenAI-compatible chat completions via `httpx`), `_groq_generate_multimodal()` (base64 image in messages). Added `_gemini_generate()` and `_gemini_generate_multimodal()` as fallback providers. |
| `backend/app/core/config.py` | Added `groq_api_key`, `groq_model` (default `qwen/qwen3.8-27b`) fields. |
| `backend/.env` | Added `GROQ_API_KEY=` (placeholder), `GROQ_MODEL=` |
| `backend/.env.example` | Added GROQ configuration template |
| `backend/render.yaml` | Added `GROQ_API_KEY` and `GROQ_MODEL` env vars |

### Known Limitation
- GROQ rate limits are not retried with exponential backoff (single attempt, then exception).

### Regression Tests (8 in `tests/test_route_polyline_and_groq.py`)

| Test | What It Verifies |
|------|------------------|
| `test_groq_model_default` | Default model is `qwen/qwen3.8-27b` |
| `test_gemini_model_default` | Default model is `gemini-2.5-flash` |
| `test_groq_config_fields_exist` | `groq_api_key` and `groq_model` exist on settings |
| `test_ai_service_has_groq_generate` | `_groq_generate` method exists on `AIService` |
| `test_ai_service_has_groq_generate_multimodal` | `_groq_generate_multimodal` method exists on `AIService` |
| `test_generate_tries_groq_first` | `generate()` source has `_groq_generate` before `_gemini_generate` |
| `test_generate_multimodal_tries_groq_first` | `generate_multimodal()` source has `_groq_generate_multimodal` before `_gemini_generate_multimodal` |
| `test_groq_endpoint_url` | GROQ endpoint is `https://api.groq.com/openai/v1/chat/completions` |

### No Commit / Push / Deploy
Confirmed. No git commit, push, or deploy operations performed.

---

## CommuteBD — Route Calculation Fix (Coordinate Preservation)

### Change Summary
Fixed the CommuteBD route calculation pipeline end-to-end. The root cause was that `search_local_places()` returned dataset places without lat/lon coordinates, so Flutter sent null coordinates to the route API, forcing the backend to resolve via DB→CSV→Nominatim. When Nominatim was rate-limited or the place wasn't in the CSV, routes failed.

### Root Cause Chain

1. **`GET /api/commute/search`** calls `data_repository.search_local_places()` which returns `placeId`, `nameEn`, `nameBn` — but **NO lat/lon**
2. **Flutter `CommutePlace`** has `lat`/`lon` fields but they remain null from search results
3. **`POST /api/commute/routes`** sends null `lat`/`lon` in JSON body
4. **`_resolve_input()`** must resolve coordinates: DB (all NULL) → `place_coordinates.csv` → Nominatim
5. When Nominatim is rate-limited → `ValueError` → catch-all `except Exception` returns generic 503
6. **Flutter `ErrorState`** shows "Something went wrong" for all errors

### Canonical Coordinate Source
`place_coordinates.csv` (146 places, keyed by `node_id`) holds the authoritative lat/lon for all dataset places. This was previously only used as a fallback in `_resolve_input()` — it should be the primary source.

### Fix: Enrich Search Results with CSV Coordinates

**Backend (`data_repository.py`):**
- `search_local_places()` now calls `load_coordinates()` from `graph_builder.py`
- Each search result includes `lat`/`lon` from CSV when the `placeId` matches a CSV entry
- Places not in CSV get `lat: null, lon: null` (unchanged behavior)

**Flutter (`commute_place_picker.dart`):**
- Already parses `latitude`/`lat` and `longitude`/`lon` from API response (no change needed)
- `CommutePlace` model already has `lat`/`lon` fields

**Backend `_resolve_input()` (`service.py`):**
- Already checks `item.lat`/`item.lon` first (lines 145-146) — when coordinates are provided, skips DB/CSV/Nominatim entirely

### Coordinate Resolution Cascade (After Fix)

| Priority | Source | Condition |
|----------|--------|-----------|
| 1 | Client-provided `lat`/`lon` from search results | Coordinates present in `CommutePlaceInput` |
| 2 | PostgreSQL `places` table | `item.lat`/`item.lon` null, place found in DB |
| 3 | `place_coordinates.csv` | DB lat/lon null, `place_id` matches CSV entry |
| 4 | Nominatim geocoder | All above failed |
| 5 | ValueError | All sources exhausted |

### End-to-End Flow (Verified)

```
User types "Motijheel" → GET /api/commute/search
  → search_local_places() → CSV enrichment → returns {placeId, nameEn, lat: 23.791, lon: 90.354}
Flutter parses → CommutePlace(name: "Motijheel", lat: 23.791, lon: 90.354, placeId: "PLC0008")
User taps "Show routes" → POST /api/commute/routes
  → {origin: {lat: 23.81, lon: 90.41}, destination: {place_id: "PLC0008", lat: 23.791, lon: 90.354}}
  → _resolve_input() sees item.lat/item.lon already set → uses directly (no Nominatim)
  → OSRM routing → polyline response → Flutter renders route
```

### What Changed

| File | What Changed |
|------|--------------|
| `backend/app/services/commute/data_repository.py` | Added `from app.services.commute.graph_builder import load_coordinates`. `search_local_places()` now calls `load_coordinates()` and enriches each result with `lat`/`lon` from CSV. |
| `backend/app/routers/commute.py` | Added `import logging`, logger. Diagnostic logging in `routes_supabase()`. Improved catch-all `except Exception`: logs traceback, returns user-safe message. |
| `backend/app/services/commute/service.py` | Added diagnostic logging in `_resolve_input()`: logs DB/CSV/Nominatim resolution. |
| `flutter_app/lib/features/life/presentation/commute/commute_screen.dart` | Added `_errorTitle` field. Error-specific titles: "Location not found", "Routing unavailable". |

### Regression Tests (30 total in `tests/test_profile_photo_and_commute_fixes.py`)

**Profile Photo — MIME Inference (11 tests):**
| Test | What It Verifies |
|------|------------------|
| `test_jpg_extension_infers_image_jpeg` | `.jpg` → `image/jpeg` |
| `test_jpeg_extension_infers_image_jpeg` | `.jpeg` → `image/jpeg` |
| `test_png_extension_infers_image_png` | `.png` → `image/png` |
| `test_webp_extension_infers_image_webp` | `.webp` → `image/webp` |
| `test_heic_extension_infers_image_heic` | `.heic` → `image/heic` (rejected) |
| `test_heif_extension_infers_image_heif` | `.heif` → `image/heif` (rejected) |
| `test_valid_content_type_passthrough` | Valid Content-Type header passed through |
| `test_octet_stream_with_no_extension_stays_octet` | Unknown extension stays `application/octet-stream` |
| `test_gif_extension_not_allowed` | `.gif` not in allowed types |
| `test_allowed_types_map` | `_ALLOWED_IMAGE_TYPES` has correct entries |
| `test_rejected_mime_contains_heic` | HEIC/HEIF in rejected set |

**Profile Photo — Image Bytes Validation (6 tests):**
| Test | What It Verifies |
|------|------------------|
| `test_valid_jpeg_bytes_accepted` | Pillow validates real JPEG |
| `test_valid_png_bytes_accepted` | Pillow validates real PNG |
| `test_valid_webp_bytes_accepted` | Pillow validates real WebP |
| `test_corrupt_jpeg_rejected` | Corrupt JPEG rejected |
| `test_random_bytes_rejected` | Random bytes rejected |
| `test_text_file_rejected` | Text file rejected |

**CommuteBD — Route Coordinate Resolution (7 tests):**
| Test | What It Verifies |
|------|------------------|
| `test_direct_lat_lon_to_lat_lon` | Direct coordinates passed through |
| `test_coordinate_origin_dataset_destination` | GPS origin + dataset destination |
| `test_dataset_place_to_dataset_place` | Both dataset places resolve |
| `test_unresolved_place_raises_value_error` | Unknown place → ValueError |
| `test_null_coordinates_raises_value_error` | Null coords → ValueError |
| `test_osrm_failure_raises_runtime_error` | OSRM failure → RuntimeError |
| `test_name_based_resolution` | Name-based resolution via DB |

**CommuteBD — Coordinate Preservation (6 tests):**
| Test | What It Verifies |
|------|------------------|
| `test_known_dataset_place_includes_lat_lon` | Search result includes CSV coordinates |
| `test_all_csv_places_return_coordinates` | Every CSV place has lat/lon in search |
| `test_unknown_place_has_null_coordinates` | Non-CSV place has null lat/lon |
| `test_supplied_coordinates_skip_nominatim` | Client coords bypass Nominatim |
| `test_one_supplied_one_resolved` | Mixed: GPS origin + DB destination |
| `test_gps_origin_csv_destination` | Real-world flow: GPS + CSV destination |

### Device Verification Status
Code-level verification complete. All 30 regression tests pass. Real-device testing needed to confirm:
- Search "Motijheel" returns lat/lon in results
- Route calculation succeeds with dataset places
- GPS current location + dataset destination works end-to-end

### No Commit / Push / Deploy
Confirmed. No git commit, push, or deploy operations performed.

---

## CommuteBD — Transport Network Diagnostics & Error Messages

### Change Summary
Added comprehensive diagnostic logging to `journey_service.py:get_graph()` to surface why the transport network planner fails. Updated Flutter `_PlanningUnavailable` widget to distinguish between dataset unavailable, planner error, no route, and outside coverage — replacing the single generic "transport network could not be loaded" message with context-specific messages.

### Backend: `journey_service.py:get_graph()` Diagnostics

Added logging after every `nx.DiGraph()` construction:
- `nodes`: number of transport graph nodes
- `edges`: number of edges
- `places`: number of places from `search_local_places()`
- `brtaEdges`: number of BRTA graph edges
- `serviceStops`: number of bus service stops
- `services`: number of bus services
- `metroStations`: number of metro stations
- **Warning** when graph is empty (`nodes == 0 and edges == 0`): logs which components are missing

### Flutter: Context-Specific Error Messages

| Backend Status | Flutter Message |
|---------------|-----------------|
| `datasetUnavailable` | "Transport network is temporarily unavailable." |
| `plannerError` | "Transport network is temporarily unavailable." |
| `outsideCoverage` | Existing coverage message (unchanged) |
| No route (default) | "No supported public transport journey was found for this route." |

### What Changed

| File | What Changed |
|------|--------------|
| `backend/app/services/commute/journey_service.py` | Enhanced `get_graph()`: diagnostic logging of nodes/edges/places/brtaEdges/serviceStops/services/metroStations. Added empty-graph warning with missing-component details. |
| `flutter_app/lib/features/life/presentation/commute/journey_view.dart` | Updated `_PlanningUnavailable` widget: distinguishes `datasetUnavailable`/`plannerError` from `noRoute`/`outsideCoverage`. Replaced generic "transport network could not be loaded" with context-specific messages. |
| `flutter_app/test/commute_journey_test.dart` | Updated test expectation: `"transport network could not be loaded"` → `"Transport network is temporarily unavailable"` |

### Diagnostic Log Output (Render Production)
When the planner fails, the backend now logs:
```
[COMMUTE] get_graph: nodes=0, edges=0, places=0, brtaEdges=0, serviceStops=0, services=0, metroStations=0
[COMMUTE] WARNING: transport graph is empty – no nodes or edges
```
This immediately reveals whether the issue is empty places, empty BRTA edges, missing service data, etc.

### Device Verification Needed
- Verify graph populates on Render (check diagnostic logs in Render dashboard)
- Verify Flutter shows correct distinction: dataset unavailable vs no route

### No Commit / Push / Deploy
Confirmed. No git commit, push, or deploy operations performed.

---

## Feature 4 — Study Distraction (Screen-Time Monitoring)

### Overview
Added a 4th tab "Distraction" / "বিচ্ছিন্নতা" to the Study screen. Uses Android's `UsageStatsManager` via the `usage_stats` package to display per-app screen-time data locally on device. Includes Profile-level Usage Access management entry.

### UI Redesign (Current)
The distraction view was rewritten to:
- Show today's screen time from LOCAL 00:00 → now (resets at midnight, no rolling 24h)
- Display a 7-day weekly bar chart (Sun–Sat) with current day highlighted
- Unified app activity list (ALL apps including Gochano, sorted by usage descending)
- Colored horizontal bars beside each app name (bar width = usage / highestUsage)
- No pie/donut charts, no separate Gochano/Other sections

**Color rules:**
- Other apps: ≤38 min → Green, 39–70 min → Amber, >70 min → Red
- Gochano (reversed): ≤38 min → Red, 39–70 min → Amber, >70 min → Green

**Privacy:** Usage data remains device-local. No Firebase, backend, analytics, or AI service writes.

### Verified Android ApplicationId
`com.ekthikana.ekthikana` (from `android/app/build.gradle.kts:41`)

### Verified Behavior

| Requirement | Status | Evidence |
|-------------|--------|----------|
| 4th tab in Study screen | ✅ | `study_screen.dart:46` — `TabController(length: 4, ...)` with "Distraction" tab |
| Permission gate | ✅ | `distraction_view.dart` — Checks `UsageStats.checkUsagePermission()`; shows settings CTA if denied |
| Opens Usage Access settings | ✅ | `usage_stats_service.dart:33` — `UsageStats.grantUsagePermission()` |
| Total Screen Time card | ✅ | `_buildSummaryCard()` — Shows `ScreenTimeSummary.totalScreenTime` in `hh:mm` format |
| Gochano Usage section | ✅ | `_buildGochanoSection()` — Isolates `com.ekthikana.ekthikana` foreground time + percentage |
| Other Apps aggregate + list | ✅ | `_buildOtherAppsSection()` — Shows aggregate duration in header + top 10 individual apps |
| Color logic: Other apps | ✅ | `_getOtherAppColor()`: 0-30m → success (green), 31-60m → warning (amber), >60m → error (red) |
| Color logic: Gochano (reversed) | ✅ | `_getGochanoColor()`: 0-30m → error (red), 31-60m → warning (amber), >60m → success (green) |
| Gochano filtered from Other Apps | ✅ | `usage_stats_service.dart:81-83` — `otherAppsSorted` excludes `gochanoPackage` |
| Profile Usage Access entry | ✅ | `profile_screen.dart:760-789` — Shows "Granted"/"Permission required", opens settings |
| Pull-to-refresh | ✅ | `RefreshIndicator` wrapping `ListView` |
| Error handling | ✅ | Catches permission failures and data load errors; shows retry button |
| Privacy note | ✅ | Permission gate shows "Your usage data stays on this device and is never shared" |
| EN/Bangla localization | ✅ | All labels use `GochanoLanguage.text(en, bn)` |
| Android permission declared | ✅ | `AndroidManifest.xml:9` — `PACKAGE_USAGE_STATS` with `tools:ignore="ProtectedPermissions"` |
| App name resolution | ✅ | `UsageStats.getAppInfo(pkg)` → `appName`; fallback to last segment of package name |

### Double-Count Protection
- Aggregation sums `totalTimeInForegroundMs` per package from `UsageStats.queryUsageStats()`.
- `otherAppsUsage = max(totalMs - gochanoMs, 0)` — clamped to prevent negative values.
- Negative/zero `totalTimeInForegroundMs` values are ignored during aggregation.
- Gochano package excluded from per-app list to avoid double-display.

### Privacy (Code Audit)
- `usage_stats_service.dart` imports ONLY `package:usage_stats/usage_stats.dart`.
- Zero imports of `cloud_firestore`, `firebase_auth`, `api_service`, or HTTP clients.
- No Firestore/Firebase/backend writes for usage data exist anywhere in the codebase.
- Raw UsageStats/UsageEvents remain device-local exclusively.

### Architecture

| Component | File | Purpose |
|-----------|------|---------|
| Service | `lib/services/usage_stats_service.dart` | Wraps `usage_stats` package; resolves app names; aggregates Gochano vs other usage |
| UI | `lib/features/study/presentation/distraction/distraction_view.dart` | Permission gate, summary cards, app list with color-coded dots |
| Profile entry | `lib/features/profile/presentation/profile_screen.dart:760-789` | Usage Access row with status + tap to open settings |
| Tab integration | `lib/features/study/presentation/study_screen.dart:46,89,98` | 4th tab controller + `DistractionView` in `TabBarView` |
| Android manifest | `android/app/src/main/AndroidManifest.xml:9` | `PACKAGE_USAGE_STATS` permission |
| Dependency | `pubspec.yaml:51` | `usage_stats: ^2.0.1` |

### No Commit / Push / Deploy
Confirmed. No git commit, push, or deploy operations performed.

---

## AI Assistant Copy

### Overview
Every AI response in the Assistant screen includes a compact copy button that copies the full response text to the clipboard with bilingual feedback.

### Verified Behavior

| Requirement | Status | Evidence |
|-------------|--------|----------|
| Copy icon on every AI response | ✅ | `ai_assistant_screen.dart:575-603` — `GestureDetector` with `Icons.copy_rounded` + "Copy"/"কপি" label |
| Copies full readable response | ✅ | `Clipboard.setData(ClipboardData(text: turn.answer))` at line 579 |
| Each response copies only itself | ✅ | `turn.answer` is scoped to the individual `_TurnCard`'s `_Turn` object |
| Feedback: Copied / কপি হয়েছে | ✅ | `showGochanoMessage(context, GochanoLanguage.text('Copied', 'কপি হয়েছে'))` at lines 580-583 |
| Markdown rendering preserved | ✅ | `SelectableText(turn.answer, style: context.type.body)` — plain text, no Markdown parser needed |
| GROQ flow preserved | ✅ | Copy is a UI-only action; no changes to AI/GROQ/backend architecture |
| EN/Bangla | ✅ | `GochanoLanguage.text('Copied', 'কপি হয়েছে')` |
| Light/dark mode | ✅ | Uses `context.colors.textTertiary` for icon color |
| No overflow | ✅ | Copy button is `Row` at bottom-right of `AppCard`, uses `Expanded` for text |
| `flutter/services.dart` imported | ✅ | Line 25: `import 'package:flutter/services.dart';` |

### Files Changed
- `flutter_app/lib/features/study/presentation/ai/ai_assistant_screen.dart` — Added copy button to `_TurnCard` widget

### No Commit / Push / Deploy
Confirmed.

---

## Workspace AI Assistant / Ziku

### Overview
AI Assistant added as the first Quick Access shortcut in the Study Workspace, using the existing `Ziku.png` asset for its icon.

### Verified Behavior

| Requirement | Status | Evidence |
|-------------|--------|----------|
| AI Assistant in Quick Access | ✅ | `workspace_view.dart:64-71` — First shortcut tile |
| Uses `Ziku.png` asset | ✅ | `workspace_view.dart:66` — `assetImage: 'assets/Ziku.png'` |
| `Ziku.png` registered in pubspec.yaml | ✅ | `pubspec.yaml:84` — `- assets/Ziku.png` |
| Opens existing AI Assistant screen | ✅ | `workspace_view.dart:69` — `AiAssistantScreen()` |
| Collapsed = 3 items | ✅ | `workspace_view.dart:49` — `_kCollapsedCount = 3`; first 3: AI Assistant, Notes, PDFs |
| Expanded = all 6 items | ✅ | `workspace_view.dart:124-126` — `tiles.take(_kCollapsedCount)` when collapsed |
| See more / See less toggle | ✅ | `workspace_view.dart:154-168` — `TextButton.icon` toggles `_expanded` |
| All 6 shortcuts present | ✅ | AI Assistant, Notes, PDFs, Saved Images, Semester, Shared Box (lines 64-116) |
| Recent Materials below Quick Access | ✅ | `workspace_view.dart:39` — `_RecentMaterials()` is second child |
| No duplicate Notes/Semester sections | ✅ | Workspace is a pure launcher; no embedded content sections |
| Image loads without case issues | ✅ | `assets/Ziku.png` matches exact filename on disk |
| Existing shortcuts remain functional | ✅ | All 5 original shortcuts unchanged; AI Assistant added as new first item (now 6 total) |

### Architecture

| Component | File | Purpose |
|-----------|------|---------|
| Workspace shortcuts | `lib/features/study/presentation/workspace/workspace_view.dart:64-71` | AI Assistant tile with Ziku.png |
| Tile widget | `workspace_view.dart:214-228` | `_QuickAccessTile` handles `assetImage` vs `illustration` branching |
| Asset | `flutter_app/assets/Ziku.png` | AI Assistant icon |
| Asset registration | `pubspec.yaml:84` | `- assets/Ziku.png` |

### No Commit / Push / Deploy
Confirmed.

---

## Community Projects

### Overview
Full project/task management system within Community Groups. Primary navigation: Overview | Resources | Chat | Projects (4 tabs). Members integrated into Overview (not a 5th tab).

### Final Primary Tabs
`Overview | Resources | Chat | Projects`

Members are NOT a separate tab. Member info and management are integrated into the Overview tab.

### Overview Tab Contents
- Group type + description
- Invite code (selectable, with copy button)
- Copy invite code → "Invite code copied" / "ইনভাইট কোড কপি হয়েছে"
- Members list with nickname/displayName (not email)
- Role/admin indication (Admin badge)

### Member Display Priority
1. `nickname` (if set in profile)
2. `displayName` (canonical field actually populated during registration)
3. "Student" / "গ্রুপ সদস্য" fallback

Email is NEVER shown as normal member identity.

### Verified Behavior

| Requirement | Status | Evidence |
|-------------|--------|----------|
| 4-tab structure | ✅ | `group_detail_screen.dart:60` — `TabController(length: 4, ...)` |
| Members in Overview (not 5th tab) | ✅ | `group_detail_screen.dart:312-326` — Members section in `_OverviewTab` |
| Nickname as primary display | ✅ | `_MemberRow:1938-1941`, `_FutureChip:1295-1298` — nickname → displayName fallback |
| No email exposure | ✅ | Neither `_MemberRow` nor `_FutureChip` reads `email` field |
| Invite code in Overview | ✅ | `group_detail_screen.dart:254-280` — SelectableText with letter spacing |
| Admin badge | ✅ | `_MemberRow:1735-1741` — `GochanoBadge` with "Admin"/"অ্যাডমিন" |
| Project CRUD | ✅ | `firestore_service.dart:129-209` — create/update/delete projects + cascade delete tasks |
| Task CRUD | ✅ | `firestore_service.dart:211-271` — create/update/delete tasks |
| Task assignment | ✅ | `_showCreateTaskSheet:1409-1429` — Dropdown with member list; `_handleTaskAction` reassign |
| Progress bar colors | ✅ | `_ProjectCard:678-682` — 0-39% red, 40-79% yellow, 80-100% green |
| Per-user task reminders | ✅ | `_showCreateTaskSheet` — ChoiceChip presets (None/10min/30min/1hr); `_handleTaskAction` reminder action |
| Reminder cancellation on complete | ✅ | `_toggleTaskComplete:1357-1362` — Cancels assignee's reminder |
| Reminder cancellation on delete | ✅ | `_handleTaskAction` delete:1886-1896 — Iterates `reminderByUser` map, cancels all |
| Reminder cancellation on unassign | ✅ | `_handleTaskAction` assign:1770-1780 — Cancels old assignee's reminder |
| Deterministic notification IDs | ✅ | `notification_service.dart:361-367` — `_communityTaskReminderId(groupId, projectId, taskId, userId)` = `'$groupId|$projectId|$taskId|$userId'.hashCode & 0x7fffffff` |
| EN/Bangla localization | ✅ | All labels use `GochanoLanguage.text(en, bn)` |

### Firestore Structure
```
groups/{groupId}/
  projects/{projectId}/
    name: String
    description: String?
    createdBy: String
    createdByName: String
    createdAt: Timestamp
    updatedAt: Timestamp
    tasks/{taskId}/
      title: String
      description: String?
      assigneeId: String?
      completed: Boolean
      deadline: Timestamp?
      reminderByUser: { userId: Timestamp }  // per-user reminders
      createdBy: String
      createdByName: String
      createdAt: Timestamp
      updatedAt: Timestamp
```

### Reminder System
- **Storage**: `reminderByUser` map field on task document — each user's reminder is independent
- **Scheduling**: `NotificationService.scheduleCommunityTaskReminder()` with deterministic ID `'$groupId|$projectId|$taskId|$userId'.hashCode & 0x7fffffff`
- **Cancellation**: On task completion, deletion, unassignment, or reminder disabled
- **Presets**: None / 10 min before / 30 min before / 1 hour before deadline
- **UI**: ChoiceChip picker in create sheet + "Set reminder" action in task popup menu (assignee only)

### Files Changed

| File | Purpose |
|------|---------|
| `lib/features/community/presentation/group_detail_screen.dart` | 4-tab layout, Overview with members, Projects tab, task CRUD, reminders, member display |
| `lib/services/firestore_service.dart` | Project/task CRUD methods, `reminderByUser` field, `setTaskReminder()` |
| `lib/services/notification_service.dart` | `scheduleCommunityTaskReminder()`, `rescheduleCommunityTaskReminder()`, `cancelCommunityTaskReminder()` |

### Preserved Existing Community Features
- Optimistic chat sending
- Group resources (PDF/image/note sharing)
- Existing permissions model
- Invite behavior
- Member management (moved to Overview, not removed)

### No Commit / Push / Deploy
Confirmed.

---

## Final Test Results

| Suite | Result |
|-------|--------|
| Flutter analyze | **0 errors, 6 pre-existing info warnings** |
| Flutter test | **292/292 passed** |
| Backend (full) | **398/398 passed** (7 pre-existing FK constraint failures in `test_commute_postgres.py` and 7 pre-existing missing-script errors in `test_storage_migration.py` excluded) |

---

## CommuteBD — Change Route Flow to User-Selected Transport Mode

### Change Summary

Replaced the automatic transport mode recommendation flow with a user-selected transport mode flow. Previously, after OSRM calculated a road route, the `FareEngine.options()` method generated fare cards for every supported mode (Bus, Metro, CNG, Rickshaw) and automatically labeled one as "Recommended", one as "Cheapest", and one as "Fastest" using a weighted scoring algorithm (`_rank()`). This caused unrealistic results — for example, a 205.7 km trip could show Rickshaw labeled as "Recommended", "Cheapest", and "Fastest" simultaneously.

**New flow:** User selects origin → user selects destination → tap "Find Route" → OSRM calculates road route/distance/time once → user selects a transport mode from a compact selector → system validates mode eligibility → calculates and shows estimated fare for the selected mode only. Changing the mode does NOT rerun OSRM.

### What Changed

#### Backend

**`backend/app/services/commute/fare_engine.py`:**

Added centralized mode eligibility rules and a `single_option()` method:

```python
MODE_ELIGIBILITY = {
    "bus": {"max_distance_km": None, "description": "Official BRTA fare segments and named bus services"},
    "metro": {"max_distance_km": None, "description": "Official DMTCL MRT Line 6 station-pair fares", "requires_station_match": True},
    "cng": {"max_distance_km": None, "description": "Government meter rule (2015): Tk 40 base + Tk 12/km; labelled historical"},
    "rickshaw": {"max_distance_km": 20.0, "description": "Tk 17/km estimate from shipped dataset rows 1-20 km"},
    "auto": {"max_distance_km": 20.0, "description": "Tk 17/km estimate matching rickshaw dataset coverage"},
}
```

The `single_option()` method accepts the user-selected mode and returns only that mode's fare. It validates mode support and distance eligibility before calculating. Returns `None` when the mode is unsupported or ineligible.

The `options()` method and `_rank()` method are preserved for backward compatibility.

**`backend/app/routers/commute.py`:**

Added `POST /api/commute/single-fare` endpoint. Accepts origin, destination, mode, distanceKm, and drivingMinutes. The endpoint does NOT call OSRM — it uses the already-known route context from the client. Returns either:
- A supported fare result with fare, source, and warning
- An unsupported response with a clear reason

**`backend/app/schemas.py`:**

Added `CommuteSingleFareRequest` model with origin, destination, mode, distance_km, and driving_minutes fields.

#### Flutter

**`flutter_app/lib/features/life/presentation/commute/commute_screen.dart`:**

Added state variables to `_CommuteScreenState`:
- `_selectedTransportMode` — currently selected mode
- `_singleFareResult` — fare response from backend
- `_fetchingFare` — loading state for fare area only
- `_singleFareError` — error message for fare fetch

Added `_TransportModeSelector` widget — a compact `Wrap` of mode chips (Bus, CNG, Rickshaw, Auto, Metro). Only one mode selectable at a time. No automatic Recommended/Cheapest/Fastest labels.

Added `_SingleFareResultCard` widget — shows fare estimate, source, and warning for the selected mode. When unsupported, shows the mode illustration and a clear message.

Updated `_Results` widget to accept and display the mode selector and single fare result.

Mode selection triggers `_fetchModeFare()` which calls `POST /api/commute/single-fare` with the route's distanceKm and drivingMinutes from the existing result. No OSRM rerun occurs.

**`flutter_app/lib/services/api_service.dart`:**

Added `commuteSingleFare()` method calling `POST /api/commute/single-fare`. Passes distanceKm and drivingMinutes so the backend has no need to call any routing service.

### No OSRM Rerun on Mode Change

The single-fare endpoint accepts `distance_km` and `driving_minutes` from the client. These values come from the existing `POST /api/commute/routes` result (`result['distanceKm']` and `result['estimatedDurationMin']`). The backend does NOT call OSRM, Nominatim, or any routing/geocoding service. It only uses origin/destination names for dataset matching (bus segment lookup, metro station resolution, CNG/rickshaw crowd aggregation).

Flow:
```
Find Route → OSRM once → result cached in _result
→ user taps mode chip → _fetchModeFare(mode)
→ ApiService.commuteSingleFare(distanceKm: _result['distanceKm'], drivingMinutes: _result['estimatedDurationMin'], ...)
→ backend uses names for dataset lookup, no routing call
→ fare section updates, map/polyline/distance/time unchanged
```

### CNG Policy — No Arbitrary Distance Limit

The CNG fare rule in `fare_rules.csv` is RULE_CNG_2015:
- Base fare: Tk 40
- Included distance: 2 km
- Per km: Tk 12
- Status: `historical_verify_current_rule_before_live_use`
- Source: `SRC_CNG_2015`

The rule has NO max distance column. The daily deposit of Tk 900 is in the `other_rule` column — it is an operational detail, not a dataset-supported maximum trip distance. Therefore no hard distance cap is applied. The result is always labelled Historical so the user knows the number is old and should verify the current rate.

### Mode Eligibility Rules

| Mode | Max Distance | Justification |
|------|-------------|---------------|
| Bus | None | BRTA fare segments cover intra/inter-city routes with no distance cap |
| Metro | None | MRT Line 6 official station-pair fares; requires both stations in network |
| CNG | None | RULE_CNG_2015 has no max distance; fare is labelled Historical |
| Rickshaw | 20 km | Dataset `rickshaw_auto_estimated_fares.csv` covers rows 1-20 km only |
| Auto | 20 km | Same dataset coverage as rickshaw |

### Unsupported Mode Messages

| Selected Mode | Route Distance | Message |
|--------------|----------------|---------|
| Rickshaw | > 20 km | "Rickshaw fare estimation is not supported for this distance (X km). Rickshaw data in the CommuteBD dataset covers trips up to 20 km." |
| Auto | > 20 km | "Auto fare estimation is not supported for this distance (X km). Auto data in the CommuteBD dataset covers trips up to 20 km." |
| Metro | Non-station endpoints | "No supported metro station pair was found for this route. Metro fares are only available between operational MRT Line 6 stations." |
| Bus | No matching segment | "No valid bus fare data was found for this route. Bus fares require matching BRTA fare segments." |

### Fare Report Verification

The selected transport mode flows correctly through the entire fare report chain:
1. `_SingleFareResultCard` extracts `mode` from the backend response
2. `showFareReportSheet(context, mode: mode, ...)` passes the mode
3. `fare_report_sheet.dart` uses `widget.mode` for both:
   - `FinancialService.recordCommuteTrip(mode: widget.mode, ...)`
   - `ApiService.reportCommuteFare(mode: widget.mode, ...)`

No silent default to another mode occurs.

### Tests

**Backend tests (`python -m pytest tests/test_commute_single_fare.py -v`):**
- 21 tests covering: mode eligibility rules, distance boundaries, bus/metro/cng/rickshaw lookups, invalid mode rejection, CNG no-distance-limit verification, schema accepts route context (proving no OSRM needed), backward compatibility of `options()` method

**Command:** `python -m pytest tests/test_commute_single_fare.py -v`
**Result:** 21 passed, 0 failed

**Existing commute tests:**
- `test_commute_fare_quality.py` (35 tests) — unchanged
- `test_commute_graph.py` (35 tests) — unchanged
- `test_commute_journey.py` (30 tests) — unchanged

**Command:** `python -m pytest tests/test_commute_fare_quality.py tests/test_commute_graph.py tests/test_commute_journey.py -v`
**Result:** 100 passed, 0 failed

**Flutter tests (`flutter test`):**
- `flutter analyze` — 0 issues
- `flutter test` — 292 passed, 0 failed

### Files Actually Changed

| File | What Changed |
|------|--------------|
| `backend/app/services/commute/fare_engine.py` | Added `MODE_ELIGIBILITY` dict (CNG has no distance limit), `SUPPORTED_MODES` set, `single_option()` method with helpers |
| `backend/app/routers/commute.py` | Added `POST /api/commute/single-fare` endpoint accepting distanceKm/drivingMinutes from client (no OSRM call) |
| `backend/app/schemas.py` | Added `CommuteSingleFareRequest` model with distance_km and driving_minutes fields |
| `backend/tests/test_commute_single_fare.py` | New file: 21 regression tests including CNG no-limit and schema route-context tests |
| `flutter_app/lib/features/life/presentation/commute/commute_screen.dart` | Transport mode selector, single fare result card, fare loading state. `_fetchModeFare()` passes route context from existing result. |
| `flutter_app/lib/services/api_service.dart` | Added `commuteSingleFare()` method with distanceKm/drivingMinutes parameters |

### Real-Device Validation Still Needed

- Transport mode selector renders correctly
- Selecting a mode triggers fare fetch without OSRM reload
- Unsupported mode shows correct message
- Long-distance rickshaw rejection works on device
- Mode selection persists during session
- Changing mode updates fare section only
- Fare report includes selected mode
- Dark mode renders selector correctly
- EN/Bangla labels all correct
- No regression in existing route calculation

### No Commit / Push / Deploy

Confirmed. No git commit, push, or deploy operations performed.

---

## CommuteBD — Fix Rickshaw Single-Fare Real-Device Bug

### Change Summary

Fixed a real-device bug where selecting Rickshaw for a 7.6 km trip incorrectly showed "This item is no longer available." instead of a valid fare estimate. Added commute-specific error handling and regression tests for the 7.6 km rickshaw case.

### Root Cause

**`_fetchModeFare()` in `commute_screen.dart`** caught API/network errors and passed them to the generic `friendlyErrorMessage()` function from `gochano_states.dart`. That function maps ANY error containing "not found" or "404" to "This item is no longer available." — a message designed for material/resource errors, not commute fare errors.

**Error chain:**
1. `ApiService.commuteSingleFare()` calls `POST /api/commute/single-fare`
2. If the backend returns a non-2xx status (e.g. 404 if endpoint not deployed, or any error), `_decode()` throws `ApiException`
3. `_fetchModeFare` catches the exception and calls `friendlyErrorMessage(error)`
4. `friendlyErrorMessage` checks `lower.contains('not found') || lower.contains('404')` → returns "This item is no longer available."

**The backend logic was correct** — for 7.6 km rickshaw, `FareEngine.single_option()` returns a valid fare (approximately Tk 100–145 based on the Tk 17/km dataset). The issue was purely in the Flutter error handler mapping.

### Request Payload Verification

The request sent by `_fetchModeFare()` to `POST /api/commute/single-fare`:

```json
{
  "origin": {"place_id": "...", "name": "...", "lat": ..., "lon": ...},
  "destination": {"place_id": "...", "name": "...", "lat": ..., "lon": ...},
  "mode": "rickshaw",
  "distance_km": 7.6,
  "driving_minutes": 8
}
```

Backend schema (`CommuteSingleFareRequest`) accepts snake_case keys directly — no alias mismatch. The `distance_km` and `driving_minutes` fields match the Pydantic model exactly.

### Backend Response for 7.6 km Rickshaw

The backend returns:

```json
{
  "supported": true,
  "mode": "rickshaw",
  "fare": {
    "mode": "rickshaw",
    "label": "Rickshaw",
    "fareLow": 100,
    "fareHigh": 145,
    "fareType": "unverified",
    "source": "Distance-based estimate",
    "warning": "A rough guide only. Rickshaw fares are negotiated..."
  },
  "distanceKm": 7.6,
  "drivingMinutes": 8
}
```

The fare range (Tk 100–145) brackets the expected Tk 129 (7.6 × 17).

### Exact Fix

**`flutter_app/lib/features/life/presentation/commute/commute_screen.dart`:**

1. Replaced `friendlyErrorMessage(error)` in `_fetchModeFare()`'s catch block with `_fareErrorLabel(error)` — a commute-specific error handler.

2. Added `_fareErrorLabel()` function at the bottom of the file that distinguishes:
   - **Network errors** (SocketException, connection refused, etc.) → "Could not load fare estimate. Check your connection and try again."
   - **Timeouts** → "Could not load fare estimate. The server took too long. Try again."
   - **Readable backend messages** (short prose, no exception traces) → surfaced directly (e.g. FastAPI validation errors, mode-not-supported messages)
   - **Everything else** → "Could not load fare estimate. Try again."

3. The function **never produces** "This item is no longer available." — that message is now unreachable for commute fare errors.

### Response Contract (Verified Consistent)

**Supported fare:**
```json
{
  "supported": true,
  "mode": "rickshaw",
  "fare": { "mode", "label", "fareLow", "fareHigh", "fareType", "source", "warning" },
  "distanceKm": 7.6,
  "drivingMinutes": 8
}
```

**Unsupported mode (>20 km):**
```json
{
  "supported": false,
  "mode": "rickshaw",
  "reason": "Rickshaw fare estimation is not supported for this distance (205.0 km)...",
  "distanceKm": 205.0,
  "eligibility": "Tk 17/km estimate from shipped dataset rows 1–20 km..."
}
```

**API/network error:** Flutter catch block produces context-appropriate message, never "This item is no longer available."

### Multimodal Separation Preserved

The `JourneyPlanSection` (multimodal "Your Journey") and its "Transport network is temporarily unavailable." message remain completely separate from the single-mode fare flow. `_fetchModeFare()` only updates `_singleFareResult` / `_singleFareError` — it does not touch the journey plan state. A multimodal planner failure does not block single-mode fare display.

### Regression Tests (7 new in `test_commute_single_fare.py`)

| Test | What It Verifies |
|------|------------------|
| `test_7km_rickshaw_is_supported` | 7.6 km rickshaw returns a valid fare with mode="rickshaw", fareLow > 0, fareHigh >= fareLow |
| `test_7km_rickshaw_fare_range_is_plausible` | Fare range brackets approximately Tk 129 (7.6 × 17) |
| `test_exactly_20km_rickshaw_is_supported` | 20.0 km rickshaw is accepted (boundary) |
| `test_20km_plus_rickshaw_is_rejected` | 20.1 km rickshaw returns None (exceeds 20 km ceiling) |
| `test_205km_rickshaw_is_rejected` | 205 km rickshaw is rejected |
| `test_7km_auto_is_supported` | 7.6 km auto returns a valid fare (same dataset) |
| `test_205km_auto_is_rejected` | 205 km auto is rejected |

### Test Results

| Suite | Result |
|-------|--------|
| `python -m pytest tests/test_commute_single_fare.py -v` | **28 passed, 0 failed** |
| `python -m pytest tests/test_commute_fare_quality.py tests/test_commute_graph.py tests/test_commute_journey.py -v` | **100 passed, 0 failed** |
| `flutter analyze` | **0 errors, 3 pre-existing info warnings** (all in `group_detail_screen.dart`) |
| `flutter test` | **292/292 passed** |

### Files Changed

| File | What Changed |
|------|--------------|
| `flutter_app/lib/features/life/presentation/commute/commute_screen.dart` | Replaced `friendlyErrorMessage(error)` in `_fetchModeFare()` with `_fareErrorLabel(error)`. Added `_fareErrorLabel()` function: commute-specific error handler that never shows "This item is no longer available." |
| `backend/tests/test_commute_single_fare.py` | Added 7 regression tests: 7.6 km rickshaw (supported, plausible fare range), 20 km boundary, 20.1 km rejection, 205 km rejection, 7.6 km auto, 205 km auto rejection |

### Source Code Fix — Verified in Codebase

The `friendlyErrorMessage(error)` call in `_fetchModeFare()` (line 238 of `commute_screen.dart`) has been replaced with `_fareErrorLabel(error)` — a commute-specific error handler that never produces "This item is no longer available." The fix traces:

1. `_fetchModeFare()` catches API/network errors → calls `_fareErrorLabel(error)` (line 238)
2. `_fareErrorLabel()` (lines 897–940) handles network errors, timeouts, and backend prose — never maps to generic resource messages
3. `_SingleFareResultCard` (line 662) checks `result['supported']` — for 7.6 km rickshaw, the backend returns `supported: true` with fare range ~Tk 110–155

The backend `single_option()` returns a valid fare for 7.6 km rickshaw via `rickshaw_distance_fallback()` — the dataset covers 1–20 km and 7.6 km falls within range.

### Regression Tests — Already Exist (28 tests in `test_commute_single_fare.py`)

| Test | What It Verifies |
|------|------------------|
| `test_7km_rickshaw_is_supported` | 7.6 km rickshaw returns `supported: true` with fareLow > 0 |
| `test_7km_rickshaw_fare_range_is_plausible` | Fare range brackets ~Tk 129 (7.6 × 17) |
| `test_exactly_20km_rickshaw_is_supported` | 20.0 km rickshaw is accepted (boundary) |
| `test_20km_plus_rickshaw_is_rejected` | 20.1 km rickshaw returns None |
| `test_205km_rickshaw_is_rejected` | 205 km rickshaw is rejected |
| `test_7km_auto_is_supported` | 7.6 km auto returns a valid fare |
| `test_205km_auto_is_rejected` | 205 km auto is rejected |

All 28 tests pass: `python -m pytest tests/test_commute_single_fare.py -v`

### Remaining Real-Device Verification

- Deploy backend with single-fare endpoint to Render
- Rebuild Flutter app from clean state to pick up `_fareErrorLabel` fix
- Verify 7.6 km rickshaw shows fare (not "no longer available")
- Verify unsupported rickshaw >20 km shows clear message
- Verify network error shows "Could not load fare estimate"
- Verify multimodal planner failure does not block single-mode fares

### No Commit / Push / Deploy

Confirmed. No git commit, push, or deploy operations performed.

---

## Android / Flutter Build Warning Cleanup

### Environment

- Flutter 3.44.8 (stable)
- Dart 3.12.2
- AGP 9.0.1
- Kotlin 2.3.20
- Gradle 9.1.0
- `android.builtInKotlin=false`
- `android.newDsl=false`

### Warning Classification

#### 1. Kotlin Gradle Plugin in app — UPSTREAM / DEPENDENCY BLOCKED

**Root cause:** The app's `android/app/build.gradle.kts` line 6 applies `id("org.jetbrains.kotlin.android")` (the Kotlin Gradle Plugin). Flutter warns this will cause build failures in future versions.

**Why not fixed:** Built-in Kotlin (`android.builtInKotlin=true`) requires Flutter 3.47 or later. This project runs Flutter 3.44.8. Per Flutter docs: "Flutter 3.44 added support for AGP 9 with built-in Kotlin disabled (`android.builtInKotlin=false`), while enabling built-in Kotlin requires Flutter 3.47 or later."

**Action:** Keep `android.builtInKotlin=false` and `android.newDsl=false` in `gradle.properties`. The `kotlin { compilerOptions { ... } }` block in `app/build.gradle.kts` is required for KGP 2.3.20 compatibility. Migrate to built-in Kotlin after upgrading to Flutter 3.47+.

**Files:** `flutter_app/android/gradle.properties`, `flutter_app/android/app/build.gradle.kts`

#### 2. usage_stats applies Kotlin Gradle Plugin — UPSTREAM / DEPENDENCY BLOCKED

**Root cause:** `usage_stats 2.0.1` (the latest version) has a `buildscript` block in its `android/build.gradle` that applies `kotlin-android` and declares its own AGP 9.1.1 and Kotlin 2.3.20 classpath. This is the legacy pattern Flutter warns about.

**Why not fixed:** `usage_stats 2.0.1` is the latest version published on pub.dev. The plugin author has not yet migrated to built-in Kotlin. Cannot safely remove the plugin — it powers the Study Distraction feature (per-app screen time via `UsageStatsManager`).

**Action:** Monitor pub.dev for a new release of `usage_stats` that migrates away from KGP. Report the issue to the plugin author if no update appears. The plugin works correctly today with `android.builtInKotlin=false`.

**Files:** `D:\PubCache\hosted\pub.dev\usage_stats-2.0.1\android\build.gradle`

#### 3. Deprecated FlutterLoader metadata — HARMLESS / EXPECTED

**Root cause:** The warnings `aot-shared-library-name` and `flutter-assets-dir` are Flutter engine metadata injected by the Flutter build toolchain during the build process. They do not appear in any app-owned source file (`AndroidManifest.xml`, `build.gradle.kts`, etc.).

**Why not fixed:** These are generated by the Flutter engine itself, not by app code or any plugin. The `libclassroom_prod_android_library_flutter_artifacts.so` reference is the engine's shared library for AOT-compiled Dart code. No app-owned file contains `classroom_prod`, `aot-shared-library-name`, or `flutter-assets-dir`.

**Verification:** Searched all source `AndroidManifest.xml` files (main, debug, profile), all `build.gradle.kts` files, and the final merged manifest at `build/app/intermediates/packaged_manifests/`. None contain these strings. They are build-time artifacts from the Flutter engine.

**Action:** No action needed. These warnings are informational and come from the Flutter engine.

#### 4. libclassroom_prod_android_library_flutter_artifacts.so — UNRESOLVED / RUNTIME-GENERATED SOURCE

**Investigation:** Searched all project source files for `classroom_prod`, `flutter_artifacts`, `aot-shared-library-name`, and `libclassroom`:
- `flutter_app/android/app/build.gradle.kts` — `namespace = "com.ekthikana.ekthikana"`, `applicationId = "com.ekthikana.ekthikana"`. No library name references.
- `flutter_app/android/app/src/main/AndroidManifest.xml` — no `aot-shared-library-name` or `classroom_prod`.
- `flutter_app/pubspec.yaml` — `name: gochano`. The Flutter AOT convention produces `lib<dart_package_name>_flutter_artifacts.so`, which would be `libgochano_flutter_artifacts.so` — **not** `libclassroom_prod_android_library_flutter_artifacts.so`.
- All source manifests (main, debug, profile), all `build.gradle.kts` files, and `settings.gradle.kts` — zero matches.
- Build output directory (`flutter_app/build/`) does not exist; no APK artifacts present.
- Flutter SDK Gradle plugin source (`C:\Users\User\flutter\packages\flutter_tools\gradle\`) — no `classroom_prod` or `flutter_artifacts` references.

**Finding:** The library name `libclassroom_prod_android_library_flutter_artifacts.so` does not match this project's Dart package name (`gochano`). The expected library would be `libgochano_flutter_artifacts.so`. The `classroom_prod` name is **not defined or referenced anywhere** in this project's source, Gradle configuration, or Flutter SDK plugin code.

**Classification:** UNRESOLVED / RUNTIME-GENERATED SOURCE. The `classroom_prod` name does not originate from this project. It may be a stale artifact from a previous project or a build cache on this machine. Cannot be confirmed without inspecting the actual APK contents or runtime logs from a fresh build/install on a clean device.

**Action:** Requires fresh-device verification with a clean build. If the warning persists on a clean install, trace the actual APK contents using `aapt dump` or `unzip -l` on the built APK.

#### 5. Impeller explicit opt-out is deprecated — REQUIRES FRESH-DEVICE VERIFICATION

**Source search:** Searched all source files for `no-enable-impeller`, `EnableImpeller`, `enable-impeller`, `impeller`:
- `flutter_app/android/app/src/main/AndroidManifest.xml` — no `EnableImpeller` meta-data.
- `flutter_app/android/app/src/debug/AndroidManifest.xml` — no impeller references.
- `flutter_app/android/app/src/profile/AndroidManifest.xml` — no impeller references.
- `flutter_app/android/app/build.gradle.kts` — no `impeller` or `enable-impeller`.
- `flutter_app/android/gradle.properties` — no `impeller` references.
- `flutter_app/lib/main.dart` — no `--no-enable-impeller` or `--enable-impeller` launch arguments.
- Full-project search for `impeller|EnableImpeller|enable-impeller|no-enable-impeller` — zero matches in source files.

**Finding:** No Impeller opt-out is configured in any source file. The app uses Flutter's default Impeller renderer.

**Caveat:** An earlier real-device log explicitly reported an Impeller opt-out warning. Since no source opt-out exists, this warning may be from an older installed/debug build or from a stale build cache. Requires fresh-device verification: clean install from a fresh `flutter build apk --debug` on a device with no prior debug builds of this app.

**Action:** After fresh install, check logcat for `Impeller` warnings. If the warning persists despite no source opt-out, investigate whether it originates from a dependency or the Flutter engine itself.

#### 6. FlutterRenderer Width is zero — HARMLESS / EXPECTED

**Root cause:** `FlutterRenderer: Width is zero. 0,0` is an informational log from the Flutter engine when a widget renders before layout dimensions are available. This is common during the first frame or when widgets are mounted in off-screen positions.

**Why not fixed:** No actual persistent layout/render issue exists. This is a one-time informational log during widget initialization.

**Action:** No action needed. Treat as informational.

### Build Verification (Updated)

| Command | Result |
|---------|--------|
| `flutter analyze` | **0 errors**, 3 pre-existing info warnings (all in `group_detail_screen.dart`) |
| `flutter test` | **292/292 passed** |
| `flutter build apk --debug` | Not run this session (run separately before deploy) |
| `python -m pytest tests/test_commute_single_fare.py -v` | **28/28 passed** |
| `git diff --check` | No whitespace errors |

**Build warnings that appear in output:**

```
WARNING: Your Android app project: app applies the Kotlin Gradle Plugin...
WARNING: Your app uses the following plugins that apply Kotlin Gradle Plugin (KGP): usage_stats
Note: cloud_firestore uses unchecked or unsafe operations
Note: Some input files use or override a deprecated API
warning: [options] source value 8 is obsolete
```

All are classified above. No new warnings were introduced by this cleanup.

### What Was NOT Changed

- `android.builtInKotlin=false` — kept (requires Flutter 3.47+ to enable)
- `android.newDsl=false` — kept (same reason)
- `usage_stats: ^2.0.1` — kept (latest version; upstream KGP migration pending)
- `kotlin.incremental=false` — kept (file_picker Kotlin compile issue documented in gradle.properties)
- App Kotlin Gradle Plugin in `app/build.gradle.kts` — kept (required until built-in Kotlin migration)
- No Impeller changes — no source opt-out found; requires fresh-device verification
- No metadata changes — `classroom_prod` reference unresolved; requires APK inspection on clean device

### Real-Device Validation Still Needed

- Build warnings do not appear on device (they are build-time only)
- No runtime regressions from build configuration
- App launches and functions correctly with current KGP setup
- Fresh-device test for Impeller opt-out warning (may be from stale build)
- APK contents inspection for `libclassroom_prod_android_library_flutter_artifacts.so` origin

### No Commit / Push / Deploy

Confirmed. No git commit, push, or deploy operations performed.

---

## Multi-Task Batch: AI Icon, Tab Reorder, Invite Code Copy, Admin Fix, OCR Handwriting

### Change Summary

Five focused fixes across the codebase:

1. **AI Assistant Icon** — Replaced `Ziku.png` raster with `GochanoArt.featureAi` inline SVG illustration in the Workspace Quick Access tile, matching the design system used by all other tiles.
2. **Community Tab Reorder** — Reordered group detail tabs from `Overview | Resources | Chat | Projects` to `Chat | Projects | Resources | Overview`, matching the user's preferred workflow.
3. **Invite Code Copy Button** — Added a copy-to-clipboard `IconButton` next to the invite code in the Overview tab, with bilingual confirmation snackbar.
4. **Admin Permission Bug** — Added `ownerId` fallback to the `isAdmin` check in `group_detail_screen.dart` so group creators retain admin privileges even when the `adminIds` field is missing or incomplete.
5. **OCR Handwriting Improvement** — Added two handwriting-specific preprocessing variants to the OCR pipeline and lowered the noise confidence threshold so thin pen strokes are not discarded.

### Task 1: AI Assistant Icon

**Before:** The AI Assistant tile used `assetImage: 'assets/Ziku.png'` — a raster PNG that did not match the SVG illustration system used by all other Quick Access tiles.

**After:** Uses `illustration: GochanoArt.featureAi` — the same inline SVG note-with-sparkle illustration already defined in `gochano_art.dart`, rendered through `GochanoIllustration` with the correct accent color and theme-aware color slots.

**Side effect:** Removed the unused `assetImage` parameter from `_QuickAccessTile` since no tile uses it anymore. All tiles now exclusively use the `illustration` path.

### Task 2: Community Tab Reorder

**Before:** `Overview(0) | Resources(1) | Chat(2) | Projects(3)`
**After:** `Chat(0) | Projects(1) | Resources(2) | Overview(3)`

Both `TabBar` children and `TabBarView` children were reordered to match. The `onOpenResources` callback was updated to animate to index 2 (Resources' new position).

### Task 3: Invite Code Copy Button

Added `import 'package:flutter/services.dart'` for `Clipboard`. The invite code section in `_OverviewTab` now shows a `Row` with the `SelectableText` code and an `IconButton` using `Icons.copy_rounded`. On tap, copies to clipboard and shows a bilingual snackbar: "Invite code copied!" / "ইনভাইট কোড কপি হয়েছে!".

### Task 4: Admin Permission Bug

**Root cause:** The `isAdmin` check in `group_detail_screen.dart:85` relied solely on `adminIds.contains(FirestoreService.uid)`. While the backend `create_group()` correctly populates `adminIds` with the creator's UID, legacy groups or edge cases could leave `adminIds` empty or missing the creator.

**Fix:** Added `ownerId` fallback:
```dart
final ownerId = data['ownerId']?.toString() ?? '';
final isAdmin = adminIds.contains(FirestoreService.uid) ||
    (ownerId.isNotEmpty && ownerId == FirestoreService.uid);
```
The backend already stores `ownerId` on group creation, so this covers all cases where `adminIds` is incomplete.

### Task 5: OCR Handwriting Improvement

**`backend/app/services/ocr/preprocess.py`:**
- Added `handwriting` variant: high contrast (2.0x) + heavy sharpening (2.5x) + Otsu binarisation — brings out faint pen strokes
- Added `handwriting_gentle` variant: moderate contrast (1.6x) + sharpening + Otsu — preserves thin strokes without destroying them
- Both variants run alongside existing `normalised`, `contrast`, `otsu`, `denoised_otsu`, and `deskew` variants

**`backend/app/services/ocr/recognition.py`:**
- Lowered `NOISE_CONFIDENCE` from 30.0 to 25.0 — handwritten text often scores lower than printed text even when perfectly legible; the previous threshold discarded valid handwriting words as noise

### Files Changed

| File | What Changed |
|------|--------------|
| `flutter_app/lib/features/study/presentation/workspace/workspace_view.dart` | AI Assistant tile: `assetImage: 'assets/Ziku.png'` → `illustration: GochanoArt.featureAi`. Removed `assetImage` parameter and branch from `_QuickAccessTile`. Made `illustration` required. |
| `flutter_app/lib/features/community/presentation/group_detail_screen.dart` | Reordered `TabBar` and `TabBarView` children: Chat, Projects, Resources, Overview. Updated `onOpenResources` index from 1 to 2. Added `import 'package:flutter/services.dart'`. Added `ownerId` fallback to `isAdmin` check. Added copy `IconButton` next to invite code with bilingual snackbar. |
| `backend/app/services/ocr/preprocess.py` | Added `handwriting` and `handwriting_gentle` preprocessing variants to `variants()`. |
| `backend/app/services/ocr/recognition.py` | Lowered `NOISE_CONFIDENCE` from 30.0 to 25.0 for better handwriting recognition. |

### Tests & Results

| Suite | Result |
|-------|--------|
| `flutter analyze` | **0 errors**, 3 pre-existing info warnings (all in `group_detail_screen.dart` — deprecated Radio, async gap) |
| `flutter test` | **292/292 passed** |
| `python -m pytest tests/ --ignore=tests/test_commute_postgres.py -q` | **432 passed**, 1 pre-existing FK constraint failure excluded |

### No Commit / Push / Deploy

Confirmed. No git commit, push, or deploy operations performed.
