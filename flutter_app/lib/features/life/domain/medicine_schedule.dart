// Today's medicine schedule, derived from the `medicines` documents.
//
// Extracted from `MedicineScreen` so Home ("Next medicine") and the Medicine
// hub compute the same doses from the same rules. Two independent copies of
// this logic would eventually disagree about what a student's next dose is,
// which is not a difference a medicine feature can afford.
//
// This module derives *nothing medical*: it only expands the times the
// student themselves saved on the medicine, and reads back whatever dose
// record already exists. It never invents a dose, a time or a schedule
// (spec §57).

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../services/financial_service.dart';

/// Where a scheduled dose stands right now.
enum DoseStatus {
  /// Due later today, or due within the last hour and not yet acted on.
  pending,

  /// The student marked it taken.
  taken,

  /// The student explicitly skipped it.
  skipped,

  /// More than an hour past its time with no action recorded.
  missed;

  static DoseStatus parse(String? raw) => switch (raw) {
        'taken' => DoseStatus.taken,
        'skipped' => DoseStatus.skipped,
        'missed' => DoseStatus.missed,
        _ => DoseStatus.pending,
      };

  String get id => name;
}

/// One scheduled dose of one medicine on one day.
class ScheduledDose {
  const ScheduledDose({
    required this.medicineId,
    required this.medicine,
    required this.time,
    required this.status,
    required this.record,
  });

  final String medicineId;

  /// The raw medicine document.
  final Map<String, dynamic> medicine;

  /// Scheduled time as `HH:mm`.
  final String time;

  final DoseStatus status;

  /// The persisted `medicine_doses` document, when one exists.
  final Map<String, dynamic>? record;

  String get medicineName => medicine['name']?.toString() ?? '';

  String get strength => medicine['strength']?.toString() ?? '';

  String get instruction => medicine['instruction']?.toString() ?? '';

  String get unit => medicine['unit']?.toString() ?? 'tablet';

  double get unitPrice => (medicine['unitPrice'] as num?)?.toDouble() ?? 0;

  /// True when the dose still needs the student to act on it.
  bool get needsAction =>
      status == DoseStatus.pending || status == DoseStatus.missed;

  /// The dose's scheduled moment on [day].
  DateTime scheduledAt(DateTime day) {
    final parts = time.split(':');
    final hour = int.tryParse(parts.first) ?? 0;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return DateTime(day.year, day.month, day.day, hour, minute);
  }
}

/// Builds today's dose list from the student's medicines and dose records.
abstract final class MedicineSchedule {
  /// A dose still showing `pending` this long after its time is treated as
  /// missed. One hour matches the reminder grace period.
  static const Duration missedAfter = Duration(hours: 1);

  /// Expands [medicines] into the doses scheduled for [now]'s calendar day.
  ///
  /// Skips medicines that are inactive, paused, or outside their start/end
  /// date range. The result is sorted by time.
  static List<ScheduledDose> forDay(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> medicines,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> doseDocs, {
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final today = DateTime(at.year, at.month, at.day);
    final byId = {for (final d in doseDocs) d.id: d.data()};
    final result = <ScheduledDose>[];

    for (final med in medicines) {
      final data = med.data();
      if (data['active'] != true || data['paused'] == true) continue;

      final start = data['startDate'] is Timestamp
          ? (data['startDate'] as Timestamp).toDate()
          : DateTime(2000);
      if (today.isBefore(DateTime(start.year, start.month, start.day))) {
        continue;
      }
      final end = data['endDate'] is Timestamp
          ? (data['endDate'] as Timestamp).toDate()
          : null;
      if (end != null && today.isAfter(DateTime(end.year, end.month, end.day))) {
        continue;
      }

      final times = ((data['times'] as List?) ?? const [])
          .map((e) => e.toString())
          .where((e) => e.isNotEmpty)
          .toList()
        ..sort();

      for (final hhmm in times) {
        final record = byId[FinancialService.doseId(med.id, at, hhmm)];
        var status = DoseStatus.parse(record?['status']?.toString());

        if (status == DoseStatus.pending) {
          final parts = hhmm.split(':');
          final hour = int.tryParse(parts.first) ?? 0;
          final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
          final scheduled =
              DateTime(at.year, at.month, at.day, hour, minute);
          if (scheduled.isBefore(at.subtract(missedAfter))) {
            status = DoseStatus.missed;
          }
        }

        result.add(
          ScheduledDose(
            medicineId: med.id,
            medicine: data,
            time: hhmm,
            status: status,
            record: record,
          ),
        );
      }
    }

    result.sort((a, b) => a.time.compareTo(b.time));
    return result;
  }

  /// The next dose the student still has to act on, or null when today is
  /// done. Prefers an upcoming dose over an already-missed one, so Home
  /// shows "what's next" rather than "what you forgot".
  static ScheduledDose? next(List<ScheduledDose> schedule, {DateTime? now}) {
    final at = now ?? DateTime.now();
    ScheduledDose? upcoming;
    ScheduledDose? overdue;

    for (final dose in schedule) {
      if (!dose.needsAction) continue;
      if (dose.scheduledAt(at).isBefore(at)) {
        overdue ??= dose;
      } else {
        upcoming ??= dose;
        break;
      }
    }
    return upcoming ?? overdue;
  }

  /// Counts by status, for the Medicine hub summary row.
  static ({int taken, int skipped, int missed, int pending}) counts(
    List<ScheduledDose> schedule,
  ) {
    var taken = 0, skipped = 0, missed = 0, pending = 0;
    for (final dose in schedule) {
      switch (dose.status) {
        case DoseStatus.taken:
          taken++;
        case DoseStatus.skipped:
          skipped++;
        case DoseStatus.missed:
          missed++;
        case DoseStatus.pending:
          pending++;
      }
    }
    return (taken: taken, skipped: skipped, missed: missed, pending: pending);
  }
}
