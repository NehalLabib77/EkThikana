import 'package:cloud_firestore/cloud_firestore.dart';

/// Canonical student-event types derived from existing Firestore data.
enum StudentEventType {
  task,
  assignment,
  medicine,
}

/// Status of a student event, normalised across source types.
enum StudentEventStatus {
  pending,
  completed,
  overdue,
  skipped,
  missed,
}

/// A read-only, normalised representation of a time-based student record.
///
/// `StudentEvent` is a *domain* model — it has no UI or BuildContext
/// dependencies. It is derived from existing Firestore documents via
/// adapter functions; no new persistence is created.
class StudentEvent {
  const StudentEvent({
    required this.id,
    required this.sourceId,
    required this.type,
    required this.title,
    this.scheduledAt,
    this.status = StudentEventStatus.pending,
    required this.source,
    this.priority,
    this.metadata,
  });

  /// Globally unique, deterministic ID.
  ///
  /// Built from (type, sourceId, optional dateKey) so the same source
  /// record always produces the same event ID.
  final String id;

  /// The original document / record ID in the source collection.
  final String sourceId;

  /// The kind of student event.
  final StudentEventType type;

  /// Human-readable title shown in UIs.
  final String title;

  /// When this event is due or scheduled.
  /// Null if the source record has no time component.
  final DateTime? scheduledAt;

  /// Normalised status.
  final StudentEventStatus status;

  /// Collection or system this event originated from.
  final String source;

  /// Optional priority (1 = highest). Null when unavailable.
  final int? priority;

  /// Extra data only when needed (e.g. medicine strength, dose time).
  /// Must be a flat, JSON-safe map.
  final Map<String, dynamic>? metadata;

  // ──────────────────────────────────────────────
  //  Deterministic ID helpers
  // ──────────────────────────────────────────────

  /// Build a deterministic event ID for a task or assignment.
  static String taskId(String docId) => 'task_$docId';

  /// Build a deterministic event ID for a medicine dose.
  ///
  /// Uses the same key formula as `FinancialService.doseId` so IDs
  /// are stable across rebuilds.
  static String medicineDoseId(String medicineId, DateTime date, String hhmm) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    final dateKey = '$y$m$d';
    final timeKey = hhmm.replaceAll(':', '');
    return 'med_${medicineId}_${dateKey}_$timeKey';
  }

  // ──────────────────────────────────────────────
  //  Adapter: Firestore task / assignment → StudentEvent
  // ──────────────────────────────────────────────

  /// Create a [StudentEvent] from a raw Firestore task/assignment document.
  ///
  /// The [doc] must be from the `tasks` collection with fields:
  /// `title`, `type` ('task'|'assignment'), `dueAt` (Timestamp?),
  /// `done` (bool).
  static StudentEvent fromTaskDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final rawType = data['type'] as String? ?? 'task';
    final eventType = rawType == 'assignment'
        ? StudentEventType.assignment
        : StudentEventType.task;
    final bool done = data['done'] as bool? ?? false;

    // Handle both Firestore Timestamp and plain DateTime (testing).
    DateTime? dueAt;
    final rawDue = data['dueAt'];
    if (rawDue is Timestamp) {
      dueAt = rawDue.toDate();
    } else if (rawDue is DateTime) {
      dueAt = rawDue;
    }

    final bool isOverdue =
        !done && dueAt != null && dueAt.isBefore(DateTime.now());

    final StudentEventStatus status = done
        ? StudentEventStatus.completed
        : isOverdue
            ? StudentEventStatus.overdue
            : StudentEventStatus.pending;

    return StudentEvent(
      id: taskId(doc.id),
      sourceId: doc.id,
      type: eventType,
      title: (data['title'] as String?) ?? '',
      scheduledAt: dueAt,
      status: status,
      source: 'tasks',
      metadata: null,
    );
  }

  // ──────────────────────────────────────────────
  //  Adapter: ScheduledDose → StudentEvent
  // ──────────────────────────────────────────────

  /// Create a [StudentEvent] from a [ScheduledDose].
  ///
  /// The dose must already have its status resolved by
  /// `MedicineSchedule.forDay`.
  static StudentEvent fromScheduledDose(
    dynamic dose, // ScheduledDose — using dynamic to avoid import cycle
    DateTime day,
  ) {
    final String medicineId = dose.medicineId as String;
    final String medicineName = dose.medicineName as String;
    final String time = dose.time as String;
    final dynamic doseStatus = dose.status; // DoseStatus enum
    final String statusName = doseStatus.name as String;

    final StudentEventStatus status;
    switch (statusName) {
      case 'taken':
        status = StudentEventStatus.completed;
        break;
      case 'skipped':
        status = StudentEventStatus.skipped;
        break;
      case 'missed':
        status = StudentEventStatus.missed;
        break;
      default:
        status = StudentEventStatus.pending;
    }

    final y = day.year.toString().padLeft(4, '0');
    final m = day.month.toString().padLeft(2, '0');
    final d = day.day.toString().padLeft(2, '0');
    final hh = time.length >= 2 ? time.substring(0, 2) : '00';
    final mm = time.length >= 5 ? time.substring(3, 5) : '00';
    final scheduledAt = DateTime(
      int.parse(y),
      int.parse(m),
      int.parse(d),
      int.parse(hh),
      int.parse(mm),
    );

    return StudentEvent(
      id: medicineDoseId(medicineId, day, time),
      sourceId: '$medicineId/$y-$m-$d/$time',
      type: StudentEventType.medicine,
      title: medicineName,
      scheduledAt: scheduledAt,
      status: status,
      source: 'medicines',
      metadata: {
        'medicineId': medicineId,
        'doseTime': time,
      },
    );
  }
}
