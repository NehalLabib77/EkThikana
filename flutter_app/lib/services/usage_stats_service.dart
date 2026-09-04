import 'package:usage_stats/usage_stats.dart';

class AppUsageInfo {
  final String packageName;
  final String appName;
  final Duration usage;

  const AppUsageInfo({
    required this.packageName,
    required this.appName,
    required this.usage,
  });

  int get usageMinutes => usage.inMinutes;
}

class ScreenTimeSummary {
  final Duration totalScreenTime;
  final List<AppUsageInfo> allApps;

  const ScreenTimeSummary({
    required this.totalScreenTime,
    required this.allApps,
  });

  int get highestUsageMinutes =>
      allApps.isEmpty ? 0 : allApps.first.usageMinutes;
}

class DayScreenTime {
  final DateTime date;
  final Duration total;

  const DayScreenTime({required this.date, required this.total});

  int get minutes => total.inMinutes;
}

class UsageStatsService {
  static const gochanoPackage = 'com.ekthikana.ekthikana';

  static Future<bool> hasPermission() async {
    final granted = await UsageStats.checkUsagePermission();
    return granted ?? false;
  }

  static Future<void> openSettings() async {
    await UsageStats.grantUsagePermission();
  }

  /// Today's screen time from LOCAL 00:00 → now.
  /// Returns ALL apps (including Gochano) sorted by usage descending.
  static Future<ScreenTimeSummary> getScreenTimeSummary({
    DateTime? day,
  }) async {
    final now = DateTime.now();
    final startTime = day ?? DateTime(now.year, now.month, now.day);

    final usage = await UsageStats.queryUsageStats(
      startTime,
      now,
      intervalType: IntervalType.best,
    );

    final appUsageMap = <String, int>{};

    for (final stat in usage) {
      final pkg = stat.packageName ?? '';
      if (pkg.isEmpty) continue;

      final ms = stat.totalTimeInForegroundMs ?? 0;
      if (ms <= 0) continue;
      appUsageMap[pkg] = (appUsageMap[pkg] ?? 0) + ms;
    }

    final sortedApps = appUsageMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final topPackages = sortedApps.take(20).map((e) => e.key).toList();
    final appNames = await _resolveAppNames(topPackages);

    final allApps = sortedApps.take(20).map((e) {
      return AppUsageInfo(
        packageName: e.key,
        appName: appNames[e.key] ?? e.key.split('.').last,
        usage: Duration(milliseconds: e.value),
      );
    }).toList();

    final totalMs = appUsageMap.values.fold<int>(0, (a, b) => a + b);

    return ScreenTimeSummary(
      totalScreenTime: Duration(milliseconds: totalMs),
      allApps: allApps,
    );
  }

  /// 7 days of screen time ending today (Sun–Sat for current week).
  static Future<List<DayScreenTime>> getWeeklyScreenTime() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final days = <DayScreenTime>[];
    for (int i = 6; i >= 0; i--) {
      final day = today.subtract(Duration(days: i));
      final endOfDay = day.add(const Duration(days: 1));

      final usage = await UsageStats.queryUsageStats(
        day,
        endOfDay,
        intervalType: IntervalType.best,
      );

      int totalMs = 0;
      for (final stat in usage) {
        final ms = stat.totalTimeInForegroundMs ?? 0;
        if (ms > 0) totalMs += ms;
      }

      days.add(DayScreenTime(date: day, total: Duration(milliseconds: totalMs)));
    }

    return days;
  }

  static Future<Map<String, String>> _resolveAppNames(
    List<String> packages,
  ) async {
    final names = <String, String>{};
    for (final pkg in packages) {
      try {
        final info = await UsageStats.getAppInfo(pkg);
        if (info != null && info.appName != null && info.appName!.isNotEmpty) {
          names[pkg] = info.appName!;
        }
      } catch (_) {
        // Fall back to package name parsing
      }
    }
    return names;
  }
}
