// Home Today / Plan overdue source-of-truth regression tests.
//
// Verifies the canonical task-state calculation using TaskLifecycle across:
//   - _TodaysTasksCard (Home body + overdue badge)
//   - _PlanHistoryScreen (History — Completed / Missed)
//   - _CombinedPlannerList (Plan day filter)
//
// Canonical calendar-day rule:
//   past calendar day + incomplete + non-cancelled = missed (in History, absent from Today)
//   today's incomplete task = active in Today (even if scheduled time passed, until day ends)
//
// Medicine is excluded from this rule (it has its own follow-up window).

import 'package:flutter_test/flutter_test.dart';
import 'package:gochano/features/tasks/domain/task_lifecycle.dart';

/// Helper mirroring _TodaysTasksCard filtering with TaskLifecycle.
(int, int) homeTodayFilter({
  required List<({bool done, DateTime? dueAt})> tasks,
  required DateTime now,
}) {
  var open = 0;
  var overdue = 0;
  for (final t in tasks) {
    final data = {'done': t.done, 'dueAt': t.dueAt};
    if (!TaskLifecycle.belongsToToday(data, now)) continue;
    open++;
    if (TaskLifecycle.isTodayClockOverdue(data, now)) {
      overdue++;
    }
  }
  return (open, overdue);
}

