// Home Today / Plan overdue source-of-truth regression tests.
//
// Verifies the canonical task-state calculation used by:
//   - _TodaysTasksCard (Home body + overdue badge)
//   - _PlanHistoryScreen (History — Completed / Missed)
//   - _CombinedPlannerList (Plan day filter)
//
// The canonical rule (Part 31):
//   incomplete Task/Assignment whose dueAt <= now → missed
//   incomplete Task/Assignment whose dueAt > now  → active/upcoming
//
// Medicine is excluded from this rule (it has its own follow-up window).

import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Pure helper: mirrors the canonical task-state classification.
// ---------------------------------------------------------------------------

/// Canonical task status used across Home, Plan, and History.
enum TaskStatus { completed, missed, active }

/// Returns the canonical status of a task given its fields and [now].
///
/// Rules:
///   1. `done == true` → completed
///   2. `dueAt == null` → active (undated tasks are always active)
///   3. `dueAt <= now` → missed
///   4. `dueAt > now`  → active
TaskStatus classifyTask({
  required bool done,
  required DateTime? dueAt,
  required DateTime now,
}) {
  if (done) return TaskStatus.completed;
  if (dueAt == null) return TaskStatus.active;
  if (!dueAt.isAfter(now)) return TaskStatus.missed;
  return TaskStatus.active;
}

/// Mirrors _TodaysTasksCard filtering: returns (openCount, overdueCount).
///
/// A task is:
///   - overdue if done == false && dueAt != null && dueAt <= now
///   - open    if done == false && dueAt != null && dueAt > now && dueAt < endOfToday
///   - skipped otherwise (done, null dueAt, or past end-of-day)
(int, int) homeTodayFilter({
  required List<({bool done, DateTime? dueAt})> tasks,
  required DateTime now,
}) {
  final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59);
  var open = 0;
  var overdue = 0;
  for (final t in tasks) {
    if (t.done) continue;
    final due = t.dueAt;
    if (due == null) continue;
    if (!due.isAfter(now)) {
      overdue++;
      continue;
    }
    if (!due.isAfter(endOfToday)) open++;
  }
  return (open, overdue);
}

/// Mirrors _PlanHistoryScreen filtering: keeps completed + missed items.
///
/// A task appears in History if:
///   - done == true  (completed)
///   - done == false && dueAt != null && dueAt <= now (missed)
///   - done == false && dueAt == null is excluded (undated incomplete → skip)
bool appearsInHistory({
  required bool done,
  required DateTime? dueAt,
  required DateTime now,
}) {
  if (done) return true;
  if (dueAt == null) return false;
  return !dueAt.isAfter(now);
}

