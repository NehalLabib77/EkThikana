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
import '../../../../shared/widgets/ai_widgets.dart';
import '../../../../shared/widgets/gochano_controls.dart';
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
    this.onResultSaved,
    this.saveResultFn,
    this.analyzeFn,
  });

  final List<Map<String, dynamic>> questions;
  final List<String> userAnswers;
  final List<String> correctAnswers;
  final String difficulty;
  final String subjectId;
  final String materialId;
  final int timeSpentSeconds;
  final Future<void> Function()? onResultSaved;
  final Future<Map<String, dynamic>> Function({
    required List<Map<String, dynamic>> questions,
    required List<String> userAnswers,
    required List<String> correctAnswers,
    required int score,
    required Map<String, int> topicScores,
    required String subjectId,
    required String materialId,
    required String difficulty,
    required int timeSpentSeconds,
  })?
  saveResultFn;

  /// Phase 1 — explains the mistakes this quiz just recorded, in one batch.
  ///
  /// Null hides the offer entirely, so a caller that did not record mistakes
  /// never shows a button that cannot do anything.
  final Future<Map<String, dynamic>> Function()? analyzeFn;

  @override
  State<QuizResultScreen> createState() => _QuizResultScreenState();
}

class _QuizResultScreenState extends State<QuizResultScreen> {
  bool _saving = false;
  bool _saved = false;
  String _saveError = '';

  // Phase 1 — what the backend recorded while saving the result.
  int _mistakeCount = 0;
  int _newMistakes = 0;
  int _pendingAnalysis = 0;
  bool _analysing = false;
  String _analysisNote = '';
  String _analysisError = '';

  late int _correctCount;
  late int _totalCount;
  late int _score;
  late Map<String, int> _topicScores;
  late Map<String, int> _topicCorrect;

  @override
  void initState() {
    super.initState();
    _totalCount = widget.questions.length;
    _correctCount = 0;
    _topicScores = {};
    _topicCorrect = {};

    for (var i = 0; i < _totalCount; i++) {
      if (_isAnswerCorrect(i)) {
        _correctCount++;
      }
    }

    _score = _totalCount > 0
        ? ((_correctCount / _totalCount) * 100).round()
        : 0;

    // Compute topic mastery as 0-100 percentages (the backend
    // weak_topic_service averages these values against a 0-100 threshold).
    final topicTotals = <String, int>{};
    for (var i = 0; i < _totalCount; i++) {
      final q = widget.questions[i];
      final topic = _extractTopic(q);
      final isCorrect = _isAnswerCorrect(i);
      topicTotals[topic] = (topicTotals[topic] ?? 0) + 1;
      if (isCorrect) {
        _topicCorrect[topic] = (_topicCorrect[topic] ?? 0) + 1;
      }
    }
    for (final entry in topicTotals.entries) {
      final correct = _topicCorrect[entry.key] ?? 0;
      _topicScores[entry.key] = entry.value > 0
          ? ((correct / entry.value) * 100).round()
          : 0;
    }

    _saveResult();
  }

  /// Whether the student's answer for question [i] matches the reference.
  ///
  /// MCQ generators return the option letter (`"B"`) as the reference while
  /// the quiz screen stores the tapped option text (`"B. Reduce confusion"`),
  /// so a plain equality check scored every MCQ as wrong. Bare-letter
  /// references therefore accept the letter with or without its label.
  bool _isAnswerCorrect(int i) {
    final userAns = i < widget.userAnswers.length
        ? widget.userAnswers[i].trim().toLowerCase()
        : '';
    final correctAns = i < widget.correctAnswers.length
        ? widget.correctAnswers[i].trim().toLowerCase()
        : '';
    if (userAns.isEmpty || correctAns.isEmpty) return false;
    if (userAns == correctAns) return true;
    final bareLetter = RegExp(r'^[a-d]$').hasMatch(correctAns);
    if (!bareLetter) return false;
    return RegExp('^$correctAns[.)\\s]').hasMatch(userAns);
  }

