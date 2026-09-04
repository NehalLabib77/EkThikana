import 'package:usage_stats/usage_stats.dart';

class AppUsageInfo {
  final String packageName;
  final String appName;
  final Duration usage;
  final int? lastTimeUsedMs;

  const AppUsageInfo({
    required this.packageName,
    required this.appName,
    required this.usage,
    this.lastTimeUsedMs,
  });

  int get usageMinutes => usage.inMinutes;
}

class ScreenTimeSummary {
  final Duration totalScreenTime;
  final Duration gochanoUsage;
  final Duration otherAppsUsage;
  final List<AppUsageInfo> topApps;

  const ScreenTimeSummary({
    required this.totalScreenTime,
    required this.gochanoUsage,
    required this.otherAppsUsage,
    required this.topApps,
  });

  double get gochanoUsagePercent =>
      totalScreenTime.inMinutes > 0
          ? (gochanoUsage.inMinutes / totalScreenTime.inMinutes) * 100
          : 0;

  double get otherAppsUsagePercent =>
      totalScreenTime.inMinutes > 0
          ? (otherAppsUsage.inMinutes / totalScreenTime.inMinutes) * 100
          : 0;
}

class UsageStatsService {
  /// The real Android applicationId from build.gradle.kts.
  static const gochanoPackage = 'com.ekthikana.ekthikana';

  static Future<bool> hasPermission() async {
    final granted = await UsageStats.checkUsagePermission();
    return granted ?? false;
  }

  static Future<void> openSettings() async {
    await UsageStats.grantUsagePermission();
  }

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
      // Ignore negative or zero values.
      if (ms <= 0) continue;
      appUsageMap[pkg] = (appUsageMap[pkg] ?? 0) + ms;
    }

    final sortedApps = appUsageMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Exclude Gochano from the per-app list (it has its own section).
    final otherAppsSorted = sortedApps
        .where((e) => e.key != gochanoPackage)
        .toList();

    final topPackages = otherAppsSorted.take(20).map((e) => e.key).toList();

    final appNames = await _resolveAppNames(topPackages);

    final topApps = otherAppsSorted.take(20).map((e) {
      return AppUsageInfo(
        packageName: e.key,
        appName: appNames[e.key] ?? e.key.split('.').last,
        usage: Duration(milliseconds: e.value),
      );
    }).toList();

    final totalMs = appUsageMap.values.fold<int>(0, (a, b) => a + b);
    final gochanoMs = appUsageMap[gochanoPackage] ?? 0;
    final otherMs = (totalMs - gochanoMs).clamp(0, totalMs);

    return ScreenTimeSummary(
      totalScreenTime: Duration(milliseconds: totalMs),
      gochanoUsage: Duration(milliseconds: gochanoMs),
      otherAppsUsage: Duration(milliseconds: otherMs),
      topApps: topApps,
    );
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
