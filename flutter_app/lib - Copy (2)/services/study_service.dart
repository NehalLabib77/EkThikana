import 'api_service.dart';

/// Per-session upper bound. Mirrors the ceiling used by the backend
/// (``_FOCUS_MAX_SECONDS`` in `app/routers/part3.py`) and the backfill script
/// (`scripts/backfill_focus_sessions_legacy.py`).
///
/// Historical rows sometimes carry a value that looks like minutes stored in
/// a seconds-shaped column — the most visible symptom was a single session
/// row reading "98h 37m" and the Profile "This month" stat reading 5917
/// minutes (≈ 354_920 s). The backend clamps these to 0 at read time; the
/// client mirrors the policy so a Firestore SDK offline cache or an old
/// in-process payload cannot re-introduce the poisoned value into the UI.
///
/// Values above 24 hours are treated as corruption and mapped to 0, matching
/// the backend's ``_coerce_focus_seconds`` behaviour.
const int _kMaxFocusSeconds = 24 * 60 * 60; // 86_400 s = 24h

int _coerceFocusSeconds(Object? raw) {
  int seconds;
  if (raw is num) {
    seconds = raw.toInt();
  } else if (raw is String) {
    seconds = int.tryParse(raw) ?? 0;
  } else {
    seconds = 0;
  }
  if (seconds < 0) return 0;
  if (seconds > _kMaxFocusSeconds) return 0;
  return seconds;
}

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
      elapsedSeconds: _coerceFocusSeconds(
        json['accumulatedSeconds'] ?? json['accumulated_seconds'],
      ),
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

  /// Returns the total accumulated seconds from completed focus sessions
  /// within the last 7 days (Mon→Sun week).
  static Future<int> weeklySeconds() async {
    final sessions = await list(days: 8);
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday % 7));
    final weekStart = DateTime(
      startOfWeek.year,
      startOfWeek.month,
      startOfWeek.day,
    );

    var total = 0;
    for (final s in sessions) {
      // Include completed and cancelled/stopped sessions — both are
      // terminal states with legitimate elapsedSeconds. Exclude
      // running/paused (still in progress) and corrupt durations.
      if (s.status != 'completed' && s.status != 'cancelled') continue;
      if (s.dayKey.isEmpty) continue;
      final parts = s.dayKey.split('-');
      if (parts.length != 3) continue;
      final day = DateTime.tryParse(s.dayKey);
      if (day == null || day.isBefore(weekStart)) continue;
      total += s.elapsedSeconds;
    }
    return total;
  }
}
