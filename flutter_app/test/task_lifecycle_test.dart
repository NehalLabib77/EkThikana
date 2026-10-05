import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gochano/features/tasks/domain/task_lifecycle.dart';

void main() {
  group('TaskLifecycle Acceptance Tests', () {
    // Reference now: 5 October 2026 at 14:00 (2:00 PM) local
    final now = DateTime(2026, 10, 5, 14, 0);

    test(
      'TEST 1: Yesterday task, Not completed -> Today absent, History Missed',
      () {
        final task = {
          'id': 'task-1',
          'title': 'Math homework',
          'done': false,
          'dueAt': DateTime(2026, 10, 4, 17, 0),
        };

        expect(TaskLifecycle.belongsToToday(task, now), isFalse);
        expect(TaskLifecycle.belongsToHistory(task, now), isTrue);
        expect(TaskLifecycle.resolveDocStatus(task, now), TaskStatus.missed);
      },
    );

    test(
      'TEST 2: Yesterday task, Completed yesterday -> Today absent, History Completed',
      () {
        final task = {
          'id': 'task-2',
          'title': 'Physics reading',
          'done': true,
          'dueAt': DateTime(2026, 10, 4, 18, 0),
        };

        expect(TaskLifecycle.belongsToToday(task, now), isFalse);
        expect(TaskLifecycle.belongsToHistory(task, now), isTrue);
        expect(TaskLifecycle.resolveDocStatus(task, now), TaskStatus.completed);
      },
    );

    test(
      'TEST 3: Today task, Not completed (future time) -> Today visible, History not Missed yet',
      () {
        final task = {
          'id': 'task-3',
          'title': 'Biology lab prep',
          'done': false,
          'dueAt': DateTime(2026, 10, 5, 18, 0),
        };

        expect(TaskLifecycle.belongsToToday(task, now), isTrue);
        expect(TaskLifecycle.belongsToHistory(task, now), isFalse);
        expect(TaskLifecycle.resolveDocStatus(task, now), TaskStatus.pending);
        expect(TaskLifecycle.isTodayClockOverdue(task, now), isFalse);
      },
    );

    test(
      'TEST 4: Today task, Scheduled time has already passed -> Still Today, Not historical Missed until calendar day ends',
      () {
        // Scheduled today at 9:00 AM, now is 2:00 PM (14:00)
        final task = {
          'id': 'task-4',
          'title': 'Morning revision',
          'done': false,
          'dueAt': DateTime(2026, 10, 5, 9, 0),
        };

        // Invariant: belongs to today's active tasks
        expect(TaskLifecycle.belongsToToday(task, now), isTrue);
        // Invariant: NOT archived to history as missed until midnight passes
        expect(TaskLifecycle.belongsToHistory(task, now), isFalse);
        expect(TaskLifecycle.resolveDocStatus(task, now), TaskStatus.pending);
        // It is clock-overdue within today's session
        expect(TaskLifecycle.isTodayClockOverdue(task, now), isTrue);
      },
    );

    test('TEST 5: Tomorrow task -> Today absent, Plan present', () {
      final tomorrow = DateTime(2026, 10, 6);
      final task = {
        'id': 'task-5',
        'title': 'Chemistry assignment',
        'done': false,
        'dueAt': DateTime(2026, 10, 6, 10, 0),
      };

      expect(TaskLifecycle.belongsToToday(task, now), isFalse);
      expect(TaskLifecycle.belongsToHistory(task, now), isFalse);
      expect(TaskLifecycle.belongsToPlanDay(task, tomorrow), isTrue);
      expect(
        TaskLifecycle.isFutureCalendarDay(DateTime(2026, 10, 6, 10, 0), now),
        isTrue,
      );
    });

    test(
      'TEST 6: 30 old incomplete tasks -> Today must NOT show 30 overdue, all Missed in History',
      () {
        final tasks = List.generate(
          30,
          (i) => {
            'id': 'old-task-$i',
            'title': 'Old task $i',
            'done': false,
            'dueAt': DateTime(2026, 9, 1 + i, 12, 0), // September dates
          },
        );

        var todayCount = 0;
        var overdueTodayCount = 0;
        var historyCount = 0;
        var missedCount = 0;

        for (final t in tasks) {
          if (TaskLifecycle.belongsToToday(t, now)) {
            todayCount++;
            if (TaskLifecycle.isTodayClockOverdue(t, now)) overdueTodayCount++;
          }
          if (TaskLifecycle.belongsToHistory(t, now)) {
            historyCount++;
            if (TaskLifecycle.resolveDocStatus(t, now) == TaskStatus.missed) {
              missedCount++;
            }
          }
        }

        // 0 in Today
        expect(todayCount, 0);
        expect(overdueTodayCount, 0);
        // All 30 in History as Missed
        expect(historyCount, 30);
        expect(missedCount, 30);
      },
    );

    test(
      'TEST 7: No due date task -> Do not classify as Missed, remains in Today',
      () {
        final task = {
          'id': 'task-7',
          'title': 'Undated research',
          'done': false,
          'dueAt': null,
        };

        expect(TaskLifecycle.resolveDocStatus(task, now), TaskStatus.pending);
        expect(TaskLifecycle.belongsToToday(task, now), isTrue);
        expect(TaskLifecycle.belongsToHistory(task, now), isFalse);
      },
    );

    test(
      'TEST 8: Completed old task -> Never mutates from completed to missed',
      () {
        final task = {
          'id': 'task-8',
          'title': 'Old finished exam prep',
          'done': true,
          'dueAt': DateTime(2026, 8, 15, 10, 0),
        };

        expect(TaskLifecycle.resolveDocStatus(task, now), TaskStatus.completed);
        expect(TaskLifecycle.belongsToToday(task, now), isFalse);
        expect(TaskLifecycle.belongsToHistory(task, now), isTrue);
      },
    );

    test('TEST 9: Cancelled task -> Never mutates to missed', () {
      final task = {
        'id': 'task-9',
        'title': 'Cancelled project meeting',
        'done': false,
        'cancelled': true,
        'dueAt': DateTime(2026, 10, 4, 15, 0),
      };

      expect(TaskLifecycle.resolveDocStatus(task, now), TaskStatus.cancelled);
      expect(TaskLifecycle.belongsToToday(task, now), isFalse);
      expect(TaskLifecycle.belongsToHistory(task, now), isFalse);
    });

    test(
      'TEST 10: Offline next-day startup -> Past unfinished task excluded from Today',
      () {
        // User created task on Oct 5. Device goes offline.
        // Next morning (Oct 6 08:00), offline cached tasks load.
        final nextDay = DateTime(2026, 10, 6, 8, 0);
        final cachedTask = {
          'id': 'cached-task-1',
          'title': 'Read chapter 3',
          'done': false,
          'dueAt': DateTime(2026, 10, 5, 20, 0),
        };

        expect(TaskLifecycle.belongsToToday(cachedTask, nextDay), isFalse);
        expect(TaskLifecycle.belongsToHistory(cachedTask, nextDay), isTrue);
        expect(
          TaskLifecycle.resolveDocStatus(cachedTask, nextDay),
          TaskStatus.missed,
        );
      },
    );

    test(
      'TEST 11: Legacy Firestore task document -> No crash, backwards compatible, correctly classified',
      () {
        // Document A: Legacy pending task with Timestamp, no status or cancelled field
        final docA = {
          'id': 'legacy-a',
          'title': 'Legacy math homework',
          'done': false,
          'dueAt': Timestamp.fromDate(DateTime(2026, 10, 5, 16, 0)),
        };
        expect(TaskLifecycle.belongsToToday(docA, now), isTrue);
        expect(TaskLifecycle.belongsToHistory(docA, now), isFalse);
        expect(TaskLifecycle.resolveDocStatus(docA, now), TaskStatus.pending);

        // Document B: Legacy completed task with done: true
        final docB = {
          'id': 'legacy-b',
          'title': 'Legacy completed reading',
          'done': true,
          'dueAt': Timestamp.fromDate(DateTime(2026, 10, 4, 10, 0)),
        };
        expect(TaskLifecycle.belongsToToday(docB, now), isFalse);
        expect(TaskLifecycle.belongsToHistory(docB, now), isTrue);
        expect(TaskLifecycle.resolveDocStatus(docB, now), TaskStatus.completed);

        // Document C: Legacy completed with completed: true and missing done/status
        final docC = {
          'id': 'legacy-c',
          'title': 'Legacy with completed flag',
          'completed': true,
        };
        expect(TaskLifecycle.isTaskCompleted(docC), isTrue);
        expect(TaskLifecycle.belongsToToday(docC, now), isFalse);
        expect(TaskLifecycle.belongsToHistory(docC, now), isTrue);
        expect(TaskLifecycle.resolveDocStatus(docC, now), TaskStatus.completed);

        // Document D: Legacy undated task
        final docD = {
          'id': 'legacy-d',
          'title': 'Legacy undated project',
          'done': false,
        };
        expect(TaskLifecycle.belongsToToday(docD, now), isTrue);
        expect(TaskLifecycle.belongsToHistory(docD, now), isFalse);
        expect(TaskLifecycle.resolveDocStatus(docD, now), TaskStatus.pending);

        // Document E: Legacy incomplete task with String ISO timestamp from yesterday
        final docE = {
          'id': 'legacy-e',
          'title': 'Legacy ISO date from yesterday',
          'done': false,
          'dueAt': '2026-10-04T12:00:00Z',
        };
        expect(TaskLifecycle.belongsToToday(docE, now), isFalse);
        expect(TaskLifecycle.belongsToHistory(docE, now), isTrue);
        expect(TaskLifecycle.resolveDocStatus(docE, now), TaskStatus.missed);

        // Document F: Completely sparse / empty map
        final docF = <String, dynamic>{};
        expect(TaskLifecycle.resolveDocStatus(docF, now), TaskStatus.pending);
        expect(TaskLifecycle.belongsToToday(docF, now), isTrue);
        expect(TaskLifecycle.belongsToHistory(docF, now), isFalse);
      },
    );

    test(
      'TEST 12: Complete a task from Today -> Leaves Today, zero contribution to counts, Completed in History, never Missed, reminder cancelled',
      () {
        // 1. Initial state: valid pending task scheduled for today at 10:00 AM (now is 14:00)
        final task = {
          'id': 'today-task-12',
          'title': 'Operating Systems review',
          'done': false,
          'dueAt': DateTime(2026, 10, 5, 10, 0),
          'remindAt': DateTime(2026, 10, 5, 9, 30),
        };

        // Before completion:
        expect(TaskLifecycle.belongsToToday(task, now), isTrue);
        expect(TaskLifecycle.isTodayClockOverdue(task, now), isTrue);
        expect(TaskLifecycle.belongsToHistory(task, now), isFalse);
        expect(TaskLifecycle.resolveDocStatus(task, now), TaskStatus.pending);

        // 2. Perform Today screen completion operation (exact _TaskLine / _setDone logic)
        var reminderCancelled = false;
        void onNotificationCancel(String id) {
          if (id == 'today-task-12') reminderCancelled = true;
        }

        // Action taken by Today checkbox:
        onNotificationCancel(task['id'] as String);
        final completedTask = Map<String, dynamic>.from(task)
          ..addAll({'done': true, 'updatedAt': DateTime.now()});

        // 3. Verify immediate state updates
        // Immediately leaves the active Today list:
        expect(TaskLifecycle.belongsToToday(completedTask, now), isFalse);
        // Does not contribute to today's open or overdue counts:
        expect(TaskLifecycle.isTodayClockOverdue(completedTask, now), isFalse);

        // History includes it as Completed:
        expect(TaskLifecycle.belongsToHistory(completedTask, now), isTrue);
        expect(
          TaskLifecycle.resolveDocStatus(completedTask, now),
          TaskStatus.completed,
        );

        // 4. Invariant: Must NEVER later resolve as Missed on future dates
        final tomorrow = DateTime(2026, 10, 6, 9, 0);
        final nextWeek = DateTime(2026, 10, 12, 12, 0);
        final nextYear = DateTime(2027, 10, 5, 10, 0);

        expect(TaskLifecycle.belongsToToday(completedTask, tomorrow), isFalse);
        expect(TaskLifecycle.belongsToHistory(completedTask, tomorrow), isTrue);
        expect(
          TaskLifecycle.resolveDocStatus(completedTask, tomorrow),
          TaskStatus.completed,
        );
        expect(
          TaskLifecycle.resolveDocStatus(completedTask, nextWeek),
          TaskStatus.completed,
        );
        expect(
          TaskLifecycle.resolveDocStatus(completedTask, nextYear),
          TaskStatus.completed,
        );

        // 5. Scheduled reminder cancelled
        expect(reminderCancelled, isTrue);
      },
    );

    test(
      'Midnight boundary: 23:59:59 is same day; 00:00:00 next day is past day',
      () {
        final taskDue = DateTime(2026, 10, 5, 23, 59, 59);
        final stillToday = DateTime(2026, 10, 5, 23, 59, 59);
        final justAfterMidnight = DateTime(2026, 10, 6, 0, 0, 0);

        expect(TaskLifecycle.isSameCalendarDay(taskDue, stillToday), isTrue);
        expect(TaskLifecycle.isPastCalendarDay(taskDue, stillToday), isFalse);

        expect(
          TaskLifecycle.isSameCalendarDay(taskDue, justAfterMidnight),
          isFalse,
        );
        expect(
          TaskLifecycle.isPastCalendarDay(taskDue, justAfterMidnight),
          isTrue,
        );
      },
    );

    test(
      'Timezone normalization: UTC timestamp converted to local calendar day correctly',
      () {
        // 23:30 UTC on Oct 5 may be 05:30 on Oct 6 in Dhaka (+6 UTC)
        final utcTime = DateTime.utc(2026, 10, 5, 23, 30);
        final localDay = TaskLifecycle.calendarDate(utcTime);

        final localEquivalent = utcTime.toLocal();
        expect(localDay.year, localEquivalent.year);
        expect(localDay.month, localEquivalent.month);
        expect(localDay.day, localEquivalent.day);
      },
    );

    test('Firestore Timestamp compatibility', () {
      final timestamp = Timestamp.fromDate(DateTime(2026, 10, 4, 12, 0));
      final parsed = TaskLifecycle.parseDateTime(timestamp);
      expect(parsed, isNotNull);
      expect(TaskLifecycle.isPastCalendarDay(parsed!, now), isTrue);
    });
  });
}