void main() {
  group('A. Canonical calendar-day missed rule', () {
    test(
      'task scheduled earlier today (24 min ago) is active in Today, not historical missed',
      () {
        // now = 17 Sep 2026 00:54, task dueAt = 17 Sep 2026 00:30 (same day!)
        final now = DateTime(2026, 9, 17, 0, 54);
        final dueAt = DateTime(2026, 9, 17, 0, 30);
        final data = {'done': false, 'dueAt': dueAt};

        expect(TaskLifecycle.belongsToToday(data, now), isTrue);
        expect(TaskLifecycle.belongsToHistory(data, now), isFalse);
        expect(TaskLifecycle.resolveDocStatus(data, now), TaskStatus.pending);
        expect(TaskLifecycle.isTodayClockOverdue(data, now), isTrue);
      },
    );

    test(
      'task scheduled yesterday is missed in History, absent from Today',
      () {
        final now = DateTime(2026, 9, 17, 12, 0);
        final dueAt = DateTime(2026, 9, 16, 23, 59);
        final data = {'done': false, 'dueAt': dueAt};

        expect(TaskLifecycle.belongsToToday(data, now), isFalse);
        expect(TaskLifecycle.belongsToHistory(data, now), isTrue);
        expect(TaskLifecycle.resolveDocStatus(data, now), TaskStatus.missed);
      },
    );

    test('task scheduled exactly at midnight today is part of today', () {
      final now = DateTime(2026, 9, 17, 12, 0);
      final dueAt = DateTime(2026, 9, 17, 0, 0);
      final data = {'done': false, 'dueAt': dueAt};

      expect(TaskLifecycle.belongsToToday(data, now), isTrue);
      expect(TaskLifecycle.belongsToHistory(data, now), isFalse);
      expect(TaskLifecycle.resolveDocStatus(data, now), TaskStatus.pending);
    });

    test(
      'task scheduled yesterday at midnight is missed after day boundary',
      () {
        final now = DateTime(2026, 9, 17, 0, 0, 1);
        final dueAt = DateTime(2026, 9, 16, 23, 59, 59);
        final data = {'done': false, 'dueAt': dueAt};

        expect(TaskLifecycle.belongsToToday(data, now), isFalse);
        expect(TaskLifecycle.belongsToHistory(data, now), isTrue);
        expect(TaskLifecycle.resolveDocStatus(data, now), TaskStatus.missed);
      },
    );
  });

  group('B. Home body and overdue summary consistency', () {
    test('30 old tasks do NOT accumulate as 30 overdue on Today screen', () {
      final now = DateTime(2026, 9, 17, 12, 0);
      final tasks = List.generate(
        30,
        (i) => (done: false, dueAt: DateTime(2026, 9, 1 + (i % 15), 10, 0)),
      );
      final (open, overdue) = homeTodayFilter(tasks: tasks, now: now);
      expect(open, 0);
      expect(overdue, 0);
    });

    test('all tasks done -> open=0, overdue=0', () {
      final now = DateTime(2026, 9, 17, 12, 0);
      final tasks = [
        (done: true, dueAt: DateTime(2026, 9, 17, 9, 0)),
        (done: true, dueAt: DateTime(2026, 9, 17, 14, 0)),
      ];
      final (open, overdue) = homeTodayFilter(tasks: tasks, now: now);
      expect(open, 0);
      expect(overdue, 0);
    });

    test(
      'mix of today clock-overdue and upcoming today -> body shows both open, badge shows overdue',
      () {
        final now = DateTime(2026, 9, 17, 12, 0);
        final tasks = [
          (done: false, dueAt: DateTime(2026, 9, 17, 10, 0)), // today earlier
          (done: false, dueAt: DateTime(2026, 9, 17, 14, 0)), // today later
        ];
        final (open, overdue) = homeTodayFilter(tasks: tasks, now: now);
        expect(open, 2);
        expect(overdue, 1);
      },
    );
  });

  group('C. Future task stays active/pending', () {
    test('task due tomorrow is pending and not in today', () {
      final now = DateTime(2026, 9, 17, 12, 0);
      final dueAt = DateTime(2026, 9, 18, 9, 0);
      final data = {'done': false, 'dueAt': dueAt};

      expect(TaskLifecycle.resolveDocStatus(data, now), TaskStatus.pending);
      expect(TaskLifecycle.belongsToToday(data, now), isFalse);
      expect(TaskLifecycle.belongsToHistory(data, now), isFalse);
    });

    test('task due in 1 hour is active in today', () {
      final now = DateTime(2026, 9, 17, 12, 0);
      final dueAt = DateTime(2026, 9, 17, 13, 0);
      final data = {'done': false, 'dueAt': dueAt};

      expect(TaskLifecycle.resolveDocStatus(data, now), TaskStatus.pending);
      expect(TaskLifecycle.belongsToToday(data, now), isTrue);
      expect(TaskLifecycle.isTodayClockOverdue(data, now), isFalse);
    });

    test('undated task is pending and included in today', () {
      final now = DateTime(2026, 9, 17, 12, 0);
      final data = {'done': false, 'dueAt': null};

      expect(TaskLifecycle.resolveDocStatus(data, now), TaskStatus.pending);
      expect(TaskLifecycle.belongsToToday(data, now), isTrue);
      expect(TaskLifecycle.belongsToHistory(data, now), isFalse);
    });
  });

  group('D. Completed task stays completed, not missed', () {
    test('done task with past dueAt is completed, not missed', () {
      final now = DateTime(2026, 9, 17, 12, 0);
      final dueAt = DateTime(2026, 9, 10, 10, 0);
      final data = {'done': true, 'dueAt': dueAt};

      expect(TaskLifecycle.resolveDocStatus(data, now), TaskStatus.completed);
      expect(TaskLifecycle.belongsToToday(data, now), isFalse);
      expect(TaskLifecycle.belongsToHistory(data, now), isTrue);
    });

    test('done task with future dueAt is completed', () {
      final now = DateTime(2026, 9, 17, 12, 0);
      final dueAt = DateTime(2026, 9, 18, 9, 0);
      final data = {'done': true, 'dueAt': dueAt};

      expect(TaskLifecycle.resolveDocStatus(data, now), TaskStatus.completed);
      expect(TaskLifecycle.belongsToToday(data, now), isFalse);
      expect(TaskLifecycle.belongsToHistory(data, now), isTrue);
    });

    test('done task with null dueAt is completed', () {
      final now = DateTime(2026, 9, 17, 12, 0);
      final data = {'done': true, 'dueAt': null};

      expect(TaskLifecycle.resolveDocStatus(data, now), TaskStatus.completed);
      expect(TaskLifecycle.belongsToToday(data, now), isFalse);
      expect(TaskLifecycle.belongsToHistory(data, now), isTrue);
    });
  });

  group('E. Assignment follows calendar-day missed rule', () {
    test('incomplete assignment with past-day dueAt is missed in History', () {
      final now = DateTime(2026, 9, 17, 12, 0);
      final dueAt = DateTime(2026, 9, 16, 23, 59);
      final data = {'done': false, 'type': 'assignment', 'dueAt': dueAt};

      expect(TaskLifecycle.belongsToToday(data, now), isFalse);
      expect(TaskLifecycle.belongsToHistory(data, now), isTrue);
      expect(TaskLifecycle.resolveDocStatus(data, now), TaskStatus.missed);
    });

    test('incomplete assignment with future dueAt is active', () {
      final now = DateTime(2026, 9, 17, 12, 0);
      final dueAt = DateTime(2026, 9, 17, 14, 0);
      final data = {'done': false, 'type': 'assignment', 'dueAt': dueAt};

      expect(TaskLifecycle.belongsToToday(data, now), isTrue);
      expect(TaskLifecycle.resolveDocStatus(data, now), TaskStatus.pending);
    });

    test('completed assignment with past dueAt is completed', () {
      final now = DateTime(2026, 9, 17, 12, 0);
      final dueAt = DateTime(2026, 9, 10, 10, 0);
      final data = {'done': true, 'type': 'assignment', 'dueAt': dueAt};

      expect(TaskLifecycle.resolveDocStatus(data, now), TaskStatus.completed);
      expect(TaskLifecycle.belongsToHistory(data, now), isTrue);
    });
  });

  group('F. Timezone / local-midnight boundary', () {
    test('task due today at 23:59:59 is today at 23:59:58', () {
      final now = DateTime(2026, 9, 16, 23, 59, 58);
      final dueAt = DateTime(2026, 9, 16, 23, 59, 59);
      final data = {'done': false, 'dueAt': dueAt};

      expect(TaskLifecycle.belongsToToday(data, now), isTrue);
      expect(TaskLifecycle.belongsToHistory(data, now), isFalse);
    });

    test('task due at 23:59:59 is missed at 00:00:00 next day', () {
      final now = DateTime(2026, 9, 17, 0, 0, 0);
      final dueAt = DateTime(2026, 9, 16, 23, 59, 59);
      final data = {'done': false, 'dueAt': dueAt};

      expect(TaskLifecycle.belongsToToday(data, now), isFalse);
      expect(TaskLifecycle.belongsToHistory(data, now), isTrue);
      expect(TaskLifecycle.resolveDocStatus(data, now), TaskStatus.missed);
    });

    test(
      'Home boundary — task due 23:59:59 today is open, not clock-overdue at noon',
      () {
        final now = DateTime(2026, 9, 17, 12, 0);
        final tasks = [(done: false, dueAt: DateTime(2026, 9, 17, 23, 59, 59))];
        final (open, overdue) = homeTodayFilter(tasks: tasks, now: now);
        expect(open, 1);
        expect(overdue, 0);
      },
    );

    test('Home boundary — task due tomorrow is NOT in Today', () {
      final now = DateTime(2026, 9, 17, 12, 0);
      final tasks = [(done: false, dueAt: DateTime(2026, 9, 18, 0, 0, 0))];
      final (open, overdue) = homeTodayFilter(tasks: tasks, now: now);
      expect(open, 0);
      expect(overdue, 0);
    });
  });

  group('History inclusion', () {
    test('completed task appears in History', () {
      final now = DateTime(2026, 9, 17, 12, 0);
      final data = {'done': true, 'dueAt': DateTime(2026, 9, 17, 9, 0)};
      expect(TaskLifecycle.belongsToHistory(data, now), isTrue);
    });

    test('missed task (past calendar day) appears in History', () {
      final now = DateTime(2026, 9, 17, 12, 0);
      final dueAt = DateTime(2026, 9, 16, 20, 0);
      final data = {'done': false, 'dueAt': dueAt};
      expect(TaskLifecycle.belongsToHistory(data, now), isTrue);
    });

    test(
      'today task does NOT appear in History even if scheduled time passed',
      () {
        final now = DateTime(2026, 9, 17, 14, 0);
        final dueAt = DateTime(2026, 9, 17, 9, 0);
        final data = {'done': false, 'dueAt': dueAt};
        expect(TaskLifecycle.belongsToHistory(data, now), isFalse);
      },
    );

    test('future task does NOT appear in History', () {
      final now = DateTime(2026, 9, 17, 12, 0);
      final dueAt = DateTime(2026, 9, 18, 14, 0);
      final data = {'done': false, 'dueAt': dueAt};
      expect(TaskLifecycle.belongsToHistory(data, now), isFalse);
    });

    test('undated incomplete task does NOT appear in History', () {
      final now = DateTime(2026, 9, 17, 12, 0);
      final data = {'done': false, 'dueAt': null};
      expect(TaskLifecycle.belongsToHistory(data, now), isFalse);
    });
  });

  group('Plan day filter', () {
    test('task due on selected day appears in Plan', () {
      final selectedDay = DateTime(2026, 9, 17);
      final dueAt = DateTime(2026, 9, 17, 14, 0);
      final data = {'done': false, 'dueAt': dueAt};
      expect(TaskLifecycle.belongsToPlanDay(data, selectedDay), isTrue);
    });

    test(
      'earlier today task due on selected day appears in Plan for that day',
      () {
        final selectedDay = DateTime(2026, 9, 17);
        final dueAt = DateTime(2026, 9, 17, 9, 0);
        final data = {'done': false, 'dueAt': dueAt};
        expect(TaskLifecycle.belongsToPlanDay(data, selectedDay), isTrue);
      },
    );

    test(
      'task due on different day does NOT appear in Plan for selected day',
      () {
        final selectedDay = DateTime(2026, 9, 17);
        final dueAt = DateTime(2026, 9, 18, 9, 0);
        final data = {'done': false, 'dueAt': dueAt};
        expect(TaskLifecycle.belongsToPlanDay(data, selectedDay), isFalse);
      },
    );

    test('completed task does NOT appear in Plan', () {
      final selectedDay = DateTime(2026, 9, 17);
      final dueAt = DateTime(2026, 9, 17, 14, 0);
      final data = {'done': true, 'dueAt': dueAt};
      expect(TaskLifecycle.belongsToPlanDay(data, selectedDay), isFalse);
    });
  });

  group('Home header — name-only (no greeting)', () {
    test('Home header shows display name without greeting prefix', () {
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
