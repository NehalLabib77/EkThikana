/// Phase 15.6 — Exam Readiness Screen.
///
/// Explainable readiness scoring based on the 5-component deterministic formula:
/// 35% Mastery Coverage + 25% Mock Exam Performance + 15% Recent Practice +
/// 15% Revision Coverage + 10% Focus Consistency.
library;

import 'package:flutter/material.dart';

import '../../../../core/design_system/app_design_system.dart';
import '../../../../services/api_service.dart';
import 'exam_ecosystem_models.dart';

class ExamReadinessScreen extends StatefulWidget {
  const ExamReadinessScreen({super.key});

  static const routeName = '/exam-readiness';

  @override
  State<ExamReadinessScreen> createState() => _ExamReadinessScreenState();
}

class _ExamReadinessScreenState extends State<ExamReadinessScreen> {
  bool _loading = true;
  String? _error;
  ExamReadiness? _readiness;
  List<Map<String, dynamic>> _history = [];
  final int _historyDays = 30;

  @override
  void initState() {
    super.initState();
    _loadReadiness();
  }

  Future<void> _loadReadiness() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiService.getExamReadiness();
      _readiness = ExamReadiness.fromJson(res);

      try {
        final histRes = await ApiService.getReadinessHistory(days: _historyDays);
        final list = histRes['history'] as List<dynamic>? ?? [];
        _history = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      } catch (_) {
        // history is optional
      }
    } on ApiException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Failed to calculate exam readiness.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(color: colors.border, height: 0.5),
        ),
        title: Text(
          'Exam Readiness',
          style: type.cardHeading.copyWith(fontSize: 17),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: colors.brand),
            onPressed: _loadReadiness,
            tooltip: 'Recalculate',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, style: TextStyle(color: colors.textSecondary)),
                      const SizedBox(height: 12),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: colors.brand),
                        onPressed: _loadReadiness,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _readiness == null
                  ? Center(child: Text('No readiness data available.', style: type.bodySecondary))
                  : AppPageBackground(
                      height: 240,
                      gradient: isDark
                          ? LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                colors.brand.withValues(alpha: 0.12),
                                colors.background,
                              ],
                            )
                          : AppGradients.academicHealth,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          _buildGaugeCard(context),
                          const SizedBox(height: 16),
                          if (_readiness!.recommendedNextAction.isNotEmpty)
                            _buildNextActionCard(context, isDark),
                          const SizedBox(height: 16),
                          _buildComponentsBreakdown(context),
                          const SizedBox(height: 16),
                          if (_readiness!.criticalTopics.isNotEmpty)
                            _buildTopicsSection(
                              context,
                              title: 'Topics Needing Attention',
                              topics: _readiness!.criticalTopics,
                              color: colors.error,
                            ),
                          const SizedBox(height: 16),
                          if (_readiness!.strongTopics.isNotEmpty)
                            _buildTopicsSection(
                              context,
                              title: 'Strong Topics',
                              topics: _readiness!.strongTopics,
                              color: colors.success,
                            ),
                          const SizedBox(height: 16),
                          if (_history.isNotEmpty) _buildHistoryCard(context),
                          const SizedBox(height: 16),
                          _buildDisclaimerCard(context),
                        ],
                      ),
                    ),
    );
  }

  Widget _buildGaugeCard(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final r = _readiness!;
    final score = r.overallReadiness.toInt();
    final color = score >= 85
        ? colors.success
        : score >= 70
            ? AppGradients.emeraldAccent
            : score >= 55
                ? colors.warning
                : score >= 40
                    ? AppGradients.orangeAccent
                    : colors.error;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: GochanoRadius.lgAll,
        border: Border.all(color: color.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          SizedBox(
            width: 140,
            height: 140,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 130,
                  height: 130,
                  child: CircularProgressIndicator(
                    value: score / 100,
                    strokeWidth: 10,
                    backgroundColor: colors.border,
                    color: color,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$score%',
                      style: type.display.copyWith(
                        color: color,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Readiness',
                      style: type.caption,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            r.label,
            style: type.cardHeading.copyWith(
              color: color,
              fontSize: 17,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                r.trend > 0
                    ? Icons.arrow_upward_rounded
                    : r.trend < 0
                        ? Icons.arrow_downward_rounded
                        : Icons.remove_rounded,
                size: 16,
                color: r.trend > 0
                    ? colors.success
                    : r.trend < 0
                        ? colors.error
                        : colors.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                r.trend != 0
                    ? '${r.trend > 0 ? "+" : ""}${r.trend.toInt()}% over last 7 days'
                    : 'Stable performance trend',
                style: type.caption,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNextActionCard(BuildContext context, bool isDark) {
    final colors = context.colors;
    final type = context.type;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: isDark
            ? LinearGradient(
                colors: [
                  colors.brand.withValues(alpha: 0.18),
                  colors.surface,
                ],
              )
            : AppGradients.examHero,
        borderRadius: GochanoRadius.mdAll,
        border: Border.all(color: colors.brand.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: colors.brand.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.directions_run_rounded, color: colors.brand, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Recommended Next Step',
                  style: type.cardHeading.copyWith(color: colors.brand),
                ),
                const SizedBox(height: 4),
                Text(
                  _readiness!.recommendedNextAction,
                  style: type.body,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComponentsBreakdown(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final comps = _readiness!.components;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: GochanoRadius.lgAll,
        border: Border.all(color: colors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Readiness Components',
            style: type.cardHeading,
          ),
          const SizedBox(height: 12),
          _ReadinessRow(
            label: 'Mastery Coverage',
            weight: '35%',
            value: comps['masteryCoverage'] ?? 50,
            accentColor: colors.brand,
          ),
          _ReadinessRow(
            label: 'Mock Exam Performance',
            weight: '25%',
            value: comps['mockExamPerformance'] ?? 50,
            accentColor: AppGradients.roseAccent,
          ),
          _ReadinessRow(
            label: 'Recent Practice Regularity',
            weight: '15%',
            value: comps['recentPractice'] ?? 50,
            accentColor: colors.study,
          ),
          _ReadinessRow(
            label: 'Revision Queue Coverage',
            weight: '15%',
            value: comps['revisionCoverage'] ?? 50,
            accentColor: AppGradients.amberOrange,
          ),
          _ReadinessRow(
            label: 'Focus Consistency',
            weight: '10%',
            value: comps['focusConsistency'] ?? 50,
            accentColor: AppGradients.violetLight,
          ),
        ],
      ),
    );
  }

  Widget _buildTopicsSection(
    BuildContext context, {
    required String title,
    required List<String> topics,
    required Color color,
  }) {
    final type = context.type;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: type.cardHeading,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: topics.map((t) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: GochanoRadius.smAll,
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: Text(
                t,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildHistoryCard(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: GochanoRadius.lgAll,
        border: Border.all(color: colors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Readiness Snapshots (${_history.length})',
            style: type.cardHeading,
          ),
          const SizedBox(height: 4),
          Text(
            'Snapshots are recorded when key milestones occur (mocks completed, mastery updates, plan recalculations).',
            style: type.caption,
          ),
          const SizedBox(height: 12),
          ..._history.reversed.take(5).map((snap) {
            final score = (snap['overallReadiness'] as num?)?.toInt() ?? 0;
            final label = snap['label'] as String? ?? '';
            final dateStr = (snap['calculatedAt'] as String? ?? '').split('T').first;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(dateStr, style: type.caption),
                  Text(label, style: type.body),
                  Text(
                    '$score%',
                    style: type.body.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colors.brand,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildDisclaimerCard(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceVariant.withValues(alpha: 0.5),
        borderRadius: GochanoRadius.mdAll,
        border: Border.all(color: colors.border),
      ),
      child: Text(
        'Note: Exam readiness scores evaluate your study coverage, revision consistency, and practice test results. They do not predict exact exam questions or guarantee academic scores.',
        style: type.caption.copyWith(fontStyle: FontStyle.italic),
      ),
    );
  }
}

class _ReadinessRow extends StatelessWidget {
  const _ReadinessRow({
    required this.label,
    required this.weight,
    required this.value,
    required this.accentColor,
  });

  final String label;
  final String weight;
  final double value;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$label ($weight)',
                style: type.caption,
              ),
              Text(
                '${value.toInt()}%',
                style: type.caption.copyWith(
                  fontWeight: FontWeight.bold,
                  color: accentColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: (value / 100).clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: colors.surfaceVariant,
              valueColor: AlwaysStoppedAnimation<Color>(accentColor),
            ),
          ),
        ],
      ),
    );
  }
}
