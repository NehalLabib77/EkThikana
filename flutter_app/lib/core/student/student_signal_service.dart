/// Deterministic signal computation from StudentContext.
///
/// [StudentSignalService] is a pure function: StudentContext in, signals out.
/// No Firestore reads, no AI calls, no persistence. The service is
/// stateless and can be called from any rebuild cycle.
library;

import 'student_context.dart';
import 'student_event.dart';
import 'student_signal.dart';

/// Pure computation service that derives [StudentSignal]s from a
/// [StudentContext] snapshot.
class StudentSignalService {
  const StudentSignalService._();

  // ──────────────────────────────────────────────
  //  Configuration (centralised, testable)
  // ──────────────────────────────────────────────

  /// Events today at or above this count trigger a heavy-day signal.
  static const int heavyDayThreshold = 5;

  /// How far ahead to look for due-soon items (default 24 hours).
  static const Duration dueSoonWindow = Duration(hours: 24);

  /// Remaining budget below this absolute amount triggers attention.
  /// Only applied when money data is available.
  static const double budgetLowThreshold = 200.0;

  // ──────────────────────────────────────────────
  //  Public API
  // ──────────────────────────────────────────────

  /// Evaluate a [StudentContext] and return a priority-sorted list of signals.
  ///
  /// Returns an empty list when no signals are relevant (e.g. clear day
  /// with no issues — the UI may show a calm message separately).
  ///
  /// The [now] parameter allows callers to inject the current time for
  /// deterministic testing. Defaults to [DateTime.now].
  static List<StudentSignal> evaluate(
    StudentContext ctx, {
    DateTime? now,
  }) {
    final t = now ?? DateTime.now();
    final signals = <StudentSignal>[];

    // Each signal builder is independent — a failure in one does not
    // prevent the others from running.
    _overdueWork(ctx, signals);
    _missedMedicine(ctx, signals);
    _dueSoon(ctx, t, signals);
    _heavyDay(ctx, t, signals);
    _upcomingAssignment(ctx, t, signals);
    _budgetAttention(ctx, signals);

    // Sort by priority (lower value = higher priority).
    signals.sort((a, b) => a.priority.value.compareTo(b.priority.value));

    // If nothing needs attention, produce a clear-day signal.
    if (signals.isEmpty && ctx.studyAvailable) {
      signals.add(StudentSignal(
        type: SignalType.clearDay,
        priority: SignalPriority.clear,
        title: 'Schedule clear',
        subtitle: 'No urgent items right now',
        explanation: 'You have no overdue work or deadlines today.',
      ));
    }

    return signals;
  }

  /// Return only the top [maxSignals] signals for the Smart Attention section.
  static List<StudentSignal> topSignals(
    StudentContext ctx, {
    int maxSignals = 3,
    DateTime? now,
  }) {
    final all = evaluate(ctx, now: now);
    return all.take(maxSignals).toList();
  }

  // ──────────────────────────────────────────────
  //  Individual signal builders
  // ──────────────────────────────────────────────

  static void _overdueWork(StudentContext ctx, List<StudentSignal> out) {
    final overdue = ctx.overdueEvents
        .where((e) =>
            e.type == StudentEventType.task ||
            e.type == StudentEventType.assignment)
        .toList();

    if (overdue.isEmpty) return;

    final nearest = overdue.first; // already sorted by scheduledAt ascending
    final count = overdue.length;

    out.add(StudentSignal(
      type: SignalType.overdueWork,
      priority: SignalPriority.overdue,
      title: '$count overdue ${count == 1 ? "item" : "items"}',
      subtitle: '"${nearest.title}" is past due',
      explanation:
          '$count study ${count == 1 ? "item" : "items"} ${count == 1 ? "is" : "are"} overdue and need attention.',
      count: count,
      nearestEvent: nearest,
      destinationLabel: 'Study → Plan',
    ));
  }

  static void _missedMedicine(StudentContext ctx, List<StudentSignal> out) {
    if (!ctx.medicineAvailable) return;

    final pending = ctx.pendingMedicine
        .where((e) =>
            e.status == StudentEventStatus.pending ||
            e.status == StudentEventStatus.missed ||
            e.status == StudentEventStatus.overdue)
        .toList();

    if (pending.isEmpty) return;

    final count = pending.length;
    final nearest = pending.first;

    out.add(StudentSignal(
      type: SignalType.missedMedicine,
      priority: SignalPriority.medicine,
      title: '$count medicine ${count == 1 ? "dose" : "doses"} pending',
      subtitle: '"${nearest.title}" needs attention',
      explanation:
          '$count scheduled medicine ${count == 1 ? "dose" : "doses"} still need${count == 1 ? "s" : ""} to be taken.',
      count: count,
      nearestEvent: nearest,
      destinationLabel: 'Medicine',
    ));
  }

