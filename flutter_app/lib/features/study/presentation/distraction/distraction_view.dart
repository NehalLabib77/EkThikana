import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/design_system/gochano_colors.dart';
import '../../../../core/design_system/gochano_spacing.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../services/usage_stats_service.dart';
import '../../../../shared/states/gochano_states.dart';
import '../../../../shared/widgets/gochano_surfaces.dart';

class DistractionView extends StatefulWidget {
  const DistractionView({super.key});

  @override
  State<DistractionView> createState() => _DistractionViewState();
}

class _DistractionViewState extends State<DistractionView>
    with WidgetsBindingObserver {
  ScreenTimeSummary? _summary;
  List<DayScreenTime>? _weekly;
  bool _loading = true;
  bool _hasPermission = false;
  bool _refreshing = false;
  DateTime? _lastLoadedLocalDate;
  Timer? _midnightTimer;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleNextMidnight();
    _checkPermissionAndLoad();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _midnightTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshOnceOnResume();
    }
  }

  DateTime _localDate() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  void _scheduleNextMidnight() {
    _midnightTimer?.cancel();
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day + 1);
    _midnightTimer = Timer(next.difference(now), () {
      if (!mounted) return;
      _scheduleNextMidnight();
      if (_lastLoadedLocalDate != null &&
          _localDate() != _lastLoadedLocalDate) {
        _checkPermissionAndLoad(showLoading: false);
      }
    });
  }

  Future<void> _checkPermissionAndLoad({bool showLoading = true}) async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final hasPermission = await UsageStatsService.hasPermission();
      if (!hasPermission) {
        if (!mounted) return;
        setState(() {
          _hasPermission = false;
          _summary = null;
          _weekly = null;
          _error = null;
          _loading = false;
        });
        _lastLoadedLocalDate = null;
        return;
      }

      if (mounted) {
        setState(() {
          _hasPermission = true;
          if (showLoading && (_summary == null || _weekly == null)) {
            _loading = true;
          }
          _error = null;
        });
      }
      await _loadData(showLoading: showLoading);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Permission check failed';
        _loading = false;
      });
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _refreshOnceOnResume() async {
    final dateChanged =
        _lastLoadedLocalDate != null && _localDate() != _lastLoadedLocalDate;
    await _checkPermissionAndLoad(showLoading: false);
    if (dateChanged) _scheduleNextMidnight();
  }

  Future<void> _loadData({bool showLoading = true}) async {
    if (!mounted) return;
    if (showLoading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else if (_error != null) {
      setState(() => _error = null);
    }

    try {
      final results = await Future.wait([
        UsageStatsService.getScreenTimeSummary(),
        UsageStatsService.getWeeklyScreenTime(),
      ]);
      if (!mounted) return;
      setState(() {
        _summary = results[0] as ScreenTimeSummary;
        _weekly = results[1] as List<DayScreenTime>;
        _loading = false;
        _lastLoadedLocalDate = _localDate();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load screen time data';
        _loading = false;
      });
    }
  }

  Future<void> _refreshData() => _checkPermissionAndLoad(showLoading: false);

  Future<void> _requestPermission() async {
    try {
      await UsageStatsService.openSettings();
      await _checkPermissionAndLoad(showLoading: false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to open settings';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && (_summary == null || _weekly == null)) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_hasPermission) {
      return _buildPermissionGate();
    }

    if (_error != null) {
      return _buildError();
    }

    return _buildContent();
  }

  Widget _buildPermissionGate() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(GochanoSpacing.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.screen_lock_portrait_rounded,
              size: 64,
              color: context.colors.textTertiary,
            ),
            const SizedBox(height: GochanoSpacing.md),
            Text(
              GochanoLanguage.text(
                'Screen Time Access',
                'স্ক্রিন টাইম অ্যাক্সেস',
              ),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: GochanoSpacing.sm),
            Text(
              GochanoLanguage.text(
                'To monitor screen time and app usage, please grant Usage Access permission in Settings.',
                'স্ক্রিন টাইম ও অ্যাপ ব্যবহার ট্র্যাক করতে, সেটিংসে Usage Access অনুমতি দিন।',
              ),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: GochanoSpacing.lg),
            FilledButton.icon(
              onPressed: _requestPermission,
              icon: const Icon(Icons.settings_rounded),
              label: Text(
                GochanoLanguage.text('Open Settings', 'সেটিংস খুঁজুন'),
              ),
            ),
            const SizedBox(height: GochanoSpacing.md),
            Text(
              GochanoLanguage.text(
                'Privacy: Your usage data stays on this device and is never shared.',
                'গোপনীয়তা: আপনার ব্যবহারের তথ্য শুধুমাত্র এই ডিভাইসে থাকে, কারো সাথে শেয়ার হয় না।',
              ),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.colors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(GochanoSpacing.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: context.colors.error,
            ),
            const SizedBox(height: GochanoSpacing.md),
            Text(
              _error!,
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: GochanoSpacing.lg),
            FilledButton.tonal(
              onPressed: _refreshData,
              child: Text(GochanoLanguage.text('Retry', 'আবার চেষ্টা করুন')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final summary = _summary;
    final weekly = _weekly;
    if (summary == null || weekly == null) {
      return const Center(child: Text('No data'));
    }

    return RefreshIndicator(
      onRefresh: _refreshData,
      child: ListView(
        padding: const EdgeInsets.all(GochanoSpacing.md),
        children: [
          if (_refreshing) const LinearProgressIndicator(minHeight: 2),
          if (_error != null) ...[
            const SizedBox(height: GochanoSpacing.sm),
            ErrorState(compact: true, message: _error!),
          ],
          _buildWeeklyChart(weekly),
          const SizedBox(height: GochanoSpacing.md),
          _buildAppList(summary),
        ],
      ),
    );
  }

  Widget _buildWeeklyChart(List<DayScreenTime> weekly) {
    final maxMinutes = weekly.fold<int>(
      0,
      (m, d) => d.minutes > m ? d.minutes : m,
    );
    final today = DateTime.now();
    final todayStr =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            GochanoLanguage.text('This Week', 'এই সপ্তাহ'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: GochanoSpacing.sm),
          SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: weekly.map((day) {
                final dayStr =
                    '${day.date.year}-${day.date.month.toString().padLeft(2, '0')}-${day.date.day.toString().padLeft(2, '0')}';
                final isToday = dayStr == todayStr;
                final fraction = maxMinutes > 0
                    ? day.minutes / maxMinutes
                    : 0.0;
                final barHeight = (fraction * 80).clamp(2.0, 80.0);

                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (day.minutes > 0)
                          Text(
                            _shortDuration(day.total),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  fontSize: 9,
                                  color: isToday
                                      ? context.colors.brand
                                      : context.colors.textTertiary,
                                ),
                            maxLines: 1,
                          ),
                        const SizedBox(height: 2),
                        Container(
                          height: barHeight,
                          decoration: BoxDecoration(
                            color: isToday
                                ? context.colors.brand
                                : context.colors.brand.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _dayLabel(day.date),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                fontSize: 10,
                                fontWeight: isToday
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                                color: isToday
                                    ? context.colors.brand
                                    : context.colors.textTertiary,
                              ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppList(ScreenTimeSummary summary) {
    final apps = summary.allApps;
    final highestMinutes = summary.highestUsageMinutes;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.apps_rounded,
                color: context.colors.textTertiary,
                size: 20,
              ),
              const SizedBox(width: GochanoSpacing.xs),
              Text(
                GochanoLanguage.text('App Activity', 'অ্যাপ ব্যবহার'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: GochanoSpacing.sm),
          if (apps.isEmpty)
            Text(
              GochanoLanguage.text(
                'No app usage recorded',
                'কোনো অ্যাপ ব্যবহার রেকর্ড হয়নি',
              ),
              style: Theme.of(context).textTheme.bodyMedium,
            )
          else
            ...apps.take(15).map((app) => _buildAppRow(app, highestMinutes)),
        ],
      ),
    );
  }

  Widget _buildAppRow(AppUsageInfo app, int highestMinutes) {
    final isGochano = app.packageName == UsageStatsService.gochanoPackage;
    final minutes = app.usageMinutes;
    final color = isGochano
        ? _getGochanoColor(context, minutes)
        : _getOtherAppColor(context, minutes);
    final barFraction = highestMinutes > 0
        ? (minutes / highestMinutes).clamp(0.0, 1.0)
        : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              app.appName,
              style: Theme.of(context).textTheme.bodyMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: GochanoSpacing.sm),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: barFraction,
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: GochanoSpacing.sm),
          SizedBox(
            width: 55,
            child: Text(
              _formatDuration(app.usage),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.colors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Color _getOtherAppColor(BuildContext context, int minutes) {
    if (minutes <= 38) return context.colors.usageLow;
    if (minutes <= 70) return context.colors.usageMedium;
    return context.colors.usageHigh;
  }

  Color _getGochanoColor(BuildContext context, int minutes) {
    if (minutes <= 38) return context.colors.usageHigh;
    if (minutes <= 70) return context.colors.usageMedium;
    return context.colors.usageLow;
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;

    if (hours > 0) {
      return GochanoLanguage.text(
        '$hours h $minutes m',
        '$hours ঘ $minutes মি',
      );
    }
    return GochanoLanguage.text('$minutes m', '$minutes মি');
  }

  String _shortDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    if (hours > 0) return '${hours}h${minutes}m';
    return '${minutes}m';
  }

  String _dayLabel(DateTime date) {
    const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return days[date.weekday % 7];
  }
}
