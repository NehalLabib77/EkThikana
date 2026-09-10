import 'package:flutter_test/flutter_test.dart';
import 'package:gochano/core/student/student.dart';

void main() {
  // Helper to create a StudentContext with overrides
  StudentContext makeContext({
    List<StudentEvent> todayEvents = const [],
    List<StudentEvent> upcomingEvents = const [],
    List<StudentEvent> overdueEvents = const [],
    List<StudentEvent> pendingMedicine = const [],
    bool medicineAvailable = true,
    StudySummary? studySummary,
    MoneySummary? moneySummary,
  }) {
    return StudentContext(
      generatedAt: DateTime(2026, 9, 10),
      todayEvents: todayEvents,
      upcomingEvents: upcomingEvents,
      overdueEvents: overdueEvents,
      pendingMedicine: pendingMedicine,
      medicineAvailable: medicineAvailable,
      studySummary: studySummary,
      moneySummary: moneySummary,
    );
  }

  int eventCounter = 0;

  StudentEvent makeEvent({
    StudentEventType type = StudentEventType.task,
    StudentEventStatus status = StudentEventStatus.pending,
    String title = 'Test Task',
    DateTime? scheduledAt,
    String? id,
  }) {
    return StudentEvent(
      id: id ?? 'event_${eventCounter++}',
      sourceId: 'src_1',
      type: type,
      title: title,
      scheduledAt: scheduledAt,
      status: status,
      source: 'tasks',
    );
  }

  group('StudentSignal', () {
    test('signal types exist', () {
      expect(SignalType.values.length, 7);
    });

    test('signal priorities have correct order', () {
      expect(SignalPriority.overdue.value, 1);
      expect(SignalPriority.medicine.value, 2);
      expect(SignalPriority.dueSoon.value, 3);
      expect(SignalPriority.upcoming.value, 4);
      expect(SignalPriority.heavyDay.value, 5);
      expect(SignalPriority.budget.value, 6);
      expect(SignalPriority.clear.value, 7);
    });
  });

  group('StudentSignalService.evaluate', () {
    test('returns empty list for empty context', () {
      final ctx = makeContext();
      final signals = StudentSignalService.evaluate(ctx);
      // Empty context should produce clearDay
      expect(signals.length, 1);
      expect(signals.first.type, SignalType.clearDay);
    });

    test('creates overdueWork signal for overdue tasks', () {
      final overdue = makeEvent(
        type: StudentEventType.task,
        status: StudentEventStatus.overdue,
        title: 'Late Assignment',
        scheduledAt: DateTime(2026, 9, 9),
      );
      final ctx = makeContext(overdueEvents: [overdue]);
      final signals = StudentSignalService.evaluate(ctx);
      expect(signals.any((s) => s.type == SignalType.overdueWork), isTrue);
      final overdueSignal =
          signals.firstWhere((s) => s.type == SignalType.overdueWork);
      expect(overdueSignal.count, 1);
      expect(overdueSignal.nearestEvent!.title, 'Late Assignment');
    });

    test('creates overdueWork for overdue assignments too', () {
      final overdue = makeEvent(
        type: StudentEventType.assignment,
        status: StudentEventStatus.overdue,
        title: 'Report',
        scheduledAt: DateTime(2026, 9, 8),
      );
      final ctx = makeContext(overdueEvents: [overdue]);
      final signals = StudentSignalService.evaluate(ctx);
      expect(signals.any((s) => s.type == SignalType.overdueWork), isTrue);
    });

    test('counts multiple overdue items', () {
      final overdue1 = makeEvent(
        type: StudentEventType.task,
        status: StudentEventStatus.overdue,
        title: 'Task 1',
      );
      final overdue2 = makeEvent(
        type: StudentEventType.assignment,
        status: StudentEventStatus.overdue,
        title: 'Task 2',
      );
      final ctx = makeContext(overdueEvents: [overdue1, overdue2]);
      final signals = StudentSignalService.evaluate(ctx);
      final overdueSignal =
          signals.firstWhere((s) => s.type == SignalType.overdueWork);
      expect(overdueSignal.count, 2);
    });

    test('creates missedMedicine signal for pending medicine', () {
      final med = makeEvent(
        type: StudentEventType.medicine,
        status: StudentEventStatus.pending,
        title: 'Paracetamol',
      );
      final ctx = makeContext(pendingMedicine: [med], medicineAvailable: true);
      final signals = StudentSignalService.evaluate(ctx);
      expect(signals.any((s) => s.type == SignalType.missedMedicine), isTrue);
    });

    test('does NOT create missedMedicine when medicine unavailable', () {
      final ctx = makeContext(medicineAvailable: false);
      final signals = StudentSignalService.evaluate(ctx);
      expect(signals.any((s) => s.type == SignalType.missedMedicine), isFalse);
    });

    test('does NOT create missedMedicine when no pending doses', () {
      final ctx = makeContext(pendingMedicine: [], medicineAvailable: true);
      final signals = StudentSignalService.evaluate(ctx);
      expect(signals.any((s) => s.type == SignalType.missedMedicine), isFalse);
    });

    test('creates dueSoon signal for items due within 24h', () {
      final now = DateTime(2026, 9, 10, 12, 0);
      final dueSoon = makeEvent(
        type: StudentEventType.assignment,
        status: StudentEventStatus.pending,
        title: 'Quiz',
        scheduledAt: now.add(const Duration(hours: 6)),
      );
      final ctx = makeContext(todayEvents: [dueSoon]);
      final signals = StudentSignalService.evaluate(ctx, now: now);
      expect(signals.any((s) => s.type == SignalType.dueSoon), isTrue);
    });

    test('does NOT create dueSoon for items due after 24h', () {
      final now = DateTime(2026, 9, 10, 12, 0);
      final dueLater = makeEvent(
        type: StudentEventType.assignment,
        status: StudentEventStatus.pending,
        title: 'Project',
        scheduledAt: now.add(const Duration(hours: 48)),
      );
      final ctx = makeContext(upcomingEvents: [dueLater]);
      final signals = StudentSignalService.evaluate(ctx, now: now);
      expect(signals.any((s) => s.type == SignalType.dueSoon), isFalse);
    });

    test('creates heavyDay when actionable today events >= threshold', () {
      final now = DateTime(2026, 9, 10, 12, 0);
      final events = List.generate(
        StudentSignalService.heavyDayThreshold,
        (i) => makeEvent(
          title: 'Task $i',
          scheduledAt: now.add(Duration(hours: i)),
        ),
      );
      final ctx = makeContext(todayEvents: events);
      final signals = StudentSignalService.evaluate(ctx, now: now);
      expect(signals.any((s) => s.type == SignalType.heavyDay), isTrue);
    });

    test('does NOT create heavyDay below threshold', () {
      final now = DateTime(2026, 9, 10, 12, 0);
      final events = List.generate(
        StudentSignalService.heavyDayThreshold - 1,
        (i) => makeEvent(
          title: 'Task $i',
          scheduledAt: now.add(Duration(hours: i)),
        ),
      );
      final ctx = makeContext(todayEvents: events);
      final signals = StudentSignalService.evaluate(ctx, now: now);
      expect(signals.any((s) => s.type == SignalType.heavyDay), isFalse);
    });

    test('creates budgetAttention when remaining is low', () {
      final money = MoneySummary(
        backendRemaining: 100,
        totalSpent: 4900,
      );
      final ctx = makeContext(moneySummary: money);
      final signals = StudentSignalService.evaluate(ctx);
      expect(signals.any((s) => s.type == SignalType.budgetAttention), isTrue);
    });

    test('does NOT create budgetAttention when remaining is adequate', () {
      final money = MoneySummary(
        backendRemaining: 1000,
        totalSpent: 4000,
      );
      final ctx = makeContext(moneySummary: money);
      final signals = StudentSignalService.evaluate(ctx);
      expect(signals.any((s) => s.type == SignalType.budgetAttention), isFalse);
    });

    test('does NOT create budgetAttention when money unavailable', () {
      final ctx = makeContext(moneySummary: null);
      final signals = StudentSignalService.evaluate(ctx);
      expect(signals.any((s) => s.type == SignalType.budgetAttention), isFalse);
    });

    test('creates clearDay when no other signals', () {
      final ctx = makeContext();
      final signals = StudentSignalService.evaluate(ctx);
      expect(signals.length, 1);
      expect(signals.first.type, SignalType.clearDay);
      expect(signals.first.priority, SignalPriority.clear);
    });

    test('signals are sorted by priority', () {
      final now = DateTime(2026, 9, 10, 12, 0);
      final overdue = makeEvent(
        type: StudentEventType.task,
        status: StudentEventStatus.overdue,
        title: 'Overdue',
      );
      final dueSoon = makeEvent(
        type: StudentEventType.assignment,
        status: StudentEventStatus.pending,
        title: 'Due Soon',
        scheduledAt: now.add(const Duration(hours: 2)),
      );
      final med = makeEvent(
        type: StudentEventType.medicine,
        status: StudentEventStatus.pending,
        title: 'Medicine',
      );
      final ctx = makeContext(
        overdueEvents: [overdue],
        todayEvents: [dueSoon],
        pendingMedicine: [med],
        medicineAvailable: true,
      );
      final signals = StudentSignalService.evaluate(ctx, now: now);
      // Should be: overdue(1) < medicine(2) < dueSoon(3)
      expect(signals.first.type, SignalType.overdueWork);
      expect(signals.last.type, SignalType.dueSoon);
    });
  });

  group('StudentSignalService.topSignals', () {
    test('returns at most maxSignals items', () {
      final now = DateTime(2026, 9, 10, 12, 0);
      final overdue = makeEvent(
        type: StudentEventType.task,
        status: StudentEventStatus.overdue,
        title: 'Overdue',
      );
      final med = makeEvent(
        type: StudentEventType.medicine,
        status: StudentEventStatus.pending,
        title: 'Med',
      );
      final dueSoon = makeEvent(
        type: StudentEventType.assignment,
        status: StudentEventStatus.pending,
        title: 'Due',
        scheduledAt: now.add(const Duration(hours: 2)),
      );
      final ctx = makeContext(
        overdueEvents: [overdue],
        todayEvents: [dueSoon],
        pendingMedicine: [med],
        medicineAvailable: true,
      );
      final top = StudentSignalService.topSignals(ctx, maxSignals: 2, now: now);
      expect(top.length, 2);
    });

    test('excludes clearDay from results when other signals exist', () {
      final overdue = makeEvent(
        type: StudentEventType.task,
        status: StudentEventStatus.overdue,
        title: 'Overdue',
      );
      final ctx = makeContext(overdueEvents: [overdue]);
      final signals = StudentSignalService.evaluate(ctx);
      // Should have overdueWork, not clearDay
      expect(signals.any((s) => s.type == SignalType.overdueWork), isTrue);
      expect(signals.any((s) => s.type == SignalType.clearDay), isFalse);
    });
  });

  group('Edge cases', () {
    test('midnight boundary - events at 23:59 vs 00:01', () {
      final now = DateTime(2026, 9, 10, 23, 59);
      final tomorrow = makeEvent(
        type: StudentEventType.assignment,
        status: StudentEventStatus.pending,
        title: 'Tomorrow',
        scheduledAt: DateTime(2026, 9, 11, 0, 1),
      );
      final ctx = makeContext(upcomingEvents: [tomorrow]);
      final signals = StudentSignalService.evaluate(ctx, now: now);
      // 2 minutes away = due soon
      expect(signals.any((s) => s.type == SignalType.dueSoon), isTrue);
    });

    test('year boundary', () {
      final now = DateTime(2026, 12, 31, 23, 0);
      final nextYear = makeEvent(
        type: StudentEventType.assignment,
        status: StudentEventStatus.pending,
        title: 'New Year Task',
        scheduledAt: DateTime(2027, 1, 1, 1, 0),
      );
      final ctx = makeContext(upcomingEvents: [nextYear]);
      final signals = StudentSignalService.evaluate(ctx, now: now);
      // 2 hours away = due soon
      expect(signals.any((s) => s.type == SignalType.dueSoon), isTrue);
    });

    test('partial context - only money, no study', () {
      final money = MoneySummary(backendRemaining: 50, totalSpent: 4950);
      final ctx = makeContext(moneySummary: money);
      final signals = StudentSignalService.evaluate(ctx);
      // Should have budgetAttention, not clearDay
      expect(signals.any((s) => s.type == SignalType.budgetAttention), isTrue);
    });

    test('overdue + dueSoon signals coexist', () {
      final now = DateTime(2026, 9, 10, 12, 0);
      final overdue = makeEvent(
        type: StudentEventType.task,
        status: StudentEventStatus.overdue,
        title: 'Late',
      );
      final dueSoon = makeEvent(
        type: StudentEventType.assignment,
        status: StudentEventStatus.pending,
        title: 'Soon',
        scheduledAt: now.add(const Duration(hours: 3)),
      );
      final ctx = makeContext(
        overdueEvents: [overdue],
        todayEvents: [dueSoon],
      );
      final signals = StudentSignalService.evaluate(ctx, now: now);
      expect(signals.any((s) => s.type == SignalType.overdueWork), isTrue);
      expect(signals.any((s) => s.type == SignalType.dueSoon), isTrue);
    });
  });

  // ======================================================================
  // Phase 7.1 — upcomingAssignment
  // ======================================================================

  group('upcomingAssignment', () {
    test('exists in SignalType enum', () {
      expect(SignalType.upcomingAssignment, isNotNull);
    });

    test('selects nearest incomplete assignment beyond dueSoon window', () {
      final now = DateTime(2026, 9, 10, 12, 0);
      final far = makeEvent(
        type: StudentEventType.assignment,
        status: StudentEventStatus.pending,
        title: 'Final Project',
        scheduledAt: now.add(const Duration(days: 10)),
      );
      final near = makeEvent(
        type: StudentEventType.assignment,
        status: StudentEventStatus.pending,
        title: 'Lab Report',
        scheduledAt: now.add(const Duration(days: 3)),
      );
      final ctx = makeContext(upcomingEvents: [far, near]);
      final signals = StudentSignalService.evaluate(ctx, now: now);
      final upcoming = signals.where((s) => s.type == SignalType.upcomingAssignment).toList();
      expect(upcoming.length, 1);
      expect(upcoming.first.nearestEvent!.title, 'Lab Report');
    });

    test('A: unrelated dueSoon Task does NOT suppress future Assignment', () {
      final now = DateTime(2026, 9, 10, 12, 0);
      // Task due in 2 hours — captured by dueSoon
      final taskDueSoon = makeEvent(
        type: StudentEventType.task,
        status: StudentEventStatus.pending,
        title: 'Quick Task',
        scheduledAt: now.add(const Duration(hours: 2)),
      );
      // Assignment due in 3 days — beyond dueSoon window
      final assignmentFuture = makeEvent(
        type: StudentEventType.assignment,
        status: StudentEventStatus.pending,
        title: 'Term Paper',
        scheduledAt: now.add(const Duration(days: 3)),
      );
      final ctx = makeContext(
        todayEvents: [taskDueSoon],
        upcomingEvents: [assignmentFuture],
      );
      final signals = StudentSignalService.evaluate(ctx, now: now);
      // BOTH signals should exist
      expect(signals.any((s) => s.type == SignalType.dueSoon), isTrue);
      expect(signals.any((s) => s.type == SignalType.upcomingAssignment), isTrue);
      // dueSoon is for the Task, upcomingAssignment is for the Assignment
      final dueSoon = signals.firstWhere((s) => s.type == SignalType.dueSoon);
      final upcoming = signals.firstWhere((s) => s.type == SignalType.upcomingAssignment);
      expect(dueSoon.nearestEvent!.title, 'Quick Task');
      expect(upcoming.nearestEvent!.title, 'Term Paper');
    });

    test('B: Assignment due in 2h appears in dueSoon, NOT duplicated as upcoming', () {
      final now = DateTime(2026, 9, 10, 12, 0);
      final assignmentDueSoon = makeEvent(
        type: StudentEventType.assignment,
        status: StudentEventStatus.pending,
        title: 'Quiz',
        scheduledAt: now.add(const Duration(hours: 2)),
      );
      final ctx = makeContext(todayEvents: [assignmentDueSoon]);
      final signals = StudentSignalService.evaluate(ctx, now: now);
      expect(signals.any((s) => s.type == SignalType.dueSoon), isTrue);
      expect(signals.any((s) => s.type == SignalType.upcomingAssignment), isFalse);
    });

    test('C: overdue Assignment + future Assignment — overdue handled, future eligible', () {
      final now = DateTime(2026, 9, 10, 12, 0);
      final overdue = makeEvent(
        type: StudentEventType.assignment,
        status: StudentEventStatus.overdue,
        title: 'Late Report',
        scheduledAt: now.subtract(const Duration(days: 1)),
      );
      final future = makeEvent(
        type: StudentEventType.assignment,
        status: StudentEventStatus.pending,
        title: 'Next Assignment',
        scheduledAt: now.add(const Duration(days: 5)),
      );
      final ctx = makeContext(
        overdueEvents: [overdue],
        upcomingEvents: [future],
      );
      final signals = StudentSignalService.evaluate(ctx, now: now);
      expect(signals.any((s) => s.type == SignalType.overdueWork), isTrue);
      expect(signals.any((s) => s.type == SignalType.upcomingAssignment), isTrue);
      final upcoming = signals.firstWhere((s) => s.type == SignalType.upcomingAssignment);
      expect(upcoming.nearestEvent!.title, 'Next Assignment');
    });

    test('D: multiple future Assignments — nearest eligible chosen', () {
      final now = DateTime(2026, 9, 10, 12, 0);
      final far = makeEvent(
        type: StudentEventType.assignment,
        status: StudentEventStatus.pending,
        title: 'Final',
        scheduledAt: now.add(const Duration(days: 14)),
      );
      final mid = makeEvent(
        type: StudentEventType.assignment,
        status: StudentEventStatus.pending,
        title: 'Midterm',
        scheduledAt: now.add(const Duration(days: 7)),
      );
      final ctx = makeContext(upcomingEvents: [far, mid]);
      final signals = StudentSignalService.evaluate(ctx, now: now);
      final upcoming = signals.where((s) => s.type == SignalType.upcomingAssignment).toList();
      expect(upcoming.length, 1);
      expect(upcoming.first.nearestEvent!.title, 'Midterm');
    });

    test('does NOT duplicate overdue assignment as upcoming', () {
      final now = DateTime(2026, 9, 10, 12, 0);
      final overdue = makeEvent(
        type: StudentEventType.assignment,
        status: StudentEventStatus.overdue,
        title: 'Late Report',
        scheduledAt: now.subtract(const Duration(days: 1)),
      );
      final ctx = makeContext(overdueEvents: [overdue]);
      final signals = StudentSignalService.evaluate(ctx, now: now);
      expect(signals.any((s) => s.type == SignalType.overdueWork), isTrue);
      expect(signals.any((s) => s.type == SignalType.upcomingAssignment), isFalse);
    });

    test('uses upcoming priority level', () {
      expect(SignalPriority.upcoming.value, 4);
    });
  });

  // ======================================================================
  // Phase 7.1 — clearDay availability safety
  // ======================================================================

  group('clearDay availability', () {
    test('Study unavailable → NO clearDay signal', () {
      // Manually set studyAvailable to false
      final unavailableCtx = StudentContext(
        generatedAt: DateTime(2026, 9, 10),
        studyAvailable: false,
      );
      final signals = StudentSignalService.evaluate(unavailableCtx);
      // Should NOT produce clearDay when study is unavailable
      expect(signals.any((s) => s.type == SignalType.clearDay), isFalse);
    });

    test('Study available + genuinely empty → clearDay allowed', () {
      final ctx = makeContext(
        todayEvents: [],
        upcomingEvents: [],
        overdueEvents: [],
        pendingMedicine: [],
        medicineAvailable: false, // medicine unavailable should not block clearDay
      );
      final signals = StudentSignalService.evaluate(ctx);
      expect(signals.length, 1);
      expect(signals.first.type, SignalType.clearDay);
    });

    test('Study unavailable + no other signals → no clearDay, no reassurance', () {
      final unavailableCtx = StudentContext(
        generatedAt: DateTime(2026, 9, 10),
        studyAvailable: false,
      );
      final signals = StudentSignalService.evaluate(unavailableCtx);
      // Should NOT produce clearDay — no reassuring "all clear" from missing data
      expect(signals.any((s) => s.type == SignalType.clearDay), isFalse);
      // Should produce empty list (no signals at all)
      expect(signals, isEmpty);
    });
  });
}
