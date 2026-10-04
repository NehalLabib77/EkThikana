import 'package:flutter/foundation.dart';

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

class UsageEventSample {
  final String packageName;
  final DateTime timestamp;
  final int eventType;

  const UsageEventSample({
    required this.packageName,
    required this.timestamp,
    required this.eventType,
  });
}

class UsageSessionCalculator {
  static const foregroundEvents = {1, 19};
  static const backgroundEvents = {2, 20, 23};

  static bool _isSystemPackage(String packageName) {
    final normalized = packageName.toLowerCase();
    return normalized == 'android' ||
        normalized == 'com.android.systemui' ||
        normalized == 'com.android.settings' ||
        normalized.contains('launcher') ||
        normalized == 'com.miui.home' ||
        normalized == 'com.sec.android.app.launcher';
  }

  static Map<String, int> calculate(
    Iterable<UsageEventSample> source, {
    required DateTime start,
    required DateTime end,
    void Function(String message)? diagnostic,
  }) {
    if (!end.isAfter(start)) return const {};

    final events = source.toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final totals = <String, int>{};
    String? activePackage;
    DateTime? activeSince;

    void closeActive(DateTime at) {
      final packageName = activePackage;
      final since = activeSince;
      if (packageName == null || since == null) return;
      final clippedStart = since.isAfter(start) ? since : start;
      final clippedEnd = at.isBefore(end) ? at : end;
      if (clippedEnd.isAfter(clippedStart)) {
        totals[packageName] =
            (totals[packageName] ?? 0) +
            clippedEnd.difference(clippedStart).inMilliseconds;
        diagnostic?.call(
          'session package=$packageName start=$clippedStart '
          'end=$clippedEnd durationMs=${clippedEnd.difference(clippedStart).inMilliseconds}',
        );
      }
      activePackage = null;
      activeSince = null;
    }

    for (final event in events) {
      final packageName = event.packageName.trim();
      if (packageName.isEmpty || _isSystemPackage(packageName)) continue;
      final time = event.timestamp;
      if (time.isBefore(start.subtract(const Duration(days: 1))) ||
          time.isAfter(end)) {
        continue;
      }

      if (foregroundEvents.contains(event.eventType)) {
        if (activePackage == packageName) continue;
        if (activePackage != null) closeActive(time);
        activePackage = packageName;
        activeSince = time;
      } else if (backgroundEvents.contains(event.eventType) &&
          activePackage == packageName) {
        closeActive(time);
      }
    }

    if (activePackage != null) closeActive(end);
    return totals..removeWhere((_, milliseconds) => milliseconds <= 0);
  }
}

class UsageStatsService {
  static const gochanoPackage = 'com.ekthikana.ekthikana';

  /// Cross-app usage tracking is intentionally disabled for Google Play compliance.
  static Future<bool> hasPermission() async {
    return false;
  }

  /// Opens Android's Usage Access settings if requested, or logs disabled status.
  static Future<void> openSettings() async {
    if (kDebugMode) {
      debugPrint(
        '[UsageStats] App usage tracking is unavailable in this release.',
      );
    }
  }

  /// Today's screen time summary. Graceful fallback for this release.
  static Future<ScreenTimeSummary> getScreenTimeSummary({DateTime? day}) async {
    return const ScreenTimeSummary(
      totalScreenTime: Duration.zero,
      allApps: [],
    );
  }

  /// 7 days of screen time ending today. Graceful fallback for this release.
  static Future<List<DayScreenTime>> getWeeklyScreenTime() async {
    return const [];
  }
}
