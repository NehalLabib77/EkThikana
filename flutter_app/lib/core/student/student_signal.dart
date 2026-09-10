/// A deterministic, runtime-derived fact about the student's current state.
///
/// Signals are computed from [StudentContext] by [StudentSignalService].
/// They are NOT persisted and NOT a new source of truth.
///
/// Each signal carries enough data for the UI to render a compact
/// attention card and navigate to the relevant screen.
library;

import 'student_event.dart';

/// The kind of signal.
enum SignalType {
  /// One or more incomplete tasks/assignments are past their due date.
  overdueWork,

  /// A task/assignment is due within the upcoming window (default 24h).
  dueSoon,

  /// Today has an unusually high number of actionable events.
  heavyDay,

  /// No overdue work and no deadlines today — schedule is clear.
  clearDay,

  /// An incomplete assignment is approaching its deadline.
  upcomingAssignment,

  /// A scheduled medicine dose was missed or is pending.
  missedMedicine,

  /// Money remaining is low relative to what's been spent.
  budgetAttention,
}

/// Priority level for ranking signals.
///
/// Lower number = higher priority. Centralised in [SignalPriority].
enum SignalPriority {
  overdue(1),
  medicine(2),
  dueSoon(3),
  upcoming(4),
  heavyDay(5),
  budget(6),
  clear(7);

  const SignalPriority(this.value);
  final int value;
}

/// A single derived signal about the student's current state.
class StudentSignal {
  const StudentSignal({
    required this.type,
    required this.priority,
    required this.title,
    required this.subtitle,
    required this.explanation,
    this.count,
    this.nearestEvent,
    this.destinationLabel,
    this.aiPrompt,
  });

  /// The kind of signal.
  final SignalType type;

  /// Priority for ranking (lower = more important).
  final SignalPriority priority;

  /// Short user-facing title (EN/BN handled by caller).
  final String title;

  /// One-line subtitle with key fact.
  final String subtitle;

  /// Deterministic explanation of why this signal is shown.
  final String explanation;

  /// Optional count of items contributing to this signal.
  final int? count;

  /// The nearest/highest-priority event driving this signal.
  final StudentEvent? nearestEvent;

  /// Label for the navigation destination (e.g. "Study → Plan").
  final String? destinationLabel;

  /// Optional prefilled AI prompt (for Plan My Day / Rescue My Day).
  /// When non-null, tapping the signal can open the AI Assistant.
  final String? aiPrompt;
}
