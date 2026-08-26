import 'api_service.dart';

class FocusSession {
  const FocusSession({
    required this.id,
    required this.label,
    required this.plannedMinutes,
    required this.elapsedSeconds,
    required this.status,
    required this.dayKey,
    required this.monthKey,
    required this.createdAtIso,
    this.completedAtIso,
  });

  final String id;
  final String label;
  final int plannedMinutes;
  final int elapsedSeconds;
  final String status; // running | paused | completed | cancelled
  final String dayKey;
  final String monthKey;
  final String createdAtIso;
  final String? completedAtIso;

  factory FocusSession.fromJson(Map<String, dynamic> json) {
    int readInt(String k1, String k2, [int fallback = 0]) {
      final raw = json[k1] ?? json[k2];
      if (raw is num) return raw.toInt();
      if (raw is String) return int.tryParse(raw) ?? fallback;
      return fallback;
    }

    String readStr(String k1, String k2, [String fallback = '']) {
      final raw = json[k1] ?? json[k2];
      return raw?.toString() ?? fallback;
    }

    return FocusSession(
      id: readStr('id', 'id'),
      label: readStr('label', 'label'),
      plannedMinutes: readInt('plannedMinutes', 'planned_minutes', 25),
      elapsedSeconds: readInt('elapsedSeconds', 'elapsed_seconds'),
      status: readStr('status', 'status'),
      dayKey: readStr('dayKey', 'day_key'),
      monthKey: readStr('monthKey', 'month_key'),
      createdAtIso: readStr('createdAtIso', 'created_at_iso'),
      completedAtIso: json['completedAtIso']?.toString() ??
          json['completed_at_iso']?.toString(),
    );
  }

  bool get isActive => status == 'running' || status == 'paused';
}

class StudyStats {
  const StudyStats({
    required this.todaySeconds,
    required this.monthSeconds,
    required this.streakDays,
    required this.completedTaskCount,
  });

  final int todaySeconds;
  final int monthSeconds;
  final int streakDays;
  final int completedTaskCount;

  factory StudyStats.fromJson(Map<String, dynamic> json) {
    int readInt(String k1, String k2, [int fallback = 0]) {
      final raw = json[k1] ?? json[k2];
      if (raw is num) return raw.toInt();
      if (raw is String) return int.tryParse(raw) ?? fallback;
      return fallback;
    }

    return StudyStats(
      todaySeconds: readInt('todaySeconds', 'today_seconds'),
      monthSeconds: readInt('monthSeconds', 'month_seconds'),
      streakDays: readInt('streakDays', 'streak_days'),
      completedTaskCount: readInt('completedTaskCount', 'completed_task_count'),
    );
  }
}

class StudyService {
  StudyService._();

  static Future<FocusSession> start({
    String label = '',
    int plannedMinutes = 25,
    String note = '',
  }) async {
    final raw = await ApiService.startFocus(
      label: label,
      plannedMinutes: plannedMinutes,
      note: note,
    );
    return FocusSession.fromJson(raw);
  }

  static Future<FocusSession> patch(String focusId, String action) async {
    final raw = await ApiService.patchFocus(focusId, action);
    return FocusSession.fromJson(raw);
  }

  static Future<List<FocusSession>> list({int limit = 100}) async {
    final raw = await ApiService.listFocus(limit: limit);
    return raw
        .whereType<Map<String, dynamic>>()
        .map(FocusSession.fromJson)
        .toList(growable: false);
  }

  static Future<StudyStats> stats() async {
    final raw = await ApiService.getStudyStats();
    return StudyStats.fromJson(raw);
  }
}
