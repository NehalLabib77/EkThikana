/// Phase 15 — Exam Hub Screen.
///
/// Single-request bootstrap: all dashboard data in one call.
/// No duplicate quiz/exam/planner/focus engines created.
/// Navigates to existing screens for quiz/exam execution.
library;

import 'package:flutter/material.dart';

import '../../../../services/api_service.dart';
import 'exam_ecosystem_models.dart';
import 'exam_plan_screen.dart';
import 'exam_readiness_screen.dart';
import 'past_paper_screen.dart';
import 'priority_topics_screen.dart';

class ExamHubScreen extends StatefulWidget {
  const ExamHubScreen({super.key});

  static const routeName = '/exam-hub';

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
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ApiService.examEcosystemDashboard();

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
      }

      _papersAnalyzed = (data['papersAnalyzed'] as num?)?.toInt() ?? 0;
    } on ApiException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Could not load Exam Hub. Please try again.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: CustomScrollView(
        slivers: [
          _buildAppBar(theme),
          if (_loading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            SliverFillRemaining(child: _ErrorView(message: _error!, onRetry: _load))
          else ...[
            if (_plan != null) _buildExamCountdown(theme),
            if (_readiness != null) _buildReadinessBanner(theme),
            if (_coachingUrgency.isNotEmpty) _buildCoachingUrgency(theme),
            if (_todayBlocks.isNotEmpty) _buildTodayPlan(theme),
            if (_coachingItems.isNotEmpty) _buildCoachingItems(theme),
            if (_priorities.isNotEmpty) _buildPriorityTopics(theme),
            _buildQuickActions(theme),
            _buildFooter(theme),
            const SliverToBoxAdapter(child: SizedBox(height: 80)),
          ],
        ],
      ),
    );
  }

  Widget _buildAppBar(ThemeData theme) {
    return SliverAppBar(
      expandedHeight: 100,
      pinned: true,
      backgroundColor: theme.colorScheme.primary,
      flexibleSpace: FlexibleSpaceBar(
        title: Text(
          _plan != null
              ? 'Exam Hub · ${_plan!.examName}'
              : 'Exam Hub',
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.onPrimary,
          ),
        ),
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                theme.colorScheme.primary,
                theme.colorScheme.primaryContainer,
              ],
            ),
          ),
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          color: theme.colorScheme.onPrimary,
          onPressed: _load,
          tooltip: 'Refresh',
        ),
      ],
    );
  }

  Widget _buildExamCountdown(ThemeData theme) {
    final plan = _plan!;
    final days = plan.daysRemaining;
    final urgencyColor = days <= 3
        ? Colors.red.shade700
        : days <= 7
            ? Colors.orange.shade700
            : days <= 14
                ? Colors.amber.shade700
                : theme.colorScheme.primary;

    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: urgencyColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: urgencyColor.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: urgencyColor,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                '$days',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: Colors.white,
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
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    days == 0
                        ? 'Exam day!'
                        : '$days day${days == 1 ? '' : 's'} remaining',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  Text(
                    '${plan.dailyMinutes} min/day · ${plan.durationDays}-day plan',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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
              child: const Text('View Plan'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReadinessBanner(ThemeData theme) {
    final r = _readiness!;
    final score = r.overallReadiness.toInt();
    final trendStr = r.trend > 0
        ? '+${r.trend.toInt()}%'
        : r.trend < 0
            ? '${r.trend.toInt()}%'
            : 'Stable';
    final trendColor = r.trend > 0 ? Colors.green : Colors.red;

    return SliverToBoxAdapter(
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ExamReadinessScreen()),
        ),
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              _ReadinessArc(score: score),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Exam Readiness',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      r.label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (r.recommendedNextAction.isNotEmpty)
                      Text(
                        r.recommendedNextAction,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              Column(
                children: [
                  Text(
                    trendStr,
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: trendColor),
                  ),
                  const Icon(Icons.chevron_right, size: 18),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCoachingUrgency(ThemeData theme) {
    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.tertiaryContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(Icons.school_outlined,
                size: 18, color: theme.colorScheme.onTertiaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _coachingUrgency,
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onTertiaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTodayPlan(ThemeData theme) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Today's Plan",
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ..._todayBlocks
                .map((b) => _StudyBlockTile(block: b, theme: theme)),
          ],
        ),
      ),
    );
  }

  Widget _buildCoachingItems(ThemeData theme) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ziku Recommends',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ..._coachingItems
                .map((c) => _CoachingItemTile(item: c, theme: theme)),
          ],
        ),
      ),
    );
  }

  Widget _buildPriorityTopics(ThemeData theme) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Priority Topics',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const PriorityTopicsScreen()),
                  ),
                  child: const Text('See All'),
                ),
              ],
            ),
            ..._priorities.take(5).map(
                  (t) => _PriorityTopicTile(topic: t, theme: theme),
                ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions(ThemeData theme) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Quick Practice',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _QuickActionChip(
                  icon: Icons.flash_on,
                  label: 'Quick Quiz',
                  onTap: () => _startPractice('quick_quiz'),
                ),
                _QuickActionChip(
                  icon: Icons.bug_report_outlined,
                  label: 'Mistakes',
                  onTap: () => _startPractice('mistake_revision'),
                ),
                _QuickActionChip(
                  icon: Icons.trending_up,
                  label: 'Weak Topics',
                  onTap: () => _startPractice('weak_topic_drill'),
                ),
                _QuickActionChip(
                  icon: Icons.assignment_outlined,
                  label: 'Mock Exam',
                  onTap: () => _startPractice('full_mock'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(ThemeData theme) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.history_edu, size: 18),
                label: Text('Past Papers${_papersAnalyzed > 0 ? ' ($_papersAnalyzed)' : ''}'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PastPaperScreen()),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.bar_chart, size: 18),
                label: const Text('Full Readiness'),
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
    try {
      final session = await ApiService.startPractice(mode: mode);
      if (!mounted) return;
      final engineType = session['engineType'] as String? ?? 'quiz';
      final engineConfig =
          session['engineConfig'] as Map<String, dynamic>? ?? {};
      final instruction = engineConfig['instruction'] as String? ?? '';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(instruction.isNotEmpty
              ? instruction
              : 'Practice session ready (mode: $mode)'),
          action: SnackBarAction(
            label: 'Start',
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
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Supporting widgets
// ─────────────────────────────────────────────────────────────────────────────

class _ReadinessArc extends StatelessWidget {
  const _ReadinessArc({required this.score});
  final int score;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = score >= 70
        ? Colors.green
        : score >= 55
            ? Colors.amber
            : Colors.red;
    return SizedBox(
      width: 60,
      height: 60,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: score / 100,
            strokeWidth: 6,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            color: color,
          ),
          Text(
            '$score%',
            style: theme.textTheme.labelMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _StudyBlockTile extends StatelessWidget {
  const _StudyBlockTile({required this.block, required this.theme});
  final StudyBlock block;
  final ThemeData theme;

  Color _priorityColor() {
    switch (block.priority) {
      case 'critical':
        return Colors.red.shade700;
      case 'high':
        return Colors.orange.shade700;
      default:
        return theme.colorScheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: block.isCompleted
            ? theme.colorScheme.surfaceContainerHighest
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: block.isCompleted
              ? theme.colorScheme.outlineVariant
              : _priorityColor().withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 36,
            decoration: BoxDecoration(
              color: _priorityColor(),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  block.blockTypeLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  block.topic,
                  style: theme.textTheme.bodyMedium?.copyWith(
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
            '${block.durationMinutes}m',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (block.isCompleted)
            const Padding(
              padding: EdgeInsets.only(left: 6),
              child: Icon(Icons.check_circle, color: Colors.green, size: 16),
            ),
        ],
      ),
    );
  }
}

class _CoachingItemTile extends StatelessWidget {
  const _CoachingItemTile({required this.item, required this.theme});
  final CoachingItem item;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.lightbulb_outline, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item.topic.isNotEmpty)
                  Text(
                    item.topic,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                Text(
                  item.action,
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (item.reason.isNotEmpty)
                  Text(
                    item.reason,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          Text(
            '${item.durationMinutes}m',
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _PriorityTopicTile extends StatelessWidget {
  const _PriorityTopicTile({required this.topic, required this.theme});
  final PriorityTopic topic;
  final ThemeData theme;

  Color _priorityColor() {
    switch (topic.priority) {
      case 'critical':
        return Colors.red.shade700;
      case 'high':
        return Colors.orange.shade700;
      case 'medium':
        return Colors.amber.shade700;
      default:
        return Colors.grey.shade600;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _priorityColor(),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              topic.priorityLabel,
              style: theme.textTheme.labelSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              topic.topic,
              style: theme.textTheme.bodyMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${topic.priorityScore.toInt()}',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: _priorityColor(),
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
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ActionChip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      onPressed: onTap,
      backgroundColor: theme.colorScheme.surfaceContainerHighest,
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
