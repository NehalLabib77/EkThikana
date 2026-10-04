/// Phase 15.6 — Exam Readiness Screen.
///
/// Explainable readiness scoring based on the 5-component deterministic formula:
/// 35% Mastery Coverage + 25% Mock Exam Performance + 15% Recent Practice +
/// 15% Revision Coverage + 10% Focus Consistency.
library;

import 'package:flutter/material.dart';

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
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Exam Readiness'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
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
                      Text(_error!),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _loadReadiness,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _readiness == null
                  ? const Center(child: Text('No readiness data available.'))
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _buildGaugeCard(theme),
                        const SizedBox(height: 16),
                        if (_readiness!.recommendedNextAction.isNotEmpty)
                          _buildNextActionCard(theme),
                        const SizedBox(height: 16),
                        _buildComponentsBreakdown(theme),
                        const SizedBox(height: 16),
                        if (_readiness!.criticalTopics.isNotEmpty)
                          _buildTopicsSection(
                            theme,
                            title: 'Topics Needing Attention',
                            topics: _readiness!.criticalTopics,
                            color: Colors.red.shade700,
                          ),
                        const SizedBox(height: 16),
                        if (_readiness!.strongTopics.isNotEmpty)
                          _buildTopicsSection(
                            theme,
                            title: 'Strong Topics',
                            topics: _readiness!.strongTopics,
                            color: Colors.green.shade700,
                          ),
                        const SizedBox(height: 16),
                        if (_history.isNotEmpty) _buildHistoryCard(theme),
                        const SizedBox(height: 16),
                        _buildDisclaimerCard(theme),
                      ],
                    ),
    );
  }

  Widget _buildGaugeCard(ThemeData theme) {
    final r = _readiness!;
    final score = r.overallReadiness.toInt();
    final color = score >= 85
        ? Colors.green.shade700
        : score >= 70
            ? Colors.green
            : score >= 55
                ? Colors.amber.shade800
                : score >= 40
                    ? Colors.orange.shade800
                    : Colors.red.shade800;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
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
                      strokeWidth: 12,
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                      color: color,
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$score%',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                      Text(
                        'Readiness',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              r.label,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  r.trend > 0
                      ? Icons.arrow_upward
                      : r.trend < 0
                          ? Icons.arrow_downward
                          : Icons.remove,
                  size: 16,
                  color: r.trend > 0
                      ? Colors.green
                      : r.trend < 0
                          ? Colors.red
                          : Colors.grey,
                ),
                const SizedBox(width: 4),
                Text(
                  r.trend != 0
                      ? '${r.trend > 0 ? "+" : ""}${r.trend.toInt()}% over last 7 days'
                      : 'Stable performance trend',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNextActionCard(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.directions_run, color: theme.colorScheme.primary, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Recommended Next Step',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _readiness!.recommendedNextAction,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComponentsBreakdown(ThemeData theme) {
    final comps = _readiness!.components;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Readiness Components',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            _ReadinessRow(
              label: 'Mastery Coverage',
              weight: '35%',
              value: comps['masteryCoverage'] ?? 50,
            ),
            _ReadinessRow(
              label: 'Mock Exam Performance',
              weight: '25%',
              value: comps['mockExamPerformance'] ?? 50,
            ),
            _ReadinessRow(
              label: 'Recent Practice Regularity',
              weight: '15%',
              value: comps['recentPractice'] ?? 50,
            ),
            _ReadinessRow(
              label: 'Revision Queue Coverage',
              weight: '15%',
              value: comps['revisionCoverage'] ?? 50,
            ),
            _ReadinessRow(
              label: 'Focus Consistency',
              weight: '10%',
              value: comps['focusConsistency'] ?? 50,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopicsSection(
    ThemeData theme, {
    required String title,
    required List<String> topics,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: topics.map((t) {
            return Chip(
              backgroundColor: color.withValues(alpha: 0.08),
              side: BorderSide(color: color.withValues(alpha: 0.3)),
              label: Text(
                t,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildHistoryCard(ThemeData theme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Readiness Snapshots (${_history.length})',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Snapshots are recorded when key milestones occur (mocks completed, mastery updates, plan recalculations).',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            ..._history.reversed.take(5).map((snap) {
              final score = (snap['overallReadiness'] as num?)?.toInt() ?? 0;
              final label = snap['label'] as String? ?? '';
              final dateStr = (snap['calculatedAt'] as String? ?? '').split('T').first;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(dateStr, style: theme.textTheme.bodySmall),
                    Text(label, style: theme.textTheme.bodySmall),
                    Text(
                      '$score%',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildDisclaimerCard(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Note: Exam readiness scores evaluate your study coverage, revision consistency, and practice test results. They do not predict exact exam questions or guarantee academic scores.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontSize: 11,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}

class _ReadinessRow extends StatelessWidget {
  const _ReadinessRow({
    required this.label,
    required this.weight,
    required this.value,
  });

  final String label;
  final String weight;
  final double value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$label ($weight)',
                style: theme.textTheme.bodySmall,
              ),
              Text(
                '${value.toInt()}%',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: (value / 100).clamp(0.0, 1.0),
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
        ],
      ),
    );
  }
}
