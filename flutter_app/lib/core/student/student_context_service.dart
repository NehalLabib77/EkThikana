import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../features/life/domain/medicine_schedule.dart';
import '../../models/financial_transaction.dart';
import 'student_context.dart';
import 'student_event.dart';

/// Aggregation service that produces a [StudentContext] snapshot from
/// existing data sources.  No new Firestore collections are created;
/// all data is derived from existing streams and queries.
class StudentContextService {
  const StudentContextService._();

  // ──────────────────────────────────────────────
  //  Public API
  // ──────────────────────────────────────────────

  /// Build a [StudentContext] for the given [day].
  ///
  /// Each subsystem is fetched independently; if one fails the rest
  /// still produce valid partial data.
  static Future<StudentContext> build({
    required DateTime day,
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? taskDocs,
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? medicineDocs,
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? doseDocs,
    FinancialSummary? financialSummary,
    MoneyRawFields? moneyRawFields,
    int? communityGroupCount,
  }) async {
    final now = DateTime.now();
    final events = <StudentEvent>[];

    // ── Tasks / Assignments ─────────────────────
    if (taskDocs != null) {
      events.addAll(taskDocs.map(StudentEvent.fromTaskDoc));
    }

    // ── Medicine doses ──────────────────────────
    if (medicineDocs != null && doseDocs != null) {
      final schedule = MedicineSchedule.forDay(medicineDocs, doseDocs, now: now);
      events.addAll(schedule.map((d) => StudentEvent.fromScheduledDose(d, day)));
    }

    // ── Split into today / upcoming / overdue / pending ──────
    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEnd = dayStart.add(const Duration(days: 1));

    final todayEvents = <StudentEvent>[];
    final upcomingEvents = <StudentEvent>[];
    final overdueEvents = <StudentEvent>[];
    final pendingMedicine = <StudentEvent>[];

    for (final e in events) {
      if (e.status == StudentEventStatus.overdue) {
        overdueEvents.add(e);
      }
      if (e.type == StudentEventType.medicine &&
          e.status == StudentEventStatus.pending) {
        pendingMedicine.add(e);
      }
      final dt = e.scheduledAt;
      if (dt != null && !dt.isBefore(dayStart) && dt.isBefore(dayEnd)) {
        todayEvents.add(e);
      } else if (dt != null && dt.isAfter(dayEnd)) {
        upcomingEvents.add(e);
      }
    }

    // Sort upcoming by scheduledAt ascending (deterministic).
    upcomingEvents.sort((a, b) {
      final ad = a.scheduledAt ?? DateTime(0);
      final bd = b.scheduledAt ?? DateTime(0);
      return ad.compareTo(bd);
    });

    // ── Sub-summaries (each independently fault-tolerant) ────
    final study = _buildStudySummary(taskDocs);
    final money = _buildMoneySummary(financialSummary, moneyRawFields);
    final community = _buildCommunitySummary(communityGroupCount);

    final bool medicineAvailable =
        medicineDocs != null && doseDocs != null;
    final bool studyAvailable = taskDocs != null;

    return StudentContext(
      generatedAt: now,
      todayEvents: todayEvents,
      upcomingEvents: upcomingEvents,
      overdueEvents: overdueEvents,
      pendingMedicine: pendingMedicine,
      medicineAvailable: medicineAvailable,
      studyAvailable: studyAvailable,
      studySummary: study,
      moneySummary: money,
      commuteSummary: null, // no lightweight source available yet
      communitySummary: community,
    );
  }

  // ──────────────────────────────────────────────
  //  Sub-summary builders
  // ──────────────────────────────────────────────

  static StudySummary? _buildStudySummary(
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? docs,
  ) {
    if (docs == null) return null;
    final now = DateTime.now();
    final dayEnd = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));

    int total = 0;
    int completedToday = 0;
    int upcoming = 0;
    int overdue = 0;

    for (final doc in docs) {
      final data = doc.data();
      final bool done = data['done'] as bool? ?? false;

      // Handle both Firestore Timestamp and plain DateTime (testing).
      DateTime? dueAt;
      final rawDue = data['dueAt'];
      if (rawDue is Timestamp) {
        dueAt = rawDue.toDate();
      } else if (rawDue is DateTime) {
        dueAt = rawDue;
      }

      total++;
      if (done) {
        // Handle both Timestamp and DateTime for updatedAt.
        DateTime? updatedAt;
        final rawUpdated = data['updatedAt'];
        if (rawUpdated is Timestamp) {
          updatedAt = rawUpdated.toDate();
        } else if (rawUpdated is DateTime) {
          updatedAt = rawUpdated;
        }
        if (updatedAt != null && updatedAt.isBefore(dayEnd)) {
          completedToday++;
        }
      } else if (dueAt != null && dueAt.isBefore(now)) {
        overdue++;
      } else if (dueAt != null && dueAt.isAfter(dayEnd)) {
        upcoming++;
      }
    }

    return StudySummary(
      totalTasks: total,
      completedToday: completedToday,
      upcomingCount: upcoming,
      overdueCount: overdue,
    );
  }

  static MoneySummary? _buildMoneySummary(
    FinancialSummary? summary,
    MoneyRawFields? raw,
  ) {
    if (summary == null && raw == null) return null;
    return MoneySummary(
      backendRemaining: raw?.backendRemaining ?? 0,
      totalSpent: summary?.totalSpending ?? 0,
      pawnaReceived: raw?.pawnaReceived ?? 0,
      denaPaid: raw?.denaPaid ?? 0,
    );
  }

  static CommunitySummary? _buildCommunitySummary(int? groupCount) {
    if (groupCount == null) return null;
    return CommunitySummary(groupCount: groupCount);
  }
}

/// Raw fields from the backend budget endpoint, passed through
/// without recalculation.
class MoneyRawFields {
  const MoneyRawFields({
    required this.backendRemaining,
    this.pawnaReceived = 0,
    this.denaPaid = 0,
  });

  final double backendRemaining;
  final double pawnaReceived;
  final double denaPaid;
}
