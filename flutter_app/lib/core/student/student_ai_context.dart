// Safe, serializable representation of StudentContext for AI prompts.
//
// Excludes all sensitive/private data (UID, phone, tokens, B2 URLs).
// Includes only deterministic, bounded data useful for AI reasoning.
// This DTO is the ONLY thing sent to the AI backend — never raw
// Firestore documents or full StudentContext.

import 'dart:convert';

import 'student_context.dart';
import 'student_event.dart';

/// A bounded, privacy-safe representation of the student's current state
/// for inclusion in AI prompts.
///
/// Designed to be serialized as JSON and sent to the AI backend as a
/// structured context block. All fields are optional — missing subsystems
/// degrade to null/empty.
class StudentAiContext {
  const StudentAiContext({
    this.generatedAt,
    this.todayEvents = const [],
    this.upcomingEvents = const [],
    this.overdueEvents = const [],
    this.pendingMedicine = const [],
    this.medicineAvailable = false,
    this.studySummary,
    this.moneySummary,
    this.communitySummary,
  });

  /// When this snapshot was produced (ISO 8601 string).
  final String? generatedAt;

  /// Bounded list of today's events (max 10).
  final List<AiEvent> todayEvents;

  /// Bounded list of upcoming events (max 10, nearest first).
  final List<AiEvent> upcomingEvents;

  /// Bounded list of overdue events (max 10).
  final List<AiEvent> overdueEvents;

  /// Bounded list of pending medicine doses (max 5).
  final List<AiEvent> pendingMedicine;

  /// Whether the medicine subsystem was successfully loaded.
  final bool medicineAvailable;

  /// Study summary, null when unavailable.
  final AiStudySummary? studySummary;

  /// Money summary, null when unavailable.
  final AiMoneySummary? moneySummary;

  /// Community summary, null when unavailable.
  final AiCommunitySummary? communitySummary;

  /// Maximum events per category sent to AI.
  static const int maxEvents = 10;
  static const int maxMedicine = 5;

  /// Build a safe [StudentAiContext] from a [StudentContext].
  ///
  /// Applies bounded truncation and strips all internal IDs / metadata
  /// that are not useful for AI reasoning.
  factory StudentAiContext.fromContext(StudentContext ctx) {
    return StudentAiContext(
      generatedAt: ctx.generatedAt.toIso8601String(),
      todayEvents: ctx.todayEvents
          .take(maxEvents)
          .map(AiEvent.fromStudentEvent)
          .toList(),
      upcomingEvents: ctx.upcomingEvents
          .take(maxEvents)
          .map(AiEvent.fromStudentEvent)
          .toList(),
      overdueEvents: ctx.overdueEvents
          .take(maxEvents)
          .map(AiEvent.fromStudentEvent)
          .toList(),
      pendingMedicine: ctx.pendingMedicine
          .take(maxMedicine)
          .map(AiEvent.fromStudentEvent)
          .toList(),
      medicineAvailable: ctx.medicineAvailable,
      studySummary: ctx.studySummary != null
          ? AiStudySummary.fromStudySummary(ctx.studySummary!)
          : null,
      moneySummary: ctx.moneySummary != null
          ? AiMoneySummary.fromMoneySummary(ctx.moneySummary!)
          : null,
      communitySummary: ctx.communitySummary != null
          ? AiCommunitySummary.fromCommunitySummary(ctx.communitySummary!)
          : null,
    );
  }

  /// Serialize to a JSON-safe map.
  Map<String, dynamic> toJson() => {
        if (generatedAt != null) 'generatedAt': generatedAt,
        if (todayEvents.isNotEmpty)
          'todayEvents': todayEvents.map((e) => e.toJson()).toList(),
        if (upcomingEvents.isNotEmpty)
          'upcomingEvents': upcomingEvents.map((e) => e.toJson()).toList(),
        if (overdueEvents.isNotEmpty)
          'overdueEvents': overdueEvents.map((e) => e.toJson()).toList(),
        if (pendingMedicine.isNotEmpty)
          'pendingMedicine': pendingMedicine.map((e) => e.toJson()).toList(),
        'medicineAvailable': medicineAvailable,
        if (studySummary != null) 'studySummary': studySummary!.toJson(),
        if (moneySummary != null) 'moneySummary': moneySummary!.toJson(),
        if (communitySummary != null)
          'communitySummary': communitySummary!.toJson(),
      };

  /// Serialize to a formatted JSON string for prompt injection.
  String toPromptString() {
    final json = toJson();
    // Ensure medicine availability is always explicit in the prompt.
    json['medicineAvailable'] = medicineAvailable;
    json['pendingMedicineNote'] = medicineAvailable
        ? (pendingMedicine.isEmpty ? 'no pending doses' : null)
        : 'not available';
    // Remove null note values for cleaner output.
    if (json['pendingMedicineNote'] == null) {
      json.remove('pendingMedicineNote');
    }
    return const JsonEncoder.withIndent('  ').convert(json);
  }

