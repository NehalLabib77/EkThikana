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

  /// Seconds of focus accumulated across run/pause cycles.
  ///
  /// The backend calls this `accumulatedSeconds` on every response
  /// (`/study/focus/start`, `PATCH /study/focus/{id}`, `/study/focus/list`).
  /// This model used to read `elapsedSeconds` / `elapsed_seconds`, which no
  /// response has ever contained, so the value silently fell back to 0 and
  /// every finished session showed as zero minutes of focus.
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
      elapsedSeconds: readInt('accumulatedSeconds', 'accumulated_seconds'),
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

  /// Recent focus sessions.
  ///
  /// [days] is the window the backend actually accepts (1..365). The previous
  /// signature took a `limit`, which `/study/focus/list` does not declare —
  /// FastAPI dropped it and always returned the default 30-day window.
  static Future<List<FocusSession>> list({int days = 30}) async {
    final raw = await ApiService.listFocus(days: days);
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
