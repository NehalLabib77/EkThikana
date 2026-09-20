// Phase 3C — Quiz Result Screen
//
// Displays quiz score, correct/wrong breakdown, topic performance,
// and saves the result to Firestore via the backend.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/design_system/gochano_colors.dart';
import '../../../../core/design_system/gochano_spacing.dart';
import '../../../../core/design_system/gochano_typography.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../services/api_service.dart';
import '../../../../shared/widgets/gochano_surfaces.dart';

class QuizResultScreen extends StatefulWidget {
  const QuizResultScreen({
    super.key,
    required this.questions,
    required this.userAnswers,
    required this.correctAnswers,
    required this.difficulty,
    this.subjectId = '',
    this.materialId = '',
    this.timeSpentSeconds = 0,
  });

  final List<Map<String, dynamic>> questions;
  final List<String> userAnswers;
  final List<String> correctAnswers;
  final String difficulty;
  final String subjectId;
  final String materialId;
  final int timeSpentSeconds;

  @override
  State<QuizResultScreen> createState() => _QuizResultScreenState();
}

class _QuizResultScreenState extends State<QuizResultScreen> {
  bool _saving = false;
  bool _saved = false;
  String _saveError = '';

  late int _correctCount;
  late int _totalCount;
  late int _score;
  late Map<String, int> _topicScores;

  @override
  void initState() {
    super.initState();
    _totalCount = widget.questions.length;
    _correctCount = 0;
    _topicScores = {};

    for (var i = 0; i < _totalCount; i++) {
      final userAns = i < widget.userAnswers.length ? widget.userAnswers[i].trim().toLowerCase() : '';
      final correctAns = i < widget.correctAnswers.length ? widget.correctAnswers[i].trim().toLowerCase() : '';
      if (userAns == correctAns && userAns.isNotEmpty) {
        _correctCount++;
      }
    }

    _score = _totalCount > 0 ? ((_correctCount / _totalCount) * 100).round() : 0;

    // Compute topic scores (group by question type / first word as topic proxy)
    for (var i = 0; i < _totalCount; i++) {
      final q = widget.questions[i];
      final topic = _extractTopic(q);
      _topicScores.putIfAbsent(topic, () => 0);
      final userAns = i < widget.userAnswers.length ? widget.userAnswers[i].trim().toLowerCase() : '';
      final correctAns = i < widget.correctAnswers.length ? widget.correctAnswers[i].trim().toLowerCase() : '';
      if (userAns == correctAns && userAns.isNotEmpty) {
        _topicScores[topic] = (_topicScores[topic] ?? 0) + 1;
      }
    }

    _saveResult();
  }

  String _extractTopic(Map<String, dynamic> question) {
    // Use explanation first sentence or question first few words as topic
    final explanation = question['explanation']?.toString() ?? '';
    if (explanation.isNotEmpty) {
      final firstSentence = explanation.split(RegExp(r'[.!?]')).first.trim();
      if (firstSentence.length <= 40) return firstSentence;
      return firstSentence.substring(0, 40);
    }
    final q = question['question']?.toString() ?? 'General';
    if (q.length <= 40) return q;
    return q.substring(0, 40);
  }

  Future<void> _saveResult() async {
    if (_saving || _saved) return;
    setState(() => _saving = true);

    try {
      await ApiService.saveQuizResult(
        questions: widget.questions,
        userAnswers: widget.userAnswers,
        correctAnswers: widget.correctAnswers,
        score: _score,
        topicScores: _topicScores,
        subjectId: widget.subjectId,
        materialId: widget.materialId,
        difficulty: widget.difficulty,
        timeSpentSeconds: widget.timeSpentSeconds,
      );

      if (mounted) {
        setState(() {
          _saving = false;
          _saved = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _saveError = e.toString();
        });
      }
    }
  }

  Color _scoreColor(BuildContext context) {
    final colors = context.colors;
    if (_score >= 80) return colors.success;
    if (_score >= 50) return colors.ai;
    return colors.error;
  }

