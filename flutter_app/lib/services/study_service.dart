import 'api_service.dart';

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

  static Future<StudyStats> stats() async {
    final raw = await ApiService.getStudyStats();
    return StudyStats.fromJson(raw);
  }
}
