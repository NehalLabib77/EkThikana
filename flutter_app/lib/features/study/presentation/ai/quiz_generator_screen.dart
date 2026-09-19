// Quiz Generator — AI-powered quiz creation from notes, materials, or topics.
//
// Supports MCQ, short answer, and mixed question types.
// Uses the existing QUIZ quota (3/month).

import 'package:flutter/material.dart';

import '../../../../core/design_system/gochano_colors.dart';
import '../../../../core/design_system/gochano_spacing.dart';
import '../../../../core/design_system/gochano_typography.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../services/api_service.dart';
import '../../../../shared/states/gochano_states.dart';
import '../../../../shared/widgets/gochano_controls.dart';
import '../../../../shared/widgets/gochano_surfaces.dart';

class QuizGeneratorScreen extends StatefulWidget {
  const QuizGeneratorScreen({super.key});

  @override
  State<QuizGeneratorScreen> createState() => _QuizGeneratorScreenState();
}

class _QuizGeneratorScreenState extends State<QuizGeneratorScreen> {
  final _sourceCtrl = TextEditingController();
  final _topicCtrl = TextEditingController();

  String _difficulty = 'medium';
  String _questionType = 'mcq';
  int _questionCount = 5;

  bool _busy = false;
  List<Map<String, dynamic>> _questions = [];
  String _rawResult = '';
  String _error = '';