  /// True when no context data is available.
  bool get isEmpty =>
      todayEvents.isEmpty &&
      upcomingEvents.isEmpty &&
      overdueEvents.isEmpty &&
      pendingMedicine.isEmpty &&
      studySummary == null &&
      moneySummary == null &&
      communitySummary == null;

  // -----------------------------------------------------------------------
  // Deterministic question-based context scoping (Phase 6.1).
  //
  // Money / medicine data is only included when the question is
  // related to that topic. Study events + community are always included.
  // This avoids leaking unrelated personal data to the AI.
  // -----------------------------------------------------------------------

  static final _moneyPattern = RegExp(
    r'(spend|budget|expense|money|remaining|balance|taka|tk|৳|cost|price|paid|payment|receipt|lunch|dinner|breakfast|food|meal|transport|fare|buy|bought|owe|debt|loan|save|savings)',
    caseSensitive: false,
  );

  static final _medicinePattern = RegExp(
    r'(medicine|dose|pill|drug|prescription|ওষুধ|tablets?|syrup|mg|ml|vitamin|supplement|paracetamol|ibuprofen|antibiotic|capsule|inhaler|insulin|allergy|asthma|fever|pain|headache|stomach|cold|cough|diarrhea|vomit)',
    caseSensitive: false,
  );

  /// Serialize to a scoped JSON map based on the user's question.
  ///
  /// Study context is always included. Money context is only included when
  /// the question is money-related. Medicine context is only included when
  /// the question is medicine-related. Community is always included.
  Map<String, dynamic> toJsonScoped(String question) {
    final q = question.toLowerCase();
    final base = toJson();

    if (!_moneyPattern.hasMatch(q)) {
      base.remove('moneySummary');
    }

    if (!_medicinePattern.hasMatch(q)) {
      base.remove('pendingMedicine');
      base.remove('medicineAvailable');
      base.remove('pendingMedicineNote');
    } else {
      // Medicine-related question: always include medicine fields
      // even when pendingMedicine is empty (distinguishes "available, none"
      // from "unavailable").
      base['medicineAvailable'] = medicineAvailable;
      base['pendingMedicine'] = pendingMedicine.map((e) => e.toJson()).toList();
      if (!medicineAvailable) {
        base['pendingMedicineNote'] = 'not available';
      } else if (pendingMedicine.isEmpty) {
        base['pendingMedicineNote'] = 'no pending doses';
      }
    }

    return base;
  }
}

/// Safe event representation — type, title, time, status only.
/// No internal IDs, no source collection paths, no metadata.
class AiEvent {
  const AiEvent({
    required this.type,
    required this.title,
    this.scheduledAt,
    required this.status,
  });

  final String type;
  final String title;
  final String? scheduledAt;
  final String status;

  factory AiEvent.fromStudentEvent(StudentEvent e) {
    return AiEvent(
      type: e.type.name,
      title: e.title,
      scheduledAt: e.scheduledAt?.toIso8601String(),
      status: e.status.name,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        'title': title,
        if (scheduledAt != null) 'scheduledAt': scheduledAt,
        'status': status,
      };
}

/// Safe study summary — counts only.
class AiStudySummary {
  const AiStudySummary({
    required this.totalTasks,
    required this.completedToday,
    required this.upcomingCount,
    required this.overdueCount,
  });

  final int totalTasks;
  final int completedToday;
  final int upcomingCount;
  final int overdueCount;

  factory AiStudySummary.fromStudySummary(StudySummary s) {
    return AiStudySummary(
      totalTasks: s.totalTasks,
      completedToday: s.completedToday,
      upcomingCount: s.upcomingCount,
      overdueCount: s.overdueCount,
    );
  }

  Map<String, dynamic> toJson() => {
        'totalTasks': totalTasks,
        'completedToday': completedToday,
        'upcomingCount': upcomingCount,
        'overdueCount': overdueCount,
      };
}

/// Safe money summary — amounts only. No raw fields, no settlement details.
class AiMoneySummary {
  const AiMoneySummary({
    required this.totalSpent,
    required this.remaining,
  });

  final double totalSpent;
  final double remaining;

  factory AiMoneySummary.fromMoneySummary(MoneySummary m) {
    return AiMoneySummary(
      totalSpent: m.totalSpent,
      remaining: m.adjustedRemaining,
    );
  }

  Map<String, dynamic> toJson() => {
        'totalSpent': totalSpent,
        'remaining': remaining,
      };
}

/// Safe community summary — count only.
class AiCommunitySummary {
  const AiCommunitySummary({required this.groupCount});

  final int groupCount;

  factory AiCommunitySummary.fromCommunitySummary(CommunitySummary c) {
    return AiCommunitySummary(groupCount: c.groupCount);
  }

  Map<String, dynamic> toJson() => {'groupCount': groupCount};
}
