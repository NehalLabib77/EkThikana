# IMPLEMENTATION REPORT

## Feature 1 — Assignment/Task Bento Cards + Quick Add

### Verified Behavior

| Requirement | Status | Evidence |
|-------------|--------|----------|
| Assignment due DATE + TIME | ✅ | `add_task_sheet.dart:75-106` — `showDatePicker` then `showTimePicker`, stored as `DateTime` in `_dueAt` |
| Assignment separate reminder DATE + TIME | ✅ | `add_task_sheet.dart:108-154` — `_pickReminderDate()` with date+time picker, separate `_remindAt` field |
| Task due DATE + TIME | ✅ | Same form — shared for both assignment and task |
| Task separate reminder DATE + TIME | ✅ | Same `_remindAt` field — independent of `_dueAt` |
| Edit loads existing remindAt | ✅ | `add_task_sheet.dart:65` — `_remindAt = (data['remindAt'] as Timestamp?)?.toDate()` |
| Edit preserves/reschedules reminder | ✅ | `add_task_sheet.dart:210-214` — `NotificationService.rescheduleTask(when: _remind ? _remindAt : null)` |
| Complete cancels pending reminder | ✅ | `plan_view.dart` — `_setDone()` calls `rescheduleTask(when: done ? null : remindAt)` |
| Delete cancels pending reminder | ✅ | `plan_view.dart` — `_delete()` calls `NotificationService.cancelTask(doc.id)` before Firestore delete |
| Reminder OFF cancels notification | ✅ | `add_task_sheet.dart:213` — passes null to reschedule |
| Prevent reminder after due time | ✅ | `add_task_sheet.dart:139-148,173-183` — picker validation + save safety-net |
| Reminder default near/before dueAt | ✅ | `add_task_sheet.dart:296-298` — defaults to 1 hour before `_dueAt` |
| Due date change clears stale reminder | ✅ | `add_task_sheet.dart:101-104` — clears `_remindAt` if now after new `_dueAt` |
| No duplicate notifications | ✅ | `notification_service.dart:192-193` — deterministic ID: `taskId.hashCode & 0x7fffffff` |
| Data persists after restart | ✅ | Firestore for task data; `zonedSchedule` persists in Android AlarmManager |
| EN/Bangla localization | ✅ | All labels use `GochanoLanguage.text(en, bn)` |
| Old records compatible | ✅ | `add_task_sheet.dart:65-66` — existing `remindAt == dueAt` records load correctly |

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
| Reminder ON, picks time | `_remindAt` saved to Firestore; notification scheduled at `_remindAt` |
| Reminder OFF | `remindAt` set to null; `rescheduleTask(when: null)` cancels pending |
| Edit existing task | `_remindAt` loaded from doc; picker shows existing time; reschedule on save |
| Due date changed after reminder set | If `_remindAt >= _dueAt`, auto-clear `_remindAt` |
| Reminder picked after due | Validation error: "Reminder must be before the due time." |
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
| `flutter_app/lib/features/tasks/presentation/add_task_sheet.dart` | Added `_remindAt` field, `_pickReminderDate()`, reminder picker UI, reminder-after-due validation, save writes separate `remindAt`, default 1h before due; `type` param on `showAddTaskSheet()` and `_TaskForm` |
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

## Final Tests

| Suite | Result |
|-------|--------|
| Flutter | **282/282 passed** |
| Backend (full) | **360/360 passed** |
| Backend test_part3 | **62/62 passed** |

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
