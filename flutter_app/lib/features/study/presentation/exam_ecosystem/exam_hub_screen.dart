/// Phase 15 — Exam Hub Screen.
///
/// Single-request bootstrap: all dashboard data in one call.
/// No duplicate quiz/exam/planner/focus engines created.
/// Navigates to existing screens for quiz/exam execution.
library;

import 'package:flutter/material.dart';

import '../../../../core/design_system/app_design_system.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../services/api_service.dart';
import '../../../../shared/widgets/gochano_surfaces.dart';
import 'exam_ecosystem_models.dart';
import 'exam_plan_screen.dart';
import 'exam_readiness_screen.dart';
import 'past_paper_screen.dart';
import 'priority_topics_screen.dart';

class ExamHubScreen extends StatefulWidget {
  const ExamHubScreen({
    super.key,
    this.initialPlan,
    this.initialReadiness,
    this.initialPriorities,
    this.initialTodayBlocks,
    this.initialCoachingItems,
    this.initialCoachingUrgency,
    this.initialPapersAnalyzed,
    this.initialError,
    this.loadDashboardOverride,
    this.startPracticeOverride,
  });

  static const routeName = '/exam-hub';

  final ExamPlan? initialPlan;
  final ExamReadiness? initialReadiness;
  final List<PriorityTopic>? initialPriorities;
  final List<StudyBlock>? initialTodayBlocks;
  final List<CoachingItem>? initialCoachingItems;
  final String? initialCoachingUrgency;
  final int? initialPapersAnalyzed;
  final String? initialError;
  final Future<Map<String, dynamic>> Function()? loadDashboardOverride;
  final Future<Map<String, dynamic>> Function(String mode)? startPracticeOverride;

  @override
  State<ExamHubScreen> createState() => _ExamHubScreenState();
}

class _ExamHubScreenState extends State<ExamHubScreen> {
  bool _loading = true;
  String? _error;