  String _scoreLabel() {
    if (_score >= 90) return GochanoLanguage.text('Excellent!', 'সুন্দর!');
    if (_score >= 70) return GochanoLanguage.text('Good job!', 'ভালো কাজ!');
    if (_score >= 50) return GochanoLanguage.text('Keep practicing!', 'অনুশীলন চালিয়ে যান!');
    return GochanoLanguage.text('Needs improvement.', 'উন্নতি প্রয়োজন।');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return GochanoScaffold(
      appBar: GochanoAppBar(
        title: GochanoLanguage.text('Quiz Result', 'কুইজ ফলাফল'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(GochanoSpacing.md),
        children: [
          // Score card
          AppCard(
            padding: const EdgeInsets.all(GochanoSpacing.lg),
            child: Column(
              children: [
                // Score circle
                SizedBox(
                  width: 120,
                  height: 120,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 120,
                        height: 120,
                        child: CircularProgressIndicator(
                          value: _score / 100,
                          strokeWidth: 10,
                          backgroundColor: colors.surfaceVariant,
                          valueColor: AlwaysStoppedAnimation(_scoreColor(context)),
                          strokeCap: StrokeCap.round,
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$_score%',
                            style: context.type.sectionHeading.copyWith(
                              color: _scoreColor(context),
                              fontSize: 28,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: GochanoSpacing.sm),
                Text(
                  _scoreLabel(),
                  style: context.type.cardHeading.copyWith(
                    color: _scoreColor(context),
                  ),
                ),
                const SizedBox(height: GochanoSpacing.xs),
                Text(
                  '$_correctCount/$_totalCount ${GochanoLanguage.text('correct', 'সঠিক')}',
                  style: context.type.bodySecondary.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                if (_saving) ...[
                  const SizedBox(height: GochanoSpacing.sm),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: colors.ai),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        GochanoLanguage.text('Saving…', 'সংরক্ষণ হচ্ছে…'),
                        style: context.type.caption.copyWith(color: colors.textTertiary),
                      ),
                    ],
                  ),
                ],
                if (_saved) ...[
                  const SizedBox(height: GochanoSpacing.xs),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_outline_rounded, size: 14, color: colors.success),
                      const SizedBox(width: 4),
                      Text(
                        GochanoLanguage.text('Result saved', 'ফলাফল সংরক্ষিত'),
                        style: context.type.caption.copyWith(color: colors.success),
                      ),
                    ],
                  ),
                ],
                if (_saveError.isNotEmpty) ...[
                  const SizedBox(height: GochanoSpacing.xs),
                  Text(
                    GochanoLanguage.text('Failed to save result', 'ফলাফল সংরক্ষণ ব্যর্থ'),
                    style: context.type.caption.copyWith(color: colors.error),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: GochanoSpacing.md),

          // Summary stats
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  icon: Icons.check_circle_rounded,
                  label: GochanoLanguage.text('Correct', 'সঠিক'),
                  value: '$_correctCount',
                  color: colors.success,
                ),
              ),
              const SizedBox(width: GochanoSpacing.sm),
              Expanded(
                child: _StatCard(
                  icon: Icons.cancel_rounded,
                  label: GochanoLanguage.text('Wrong', 'ভুল'),
                  value: '${_totalCount - _correctCount}',
                  color: colors.error,
                ),
              ),
              const SizedBox(width: GochanoSpacing.sm),
              Expanded(
                child: _StatCard(
                  icon: Icons.quiz_rounded,
                  label: GochanoLanguage.text('Total', 'মোট'),
                  value: '$_totalCount',
                  color: colors.ai,
                ),
              ),
            ],
          ),

          const SizedBox(height: GochanoSpacing.md),

          // Topic performance
          if (_topicScores.length > 1 || _topicScores.isNotEmpty) ...[
            Text(
              GochanoLanguage.text('Topic Performance', 'বিষয় অনুযায়ী ফলাফল'),
              style: context.type.sectionHeading,
            ),
            const SizedBox(height: GochanoSpacing.sm),
            ..._topicScores.entries.map((entry) {
              final topicTotal = _getTopicTotal(entry.key);
              final pct = topicTotal > 0 ? ((entry.value / topicTotal) * 100).round() : 0;
              return _TopicBar(
                topic: entry.key,
                correct: entry.value,
                total: topicTotal,
                percentage: pct,
              );
            }),
            const SizedBox(height: GochanoSpacing.md),
          ],

          // Question review
          Text(
            GochanoLanguage.text('Question Review', 'প্রশ্ন পর্যালোচনা'),
            style: context.type.sectionHeading,
          ),
          const SizedBox(height: GochanoSpacing.sm),
          for (var i = 0; i < _totalCount; i++)
            _QuestionReview(
              index: i + 1,
              question: widget.questions[i],
              userAnswer: i < widget.userAnswers.length ? widget.userAnswers[i] : '',
              correctAnswer: i < widget.correctAnswers.length ? widget.correctAnswers[i] : '',
            ),

          const SizedBox(height: GochanoSpacing.xl),
        ],
      ),
    );
  }

  int _getTopicTotal(String topic) {
    int total = 0;
    for (var i = 0; i < _totalCount; i++) {
      if (_extractTopic(widget.questions[i]) == topic) total++;
    }
    return total;
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppCard(
      padding: const EdgeInsets.all(GochanoSpacing.sm),
      child: Column(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 4),
          Text(value, style: context.type.cardHeading.copyWith(color: color)),
          Text(label, style: context.type.caption.copyWith(color: colors.textSecondary)),
        ],
      ),
    );
  }
}

