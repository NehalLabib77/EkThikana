// Insights — study analytics summary using ONLY existing data.
//
// Shows: Focus time, completed sessions, XP, Gems, Level, and
// distraction/screen-time summary (if usage permission granted).
//
// V1: lightweight card-based layout. No new backend or analytics database.
// All data sourced from StudyService, RewardService, and UsageStatsService.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/design_system/gochano_colors.dart';
import '../../../../core/design_system/gochano_spacing.dart';
import '../../../../core/design_system/gochano_typography.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../focus_rewards/data/reward_service.dart';
import '../../../focus_rewards/domain/level_helper.dart';
import '../../../focus_rewards/domain/reward_model.dart';
import '../../../../services/study_service.dart';
import '../../../../services/usage_stats_service.dart';
import '../../../../shared/states/gochano_states.dart';
import '../../../../shared/widgets/gochano_surfaces.dart';

class InsightsView extends StatefulWidget {
  const InsightsView({super.key});

  @override
  State<InsightsView> createState() => _InsightsViewState();
}

class _InsightsViewState extends State<InsightsView> {
  bool _loading = true;
  String _error = '';

  int _weeklyFocusSeconds = 0;
  int _completedSessions = 0;
  int _totalSessions = 0;

  RewardProfile _rewardProfile = RewardProfile.empty();
  int _weeklyXp = 0;

  ScreenTimeSummary? _screenTimeSummary;

  StreamSubscription<RewardProfile>? _rewardSub;

  @override
  void initState() {
    super.initState();
    GochanoLanguage.current.addListener(_onLanguageChange);
    _load();
    _rewardSub = RewardService.profileStream().listen((profile) {
      if (mounted) setState(() => _rewardProfile = profile);
    });
  }

  @override
  void dispose() {
    GochanoLanguage.current.removeListener(_onLanguageChange);
    _rewardSub?.cancel();
    super.dispose();
  }

  void _onLanguageChange() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final results = await Future.wait([
        StudyService.weeklySeconds(),
        StudyService.list(days: 8),
        _loadScreenTime(),
      ]);

      final weeklySeconds = results[0] as int;
      final sessions = results[1] as List<FocusSession>;
      final screenTime = results[2] as ScreenTimeSummary?;

      final now = DateTime.now();
      final startOfWeek = now.subtract(Duration(days: now.weekday % 7));
      final weekStart = DateTime(
        startOfWeek.year,
        startOfWeek.month,
        startOfWeek.day,
      );

      var completed = 0;
      var total = 0;
      for (final s in sessions) {
        if (s.dayKey.isEmpty) continue;
        final day = DateTime.tryParse(s.dayKey);
        if (day == null || day.isBefore(weekStart)) continue;
        total++;
        if (s.status == 'completed') completed++;
      }