  static void _dueSoon(
    StudentContext ctx,
    DateTime now,
    List<StudentSignal> out,
  ) {
    final windowEnd = now.add(dueSoonWindow);

    final dueSoonItems = ctx.todayEvents
        .where((e) =>
            e.status == StudentEventStatus.pending &&
            e.scheduledAt != null &&
            e.scheduledAt!.isAfter(now) &&
            e.scheduledAt!.isBefore(windowEnd) &&
            (e.type == StudentEventType.task ||
                e.type == StudentEventType.assignment))
        .toList();

    // Also check upcoming events within the window.
    final upcomingDueSoon = ctx.upcomingEvents
        .where((e) =>
            e.status == StudentEventStatus.pending &&
            e.scheduledAt != null &&
            e.scheduledAt!.isAfter(now) &&
            e.scheduledAt!.isBefore(windowEnd) &&
            (e.type == StudentEventType.task ||
                e.type == StudentEventType.assignment))
        .toList();

    final all = [...dueSoonItems, ...upcomingDueSoon];
    if (all.isEmpty) return;

    all.sort((a, b) =>
        (a.scheduledAt ?? DateTime(0)).compareTo(b.scheduledAt ?? DateTime(0)));
    final nearest = all.first;
    final count = all.length;

    final remaining = nearest.scheduledAt!.difference(now);
    final timeLabel = _formatDuration(remaining);

    out.add(StudentSignal(
      type: SignalType.dueSoon,
      priority: SignalPriority.dueSoon,
      title: '$count due soon',
      subtitle: '"${nearest.title}" in $timeLabel',
      explanation:
          '$count ${count == 1 ? "item" : "items"} ${count == 1 ? "is" : "are"} due within the next 24 hours.',
      count: count,
      nearestEvent: nearest,
      destinationLabel: 'Study → Plan',
    ));
  }

  static void _heavyDay(
    StudentContext ctx,
    DateTime now,
    List<StudentSignal> out,
  ) {
    final actionableToday = ctx.todayEvents
        .where((e) =>
            e.status == StudentEventStatus.pending ||
            e.status == StudentEventStatus.overdue)
        .toList();

    if (actionableToday.length < heavyDayThreshold) return;

    final count = actionableToday.length;

    out.add(StudentSignal(
      type: SignalType.heavyDay,
      priority: SignalPriority.heavyDay,
      title: 'Busy day',
      subtitle: '$count items on your plate today',
      explanation:
          'You have $count actionable items scheduled for today, which is above the normal threshold.',
      count: count,
      destinationLabel: 'Study → Plan',
    ));
  }

  static void _upcomingAssignment(
    StudentContext ctx,
    DateTime now,
    List<StudentSignal> out,
  ) {
    // Collect all event IDs that are already represented by other signals
    // (overdue or dueSoon). We filter at the EVENT level, not signal level,
    // so an unrelated dueSoon Task does NOT suppress a future Assignment.
    final alreadyRepresentedIds = <String>{};

    // Overdue events are already represented by overdueWork signal.
    for (final s in out) {
      if (s.type == SignalType.overdueWork && s.nearestEvent != null) {
        alreadyRepresentedIds.add(s.nearestEvent!.id);
      }
    }

    // Events within the dueSoon window are represented by dueSoon signal.
    // Collect their IDs from the source events, not from signals.
    final windowEnd = now.add(dueSoonWindow);
    for (final e in ctx.todayEvents) {
      if (e.status == StudentEventStatus.pending &&
          e.scheduledAt != null &&
          e.scheduledAt!.isAfter(now) &&
          e.scheduledAt!.isBefore(windowEnd)) {
        alreadyRepresentedIds.add(e.id);
      }
    }
    for (final e in ctx.upcomingEvents) {
      if (e.status == StudentEventStatus.pending &&
          e.scheduledAt != null &&
          e.scheduledAt!.isAfter(now) &&
          e.scheduledAt!.isBefore(windowEnd)) {
        alreadyRepresentedIds.add(e.id);
      }
    }

    // Find incomplete assignments BEYOND the dueSoon window that are not
    // already represented by overdue.
    final nextAssignment = ctx.upcomingEvents
        .where((e) =>
            e.type == StudentEventType.assignment &&
            e.status == StudentEventStatus.pending &&
            e.scheduledAt != null &&
            e.scheduledAt!.isAfter(now) &&
            e.scheduledAt!.isAfter(windowEnd) &&
            !alreadyRepresentedIds.contains(e.id))
        .toList();

    if (nextAssignment.isEmpty) return;

    nextAssignment.sort((a, b) =>
        (a.scheduledAt ?? DateTime(0)).compareTo(b.scheduledAt ?? DateTime(0)));
    final nearest = nextAssignment.first;

    final remaining = nearest.scheduledAt!.difference(now);
    final timeLabel = _formatDuration(remaining);

    out.add(StudentSignal(
      type: SignalType.upcomingAssignment,
      priority: SignalPriority.upcoming,
      title: 'Assignment approaching',
      subtitle: '"${nearest.title}" due in $timeLabel',
      explanation:
          'Your next assignment "${nearest.title}" is due in $timeLabel.',
      nearestEvent: nearest,
      destinationLabel: 'Study → Plan',
    ));
  }

  static void _budgetAttention(StudentContext ctx, List<StudentSignal> out) {
    final money = ctx.moneySummary;
    if (money == null) return;

    final remaining = money.adjustedRemaining;

    // Only show when remaining is low and we have a meaningful spent amount.
    if (remaining > budgetLowThreshold || money.totalSpent <= 0) return;

    out.add(StudentSignal(
      type: SignalType.budgetAttention,
      priority: SignalPriority.budget,
      title: 'Low balance',
      subtitle: '৳${remaining.toStringAsFixed(0)} remaining',
      explanation:
          'Your remaining balance is ৳${remaining.toStringAsFixed(0)}, which is getting low.',
      destinationLabel: 'Money',
    ));
  }

  // ──────────────────────────────────────────────
  //  Helpers
  // ──────────────────────────────────────────────

  static String _formatDuration(Duration d) {
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    return '${d.inDays}d';
  }
}
