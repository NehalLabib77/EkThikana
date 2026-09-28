// Phase T2 & T3 — Exam Rescue Data Models
//
// Typed, immutable representation of a generated Exam Rescue plan.
// Preview-only data models: no persistence logic or task creation is present here.

import 'package:flutter/foundation.dart';

/// One actionable item in a daily rescue schedule.
@immutable
class ExamRescueItem {
  const ExamRescueItem({
    required this.title,
    required this.type,
    required this.estimatedMinutes,
    this.materialId = '',
    this.actionNote = '',
  });

  /// Action title (e.g. "Review Chapter 1: Relational Algebra").
  final String title;

  /// Item type: 'study' | 'practice' | 'quiz' | 'revision'.
  final String type;

  /// Estimated time needed in minutes.
  final int estimatedMinutes;

  /// Optional material ID if grounded in an uploaded document/note.
  final String materialId;

  /// Specific action note or advice for the student.
  final String actionNote;

  bool get isStudy => type == 'study';
  bool get isPractice => type == 'practice';
  bool get isQuiz => type == 'quiz';
  bool get isRevision => type == 'revision';

  bool get hasMaterial => materialId.trim().isNotEmpty;

  factory ExamRescueItem.fromJson(Map<String, dynamic> json) {
    int parseMinutes(dynamic val) {
      if (val is num) return val.toInt();
      if (val is String) return int.tryParse(val) ?? 30;
      return 30;
    }

    String normalizeType(dynamic val) {
      final raw = (val ?? 'study').toString().trim().toLowerCase();
      if (raw == 'study' || raw == 'practice' || raw == 'quiz' || raw == 'revision') {
        return raw;
      }
      if (raw == 'test' || raw == 'mcq' || raw == 'exam' || raw == 'assessment') {
        return 'quiz';
      }
      if (raw == 'review' || raw == 'recap') {
        return 'revision';
      }
      if (raw == 'exercise' || raw == 'problem' || raw == 'homework') {
        return 'practice';
      }
      return 'study';
    }

    return ExamRescueItem(
      title: (json['title'] ?? '').toString().trim(),
      type: normalizeType(json['type']),
      estimatedMinutes: parseMinutes(json['estimatedMinutes'] ?? json['estimated_minutes']),
      materialId: (json['materialId'] ?? json['material_id'] ?? '').toString().trim(),
      actionNote: (json['actionNote'] ?? json['action_note'] ?? '').toString().trim(),
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'type': type,
    'estimatedMinutes': estimatedMinutes,
    'materialId': materialId,
    'actionNote': actionNote,
  };

  ExamRescueItem copyWith({
    String? title,
    String? type,
    int? estimatedMinutes,
    String? materialId,
    String? actionNote,
  }) {
    return ExamRescueItem(
      title: title ?? this.title,
      type: type ?? this.type,
      estimatedMinutes: estimatedMinutes ?? this.estimatedMinutes,
      materialId: materialId ?? this.materialId,
      actionNote: actionNote ?? this.actionNote,
    );
  }
}

/// One day within an Exam Rescue plan.
@immutable
class ExamRescueDay {
  const ExamRescueDay({
    required this.dayNumber,
    required this.dateOffset,
    required this.theme,
    required this.targetMinutes,
    required this.items,
  });

  /// 1-based day index (1, 2, ... N).
  final int dayNumber;

  /// 0-based date offset from the plan start date (0 = Day 1, 1 = Day 2, etc.).
  final int dateOffset;

  /// Focal theme or subject for the day (e.g. "Core Theory & Normalization").
  final String theme;

  /// Target study budget in minutes for this day.
  final int targetMinutes;

  /// Actionable items scheduled for this day.
  final List<ExamRescueItem> items;

  int get totalMinutes => items.fold(0, (sum, i) => sum + i.estimatedMinutes);

  int get quizCount => items.where((i) => i.isQuiz).length;

  factory ExamRescueDay.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic val, int fallback) {
      if (val is num) return val.toInt();
      if (val is String) return int.tryParse(val) ?? fallback;
      return fallback;
    }

    final rawItems = json['items'];
    final itemsList = <ExamRescueItem>[];
    if (rawItems is List) {
      for (final raw in rawItems) {
        if (raw is Map) {
          itemsList.add(ExamRescueItem.fromJson(raw.map((k, v) => MapEntry(k.toString(), v))));
        }
      }
    }

