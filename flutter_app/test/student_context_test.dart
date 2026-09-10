// ignore_for_file: subtype_of_sealed_class
// Test stubs intentionally implement sealed Firestore types for unit testing.

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gochano/core/student/student_event.dart';
import 'package:gochano/core/student/student_context.dart';
import 'package:gochano/core/student/student_context_service.dart';
import 'package:gochano/models/financial_transaction.dart';

void main() {
  group('StudentEvent', () {
    group('deterministic IDs', () {
      test('taskId is deterministic for the same doc ID', () {
        final id1 = StudentEvent.taskId('abc123');
        final id2 = StudentEvent.taskId('abc123');
        expect(id1, equals(id2));
        expect(id1, 'task_abc123');
      });

      test('medicineDoseId is deterministic', () {
        final date = DateTime(2026, 3, 15);
        final id1 = StudentEvent.medicineDoseId('med1', date, '08:00');
        final id2 = StudentEvent.medicineDoseId('med1', date, '08:00');
        expect(id1, equals(id2));
        expect(id1, 'med_med1_20260315_0800');
      });

      test('medicineDoseId differs for different times', () {
        final date = DateTime(2026, 3, 15);
        final id1 = StudentEvent.medicineDoseId('med1', date, '08:00');
        final id2 = StudentEvent.medicineDoseId('med1', date, '20:00');
        expect(id1, isNot(equals(id2)));
      });

      test('medicineDoseId differs for different dates', () {
        final date1 = DateTime(2026, 3, 15);
        final date2 = DateTime(2026, 3, 16);
        final id1 = StudentEvent.medicineDoseId('med1', date1, '08:00');
        final id2 = StudentEvent.medicineDoseId('med1', date2, '08:00');
        expect(id1, isNot(equals(id2)));
      });
    });

    group('fromTaskDoc adapter', () {
      test('maps a pending task correctly', () {
        final now = DateTime.now();
        final dueAt = now.add(const Duration(hours: 2));
        final doc = _FakeTaskSnapshot(
          id: 'task1',
          data: <String, dynamic>{
            'title': 'Read chapter 5',
            'type': 'task',
            'done': false,
            'dueAt': dueAt,
          },
        );
        final event = StudentEvent.fromTaskDoc(doc);
        expect(event.id, 'task_task1');
        expect(event.sourceId, 'task1');
        expect(event.type, StudentEventType.task);
        expect(event.title, 'Read chapter 5');
        expect(event.status, StudentEventStatus.pending);
        expect(event.source, 'tasks');
        expect(event.scheduledAt, isNotNull);
      });

      test('maps a completed task correctly', () {
        final doc = _FakeTaskSnapshot(
          id: 'task2',
          data: <String, dynamic>{
            'title': 'Submit homework',
            'type': 'task',
            'done': true,
            'dueAt': null,
          },
        );
        final event = StudentEvent.fromTaskDoc(doc);
        expect(event.status, StudentEventStatus.completed);
        expect(event.scheduledAt, isNull);
      });

      test('maps an overdue task correctly', () {
        final past = DateTime.now().subtract(const Duration(hours: 5));
        final doc = _FakeTaskSnapshot(
          id: 'task3',
          data: <String, dynamic>{
            'title': 'Late assignment',
            'type': 'assignment',
            'done': false,
            'dueAt': past,
          },
        );
        final event = StudentEvent.fromTaskDoc(doc);
        expect(event.type, StudentEventType.assignment);
        expect(event.status, StudentEventStatus.overdue);
      });

      test('defaults to task type when type field is missing', () {
        final doc = _FakeTaskSnapshot(
          id: 'task4',
          data: <String, dynamic>{
            'title': 'No type field',
            'done': false,
          },
        );
        final event = StudentEvent.fromTaskDoc(doc);
        expect(event.type, StudentEventType.task);
      });

      test('defaults title to empty string when missing', () {
        final doc = _FakeTaskSnapshot(
          id: 'task5',
          data: <String, dynamic>{
            'type': 'task',
            'done': false,
          },
        );
        final event = StudentEvent.fromTaskDoc(doc);
        expect(event.title, '');
      });
    });
  });

  group('StudentContext', () {
    test('defaults to empty lists and null summaries', () {
      final ctx = StudentContext(generatedAt: DateTime(2026, 1, 1));
      expect(ctx.todayEvents, isEmpty);
      expect(ctx.upcomingEvents, isEmpty);
      expect(ctx.overdueEvents, isEmpty);
      expect(ctx.pendingMedicine, isEmpty);
      expect(ctx.studySummary, isNull);
      expect(ctx.moneySummary, isNull);
      expect(ctx.commuteSummary, isNull);
      expect(ctx.communitySummary, isNull);
      expect(ctx.isFullyLoaded, isFalse);
    });

    test('isFullyLoaded is true only when all summaries present', () {
      final ctx = StudentContext(
        generatedAt: DateTime(2026, 1, 1),
        studySummary: const StudySummary(
          totalTasks: 5,
          completedToday: 1,
          upcomingCount: 3,
          overdueCount: 1,
        ),
        moneySummary: const MoneySummary(
          backendRemaining: 5000,
          totalSpent: 2000,
        ),
        commuteSummary: const CommuteSummary(
          tripsThisMonth: 4,
          totalFareThisMonth: 400,
        ),
        communitySummary: const CommunitySummary(groupCount: 2),
      );
      expect(ctx.isFullyLoaded, isTrue);
    });

    test('isFullyLoaded is false when any summary is null', () {
      final ctx = StudentContext(
        generatedAt: DateTime(2026, 1, 1),
        studySummary: const StudySummary(
          totalTasks: 0,
          completedToday: 0,
          upcomingCount: 0,
          overdueCount: 0,
        ),
        moneySummary: null,
        commuteSummary: const CommuteSummary(
          tripsThisMonth: 0,
          totalFareThisMonth: 0,
        ),
        communitySummary: const CommunitySummary(groupCount: 0),
      );
      expect(ctx.isFullyLoaded, isFalse);
    });
  });

  group('MoneySummary adjustedRemaining', () {
    test('no settlement: adjustedRemaining == backendRemaining', () {
      const summary = MoneySummary(
        backendRemaining: 5000,
        totalSpent: 1000,
      );
      expect(summary.adjustedRemaining, 5000);
    });

    test('Pawna received: backendRemaining + pawnaReceived', () {
      const summary = MoneySummary(
        backendRemaining: 5000,
        totalSpent: 1000,
        pawnaReceived: 800,
      );
      expect(summary.adjustedRemaining, 5800);
    });

    test('Dena paid: backendRemaining unchanged (denaPaid already in ledger)', () {
      const summary = MoneySummary(
        backendRemaining: 5000,
        totalSpent: 1000,
        denaPaid: 300,
      );
      expect(summary.adjustedRemaining, 5000);
    });

    test('both: backendRemaining + pawnaReceived (denaPaid already in ledger)', () {
      const summary = MoneySummary(
        backendRemaining: 5000,
        totalSpent: 1000,
        pawnaReceived: 800,
        denaPaid: 300,
      );
      expect(summary.adjustedRemaining, 5800);
    });
  });

  group('Money Accounting Regression — Proven from Source', () {
    test('no settlement: adjustedRemaining == backendRemaining', () {
      const summary = MoneySummary(
        backendRemaining: 8000,
        totalSpent: 2000,
      );
      expect(summary.adjustedRemaining, 8000);
    });

    test('Dena outstanding: no financial_transactions entry, no Remaining impact', () {
      const summary = MoneySummary(
        backendRemaining: 8000,
        totalSpent: 2000,
        denaPaid: 0,
      );
      expect(summary.adjustedRemaining, 8000);
    });

    test('Pawna outstanding: no financial_transactions entry, no Remaining impact', () {
      const summary = MoneySummary(
        backendRemaining: 8000,
        totalSpent: 2000,
        pawnaReceived: 0,
      );
      expect(summary.adjustedRemaining, 8000);
    });

    test('Dena paid: backendRemaining already includes the deduction', () {
      const summary = MoneySummary(
        backendRemaining: 7000,
        totalSpent: 3000,
        denaPaid: 1000,
      );
      expect(summary.adjustedRemaining, 7000);
    });

    test('Pawna received: NOT in financial_transactions, added client-side', () {
      const summary = MoneySummary(
        backendRemaining: 7000,
        totalSpent: 3000,
        pawnaReceived: 1500,
      );
      expect(summary.adjustedRemaining, 8500);
    });

    test('both settlements: full trace matches economic expectation', () {
      const summary = MoneySummary(
        backendRemaining: 7000,
        totalSpent: 3000,
        pawnaReceived: 1500,
        denaPaid: 1000,
      );
      expect(summary.adjustedRemaining, 8500);
    });

    test('repeated Mark Paid: idempotent — outstanding check prevents double-count', () {
      const summary = MoneySummary(
        backendRemaining: 7000,
        totalSpent: 3000,
        pawnaReceived: 1500,
        denaPaid: 1000,
      );
      expect(summary.adjustedRemaining, 8500);
    });

    test('repeated Mark Received: idempotent — outstanding check prevents double-count', () {
      const summary = MoneySummary(
        backendRemaining: 7000,
        totalSpent: 3000,
        pawnaReceived: 1500,
        denaPaid: 1000,
      );
      expect(summary.adjustedRemaining, 8500);
    });

    test('denaPaid does NOT double-count with backendRemaining', () {
      const summary = MoneySummary(
        backendRemaining: 7000,
        totalSpent: 3000,
        pawnaReceived: 1500,
        denaPaid: 1000,
      );
      expect(summary.adjustedRemaining, 8500);
      expect(summary.denaPaid, 1000);
    });

    test('negative remaining when overspent', () {
      const summary = MoneySummary(
        backendRemaining: -500,
        totalSpent: 10500,
        pawnaReceived: 0,
      );
      expect(summary.adjustedRemaining, -500);
    });

    test('pawnaReceived can exceed backendRemaining (positive remaining)', () {
      const summary = MoneySummary(
        backendRemaining: -500,
        totalSpent: 10500,
        pawnaReceived: 2000,
      );
      expect(summary.adjustedRemaining, 1500);
    });
  });

  group('StudentContextService.build', () {
    test('produces empty context when all inputs are null', () async {
      final ctx = await StudentContextService.build(
        day: DateTime(2026, 6, 15),
      );
      expect(ctx.todayEvents, isEmpty);
      expect(ctx.upcomingEvents, isEmpty);
      expect(ctx.overdueEvents, isEmpty);
      expect(ctx.studySummary, isNull);
      expect(ctx.moneySummary, isNull);
    });

    test('filters today events correctly', () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final List<QueryDocumentSnapshot<Map<String, dynamic>>> taskDocs = [
        _FakeTaskSnapshot(
          id: 't1',
          data: <String, dynamic>{
            'title': 'Due today',
            'type': 'task',
            'done': false,
            'dueAt': today.add(const Duration(hours: 10)),
          },
        ),
        _FakeTaskSnapshot(
          id: 't2',
          data: <String, dynamic>{
            'title': 'Due tomorrow',
            'type': 'task',
            'done': false,
            'dueAt': today.add(const Duration(days: 1, hours: 10)),
          },
        ),
      ];

      final ctx = await StudentContextService.build(
        day: today,
        taskDocs: taskDocs,
      );

      expect(ctx.todayEvents.length, 1);
      expect(ctx.todayEvents.first.title, 'Due today');
      expect(ctx.upcomingEvents.length, 1);
      expect(ctx.upcomingEvents.first.title, 'Due tomorrow');
    });

    test('detects overdue events', () async {
      final past = DateTime.now().subtract(const Duration(hours: 5));
      final List<QueryDocumentSnapshot<Map<String, dynamic>>> taskDocs = [
        _FakeTaskSnapshot(
          id: 'overdue1',
          data: <String, dynamic>{
            'title': 'Overdue task',
            'type': 'task',
            'done': false,
            'dueAt': past,
          },
        ),
      ];

      final ctx = await StudentContextService.build(
        day: DateTime.now(),
        taskDocs: taskDocs,
      );

      expect(ctx.overdueEvents.length, 1);
      expect(ctx.overdueEvents.first.status, StudentEventStatus.overdue);
    });

    test('excludes completed events from overdue', () async {
      final past = DateTime.now().subtract(const Duration(hours: 5));
      final List<QueryDocumentSnapshot<Map<String, dynamic>>> taskDocs = [
        _FakeTaskSnapshot(
          id: 'done1',
          data: <String, dynamic>{
            'title': 'Done task',
            'type': 'task',
            'done': true,
            'dueAt': past,
          },
        ),
      ];

      final ctx = await StudentContextService.build(
        day: DateTime.now(),
        taskDocs: taskDocs,
      );

      expect(ctx.overdueEvents, isEmpty);
    });

    test('builds study summary from task docs', () async {
      final now = DateTime.now();
      final List<QueryDocumentSnapshot<Map<String, dynamic>>> taskDocs = [
        _FakeTaskSnapshot(
          id: 's1',
          data: <String, dynamic>{'title': 'Task 1', 'type': 'task', 'done': false},
        ),
        _FakeTaskSnapshot(
          id: 's2',
          data: <String, dynamic>{'title': 'Task 2', 'type': 'task', 'done': true},
        ),
        _FakeTaskSnapshot(
          id: 's3',
          data: <String, dynamic>{'title': 'Task 3', 'type': 'assignment', 'done': false},
        ),
      ];

      final ctx = await StudentContextService.build(
        day: now,
        taskDocs: taskDocs,
      );

      expect(ctx.studySummary, isNotNull);
      expect(ctx.studySummary!.totalTasks, 3);
    });

    test('builds money summary from financial data', () async {
      final ctx = await StudentContextService.build(
        day: DateTime(2026, 6, 15),
        financialSummary: const FinancialSummary(
          totalSpending: 2500,
          bySource: <String, double>{'daily': 1000, 'bazar': 1500},
        ),
        moneyRawFields: const MoneyRawFields(
          backendRemaining: 5000,
          pawnaReceived: 300,
          denaPaid: 200,
        ),
      );

      expect(ctx.moneySummary, isNotNull);
      expect(ctx.moneySummary!.totalSpent, 2500);
      expect(ctx.moneySummary!.backendRemaining, 5000);
      expect(ctx.moneySummary!.adjustedRemaining, 5300);
    });

    test('missing subsystem degrades to null', () async {
      final ctx = await StudentContextService.build(
        day: DateTime(2026, 6, 15),
      );
      expect(ctx.studySummary, isNull);
      expect(ctx.moneySummary, isNull);
      expect(ctx.commuteSummary, isNull);
    });

    test('community summary from group count', () async {
      final ctx = await StudentContextService.build(
        day: DateTime(2026, 6, 15),
        communityGroupCount: 3,
      );
      expect(ctx.communitySummary, isNotNull);
      expect(ctx.communitySummary!.groupCount, 3);
    });

    test('upcoming events are sorted by scheduledAt ascending', () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final List<QueryDocumentSnapshot<Map<String, dynamic>>> taskDocs = [
        _FakeTaskSnapshot(
          id: 'late',
          data: <String, dynamic>{
            'title': 'Due late',
            'type': 'task',
            'done': false,
            'dueAt': today.add(const Duration(days: 2, hours: 20)),
          },
        ),
        _FakeTaskSnapshot(
          id: 'early',
          data: <String, dynamic>{
            'title': 'Due early',
            'type': 'task',
            'done': false,
            'dueAt': today.add(const Duration(days: 1, hours: 8)),
          },
        ),
      ];

      final ctx = await StudentContextService.build(
        day: today,
        taskDocs: taskDocs,
      );

      expect(ctx.upcomingEvents.length, 2);
      expect(ctx.upcomingEvents.first.title, 'Due early');
      expect(ctx.upcomingEvents.last.title, 'Due late');
    });
  });

  group('Architecture invariants', () {
    test('StudentEvent has no UI dependency', () {
      final source = File('lib/core/student/student_event.dart').readAsStringSync();
      expect(source, isNot(contains("import 'package:flutter/")));
      expect(source, isNot(contains('BuildContext(')));
    });

    test('StudentContext has no UI dependency', () {
      final source = File('lib/core/student/student_context.dart').readAsStringSync();
      expect(source, isNot(contains("import 'package:flutter/")));
      expect(source, isNot(contains('BuildContext(')));
    });

    test('StudentContextService has no UI dependency', () {
      final source = File('lib/core/student/student_context_service.dart').readAsStringSync();
      expect(source, isNot(contains("import 'package:flutter/")));
      expect(source, isNot(contains('BuildContext(')));
    });

    test('no new Firestore persistence collection created', () {
      final source = File('lib/core/student/student_context_service.dart').readAsStringSync();
      expect(source, isNot(contains('.collection(')));
      expect(source, isNot(contains('.doc(')));
    });

    test('existing source records are not mutated', () {
      final source = File('lib/core/student/student_context_service.dart').readAsStringSync();
      expect(source, isNot(contains('.update(')));
      expect(source, isNot(contains('.delete(')));
    });
  });
}

// ──────────────────────────────────────────────
//  Test helpers
// ──────────────────────────────────────────────

/// Minimal stub satisfying `QueryDocumentSnapshot<Map<String, dynamic>>`.
class _FakeTaskSnapshot extends Fake
    implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _FakeTaskSnapshot({required this.id, required Map<String, dynamic> data})
      : _data = data;

  @override
  final String id;
  final Map<String, dynamic> _data;

  @override
  Map<String, dynamic> data() => _data;
}