  @override
  void dispose() {
    _sourceCtrl.dispose();
    _topicCtrl.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final source = _sourceCtrl.text.trim();
    if (source.isEmpty) {
      setState(() => _error = GochanoLanguage.text(
        'Please enter source material or topics.',
        'অনুগ্রহ করে উৎস উপকরণ বা বিষয় লিখুন।',
      ));
      return;
    }

    setState(() {
      _busy = true;
      _error = '';
      _questions = [];
      _rawResult = '';
    });

    try {
      final result = await ApiService.quizGenerate(
        source: source,
        topic: _topicCtrl.text.trim(),
        questionCount: _questionCount,
        difficulty: _difficulty,
        questionType: _questionType,
      );

      if (!mounted) return;
      final raw = result['raw'] as String? ?? '';
      final questions = result['quiz'] as List<dynamic>? ?? [];

      setState(() {
        _busy = false;
        _rawResult = raw;
        _questions = questions
            .whereType<Map>()
            .map((q) => q.map((k, v) => MapEntry(k.toString(), v)))
            .toList();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = friendlyErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return GochanoScaffold(
      padBody: false,
      appBar: GochanoAppBar(
        title: GochanoLanguage.text('Quiz Generator', 'কুইজ জেনারেটর'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          GochanoSpacing.md,
          GochanoSpacing.sm,
          GochanoSpacing.md,
          120,
        ),
        children: [
          // Input card
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  GochanoLanguage.text('Quiz Settings', 'কুইজ সেটিংস'),
                  style: context.type.cardHeading,
                ),
                const SizedBox(height: GochanoSpacing.sm),
                TextField(
                  controller: _sourceCtrl,
                  decoration: InputDecoration(
                    labelText: GochanoLanguage.text('Source Material *', 'উৎস উপকরণ *'),
                    hintText: GochanoLanguage.text(
                      'Paste notes, textbook content, or topics…',
                      'নোট, পাঠ্যবই, বা বিষয় পেস্ট করুন…',
                    ),
                  ),
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: GochanoSpacing.sm),
                TextField(
                  controller: _topicCtrl,
                  decoration: InputDecoration(
                    labelText: GochanoLanguage.text('Topic (optional)', 'বিষয় (ঐচ্ছিক)'),
                    hintText: GochanoLanguage.text(
                      'e.g., Database Normalization',
                      'যেমন, ডাটাবেজ নরমালাইজেশন',
                    ),
                  ),
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: GochanoSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: _DropdownField(
                        label: GochanoLanguage.text('Difficulty', 'কঠিনতা'),
                        value: _difficulty,
                        items: [
                          ('easy', GochanoLanguage.text('Easy', 'সহজ')),
                          ('medium', GochanoLanguage.text('Medium', 'মাঝারি')),
                          ('hard', GochanoLanguage.text('Hard', 'কঠিন')),
                        ],
                        onChanged: (v) => setState(() => _difficulty = v),
                      ),
                    ),
                    const SizedBox(width: GochanoSpacing.sm),
                    Expanded(
                      child: _DropdownField(
                        label: GochanoLanguage.text('Type', 'ধরন'),
                        value: _questionType,
                        items: [
                          ('mcq', GochanoLanguage.text('MCQ', 'এমসিকিউ')),
                          ('short_answer', GochanoLanguage.text('Short Answer', 'ছোট উত্তর')),
                          ('mixed', GochanoLanguage.text('Mixed', 'মিশ্রিত')),
                        ],
                        onChanged: (v) => setState(() => _questionType = v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: GochanoSpacing.sm),
                _CountSelector(
                  count: _questionCount,
                  onChanged: (c) => setState(() => _questionCount = c),
                ),
              ],
            ),
          ),

          const SizedBox(height: GochanoSpacing.md),

          PrimaryButton(
            label: GochanoLanguage.text('Generate Quiz', 'কুইজ তৈরি করুন'),
            icon: Icons.quiz_rounded,
            busy: _busy,
            busyLabel: GochanoLanguage.text('Generating…', 'তৈরি হচ্ছে…'),
            onPressed: _generate,
          ),

          // Error
          if (_error.isNotEmpty) ...[
            const SizedBox(height: GochanoSpacing.sm),
            Container(
              padding: const EdgeInsets.all(GochanoSpacing.sm),
              decoration: BoxDecoration(
                color: colors.errorSoft,
                borderRadius: GochanoRadius.mdAll,
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline_rounded, size: 18, color: colors.error),
                  const SizedBox(width: GochanoSpacing.xs),
                  Expanded(
                    child: Text(_error, style: context.type.bodySecondary.copyWith(color: colors.error)),
                  ),
                ],
              ),
            ),
          ],

          // Questions
          if (_questions.isNotEmpty) ...[
            const SizedBox(height: GochanoSpacing.md),
            Text(
              GochanoLanguage.text(
                '${_questions.length} Questions Generated',
                '${_questions.length}টি প্রশ্ন তৈরি হয়েছে',
              ),
              style: context.type.sectionHeading,
            ),
            const SizedBox(height: GochanoSpacing.sm),
            for (var i = 0; i < _questions.length; i++)
              _QuestionCard(index: i + 1, question: _questions[i]),
          ],

          // Raw result fallback
          if (_questions.isEmpty && _rawResult.isNotEmpty && !_busy) ...[
            const SizedBox(height: GochanoSpacing.md),
            AppCard(
              padding: const EdgeInsets.all(GochanoSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    GochanoLanguage.text('AI Response', 'এআই উত্তর'),
                    style: context.type.cardHeading,
                  ),
                  const SizedBox(height: GochanoSpacing.sm),
                  SelectableText(_rawResult, style: context.type.body),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DropdownField extends StatelessWidget {
  const _DropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<(String, String)> items;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: context.type.caption),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: GochanoSpacing.sm),
          decoration: BoxDecoration(
            border: Border.all(color: context.colors.border),
            borderRadius: GochanoRadius.mdAll,
          ),
          child: DropdownButton<String>(
            value: value,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            items: items
                .map((item) => DropdownMenuItem(
                      value: item.$1,
                      child: Text(item.$2, style: context.type.body),
                    ))
                .toList(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      ],
    );
  }
}

class _CountSelector extends StatelessWidget {
  const _CountSelector({required this.count, required this.onChanged});

  final int count;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          GochanoLanguage.text('Number of Questions', 'প্রশ্নের সংখ্যা'),
          style: context.type.caption,
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            for (final n in [5, 10, 20]) ...[
              if (n != 5) const SizedBox(width: GochanoSpacing.xs),
              Expanded(
                child: InkWell(
                  onTap: () => onChanged(n),
                  borderRadius: GochanoRadius.mdAll,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: GochanoSpacing.xs),
                    decoration: BoxDecoration(
                      color: count == n ? colors.ai.withValues(alpha: 0.12) : colors.surfaceVariant,
                      borderRadius: GochanoRadius.mdAll,
                      border: Border.all(
                        color: count == n ? colors.ai : Colors.transparent,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$n',
                      style: context.type.body.copyWith(
                        color: count == n ? colors.ai : colors.textPrimary,
                        fontWeight: count == n ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _QuestionCard extends StatefulWidget {
  const _QuestionCard({required this.index, required this.question});

  final int index;
  final Map<String, dynamic> question;

  @override
  State<_QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends State<_QuestionCard> {
  bool _showAnswer = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final q = widget.question;
    final type = q['type']?.toString() ?? 'mcq';
    final options = (q['options'] as List<dynamic>?)?.cast<String>() ?? [];
    final correct = q['correct']?.toString() ?? '';
    final explanation = q['explanation']?.toString() ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: GochanoSpacing.sm),
      child: AppCard(
        padding: const EdgeInsets.all(GochanoSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: colors.ai.withValues(alpha: 0.12),
                    borderRadius: GochanoRadius.smAll,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${widget.index}',
                    style: context.type.caption.copyWith(
                      color: colors.ai,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: GochanoSpacing.sm),
                Expanded(
                  child: Text(
                    q['question']?.toString() ?? '',
                    style: context.type.body.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            if (type == 'mcq' && options.isNotEmpty) ...[
              const SizedBox(height: GochanoSpacing.sm),
              for (var i = 0; i < options.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: _showAnswer && options[i] == correct
                              ? colors.success.withValues(alpha: 0.2)
                              : colors.surfaceVariant,
                          borderRadius: GochanoRadius.smAll,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          String.fromCharCode(65 + i),
                          style: context.type.caption.copyWith(
                            color: _showAnswer && options[i] == correct
                                ? colors.success
                                : colors.textSecondary,
                            fontWeight: _showAnswer && options[i] == correct
                                ? FontWeight.w700
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                      const SizedBox(width: GochanoSpacing.xs),
                      Expanded(
                        child: Text(options[i], style: context.type.body),
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: GochanoSpacing.sm),
            GestureDetector(
              onTap: () => setState(() => _showAnswer = !_showAnswer),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _showAnswer ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                    size: 16,
                    color: colors.ai,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _showAnswer
                        ? GochanoLanguage.text('Hide Answer', 'উত্তর লুকান')
                        : GochanoLanguage.text('Show Answer', 'উত্তর দেখুন'),
                    style: context.type.caption.copyWith(color: colors.ai),
                  ),
                ],
              ),
            ),
            if (_showAnswer) ...[
              const SizedBox(height: GochanoSpacing.sm),
              Container(
                padding: const EdgeInsets.all(GochanoSpacing.sm),
                decoration: BoxDecoration(
                  color: colors.success.withValues(alpha: 0.08),
                  borderRadius: GochanoRadius.mdAll,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${GochanoLanguage.text('Correct', 'সঠিক')}: $correct',
                      style: context.type.body.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colors.success,
                      ),
                    ),
                    if (explanation.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(explanation, style: context.type.bodySecondary),
                    ],
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