    return ExamRescueDay(
      dayNumber: parseInt(json['dayNumber'] ?? json['day_number'], 1),
      dateOffset: parseInt(json['dateOffset'] ?? json['date_offset'], 0),
      theme: (json['theme'] ?? '').toString().trim(),
      targetMinutes: parseInt(json['targetMinutes'] ?? json['target_minutes'], 120),
      items: itemsList,
    );
  }

  Map<String, dynamic> toJson() => {
    'dayNumber': dayNumber,
    'dateOffset': dateOffset,
    'theme': theme,
    'targetMinutes': targetMinutes,
    'items': items.map((i) => i.toJson()).toList(),
  };

  ExamRescueDay copyWith({
    int? dayNumber,
    int? dateOffset,
    String? theme,
    int? targetMinutes,
    List<ExamRescueItem>? items,
  }) {
    return ExamRescueDay(
      dayNumber: dayNumber ?? this.dayNumber,
      dateOffset: dateOffset ?? this.dateOffset,
      theme: theme ?? this.theme,
      targetMinutes: targetMinutes ?? this.targetMinutes,
      items: items ?? this.items,
    );
  }
}

/// The complete Exam Rescue plan.
@immutable
class ExamRescuePlan {
  const ExamRescuePlan({
    required this.examTitle,
    required this.daysRemaining,
    required this.totalEstimatedMinutes,
    required this.strategySummary,
    required this.sourceMode,
    required this.generationMode,
    required this.days,
  });

  /// Name of the exam (e.g. "Database Systems Final").
  final String examTitle;

  /// Total days allocated in the plan.
  final int daysRemaining;

  /// Sum of all estimated minutes across the entire plan.
  final int totalEstimatedMinutes;

  /// Strategic overview explaining the preparation approach.
  final String strategySummary;

  /// Source grounding: 'materials' (grounded in uploaded documents) or 'general_subject'.
  final String sourceMode;

  /// Generation engine: 'ai' (synthesized by cascade) or 'fallback' (deterministic).
  final String generationMode;

  /// Day-by-day plan breakdown.
  final List<ExamRescueDay> days;

  bool get isGroundedInMaterials => sourceMode == 'materials';

  bool get isFallback => generationMode == 'fallback';

  int get totalItemsCount => days.fold(0, (sum, d) => sum + d.items.length);

  int get totalQuizzesCount => days.fold(0, (sum, d) => sum + d.quizCount);

  factory ExamRescuePlan.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic val, int fallback) {
      if (val is num) return val.toInt();
      if (val is String) return int.tryParse(val) ?? fallback;
      return fallback;
    }

    final rawDays = json['days'];
    final daysList = <ExamRescueDay>[];
    if (rawDays is List) {
      for (final raw in rawDays) {
        if (raw is Map) {
          daysList.add(ExamRescueDay.fromJson(raw.map((k, v) => MapEntry(k.toString(), v))));
        }
      }
    }

    return ExamRescuePlan(
      examTitle: (json['examTitle'] ?? json['exam_title'] ?? '').toString().trim(),
      daysRemaining: parseInt(json['daysRemaining'] ?? json['days_remaining'], 1),
      totalEstimatedMinutes: parseInt(
        json['totalEstimatedMinutes'] ?? json['total_estimated_minutes'],
        0,
      ),
      strategySummary: (json['strategySummary'] ?? json['strategy_summary'] ?? '').toString().trim(),
      sourceMode: (json['sourceMode'] ?? json['source_mode'] ?? 'general_subject').toString().trim(),
      generationMode: (json['generationMode'] ?? json['generation_mode'] ?? 'ai').toString().trim(),
      days: daysList,
    );
  }

  Map<String, dynamic> toJson() => {
    'examTitle': examTitle,
    'daysRemaining': daysRemaining,
    'totalEstimatedMinutes': totalEstimatedMinutes,
    'strategySummary': strategySummary,
    'sourceMode': sourceMode,
    'generationMode': generationMode,
    'days': days.map((d) => d.toJson()).toList(),
  };

  ExamRescuePlan copyWith({
    String? examTitle,
    int? daysRemaining,
    int? totalEstimatedMinutes,
    String? strategySummary,
    String? sourceMode,
    String? generationMode,
    List<ExamRescueDay>? days,
  }) {
    return ExamRescuePlan(
      examTitle: examTitle ?? this.examTitle,
      daysRemaining: daysRemaining ?? this.daysRemaining,
      totalEstimatedMinutes: totalEstimatedMinutes ?? this.totalEstimatedMinutes,
      strategySummary: strategySummary ?? this.strategySummary,
      sourceMode: sourceMode ?? this.sourceMode,
      generationMode: generationMode ?? this.generationMode,
      days: days ?? this.days,
    );
  }
}