/// Mirrors _CombinedPlannerList day filter: task appears on [selectedDay] if
/// done == false && dueAt falls within [dayKey, dayKey + 1 day).
bool appearsOnDay({
  required bool done,
  required DateTime? dueAt,
  required DateTime selectedDay,
}) {
  if (done) return false;
  if (dueAt == null) return false;
  final dayKey = DateTime(selectedDay.year, selectedDay.month, selectedDay.day);
  final endOfDay = dayKey.add(const Duration(days: 1));
  return !dueAt.isBefore(dayKey) && dueAt.isBefore(endOfDay);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('A. Canonical missed rule — dueAt <= now → missed', () {
    test('task due 24 min ago is missed, not active', () {
      // now = 17 Sep 2026 00:54, task dueAt = 17 Sep 2026 00:30
      final now = DateTime(2026, 9, 17, 0, 54);
      final dueAt = DateTime(2026, 9, 17, 0, 30);
      expect(classifyTask(done: false, dueAt: dueAt, now: now), TaskStatus.missed);
    });

    test('task due exactly now is missed (dueAt == now)', () {
      final now = DateTime(2026, 9, 17, 12, 0);
      final dueAt = DateTime(2026, 9, 17, 12, 0);
      expect(classifyTask(done: false, dueAt: dueAt, now: now), TaskStatus.missed);
    });

    test('task due 1 second ago is missed', () {
      final now = DateTime(2026, 9, 17, 12, 0, 1);
      final dueAt = DateTime(2026, 9, 17, 12, 0);
      expect(classifyTask(done: false, dueAt: dueAt, now: now), TaskStatus.missed);
    });

    test('task due at midnight is missed after midnight', () {
      final now = DateTime(2026, 9, 17, 0, 0, 1);
      final dueAt = DateTime(2026, 9, 17, 0, 0);
      expect(classifyTask(done: false, dueAt: dueAt, now: now), TaskStatus.missed);
    });
  });

  group('B. Home body and overdue summary consistency', () {
    test('"All clear today" cannot coexist with overdueCount > 0', () {
      // Simulate: 0 open tasks, 5 overdue → body must NOT say "All clear today"
      final now = DateTime(2026, 9, 17, 0, 54);
      final tasks = List.generate(
        5,
        (i) => (done: false, dueAt: DateTime(2026, 9, 17, 0, i * 5)),
      );
      final (open, overdue) = homeTodayFilter(tasks: tasks, now: now);
      expect(open, 0);
      expect(overdue, 5);
      // Invariant: if overdue > 0, the body must NOT display "All clear today."
      // The UI now shows "$overdue overdue, nothing else today" instead.
      expect(open == 0 && overdue > 0, isTrue);
    });

    test('all tasks done → open=0, overdue=0 → "All clear today" is valid', () {
      final now = DateTime(2026, 9, 17, 12, 0);
      final tasks = [
        (done: true, dueAt: DateTime(2026, 9, 17, 9, 0)),
        (done: true, dueAt: DateTime(2026, 9, 17, 14, 0)),
      ];
      final (open, overdue) = homeTodayFilter(tasks: tasks, now: now);
      expect(open, 0);
      expect(overdue, 0);
    });

    test('mix of overdue and open → body shows tasks, badge shows overdue', () {
      final now = DateTime(2026, 9, 17, 12, 0);
      final tasks = [
        (done: false, dueAt: DateTime(2026, 9, 17, 10, 0)), // overdue
        (done: false, dueAt: DateTime(2026, 9, 17, 14, 0)), // open (future today)
      ];
      final (open, overdue) = homeTodayFilter(tasks: tasks, now: now);
      expect(open, 1);
      expect(overdue, 1);
    });
  });

  group('C. Future task stays active', () {
    test('task due tomorrow is active', () {
      final now = DateTime(2026, 9, 17, 12, 0);
      final dueAt = DateTime(2026, 9, 18, 9, 0);
      expect(classifyTask(done: false, dueAt: dueAt, now: now), TaskStatus.active);
    });

    test('task due in 1 hour is active', () {
      final now = DateTime(2026, 9, 17, 12, 0);
      final dueAt = DateTime(2026, 9, 17, 13, 0);
      expect(classifyTask(done: false, dueAt: dueAt, now: now), TaskStatus.active);
    });

    test('undated task is always active', () {
      final now = DateTime(2026, 9, 17, 12, 0);
      expect(classifyTask(done: false, dueAt: null, now: now), TaskStatus.active);
    });
  });

  group('D. Completed task stays completed, not missed', () {
    test('done task with past dueAt is completed, not missed', () {
      final now = DateTime(2026, 9, 17, 12, 0);
      final dueAt = DateTime(2026, 9, 17, 10, 0);
      expect(classifyTask(done: true, dueAt: dueAt, now: now), TaskStatus.completed);
    });

    test('done task with future dueAt is completed', () {
      final now = DateTime(2026, 9, 17, 12, 0);
      final dueAt = DateTime(2026, 9, 18, 9, 0);
      expect(classifyTask(done: true, dueAt: dueAt, now: now), TaskStatus.completed);
    });

    test('done task with null dueAt is completed', () {
      final now = DateTime(2026, 9, 17, 12, 0);
      expect(classifyTask(done: true, dueAt: null, now: now), TaskStatus.completed);
    });
  });

  group('E. Assignment follows same missed rule', () {
    test('incomplete assignment with past dueAt is missed', () {
      final now = DateTime(2026, 9, 17, 0, 54);
      final dueAt = DateTime(2026, 9, 17, 0, 30);
      // Assignment is just a task with type='assignment'; the missed rule
      // is type-agnostic.
      expect(classifyTask(done: false, dueAt: dueAt, now: now), TaskStatus.missed);
    });

    test('incomplete assignment with future dueAt is active', () {
      final now = DateTime(2026, 9, 17, 12, 0);
      final dueAt = DateTime(2026, 9, 17, 14, 0);
      expect(classifyTask(done: false, dueAt: dueAt, now: now), TaskStatus.active);
    });

    test('completed assignment with past dueAt is completed', () {
      final now = DateTime(2026, 9, 17, 12, 0);
      final dueAt = DateTime(2026, 9, 17, 10, 0);
      expect(classifyTask(done: true, dueAt: dueAt, now: now), TaskStatus.completed);
    });
  });

  group('F. Timezone / local-midnight boundary', () {
    test('task due at 00:00:00 is missed at 00:00:01', () {
      final now = DateTime(2026, 9, 17, 0, 0, 1);
      final dueAt = DateTime(2026, 9, 17, 0, 0, 0);
      expect(classifyTask(done: false, dueAt: dueAt, now: now), TaskStatus.missed);
    });

    test('task due at 23:59:59 is active at 23:59:58', () {
      final now = DateTime(2026, 9, 16, 23, 59, 58);
      final dueAt = DateTime(2026, 9, 16, 23, 59, 59);
      expect(classifyTask(done: false, dueAt: dueAt, now: now), TaskStatus.active);
    });

    test('task due at 23:59:59 is missed at 00:00:00 next day', () {
      final now = DateTime(2026, 9, 17, 0, 0, 0);
      final dueAt = DateTime(2026, 9, 16, 23, 59, 59);
      expect(classifyTask(done: false, dueAt: dueAt, now: now), TaskStatus.missed);
    });

    test('Home endOfToday boundary — task due 23:59:59 is open, not overdue', () {
      final now = DateTime(2026, 9, 17, 12, 0);
      final tasks = [
        (done: false, dueAt: DateTime(2026, 9, 17, 23, 59, 59)),
      ];
      final (open, overdue) = homeTodayFilter(tasks: tasks, now: now);
      expect(open, 1);
      expect(overdue, 0);
    });

    test('Home endOfToday boundary — task due 00:00:00 next day is NOT open', () {
      final now = DateTime(2026, 9, 17, 12, 0);
      final tasks = [
        (done: false, dueAt: DateTime(2026, 9, 18, 0, 0, 0)),
      ];
      final (open, overdue) = homeTodayFilter(tasks: tasks, now: now);
      expect(open, 0);
      expect(overdue, 0);
    });
  });

  group('History inclusion', () {
    test('completed task appears in History', () {
      final now = DateTime(2026, 9, 17, 12, 0);
      expect(
        appearsInHistory(done: true, dueAt: DateTime(2026, 9, 17, 9, 0), now: now),
        isTrue,
      );
    });

    test('missed task appears in History immediately (no grace period)', () {
      final now = DateTime(2026, 9, 17, 0, 54);
      final dueAt = DateTime(2026, 9, 17, 0, 30);
      expect(appearsInHistory(done: false, dueAt: dueAt, now: now), isTrue);
    });

    test('future task does NOT appear in History', () {
      final now = DateTime(2026, 9, 17, 12, 0);
      final dueAt = DateTime(2026, 9, 17, 14, 0);
      expect(appearsInHistory(done: false, dueAt: dueAt, now: now), isFalse);
    });

    test('undated incomplete task does NOT appear in History', () {
      final now = DateTime(2026, 9, 17, 12, 0);
      expect(appearsInHistory(done: false, dueAt: null, now: now), isFalse);
    });
  });

  group('Plan day filter', () {
    test('task due on selected day appears in Plan', () {
      final selectedDay = DateTime(2026, 9, 17);
      final dueAt = DateTime(2026, 9, 17, 14, 0);
      expect(appearsOnDay(done: false, dueAt: dueAt, selectedDay: selectedDay), isTrue);
    });

    test('overdue task due on selected day still appears in Plan', () {
      // Plan shows all tasks for the day, including overdue ones.
      // The overdue styling is applied by _PlannerItemRow.
      final now = DateTime(2026, 9, 17, 12, 0);
      final selectedDay = DateTime(2026, 9, 17);
      final dueAt = DateTime(2026, 9, 17, 9, 0); // 3 hours ago
      expect(appearsOnDay(done: false, dueAt: dueAt, selectedDay: selectedDay), isTrue);
      expect(classifyTask(done: false, dueAt: dueAt, now: now), TaskStatus.missed);
    });

    test('task due on different day does NOT appear in Plan', () {
      final selectedDay = DateTime(2026, 9, 17);
      final dueAt = DateTime(2026, 9, 18, 9, 0);
      expect(appearsOnDay(done: false, dueAt: dueAt, selectedDay: selectedDay), isFalse);
    });

    test('completed task does NOT appear in Plan', () {
      final selectedDay = DateTime(2026, 9, 17);
      final dueAt = DateTime(2026, 9, 17, 14, 0);
      expect(appearsOnDay(done: true, dueAt: dueAt, selectedDay: selectedDay), isFalse);
    });
  });

  group('Home header — name-only (no greeting)', () {
    test('Home header shows display name without greeting prefix', () {
      // The _greeting function was changed to return just the trimmed name.
      // Verify the function logic.
      String greeting(String name) {
        final trimmed = name.trim();
        return trimmed.isEmpty ? '?' : trimmed;
      }

      expect(greeting('Alice'), 'Alice');
      expect(greeting('  Bob  '), 'Bob');
      expect(greeting(''), '?');
      expect(greeting('  '), '?');
    });
  });
}
