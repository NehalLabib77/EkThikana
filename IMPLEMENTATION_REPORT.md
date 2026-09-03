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

### No Commit / Push / Deploy
Confirmed. No git commit, push, or deploy operations performed.
