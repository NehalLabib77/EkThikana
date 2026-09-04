import 'package:flutter/material.dart';

import '../../../../core/design_system/gochano_colors.dart';
import '../../../../core/design_system/gochano_spacing.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../services/usage_stats_service.dart';
import '../../../../shared/widgets/gochano_surfaces.dart';

class DistractionView extends StatefulWidget {
  const DistractionView({super.key});

  @override
  State<DistractionView> createState() => _DistractionViewState();
}

class _DistractionViewState extends State<DistractionView> {
  ScreenTimeSummary? _summary;
  bool _loading = true;
  bool _hasPermission = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkPermissionAndLoad();
  }

  Future<void> _checkPermissionAndLoad() async {
    try {
      final hasPermission = await UsageStatsService.hasPermission();
      if (!hasPermission) {
        setState(() {
          _hasPermission = false;
          _loading = false;
        });
        return;
      }

      _hasPermission = true;
      await _loadData();
    } catch (e) {
      setState(() {
        _error = 'Permission check failed';
        _loading = false;
      });
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final summary = await UsageStatsService.getScreenTimeSummary();
      setState(() {
        _summary = summary;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load screen time data';
        _loading = false;
      });
    }
  }

  Future<void> _requestPermission() async {
    try {
      await UsageStatsService.openSettings();
      await _checkPermissionAndLoad();
    } catch (e) {
      setState(() {
        _error = 'Failed to open settings';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
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
              onPressed: _loadData,
              child: Text(
                GochanoLanguage.text('Retry', 'আবার চেষ্টা করুন'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final summary = _summary;
    if (summary == null) {
      return const Center(child: Text('No data'));
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(GochanoSpacing.md),
        children: [
          _buildSummaryCard(summary),
          const SizedBox(height: GochanoSpacing.md),
          _buildGochanoSection(summary),
          const SizedBox(height: GochanoSpacing.md),
          _buildOtherAppsSection(summary),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(ScreenTimeSummary summary) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            GochanoLanguage.text(
              'Today\'s Screen Time',
              'আজকের স্ক্রিন টাইম',
            ),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: GochanoSpacing.sm),
          Text(
            _formatDuration(summary.totalScreenTime),
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  color: context.colors.brand,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildGochanoSection(ScreenTimeSummary summary) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.school_rounded,
                color: context.colors.brand,
                size: 20,
              ),
              const SizedBox(width: GochanoSpacing.xs),
              Text(
                GochanoLanguage.text('Gochano Usage', 'গোচানো ব্যবহার'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: GochanoSpacing.sm),
          Row(
            children: [
              Text(
                _formatDuration(summary.gochanoUsage),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const Spacer(),
              Text(
                '${summary.gochanoUsagePercent.toStringAsFixed(1)}%',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: context.colors.brand,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOtherAppsSection(ScreenTimeSummary summary) {
    final topApps = summary.topApps;
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
                GochanoLanguage.text('Other Apps', 'অন্যান্য অ্যাপ'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              Text(
                _formatDuration(summary.otherAppsUsage),
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
          const SizedBox(height: GochanoSpacing.sm),
          if (topApps.isEmpty)
            Text(
              GochanoLanguage.text(
                'No app usage recorded',
                'কোনো অ্যাপ ব্যবহার রেকর্ড হয়নি',
              ),
              style: Theme.of(context).textTheme.bodyMedium,
            )
          else
            ...topApps.take(10).map((app) => _buildAppTile(app)),
        ],
      ),
    );
  }

  Widget _buildAppTile(AppUsageInfo app) {
    final isGochano = app.packageName == UsageStatsService.gochanoPackage;
    final minutes = app.usageMinutes;
    final color = isGochano
        ? _getGochanoColor(context, minutes)
        : _getOtherAppColor(context, minutes);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  app.appName,
                  style: Theme.of(context).textTheme.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  _formatDuration(app.usage),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: GochanoSpacing.sm),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Color _getOtherAppColor(BuildContext context, int minutes) {
    if (minutes <= 30) return context.colors.success;
    if (minutes <= 60) return context.colors.warning;
    return context.colors.error;
  }

  Color _getGochanoColor(BuildContext context, int minutes) {
    if (minutes <= 30) return context.colors.error;
    if (minutes <= 60) return context.colors.warning;
    return context.colors.success;
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
    return GochanoLanguage.text(
      '$minutes m',
      '$minutes মি',
    );
  }
}