      var weeklyXp = 0;
      try {
        final txs = await RewardService.readRecentTransactions(limit: 50);
        for (final tx in txs) {
          DateTime? txDate;
          if (tx.createdAt is DateTime) {
            txDate = tx.createdAt as DateTime;
          } else if (tx.createdAt != null) {
            try {
              txDate = tx.createdAt.toDate();
            } catch (_) {}
          }
          if (txDate != null && !txDate.isBefore(weekStart)) {
            weeklyXp += tx.xpDelta;
          }
        }
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _loading = false;
        _weeklyFocusSeconds = weeklySeconds;
        _completedSessions = completed;
        _totalSessions = total;
        _weeklyXp = weeklyXp;
        _screenTimeSummary = screenTime;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyErrorMessage(error);
      });
    }
  }

  Future<ScreenTimeSummary?> _loadScreenTime() async {
    try {
      final hasPermission = await UsageStatsService.hasPermission();
      if (!hasPermission) return null;
      return await UsageStatsService.getScreenTimeSummary();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return StaticLoadingState(
        compact: true,
        message: GochanoLanguage.text(
          'Loading insights…',
          'ইনসাইট লোড হচ্ছে…',
        ),
      );
    }

    if (_error.isNotEmpty) {
      return ErrorState(
        compact: true,
        message: _error,
        onRetry: _load,
      );
    }

    final hasFocusData = _weeklyFocusSeconds > 0 || _completedSessions > 0;
    final hasRewardData = _rewardProfile.totalXp > 0 || _rewardProfile.gems > 0;
    final hasAnyData = hasFocusData || hasRewardData;

    if (!hasAnyData) {
      return _buildEmptyState(context);
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(GochanoSpacing.md),
        children: [
          _buildThisWeekSection(context),
          const SizedBox(height: GochanoSpacing.md),
          _buildRewardSection(context),
          if (_screenTimeSummary != null) ...[
            const SizedBox(height: GochanoSpacing.md),
            _buildDistractionSection(context),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(GochanoSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.insights_rounded,
              size: 64,
              color: context.colors.textTertiary,
            ),
            const SizedBox(height: GochanoSpacing.md),
            Text(
              GochanoLanguage.text(
                'Complete Focus sessions to see your study insights.',
                'স্টাডি ইনসাইট দেখতে ফোকাস সেশন সম্পন্ন করুন।',
              ),
              style: context.type.bodySecondary,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThisWeekSection(BuildContext context) {
    final colors = context.colors;
    final focusMinutes = _weeklyFocusSeconds ~/ 60;
    final focusSecs = _weeklyFocusSeconds % 60;
    final focusLabel = focusMinutes > 0
        ? GochanoLanguage.text(
            '$focusMinutes m $focusSecs s',
            '$focusMinutes মি $focusSecs সে',
          )
        : GochanoLanguage.text('$focusSecs s', '$focusSecs সে');

    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(GochanoSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              GochanoLanguage.text('This Week', 'এই সপ্তাহ'),
              style: context.type.sectionHeading,
            ),
            const SizedBox(height: GochanoSpacing.sm),
            Row(
              children: [
                _InsightStat(
                  label: GochanoLanguage.text('Focus Time', 'ফোকাস সময়'),
                  value: focusLabel,
                  icon: Icons.timer_rounded,
                  color: colors.study,
                ),
                const SizedBox(width: GochanoSpacing.md),
                _InsightStat(
                  label: GochanoLanguage.text('Sessions', 'সেশন'),
                  value: '$_completedSessions/$_totalSessions',
                  icon: Icons.check_circle_outline_rounded,
                  color: colors.success,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRewardSection(BuildContext context) {
    final colors = context.colors;
    final level = levelForXp(_rewardProfile.totalXp);

    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(GochanoSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              GochanoLanguage.text('Rewards', 'রেনার্দ'),
              style: context.type.sectionHeading,
            ),
            const SizedBox(height: GochanoSpacing.sm),
            Row(
              children: [
                _InsightStat(
                  label: GochanoLanguage.text('XP Earned', 'XP অর্জিত'),
                  value: '$_weeklyXp',
                  icon: Icons.star_rounded,
                  color: colors.warning,
                ),
                const SizedBox(width: GochanoSpacing.md),
                _InsightStat(
                  label: GochanoLanguage.text('Gems', 'জেম'),
                  value: '${_rewardProfile.gems}',
                  icon: Icons.diamond_rounded,
                  color: colors.info,
                ),
              ],
            ),
            const SizedBox(height: GochanoSpacing.sm),
            Row(
              children: [
                _InsightStat(
                  label: GochanoLanguage.text('Level', 'লেভেল'),
                  value: '$level',
                  icon: Icons.emoji_events_rounded,
                  color: colors.study,
                ),
                const SizedBox(width: GochanoSpacing.md),
                _InsightStat(
                  label: GochanoLanguage.text('Total XP', 'মোট XP'),
                  value: '${_rewardProfile.totalXp}',
                  icon: Icons.trending_up_rounded,
                  color: colors.success,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDistractionSection(BuildContext context) {
    final summary = _screenTimeSummary;
    if (summary == null) return const SizedBox.shrink();

    final colors = context.colors;
    final totalMinutes = summary.totalScreenTime.inMinutes;
    final hours = totalMinutes ~/ 60;
    final mins = totalMinutes % 60;
    final totalLabel = hours > 0
        ? GochanoLanguage.text(
            '$hours h $mins m',
            '$hours ঘ $mins মি',
          )
        : GochanoLanguage.text('$mins m', '$mins মি');

    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(GochanoSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              GochanoLanguage.text(
                'Screen Usage',
                'স্ক্রিন ব্যবহার',
              ),
              style: context.type.sectionHeading,
            ),
            const SizedBox(height: GochanoSpacing.sm),
            Row(
              children: [
                _InsightStat(
                  label: GochanoLanguage.text(
                    'Today',
                    'আজ',
                  ),
                  value: totalLabel,
                  icon: Icons.screen_lock_portrait_rounded,
                  color: colors.textSecondary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InsightStat extends StatelessWidget {
  const _InsightStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(GochanoSpacing.sm),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(GochanoSpacing.xs),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: GochanoSpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: context.type.body.copyWith(
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                  Text(
                    label,
                    style: context.type.caption.copyWith(
                      color: context.colors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
