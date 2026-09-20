// Phase 3C — Quiz History Screen
//
// Shows past quiz attempts with scores and topic breakdowns.
// Enables weak topic detection foundation for future AI personalization.

import 'package:flutter/material.dart';

import '../../../../core/design_system/gochano_colors.dart';
import '../../../../core/design_system/gochano_spacing.dart';
import '../../../../core/design_system/gochano_typography.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../services/api_service.dart';
import '../../../../shared/states/gochano_states.dart';
import '../../../../shared/widgets/ai_widgets.dart';
import '../../../../shared/widgets/gochano_surfaces.dart';

class QuizHistoryScreen extends StatefulWidget {
  const QuizHistoryScreen({super.key});

  @override
  State<QuizHistoryScreen> createState() => _QuizHistoryScreenState();
}

class _QuizHistoryScreenState extends State<QuizHistoryScreen> {
  List<Map<String, dynamic>> _results = [];
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      final data = await ApiService.getQuizHistory(limit: 50);
      if (mounted) {
        setState(() {
          _loading = false;
          _results = (data['results'] as List<dynamic>? ?? [])
              .whereType<Map>()
              .map((r) => r.map((k, v) => MapEntry(k.toString(), v)))
              .toList();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = friendlyErrorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GochanoScaffold(
      appBar: GochanoAppBar(
        title: GochanoLanguage.text('Quiz History', 'কুইজ ইতিহাস'),
      ),
      body: _loading
          ? const AiLoadingState()
          : _error.isNotEmpty
              ? ErrorState(
                  message: _error,
                  onRetry: _loadHistory,
                )
              : _results.isEmpty
                  ? AiEmptyState(
                      icon: Icons.quiz_outlined,
                      title: GochanoLanguage.text(
                        'No quiz history yet',
                        'এখনো কুইজ ইতিহাস নেই',
                      ),
                      message: GochanoLanguage.text(
                        'Generate a quiz to start building your history and track your progress.',
                        'আপনার অগ্রগতি ট্র্যাক করতে এবং ইতিহাস তৈরি করতে একটি কুইজ তৈরি করুন।',
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadHistory,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(GochanoSpacing.md),
                        itemCount: _results.length + 1,
                        itemBuilder: (context, index) {
                          if (index == 0) return _buildSummary();
                          final result = _results[index - 1];
                          return _buildResultCard(result);
                        },
                      ),
                    ),
    );
  }

  Widget _buildSummary() {
    final colors = context.colors;
    if (_results.isEmpty) return const SizedBox.shrink();

    int totalQuizzes = _results.length;
    double avgScore = 0;
    int bestScore = 0;
    int totalCorrect = 0;
    int totalQuestions = 0;

    for (final r in _results) {
      final score = r['score'] as int? ?? 0;
      final correct = r['correctCount'] as int? ?? 0;
      final total = r['totalQuestions'] as int? ?? 0;
      avgScore += score;
      if (score > bestScore) bestScore = score;
      totalCorrect += correct;
      totalQuestions += total;
    }
    avgScore = totalQuizzes > 0 ? avgScore / totalQuizzes : 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: GochanoSpacing.md),
      child: AppCard(
        padding: const EdgeInsets.all(GochanoSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              GochanoLanguage.text('Overall Stats', 'সামগ্রিক পরিসংখ্যান'),
              style: context.type.cardHeading,
            ),
            const SizedBox(height: GochanoSpacing.sm),
            Row(
              children: [
                _SummaryStat(
                  label: GochanoLanguage.text('Quizzes', 'কুইজ'),
                  value: '$totalQuizzes',
                  color: colors.ai,
                ),
                _SummaryStat(
                  label: GochanoLanguage.text('Avg Score', 'গড় স্কোর'),
                  value: '${avgScore.round()}%',
                  color: colors.ai,
                ),
                _SummaryStat(
                  label: GochanoLanguage.text('Best', 'সেরা'),
                  value: '$bestScore%',
                  color: colors.success,
                ),
                _SummaryStat(
                  label: GochanoLanguage.text('Accuracy', 'নির্ভুলতা'),
                  value: totalQuestions > 0
                      ? '${((totalCorrect / totalQuestions) * 100).round()}%'
                      : '—',
                  color: colors.textPrimary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(Map<String, dynamic> result) {
    final colors = context.colors;
    final score = result['score'] as int? ?? 0;
    final correct = result['correctCount'] as int? ?? 0;
    final total = result['totalQuestions'] as int? ?? 0;
    final difficulty = result['difficulty']?.toString() ?? 'medium';
    final timeSpent = result['timeSpentSeconds'] as int? ?? 0;
    final dayKey = result['dayKey']?.toString() ?? '';
    final topicScores = result['topicScores'] as Map<String, dynamic>? ?? {};

    Color scoreColor;
    if (score >= 80) {
      scoreColor = colors.success;
    } else if (score >= 50) {
      scoreColor = colors.ai;
    } else {
      scoreColor = colors.error;
    }

    String formatDuration(int seconds) {
      if (seconds < 60) return '${seconds}s';
      final m = seconds ~/ 60;
      final s = seconds % 60;
      return s > 0 ? '${m}m ${s}s' : '${m}m';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: GochanoSpacing.sm),
      child: AppCard(
        padding: const EdgeInsets.all(GochanoSpacing.sm),
        child: Row(
          children: [
            // Score circle
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scoreColor.withValues(alpha: 0.12),
              ),
              alignment: Alignment.center,
              child: Text(
                '$score%',
                style: context.type.body.copyWith(
                  color: scoreColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: GochanoSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$correct/$total ${GochanoLanguage.text('correct', 'সঠিক')}',
                    style: context.type.body.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      _InfoChip(
                        icon: Icons.signal_cellular_alt_rounded,
                        text: difficulty,
                      ),
                      if (timeSpent > 0) ...[
                        const SizedBox(width: GochanoSpacing.xs),
                        _InfoChip(
                          icon: Icons.timer_outlined,
                          text: formatDuration(timeSpent),
                        ),
                      ],
                      if (dayKey.isNotEmpty) ...[
                        const SizedBox(width: GochanoSpacing.xs),
                        _InfoChip(
                          icon: Icons.calendar_today_rounded,
                          text: dayKey,
                        ),
                      ],
                    ],
                  ),
                  if (topicScores.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      runSpacing: 2,
                      children: topicScores.entries.take(3).map((e) {
                        final pct = e.value is int ? e.value : 0;
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: colors.surfaceVariant,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${e.key}: $pct',
                            style: context.type.caption.copyWith(fontSize: 10),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: colors.textTertiary),
          ],
        ),
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  const _SummaryStat({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: context.type.cardHeading.copyWith(color: color),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: context.type.caption.copyWith(
              color: context.colors.textSecondary,
              fontSize: 11,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 10, color: context.colors.textTertiary),
        const SizedBox(width: 2),
        Text(
          text,
          style: context.type.caption.copyWith(
            fontSize: 10,
            color: context.colors.textTertiary,
          ),
        ),
      ],
    );
  }
}