  String _extractTopic(Map<String, dynamic> question) {
    // Prefer an explicit topic tag when the generator provides one.
    final tagged = question['topic']?.toString().trim() ?? '';
    if (tagged.isNotEmpty) return tagged;
    // Fall back to the explanation's first sentence (or the question text).
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
      // The backend answers with the mistake counts it recorded while saving,
      // so the feedback loop (saved → explained) needs no second round trip.
      final response = widget.saveResultFn != null
          ? await widget.saveResultFn!(
              questions: widget.questions,
              userAnswers: widget.userAnswers,
              correctAnswers: widget.correctAnswers,
              score: _score,
              topicScores: _topicScores,
              subjectId: widget.subjectId,
              materialId: widget.materialId,
              difficulty: widget.difficulty,
              timeSpentSeconds: widget.timeSpentSeconds,
            )
          : await ApiService.saveQuizResult(
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

      if (widget.onResultSaved != null) {
        await widget.onResultSaved!();
      }

      if (mounted) {
        setState(() {
          _saving = false;
          _saved = true;
          _mistakeCount = _asInt(response['mistakeCount']);
          _newMistakes = _asInt(response['newMistakes']);
          _pendingAnalysis = _asInt(response['pendingAnalysis']);
        });
      }

      // Phase 4 — the Study Coach caches the profile and today's mission for
      // the day, and this quiz just changed both. Rebuild them in the
      // background (only when the real backend path saved); a failed rebuild
      // leaves yesterday's cache to expire on its own.
      if (widget.saveResultFn == null) {
        unawaited(
          ApiService.coachRecalculate().catchError(
            (Object _) => <String, dynamic>{},
          ),
        );
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

  /// One batched AI call for everything this quiz recorded.
  Future<void> _explainMistakes() async {
    final analyze = widget.analyzeFn;
    if (_analysing || analyze == null) return;
    setState(() {
      _analysing = true;
      _analysisError = '';
      _analysisNote = '';
    });
    try {
      final result = await analyze();
      if (!mounted) return;
      final analysed = _asInt(result['analyzed']);
      setState(() {
        _analysing = false;
        _pendingAnalysis = _asInt(result['pending']);
        _analysisNote = analysed > 0
            ? GochanoLanguage.text(
                'Ziku explained $analysed mistakes.',
                'জিকু $analysed টি ভুল ব্যাখ্যা করেছে।',
              )
            : GochanoLanguage.text(
                'Nothing new to explain yet.',
                'নতুন কিছু ব্যাখ্যা করার নেই।',
              );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _analysing = false;
        _analysisError = e.toString();
      });
    }
  }

  static int _asInt(dynamic value) => value is num ? value.toInt() : 0;

  Color _scoreColor(BuildContext context) {
    final colors = context.colors;
    if (_score >= 80) return colors.success;
    if (_score >= 50) return colors.ai;
    return colors.error;
  }

  String _scoreLabel() {
    if (_score >= 90) return GochanoLanguage.text('Excellent!', 'সুন্দর!');
    if (_score >= 70) return GochanoLanguage.text('Good job!', 'ভালো কাজ!');
    if (_score >= 50) {
      return GochanoLanguage.text('Keep practicing!', 'অনুশীলন চালিয়ে যান!');
    }
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
                          valueColor: AlwaysStoppedAnimation(
                            _scoreColor(context),
                          ),
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
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.ai,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        GochanoLanguage.text('Saving…', 'সংরক্ষণ হচ্ছে…'),
                        style: context.type.caption.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ],
                if (_saved) ...[
                  const SizedBox(height: GochanoSpacing.xs),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.check_circle_outline_rounded,
                        size: 14,
                        color: colors.success,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        GochanoLanguage.text('Result saved', 'ফলাফল সংরক্ষিত'),
                        style: context.type.caption.copyWith(
                          color: colors.success,
                        ),
                      ),
                    ],
                  ),
                ],
                if (_saveError.isNotEmpty) ...[
                  const SizedBox(height: GochanoSpacing.xs),
                  Text(
                    GochanoLanguage.text(
                      'Failed to save result',
                      'ফলাফল সংরক্ষণ ব্যর্থ',
                    ),
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

          // Phase 1 — the wrong answers just recorded, and the one action
          // worth taking on them. Hidden when nothing was recorded, so a
          // screen that only displays a score still only displays a score.
          if (_mistakeCount > 0) ...[
            const SizedBox(height: GochanoSpacing.md),
            AppCard(
              accent: colors.ai,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.psychology_alt_rounded,
                        size: 18,
                        color: colors.ai,
                      ),
                      const SizedBox(width: GochanoSpacing.xs),
                      Expanded(
                        child: Text(
                          GochanoLanguage.text(
                            'Saved to My Learning Brain',
                            'মাই লার্নিং ব্রেইনে সংরক্ষিত',
                          ),
                          style: context.type.cardHeading,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: GochanoSpacing.xs),
                  Text(
                    GochanoLanguage.text(
                      '$_mistakeCount wrong answers kept for revision · '
                      '$_newMistakes new',
                      '$_mistakeCount টি ভুল পুনরাবৃত্তির জন্য রাখা হয়েছে',
                    ),
                    style: context.type.bodySecondary.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  if (_pendingAnalysis > 0 &&
                      widget.analyzeFn != null) ...[
                    const SizedBox(height: GochanoSpacing.sm),
                    PrimaryButton(
                      label: GochanoLanguage.text(
                        'Explain with Ziku',
                        'জিকু দিয়ে ব্যাখ্যা',
                      ),
                      icon: Icons.auto_awesome_rounded,
                      expand: false,
                      busy: _analysing,
                      busyLabel: GochanoLanguage.text(
                        'Explaining…',
                        'ব্যাখ্যা হচ্ছে…',
                      ),
                      onPressed: _explainMistakes,
                    ),
                  ],
                  if (_analysisNote.isNotEmpty) ...[
                    const SizedBox(height: GochanoSpacing.xs),
                    Text(
                      _analysisNote,
                      style: context.type.caption.copyWith(
                        color: colors.success,
                      ),
                    ),
                  ],
                  if (_analysisError.isNotEmpty) ...[
                    const SizedBox(height: GochanoSpacing.xs),
                    AiErrorBanner(message: _analysisError),
                  ],
                ],
              ),
            ),
          ],

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
              // entry.value is already a 0-100 mastery percentage.
              return _TopicBar(
                topic: entry.key,
                correct: _topicCorrect[entry.key] ?? 0,
                total: topicTotal,
                percentage: entry.value,
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
              userAnswer: i < widget.userAnswers.length
                  ? widget.userAnswers[i]
                  : '',
              correctAnswer: i < widget.correctAnswers.length
                  ? widget.correctAnswers[i]
                  : '',
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
          Text(
            label,
            style: context.type.caption.copyWith(color: colors.textSecondary),
          ),
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
              style: context.type.caption.copyWith(
                color: colors.textTertiary,
                fontSize: 11,
              ),
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
    final options =
        (question['options'] as List<dynamic>?)?.cast<String>() ?? [];
    final explanation = question['explanation']?.toString() ?? '';
    final questionText = question['question']?.toString() ?? '';

    final isCorrect =
        userAnswer.trim().toLowerCase() == correctAnswer.trim().toLowerCase() &&
        userAnswer.trim().isNotEmpty;

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
                    style: context.type.body.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
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
                    Icon(
                      Icons.lightbulb_outline_rounded,
                      size: 14,
                      color: colors.ai,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        explanation,
                        style: context.type.caption.copyWith(
                          color: colors.textSecondary,
                        ),
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
