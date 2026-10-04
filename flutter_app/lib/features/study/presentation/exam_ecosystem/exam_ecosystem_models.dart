/// Phase 15 — Exam Ecosystem data models.
///
/// Lightweight value objects used by the Exam Hub UI.
/// All derived from API JSON — no local computation of scores/priorities.
library;

class ExamPlan {
  const ExamPlan({
    required this.planId,
    required this.examName,
    required this.examDate,
    required this.durationDays,
    required this.dailyMinutes,
    required this.status,
    this.subjects = const [],
  });

  final String planId;
  final String examName;
  final String examDate;
  final int durationDays;
  final int dailyMinutes;
  final String status;
  final List<String> subjects;

  factory ExamPlan.fromJson(Map<String, dynamic> j) => ExamPlan(
        planId: j['planId'] as String? ?? '',
        examName: j['examName'] as String? ?? 'Upcoming Exam',
        examDate: j['examDate'] as String? ?? '',
        durationDays: (j['durationDays'] as num?)?.toInt() ?? 0,
        dailyMinutes: (j['dailyMinutes'] as num?)?.toInt() ?? 120,
        status: j['status'] as String? ?? 'active',
        subjects: List<String>.from(j['subjects'] as List? ?? []),
      );

  int get daysRemaining {
    try {
      final exam = DateTime.parse(examDate);
      final diff = exam.difference(DateTime.now()).inDays;
      return diff < 0 ? 0 : diff;
    } catch (_) {
      return 0;
    }
  }
}

class PriorityTopic {
  const PriorityTopic({
    required this.topic,
    required this.priority,
    required this.priorityScore,
    this.historicalFrequency,
    this.masteryGap,
    this.mistakePressure,
    this.revisionUrgency,
    this.recentPerformanceGap,
  });

  final String topic;
  final String priority; // critical | high | medium | low
  final double priorityScore;
  final double? historicalFrequency;
  final double? masteryGap;
  final double? mistakePressure;
  final double? revisionUrgency;
  final double? recentPerformanceGap;

  factory PriorityTopic.fromJson(Map<String, dynamic> j) {
    final components = j['components'] as Map<String, dynamic>? ?? {};
    return PriorityTopic(
      topic: j['topic'] as String? ?? '',
      priority: j['priority'] as String? ?? 'medium',
      priorityScore: (j['priorityScore'] as num?)?.toDouble() ?? 0,
      historicalFrequency:
          (components['historicalFrequency'] as num?)?.toDouble(),
      masteryGap: (components['masteryGap'] as num?)?.toDouble(),
      mistakePressure: (components['mistakePressure'] as num?)?.toDouble(),
      revisionUrgency: (components['revisionUrgency'] as num?)?.toDouble(),
      recentPerformanceGap:
          (components['recentPerformanceGap'] as num?)?.toDouble(),
    );
  }

  String get priorityLabel {
    switch (priority) {
      case 'critical':
        return 'CRITICAL';
      case 'high':
        return 'HIGH';
      case 'medium':
        return 'MEDIUM';
      default:
        return 'LOW';
    }
  }
}

class ExamReadiness {
  const ExamReadiness({
    required this.overallReadiness,
    required this.label,
    required this.trend,
    required this.components,
    required this.recommendedNextAction,
    required this.dataCoverage,
    this.criticalTopics = const [],
    this.strongTopics = const [],
  });

  final double overallReadiness;
  final String label;
  final double trend;
  final Map<String, double> components;
  final String recommendedNextAction;
  final double dataCoverage;
  final List<String> criticalTopics;
  final List<String> strongTopics;

  factory ExamReadiness.fromJson(Map<String, dynamic> j) {
    final comps = j['components'] as Map<String, dynamic>? ?? {};
    return ExamReadiness(
      overallReadiness:
          (j['overallReadiness'] as num?)?.toDouble() ?? 50,
      label: j['label'] as String? ?? 'Developing',
      trend: (j['trend'] as num?)?.toDouble() ?? 0,
      components: comps.map(
        (k, v) => MapEntry(k, (v as num?)?.toDouble() ?? 50),
      ),
      recommendedNextAction:
          j['recommendedNextAction'] as String? ?? '',
      dataCoverage: (j['dataCoverage'] as num?)?.toDouble() ?? 0,
      criticalTopics: List<String>.from(j['criticalTopics'] as List? ?? []),
      strongTopics: List<String>.from(j['strongTopics'] as List? ?? []),
    );
  }
}

class StudyBlock {
  const StudyBlock({
    required this.itemId,
    required this.blockType,
    required this.topic,
    required this.durationMinutes,
    required this.priority,
    required this.status,
    this.reason = '',
    this.phase = '',
  });

  final String itemId;
  final String blockType;
  final String topic;
  final int durationMinutes;
  final String priority;
  final String status;
  final String reason;
  final String phase;

  bool get isCompleted => status == 'completed';

  String get blockTypeLabel {
    switch (blockType) {
      case 'learn_review':
        return 'Review';
      case 'practice':
        return 'Practice';
      case 'mistake_revision':
        return 'Mistakes';
      case 'quiz_recall':
        return 'Quiz';
      case 'mock_exam':
        return 'Mock Exam';
      default:
        return 'Study';
    }
  }

  factory StudyBlock.fromJson(Map<String, dynamic> j) => StudyBlock(
        itemId: j['itemId'] as String? ?? '',
        blockType: j['blockType'] as String? ?? 'learn_review',
        topic: j['topic'] as String? ?? 'General Study',
        durationMinutes: (j['durationMinutes'] as num?)?.toInt() ?? 25,
        priority: j['priority'] as String? ?? 'medium',
        status: j['status'] as String? ?? 'pending',
        reason: j['reason'] as String? ?? '',
        phase: j['phase'] as String? ?? '',
      );
}

class CoachingItem {
  const CoachingItem({
    required this.type,
    required this.topic,
    required this.action,
    required this.durationMinutes,
    required this.priority,
    this.reason = '',
  });

  final String type;
  final String topic;
  final String action;
  final int durationMinutes;
  final String priority;
  final String reason;

  factory CoachingItem.fromJson(Map<String, dynamic> j) => CoachingItem(
        type: j['type'] as String? ?? 'study_recommendation',
        topic: j['topic'] as String? ?? '',
        action: j['action'] as String? ?? '',
        durationMinutes: (j['durationMinutes'] as num?)?.toInt() ?? 25,
        priority: j['priority'] as String? ?? 'medium',
        reason: j['reason'] as String? ?? '',
      );
}

class PastPaperInsight {
  const PastPaperInsight({
    required this.papersAnalyzed,
    required this.yearsCovered,
    required this.subjects,
    required this.totalQuestions,
    required this.topicStats,
  });

  final int papersAnalyzed;
  final List<int> yearsCovered;
  final List<String> subjects;
  final int totalQuestions;
  final List<Map<String, dynamic>> topicStats;

  factory PastPaperInsight.fromJson(Map<String, dynamic> j) =>
      PastPaperInsight(
        papersAnalyzed: (j['papersAnalyzed'] as num?)?.toInt() ?? 0,
        yearsCovered: List<int>.from(
            (j['yearsCovered'] as List? ?? []).map((e) => (e as num).toInt())),
        subjects: List<String>.from(j['subjects'] as List? ?? []),
        totalQuestions: (j['totalQuestions'] as num?)?.toInt() ?? 0,
        topicStats:
            List<Map<String, dynamic>>.from(j['topicStats'] as List? ?? []),
      );
}
