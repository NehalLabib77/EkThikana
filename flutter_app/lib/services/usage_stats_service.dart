import 'package:flutter/foundation.dart';
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
  static final _historicalDayCache = <String, Map<String, int>>{};
  static final _inFlightDays = <String, Future<Map<String, int>>>{};

  static Future<bool> hasPermission() async {
    final granted = await UsageStats.checkUsagePermission();
    return granted ?? false;
  }

  /// Opens Android's Usage Access settings. The user grants or revokes access
  /// there; the app never changes this permission itself.
  static Future<void> openSettings() async {
    await UsageStats.grantUsagePermission();
  }

  /// Today's screen time from LOCAL 00:00 → now.
  /// Returns ALL apps (including Gochano) sorted by usage descending.
  static Future<ScreenTimeSummary> getScreenTimeSummary({DateTime? day}) async {
    final now = DateTime.now();
    final requested = day ?? now;
    final startTime = DateTime(requested.year, requested.month, requested.day);
    final isToday = _dayKey(startTime) == _dayKey(now);
    final endTime = isToday ? now : startTime.add(const Duration(days: 1));

    final appUsageMap = await _getDayUsage(
      startTime,
      endTime,
      refresh: isToday,
    );

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
  /// Deduplicates by package within each day and caps at 24 hours.
  static Future<List<DayScreenTime>> getWeeklyScreenTime() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = [
      for (int i = 6; i >= 0; i--) today.subtract(Duration(days: i)),
    ];
    final usages = await Future.wait([
      for (final day in days)
        _getDayUsage(
          day,
          _dayKey(day) == _dayKey(today)
              ? now
              : day.add(const Duration(days: 1)),
          refresh: _dayKey(day) == _dayKey(today),
        ),
    ]);
    return [
      for (int i = 0; i < days.length; i++)
        DayScreenTime(
          date: days[i],
          total: Duration(
            milliseconds: usages[i].values.fold<int>(0, (a, b) => a + b),
          ),
        ),
    ];
  }

  static String _dayKey(DateTime day) => '${day.year}-${day.month}-${day.day}';

  static Future<Map<String, int>> _getDayUsage(
    DateTime start,
    DateTime end, {
    required bool refresh,
  }) {
    final key = _dayKey(start);
    if (!refresh && _historicalDayCache.containsKey(key)) {
      _debug('usage cache hit day=$key');
      return Future.value(_historicalDayCache[key]!);
    }
    final existing = _inFlightDays[key];
    if (existing != null) {
      _debug('usage request coalesced day=$key');
      return existing;
    }
    final future = _foregroundUsage(start, end).then((usage) {
      if (!refresh) _historicalDayCache[key] = usage;
      return usage;
    });
    _inFlightDays[key] = future;
    return future.whenComplete(() => _inFlightDays.remove(key));
  }

  static Future<Map<String, int>> _foregroundUsage(
    DateTime start,
    DateTime end,
  ) async {
    if (!end.isAfter(start)) return const {};

    // Include the preceding day so an activity already foreground at local
    // midnight can be clipped into the requested window.
    final queryStarted = DateTime.now();
    _debug('usage query start=$start end=$end');
    final events = await UsageStats.queryEvents(
      start.subtract(const Duration(days: 1)),
      end,
    );
    _debug(
      'usage query end=${DateTime.now()} '
      'elapsedMs=${DateTime.now().difference(queryStarted).inMilliseconds}',
    );
    final samples = events
        .where(
          (event) =>
              event.packageName != null &&
              event.timeStampDate != null &&
              event.eventTypeValue != null,
        )
        .map(
          (event) => UsageEventSample(
            packageName: event.packageName!,
            timestamp: event.timeStampDate!,
            eventType: event.eventTypeValue!,
          ),
        );
    final totals = UsageSessionCalculator.calculate(
      samples,
      start: start,
      end: end,
      diagnostic: _debug,
    );
    for (final entry in totals.entries) {
      _debug('package total=${entry.key} durationMs=${entry.value}');
    }
    _debug('daily totalMs=${totals.values.fold<int>(0, (a, b) => a + b)}');
    return totals;
  }

  static Future<Map<String, String>> _resolveAppNames(
    List<String> packages,
  ) async {
    final names = <String, String>{};
    await Future.wait([
      for (final pkg in packages)
        Future<void>(() async {
          try {
            final info = await UsageStats.getAppInfo(pkg);
            if (info != null &&
                info.appName != null &&
                info.appName!.isNotEmpty) {
              names[pkg] = info.appName!;
            }
          } catch (_) {
            // Fall back to package name parsing
          }
        }),
    ]);
    return names;
  }

  static void _debug(String message) {
    if (kDebugMode) debugPrint('[UsageStats] $message');
  }
}