  ExamPlan? _plan;
  ExamReadiness? _readiness;
  List<PriorityTopic> _priorities = [];
  List<StudyBlock> _todayBlocks = [];
  List<CoachingItem> _coachingItems = [];
  String _coachingUrgency = '';
  int _papersAnalyzed = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initialPlan != null ||
        widget.initialReadiness != null ||
        widget.initialPriorities != null ||
        widget.initialTodayBlocks != null ||
        widget.initialCoachingItems != null ||
        widget.initialCoachingUrgency != null ||
        widget.initialPapersAnalyzed != null ||
        widget.initialError != null) {
      _loading = false;
      _plan = widget.initialPlan;
      _readiness = widget.initialReadiness;
      _priorities = widget.initialPriorities ?? [];
      _todayBlocks = widget.initialTodayBlocks ?? [];
      _coachingItems = widget.initialCoachingItems ?? [];
      _coachingUrgency = widget.initialCoachingUrgency ?? '';
      _papersAnalyzed = widget.initialPapersAnalyzed ?? 0;
      _error = widget.initialError;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    final isBengali = GochanoLanguage.isBangla;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final Map<String, dynamic> data;
      if (widget.loadDashboardOverride != null) {
        data = await widget.loadDashboardOverride!();
      } else {
        data = await ApiService.examEcosystemDashboard();
      }
      _parseDashboard(data);
    } on ApiException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = isBengali
          ? 'পরীক্ষা হাবের তথ্য লোড করতে ব্যর্থ হয়েছে।'
          : 'Could not load Exam Hub. Please try again.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _parseDashboard(Map<String, dynamic> data) {
    final planJson = data['activePlan'] as Map<String, dynamic>?;
    _plan = planJson != null ? ExamPlan.fromJson(planJson) : null;

    final readinessRaw = data['overallReadiness'];
    if (readinessRaw != null) {
      _readiness = ExamReadiness(
        overallReadiness: (readinessRaw as num).toDouble(),
        label: data['readinessLabel'] as String? ?? '',
        trend: (data['readinessTrend'] as num?)?.toDouble() ?? 0,
        components: const {},
        recommendedNextAction:
            data['recommendedAction'] as String? ?? '',
        dataCoverage: 0,
      );
    } else {
      _readiness = null;
    }

    final prioList =
        data['topPriorityTopics'] as List<dynamic>? ?? [];
    _priorities = prioList
        .map((e) => PriorityTopic.fromJson(e as Map<String, dynamic>))
        .toList();

    final todayList = data['todayPlan'] as List<dynamic>? ?? [];
    _todayBlocks = todayList
        .map((e) => StudyBlock.fromJson(e as Map<String, dynamic>))
        .toList();

    final coachingData = data['coaching'] as Map<String, dynamic>?;
    if (coachingData != null) {
      _coachingUrgency =
          coachingData['urgencyNote'] as String? ?? '';
      final items =
          coachingData['coachingItems'] as List<dynamic>? ?? [];
      _coachingItems = items
          .map((e) => CoachingItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } else {
      _coachingUrgency = '';
      _coachingItems = [];
    }

    _papersAnalyzed = (data['papersAnalyzed'] as num?)?.toInt() ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isBengali = GochanoLanguage.isBangla ||
        Localizations.maybeLocaleOf(context)?.languageCode == 'bn';

    final hasContent = _plan != null ||
        _readiness != null ||
        _coachingUrgency.isNotEmpty ||
        _todayBlocks.isNotEmpty ||
        _coachingItems.isNotEmpty ||
        _priorities.isNotEmpty;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: GochanoAppBar(
        title: isBengali ? 'পরীক্ষা হাব' : 'Exam Hub',
        subtitle: _plan != null
            ? (isBengali
                ? '${_plan!.examName} · ${GochanoLanguage.toBanglaDigits(_plan!.daysRemaining)} দিন বাকি'
                : '${_plan!.examName} · ${_plan!.daysRemaining} days left')
            : (isBengali
                ? 'মক টেস্ট ও প্রস্তুতি ট্র্যাকার'
                : 'Adaptive mock tests & exam readiness'),
        actions: [
          if (_plan != null)
            IconButton(
              icon: const Icon(Icons.calendar_month_outlined, color: AppGradients.orangeAccent),
              tooltip: isBengali ? 'পরিকল্পনা দেখুন' : 'View Plan',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ExamPlanScreen(plan: _plan!)),
              ),
            ),
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: colors.textSecondary),
            tooltip: isBengali ? 'রিফ্রেশ করুন' : 'Refresh',
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(AppGradients.orangeAccent),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    isBengali
                        ? 'পরীক্ষা হাবের তথ্য লোড হচ্ছে…'
                        : 'Loading exam dashboard…',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            )
          : _error != null
              ? _ErrorView(
                  message: _error!,
                  isBengali: isBengali,
                  onRetry: _load,
                )
              : RefreshIndicator(
                  color: AppGradients.orangeAccent,
                  onRefresh: _load,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      if (!hasContent)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: _buildEmptyState(context, isBengali, isDark),
                        )
                      else ...[
                        if (_plan != null)
                          _buildExamCountdown(context, isBengali, isDark),
                        if (_readiness != null)
                          _buildReadinessBanner(context, isBengali, isDark),
                        if (_coachingUrgency.isNotEmpty)
                          _buildCoachingUrgency(context, isBengali, isDark),
                        if (_todayBlocks.isNotEmpty)
                          _buildTodayPlan(context, isBengali, isDark),
                        if (_coachingItems.isNotEmpty)
                          _buildCoachingItems(context, isBengali, isDark),
                        if (_priorities.isNotEmpty)
                          _buildPriorityTopics(context, isBengali, isDark),
                        _buildQuickActions(context, isBengali, isDark),
                        _buildFooter(context, isBengali, isDark),
                        const SliverToBoxAdapter(child: SizedBox(height: 80)),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isBengali, bool isDark) {
    final colors = context.colors;
    final type = context.type;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: isDark ? null : AppGradients.toolMockTests,
                color: isDark ? colors.surfaceVariant : null,
                shape: BoxShape.circle,
                border: Border.all(color: AppGradients.orangeAccent.withValues(alpha: 0.2)),
              ),
              child: const Icon(
                Icons.assignment_turned_in_outlined,
                size: 48,
                color: AppGradients.orangeAccent,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isBengali ? 'কোন সক্রিয় পরীক্ষার তথ্য নেই' : 'No Active Exam Setup',
              style: type.sectionHeading,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              isBengali
                  ? 'আপনার মক টেস্ট ও পরীক্ষার প্রস্তুতি শুরু করতে কুইজ তৈরি করুন বা প্রস্তুতি নিন।'
                  : 'Get started by creating a practice quiz or setting up an exam study plan.',
              style: type.bodySecondary,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              icon: const Icon(Icons.bolt_rounded),
              label: Text(isBengali ? 'দ্রুত অনুশীলন শুরু করুন' : 'Start Quick Practice'),
              style: FilledButton.styleFrom(
                backgroundColor: AppGradients.orangeAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: GochanoRadius.mdAll),
              ),
              onPressed: () => _startPractice('quick_quiz'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExamCountdown(BuildContext context, bool isBengali, bool isDark) {
    final colors = context.colors;
    final type = context.type;
    final plan = _plan!;
    final days = plan.daysRemaining;
    final urgencyColor = days <= 3
        ? colors.error
        : days <= 7
            ? colors.warning
            : days <= 14
                ? AppGradients.amberOrange
                : AppGradients.orangeAccent;

    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: GochanoRadius.lgAll,
          border: Border.all(color: urgencyColor.withValues(alpha: isDark ? 0.35 : 0.25)),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: urgencyColor.withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    urgencyColor,
                    urgencyColor.withValues(alpha: 0.8),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                isBengali ? GochanoLanguage.toBanglaDigits(days) : '$days',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    plan.examName,
                    style: type.cardHeading,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    days == 0
                        ? (isBengali ? 'আজই পরীক্ষা!' : 'Exam day!')
                        : (isBengali
                            ? '${GochanoLanguage.toBanglaDigits(days)} দিন বাকি'
                            : '$days day${days == 1 ? '' : 's'} remaining'),
                    style: type.bodySecondary.copyWith(
                      color: urgencyColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    isBengali
                        ? 'দৈনিক ${GochanoLanguage.toBanglaDigits(plan.dailyMinutes)} মি · ${GochanoLanguage.toBanglaDigits(plan.durationDays)} দিনের প্ল্যান'
                        : '${plan.dailyMinutes} min/day · ${plan.durationDays}-day plan',
                    style: type.caption,
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => ExamPlanScreen(plan: plan)),
              ),
              child: Text(
                isBengali ? 'প্ল্যান দেখুন' : 'View Plan',
                style: const TextStyle(
                  color: AppGradients.orangeAccent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReadinessBanner(BuildContext context, bool isBengali, bool isDark) {
    final colors = context.colors;
    final type = context.type;
    final r = _readiness!;
    final score = r.overallReadiness.toInt();
    final trendStr = r.trend > 0
        ? '+${isBengali ? GochanoLanguage.toBanglaDigits(r.trend.toInt()) : r.trend.toInt()}%'
        : r.trend < 0
            ? '${isBengali ? GochanoLanguage.toBanglaDigits(r.trend.toInt()) : r.trend.toInt()}%'
            : (isBengali ? 'স্থিতিশীল' : 'Stable');
    final trendColor = r.trend > 0
        ? colors.success
        : (r.trend < 0 ? colors.error : colors.textSecondary);

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: GochanoRadius.lgAll,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ExamReadinessScreen()),
            ),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: isDark
                    ? LinearGradient(
                        colors: [
                          AppGradients.orangeAccent.withValues(alpha: 0.15),
                          colors.surface,
                        ],
                      )
                    : AppGradients.toolMockTests,
                borderRadius: GochanoRadius.lgAll,
                border: Border.all(
                  color: AppGradients.orangeAccent.withValues(alpha: isDark ? 0.35 : 0.25),
                ),
              ),
              child: Row(
                children: [
                  _ReadinessArc(score: score, isBengali: isBengali),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isBengali ? 'পরীক্ষা প্রস্তুতি' : 'Exam Readiness',
                          style: type.cardHeading,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          r.label,
                          style: type.bodySecondary.copyWith(
                            color: AppGradients.orangeAccent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (r.recommendedNextAction.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            r.recommendedNextAction,
                            style: type.caption,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  Column(
                    children: [
                      Text(
                        trendStr,
                        style: TextStyle(
                          color: trendColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Icon(Icons.chevron_right, size: 20, color: colors.textSecondary),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCoachingUrgency(BuildContext context, bool isBengali, bool isDark) {
    final colors = context.colors;
    final type = context.type;
    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: isDark ? null : AppGradients.zikuCoach,
          color: isDark ? colors.ai.withValues(alpha: 0.12) : null,
          borderRadius: GochanoRadius.mdAll,
          border: Border.all(color: colors.ai.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: colors.ai.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.school_outlined, size: 18, color: colors.ai),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _coachingUrgency,
                style: type.bodySecondary.copyWith(
                  color: isDark ? colors.textPrimary : AppGradients.skyDark,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTodayPlan(BuildContext context, bool isBengali, bool isDark) {
    final type = context.type;
    final completedCount = _todayBlocks.where((b) => b.isCompleted).length;

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isBengali ? 'আজকের পরিকল্পনা' : "Today's Plan",
                  style: type.cardHeading,
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppGradients.orangeAccent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    isBengali
                        ? '${GochanoLanguage.toBanglaDigits(completedCount)}/${GochanoLanguage.toBanglaDigits(_todayBlocks.length)} সম্পন্ন'
                        : '$completedCount/${_todayBlocks.length} done',
                    style: const TextStyle(
                      color: AppGradients.orangeAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ..._todayBlocks
                .map((b) => _StudyBlockTile(block: b, isBengali: isBengali)),
          ],
        ),
      ),
    );
  }

  Widget _buildCoachingItems(BuildContext context, bool isBengali, bool isDark) {
    final colors = context.colors;
    final type = context.type;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome_rounded, size: 18, color: colors.ai),
                const SizedBox(width: 6),
                Text(
                  isBengali ? 'যিকু সুপারিশ' : 'Ziku Recommends',
                  style: type.cardHeading,
                ),
              ],
            ),
            const SizedBox(height: 8),
            ..._coachingItems
                .map((c) => _CoachingItemTile(item: c, isBengali: isBengali)),
          ],
        ),
      ),
    );
  }

  Widget _buildPriorityTopics(BuildContext context, bool isBengali, bool isDark) {
    final type = context.type;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isBengali ? 'অগ্রাধিকার বিষয়সমূহ' : 'Priority Topics',
                  style: type.cardHeading,
                ),
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const PriorityTopicsScreen()),
                  ),
                  child: Text(
                    isBengali ? 'সব দেখুন' : 'See All',
                    style: const TextStyle(
                      color: AppGradients.orangeAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            ..._priorities.take(5).map(
                  (t) => _PriorityTopicTile(topic: t, isBengali: isBengali),
                ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context, bool isBengali, bool isDark) {
    final colors = context.colors;
    final type = context.type;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isBengali ? 'দ্রুত অনুশীলন' : 'Quick Practice',
              style: type.cardHeading,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _QuickActionChip(
                  icon: Icons.bolt_rounded,
                  label: isBengali ? 'দ্রুত কুইজ' : 'Quick Quiz',
                  accent: AppGradients.roseAccent,
                  onTap: () => _startPractice('quick_quiz'),
                ),
                _QuickActionChip(
                  icon: Icons.history_toggle_off_rounded,
                  label: isBengali ? 'ভুল সংশোধন' : 'Mistakes',
                  accent: colors.error,
                  onTap: () => _startPractice('mistake_revision'),
                ),
                _QuickActionChip(
                  icon: Icons.flag_rounded,
                  label: isBengali ? 'দুর্বল বিষয়' : 'Weak Topics',
                  accent: colors.study,
                  onTap: () => _startPractice('weak_topic_drill'),
                ),
                _QuickActionChip(
                  icon: Icons.timer_outlined,
                  label: isBengali ? 'মক পরীক্ষা' : 'Mock Exam',
                  accent: AppGradients.orangeAccent,
                  onTap: () => _startPractice('full_mock'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context, bool isBengali, bool isDark) {
    final colors = context.colors;
    final analyzedCountStr = _papersAnalyzed > 0
        ? (isBengali
            ? ' (${GochanoLanguage.toBanglaDigits(_papersAnalyzed)})'
            : ' ($_papersAnalyzed)')
        : '';

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(
                  Icons.history_edu_rounded,
                  size: 18,
                  color: AppGradients.emeraldDark,
                ),
                label: Text(
                  (isBengali ? 'বিগত প্রশ্ন' : 'Past Papers') + analyzedCountStr,
                  style: TextStyle(color: colors.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: colors.border),
                  backgroundColor: colors.surface,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: GochanoRadius.mdAll),
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PastPaperScreen()),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(
                  Icons.bar_chart_rounded,
                  size: 18,
                  color: AppGradients.orangeAccent,
                ),
                label: Text(
                  isBengali ? 'পূর্ণাঙ্গ প্রস্তুতি' : 'Full Readiness',
                  style: TextStyle(color: colors.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: colors.border),
                  backgroundColor: colors.surface,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: GochanoRadius.mdAll),
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const ExamReadinessScreen()),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _startPractice(String mode) async {
    final isBengali = GochanoLanguage.isBangla;
    try {
      final Map<String, dynamic> session;
      if (widget.startPracticeOverride != null) {
        session = await widget.startPracticeOverride!(mode);
      } else {
        session = await ApiService.startPractice(mode: mode);
      }
      if (!mounted) return;
      _handlePracticeSessionStarted(mode, session, isBengali);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isBengali
                ? 'অনুশীলন সেশন শুরু করা যায়নি।'
                : 'Could not start practice session.',
          ),
        ),
      );
    }
  }

  void _handlePracticeSessionStarted(
    String mode,
    Map<String, dynamic> session,
    bool isBengali,
  ) {
    final engineType = session['engineType'] as String? ?? 'quiz';
    final engineConfig =
        session['engineConfig'] as Map<String, dynamic>? ?? {};
    final instruction = engineConfig['instruction'] as String? ?? '';

    final defaultMsg = isBengali
        ? 'অনুশীলন সেশন প্রস্তুত (মোড: $mode)'
        : 'Practice session ready (mode: $mode)';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(instruction.isNotEmpty ? instruction : defaultMsg),
        action: SnackBarAction(
          label: isBengali ? 'শুরু করুন' : 'Start',
          onPressed: () {
            if (engineType == 'exam_simulator') {
              Navigator.pushNamed(context, '/exams');
            } else if (engineType == 'mistake_review') {
              Navigator.pushNamed(context, '/mistakes');
            } else {
              Navigator.pushNamed(context, '/quiz-generate');
            }
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Supporting widgets
// ─────────────────────────────────────────────────────────────────────────────

class _ReadinessArc extends StatelessWidget {
  const _ReadinessArc({required this.score, required this.isBengali});
  final int score;
  final bool isBengali;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = score >= 70
        ? colors.success
        : score >= 55
            ? colors.warning
            : colors.error;
    return SizedBox(
      width: 58,
      height: 58,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: score / 100,
            strokeWidth: 5,
            backgroundColor: colors.border,
            color: color,
          ),
          Text(
            isBengali ? '${GochanoLanguage.toBanglaDigits(score)}%' : '$score%',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _StudyBlockTile extends StatelessWidget {
  const _StudyBlockTile({required this.block, required this.isBengali});
  final StudyBlock block;
  final bool isBengali;

  Color _priorityColor(GochanoColors colors) {
    switch (block.priority) {
      case 'critical':
        return colors.error;
      case 'high':
        return colors.warning;
      default:
        return AppGradients.orangeAccent;
    }
  }

  String _formatBlockType(String type) {
    if (!isBengali) return block.blockTypeLabel;
    switch (block.blockType) {
      case 'learn_review':
        return 'পুনরাবৃত্তি';
      case 'practice':
        return 'অনুশীলন';
      case 'mistake_revision':
        return 'ভুল সংশোধন';
      case 'quiz_recall':
        return 'কুইজ';
      case 'mock_exam':
        return 'মক পরীক্ষা';
      default:
        return 'পড়াশোনা';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final pColor = _priorityColor(colors);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: block.isCompleted ? colors.surfaceVariant : colors.surface,
        borderRadius: GochanoRadius.mdAll,
        border: Border.all(
          color: block.isCompleted
              ? colors.border
              : pColor.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 36,
            decoration: BoxDecoration(
              color: pColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatBlockType(block.blockType),
                  style: type.caption,
                ),
                Text(
                  block.topic,
                  style: type.body.copyWith(
                    decoration: block.isCompleted
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Text(
            isBengali
                ? '${GochanoLanguage.toBanglaDigits(block.durationMinutes)} মি'
                : '${block.durationMinutes}m',
            style: type.caption,
          ),
          if (block.isCompleted) ...[
            const SizedBox(width: 6),
            Icon(Icons.check_circle_rounded, color: colors.success, size: 16),
          ],
        ],
      ),
    );
  }
}

class _CoachingItemTile extends StatelessWidget {
  const _CoachingItemTile({required this.item, required this.isBengali});
  final CoachingItem item;
  final bool isBengali;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: GochanoRadius.mdAll,
        border: Border.all(color: colors.ai.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: colors.ai.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.lightbulb_outline_rounded, size: 18, color: colors.ai),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item.topic.isNotEmpty)
                  Text(
                    item.topic,
                    style: type.body.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                Text(
                  item.action,
                  style: type.bodySecondary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (item.reason.isNotEmpty)
                  Text(
                    item.reason,
                    style: type.caption.copyWith(fontStyle: FontStyle.italic),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          Text(
            isBengali
                ? '${GochanoLanguage.toBanglaDigits(item.durationMinutes)} মি'
                : '${item.durationMinutes}m',
            style: type.caption,
          ),
        ],
      ),
    );
  }
}

class _PriorityTopicTile extends StatelessWidget {
  const _PriorityTopicTile({required this.topic, required this.isBengali});
  final PriorityTopic topic;
  final bool isBengali;

  Color _priorityColor(GochanoColors colors) {
    switch (topic.priority) {
      case 'critical':
        return colors.error;
      case 'high':
        return colors.warning;
      case 'medium':
        return AppGradients.amberOrange;
      default:
        return colors.textSecondary;
    }
  }

  String _formatPriorityLabel(String priority) {
    if (!isBengali) return topic.priorityLabel;
    switch (priority) {
      case 'critical':
        return 'জরুরি';
      case 'high':
        return 'উচ্চ';
      case 'medium':
        return 'মাঝারি';
      default:
        return 'সাধারণ';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final pColor = _priorityColor(colors);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: GochanoRadius.mdAll,
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: pColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: pColor.withValues(alpha: 0.3)),
            ),
            child: Text(
              _formatPriorityLabel(topic.priority),
              style: TextStyle(
                color: pColor,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              topic.topic,
              style: type.body,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            isBengali
                ? GochanoLanguage.toBanglaDigits(topic.priorityScore.toInt())
                : '${topic.priorityScore.toInt()}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: pColor,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionChip extends StatelessWidget {
  const _QuickActionChip({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: GochanoRadius.mdAll,
        side: BorderSide(color: accent.withValues(alpha: 0.3)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 16, color: accent),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.message,
    required this.isBengali,
    required this.onRetry,
  });
  final String message;
  final bool isBengali;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded, size: 48, color: colors.textSecondary),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary),
            ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppGradients.orangeAccent),
              onPressed: onRetry,
              child: Text(isBengali ? 'পুনরায় চেষ্টা করুন' : 'Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
