import 'package:cloud_firestore/cloud_firestore.dart';

/// Canonical task status enum representing the lifecycle states of a task.
enum TaskStatus { pending, completed, missed, cancelled }

/// Unified domain service for task lifecycle, calendar day normalization,
/// status resolution, and view filtering across Today, Plan, History, and Notifications.
class TaskLifecycle {
  const TaskLifecycle._();

  /// Parse dynamic date values safely from Firestore, DateTime, int, or String.
  static DateTime? parseDateTime(dynamic raw) {
    if (raw == null) return null;
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  /// Truncate a [DateTime] to its calendar day (year, month, day) in the local timezone.
  static DateTime calendarDate(DateTime dt) {
    final local = dt.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  /// True if [dueAt]'s calendar day is strictly before [now]'s calendar day in local time.
  static bool isPastCalendarDay(DateTime dueAt, DateTime now) {
    final dueDay = calendarDate(dueAt);
    final nowDay = calendarDate(now);
    return dueDay.isBefore(nowDay);
  }

  /// True if [dueAt] and [now] share the exact same calendar day in local time.
  static bool isSameCalendarDay(DateTime dueAt, DateTime now) {
    final dueDay = calendarDate(dueAt);
    final nowDay = calendarDate(now);
    return dueDay.isAtSameMomentAs(nowDay);
  }

  /// True if [dueAt]'s calendar day is strictly after [now]'s calendar day in local time.
  static bool isFutureCalendarDay(DateTime dueAt, DateTime now) {
    final dueDay = calendarDate(dueAt);
    final nowDay = calendarDate(now);
    return dueDay.isAfter(nowDay);
  }

  /// True if document data indicates completion (`done`, `completed`, or status).
  static bool isTaskCompleted(Map<String, dynamic> data) {
    if (data['done'] == true) return true;
    if (data['completed'] == true) return true;
    final status = data['status']?.toString().toLowerCase().trim();
    return status == 'completed' || status == 'done';
  }

  /// True if document data indicates cancellation or deletion.
  static bool isTaskCancelled(Map<String, dynamic> data) {
    if (data['cancelled'] == true) return true;
    if (data['deleted'] == true) return true;
    final status = data['status']?.toString().toLowerCase().trim();
    return status == 'cancelled' || status == 'canceled' || status == 'deleted';
  }

  /// Canonical status resolution for a task given its completed/cancelled state,
  /// scheduled [dueAt], and reference [now].
  ///
  /// Rules:
  /// 1. `completed` -> [TaskStatus.completed] (never mutates to missed)
  /// 2. `cancelled` -> [TaskStatus.cancelled] (never mutates to missed)
  /// 3. `dueAt == null` -> [TaskStatus.pending] (undated tasks are not missed)
  /// 4. Scheduled on a past calendar day -> [TaskStatus.missed]
  /// 5. Scheduled for today or future -> [TaskStatus.pending]
  static TaskStatus resolveStatus({
    required bool isCompleted,
    required bool isCancelled,
    required DateTime? dueAt,
    required DateTime now,
  }) {
    if (isCompleted) return TaskStatus.completed;
    if (isCancelled) return TaskStatus.cancelled;
    if (dueAt == null) return TaskStatus.pending;
    if (isPastCalendarDay(dueAt, now)) return TaskStatus.missed;
    return TaskStatus.pending;
  }

  /// Convenience resolver extracting fields directly from raw task document data.
  static TaskStatus resolveDocStatus(
    Map<String, dynamic> data, [
    DateTime? now,
  ]) {
    final currentTime = now ?? DateTime.now();
    return resolveStatus(
      isCompleted: isTaskCompleted(data),
      isCancelled: isTaskCancelled(data),
      dueAt: parseDateTime(data['dueAt']),
      now: currentTime,
    );
  }

  /// Determines whether a task belongs on the Today screen.
  ///
  /// Invariant:
  /// - Must NOT be completed or cancelled.
  /// - Must be either undated (`dueAt == null`) OR scheduled for Today's calendar day.
  /// - Past calendar day tasks are strictly excluded (they belong to History as Missed).
  /// - Future calendar day tasks are strictly excluded (they belong to Upcoming / Plan).
  static bool belongsToToday(Map<String, dynamic> data, [DateTime? now]) {
    final currentTime = now ?? DateTime.now();
    if (isTaskCompleted(data)) return false;
    if (isTaskCancelled(data)) return false;

    final dueAt = parseDateTime(data['dueAt']);
    if (dueAt == null)
      return true; // Undated tasks remain in Today active view.

    return isSameCalendarDay(dueAt, currentTime);
  }

  /// Determines whether a task scheduled for Today is overdue by clock time.
  ///
  /// Note: Only relevant for tasks belonging to Today. If the scheduled time
  /// has elapsed today, it remains active in Today, but may be highlighted as overdue.
  static bool isTodayClockOverdue(Map<String, dynamic> data, [DateTime? now]) {
    final currentTime = now ?? DateTime.now();
    if (!belongsToToday(data, currentTime)) return false;
    final dueAt = parseDateTime(data['dueAt']);
    if (dueAt == null) return false;
    return dueAt.isBefore(currentTime);
  }

  /// Determines whether a task belongs in History.
  ///
  /// Invariant:
  /// - Completed tasks always belong in History.
  /// - Incomplete, non-cancelled tasks scheduled on a past calendar day belong in
  ///   History with canonical state `missed`.
  /// - Today's tasks (even if time has passed) do NOT belong to History until the day ends.
  /// - Future tasks and undated incomplete tasks do NOT belong to History.
  static bool belongsToHistory(Map<String, dynamic> data, [DateTime? now]) {
    final currentTime = now ?? DateTime.now();
    if (isTaskCompleted(data)) return true;
    if (isTaskCancelled(data)) return false;

    final dueAt = parseDateTime(data['dueAt']);
    if (dueAt == null) return false;

    return isPastCalendarDay(dueAt, currentTime);
  }

  /// Determines whether a task belongs to a specific day on the Plan view.
  static bool belongsToPlanDay(
    Map<String, dynamic> data,
    DateTime selectedDay,
  ) {
    if (isTaskCompleted(data)) return false;
    if (isTaskCancelled(data)) return false;

    final dueAt = parseDateTime(data['dueAt']);
    if (dueAt == null) return false;

    return isSameCalendarDay(dueAt, selectedDay);
  }
}