class _TopicBar extends StatelessWidget {
  const _TopicBar({
    required this.topic,
    required this.correct,
    required this.total,
    required this.percentage,
  });

  final String topic;
  final int correct;
  final int total;
  final int percentage;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    Color barColor;
    if (percentage >= 80) {
      barColor = colors.success;
    } else if (percentage >= 50) {
      barColor = colors.ai;
    } else {
      barColor = colors.error;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: GochanoSpacing.xs),
      child: AppCard(
        padding: const EdgeInsets.all(GochanoSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    topic,
                    style: context.type.body.copyWith(fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '$percentage%',
                  style: context.type.body.copyWith(
                    color: barColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: total > 0 ? correct / total : 0,
                backgroundColor: colors.surfaceVariant,
                valueColor: AlwaysStoppedAnimation(barColor),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$correct/$total ${GochanoLanguage.text('correct', 'সঠিক')}',
              style: context.type.caption.copyWith(color: colors.textTertiary, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuestionReview extends StatelessWidget {
  const _QuestionReview({
    required this.index,
    required this.question,
    required this.userAnswer,
    required this.correctAnswer,
  });

  final int index;
  final Map<String, dynamic> question;
  final String userAnswer;
  final String correctAnswer;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = question['type']?.toString() ?? 'mcq';
    final options = (question['options'] as List<dynamic>?)?.cast<String>() ?? [];
    final explanation = question['explanation']?.toString() ?? '';
    final questionText = question['question']?.toString() ?? '';

    final isCorrect = userAnswer.trim().toLowerCase() == correctAnswer.trim().toLowerCase() && userAnswer.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: GochanoSpacing.sm),
      child: AppCard(
        padding: const EdgeInsets.all(GochanoSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: isCorrect
                        ? colors.success.withValues(alpha: 0.15)
                        : colors.error.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    isCorrect ? Icons.check_rounded : Icons.close_rounded,
                    size: 14,
                    color: isCorrect ? colors.success : colors.error,
                  ),
                ),
                const SizedBox(width: GochanoSpacing.xs),
                Expanded(
                  child: Text(
                    '$index. $questionText',
                    style: context.type.body.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),

            // MCQ options
            if (type == 'mcq' && options.isNotEmpty) ...[
              const SizedBox(height: GochanoSpacing.xs),
              for (var i = 0; i < options.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    children: [
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: options[i] == correctAnswer
                              ? colors.success.withValues(alpha: 0.2)
                              : options[i] == userAnswer && !isCorrect
                                  ? colors.error.withValues(alpha: 0.15)
                                  : colors.surfaceVariant,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          String.fromCharCode(65 + i),
                          style: context.type.caption.copyWith(
                            fontSize: 10,
                            color: options[i] == correctAnswer
                                ? colors.success
                                : options[i] == userAnswer && !isCorrect
                                    ? colors.error
                                    : colors.textTertiary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          options[i],
                          style: context.type.body.copyWith(fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],

            // Answer comparison
            const SizedBox(height: GochanoSpacing.xs),
            Row(
              children: [
                _AnswerChip(
                  label: GochanoLanguage.text('Your answer', 'আপনার উত্তর'),
                  value: userAnswer.isEmpty ? '—' : userAnswer,
                  isCorrect: isCorrect,
                ),
                const SizedBox(width: GochanoSpacing.xs),
                if (!isCorrect)
                  _AnswerChip(
                    label: GochanoLanguage.text('Correct', 'সঠিক'),
                    value: correctAnswer,
                    isCorrect: true,
                  ),
              ],
            ),

            // Explanation
            if (explanation.isNotEmpty) ...[
              const SizedBox(height: GochanoSpacing.xs),
              Container(
                padding: const EdgeInsets.all(GochanoSpacing.xs),
                decoration: BoxDecoration(
                  color: colors.ai.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lightbulb_outline_rounded, size: 14, color: colors.ai),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        explanation,
                        style: context.type.caption.copyWith(color: colors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AnswerChip extends StatelessWidget {
  const _AnswerChip({
    required this.label,
    required this.value,
    required this.isCorrect,
  });

  final String label;
  final String value;
  final bool isCorrect;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isCorrect
            ? colors.success.withValues(alpha: 0.08)
            : colors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isCorrect
              ? colors.success.withValues(alpha: 0.3)
              : colors.error.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: context.type.caption.copyWith(
              fontSize: 10,
              color: isCorrect ? colors.success : colors.error,
            ),
          ),
          Text(
            value,
            style: context.type.body.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: isCorrect ? colors.success : colors.error,
            ),
          ),
        ],
      ),
    );
  }
}
