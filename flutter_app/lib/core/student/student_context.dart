import 'student_event.dart';

/// A lightweight, read-only snapshot of the student's current state.
///
/// Built by `StudentContextService` from existing data sources.
/// Missing or unavailable data degrades to null — callers must
/// handle partial state gracefully.
class StudentContext {
  const StudentContext({
    required this.generatedAt,
    this.todayEvents = const [],
    this.upcomingEvents = const [],
    this.overdueEvents = const [],
    this.pendingMedicine = const [],
    this.medicineAvailable = true,
    this.studyAvailable = true,
    this.studySummary,
    this.moneySummary,
    this.commuteSummary,
    this.communitySummary,
  });

  /// When this snapshot was produced (local DateTime).
  final DateTime generatedAt;

  /// Events due today (scheduledAt falls on the same local calendar day).
  final List<StudentEvent> todayEvents;

  /// Events due after today, sorted ascending by scheduledAt.
  final List<StudentEvent> upcomingEvents;

  /// Events that are overdue (past due and not completed).
  final List<StudentEvent> overdueEvents;

  /// Medicine doses that still need action today.
  final List<StudentEvent> pendingMedicine;

  /// Whether the medicine subsystem was successfully loaded.
  /// False when medicine data is unavailable or failed to load.
  final bool medicineAvailable;

  /// Whether study/task data was provided to the context.
  /// When false, clearDay signals are suppressed.
  final bool studyAvailable;

  /// Lightweight study summary. Null when data is unavailable.
  final StudySummary? studySummary;

  /// Lightweight money summary. Null when data is unavailable.
  final MoneySummary? moneySummary;

  /// Lightweight commute summary. Null when data is unavailable.
  final CommuteSummary? commuteSummary;

  /// Lightweight community summary. Null when data is unavailable.
  final CommunitySummary? communitySummary;

  /// True when every subsystem returned data (no nulls).
  bool get isFullyLoaded =>
      studySummary != null &&
      moneySummary != null &&
      commuteSummary != null &&
      communitySummary != null;
}

// ──────────────────────────────────────────────
//  Sub-summaries
// ──────────────────────────────────────────────

/// Lightweight study snapshot derived from existing task/assignment data.
class StudySummary {
  const StudySummary({
    required this.totalTasks,
    required this.completedToday,
    required this.upcomingCount,
    required this.overdueCount,
  });

  final int totalTasks;
  final int completedToday;
  final int upcomingCount;
  final int overdueCount;
}

/// Lightweight money snapshot using the existing authoritative backend
/// calculation (`GET /api/budget/remaining`).
class MoneySummary {
  const MoneySummary({
    required this.backendRemaining,
    required this.totalSpent,
    this.pawnaReceived = 0,
    this.denaPaid = 0,
  });

  /// Backend-computed remaining (available − totalSpent − denaPaid).
  final double backendRemaining;

  /// Sum of all expense ledger entries this month.
  final double totalSpent;

  /// Income from lend settlements (not in ledger).
  final double pawnaReceived;

  /// Payments for borrow settlements (IS in ledger).
  final double denaPaid;

  /// Adjusted remaining matching the authoritative Gochano formula:
  /// backendRemaining + pawnaReceived − denaPaid.
  double get adjustedRemaining => backendRemaining + pawnaReceived - denaPaid;
}

/// Lightweight commute snapshot from existing trip data.
class CommuteSummary {
  const CommuteSummary({
    required this.tripsThisMonth,
    required this.totalFareThisMonth,
  });

  final int tripsThisMonth;
  final double totalFareThisMonth;
}

/// Lightweight community snapshot from existing group data.
class CommunitySummary {
  const CommunitySummary({
    required this.groupCount,
    this.hasUnreadMessages = false,
  });

  final int groupCount;
  final bool hasUnreadMessages;
}
