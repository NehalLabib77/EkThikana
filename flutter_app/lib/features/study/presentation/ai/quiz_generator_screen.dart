// Quiz Generator — AI-powered quiz creation from notes, materials, or topics.
//
// Supports MCQ, short answer, and mixed question types.
// Uses the existing QUIZ quota (3/month).
// Phase 3C: Enhanced with interactive quiz mode, answer submission,
// score persistence, and quiz history.

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../../core/design_system/gochano_colors.dart';
import '../../../../core/design_system/gochano_spacing.dart';
import '../../../../core/design_system/gochano_typography.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../core/page_route.dart';
import '../../../../services/api_service.dart';
import '../../../../shared/states/gochano_states.dart';
import '../../../../shared/widgets/ai_widgets.dart';
import '../../../../shared/widgets/gochano_controls.dart';
import '../../../../shared/widgets/gochano_surfaces.dart';
import 'material_picker_sheet.dart';
import 'quiz_history_screen.dart';
import 'quiz_result_screen.dart';

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

  // Selected source materials
  final List<Map<String, String>> _selectedMaterials = [];

  static const int _maxFiles = 3;
  static const int _maxTextChars = 12000;

  bool _busy = false;
  bool _uploading = false;
  List<Map<String, dynamic>> _questions = [];
  String _rawResult = '';
  String _error = '';

  // Phase 3C: Interactive quiz mode
  bool _quizMode = false;
  final Map<int, String> _selectedAnswers = {};
  bool _submitting = false;
  DateTime? _quizStartedAt;

  @override
  void dispose() {
    _sourceCtrl.dispose();
    _topicCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickMaterials() async {
    if (_selectedMaterials.length >= _maxFiles) {
      setState(() => _error = GochanoLanguage.text(
        'Maximum $_maxFiles files allowed. Remove a file first.',
        'সর্বোচ্চ $_maxFiles ফাইল অনুমোদিত। প্রথমে একটি ফাইল সরান।',
      ));
      return;
    }
    final result = await showMaterialPicker(context);
    if (result.isNotEmpty) {
      setState(() {
        _error = '';
        final remaining = _maxFiles - _selectedMaterials.length;
        final toAdd = result.take(remaining).toList();
        _selectedMaterials.addAll(toAdd);
        // Remove duplicates by ID
        final seen = <String>{};
        _selectedMaterials.retainWhere((m) => seen.add(m['id'] ?? ''));
        if (result.length > remaining) {
          _error = GochanoLanguage.text(
            'Only $remaining more file(s) allowed. ${result.length - remaining} file(s) skipped.',
            'আরো $remaining ফাইল অনুমোদিত। ${result.length - remaining} ফাইল বাদ দেওয়া হয়েছে।',
          );
        }
      });
    }
  }

  void _removeMaterial(String id) {
    setState(() {
      _selectedMaterials.removeWhere((m) => m['id'] == id);
    });
  }

  Future<void> _uploadSource() async {
    if (_selectedMaterials.length >= _maxFiles) {
      setState(() => _error = GochanoLanguage.text(
        'Maximum $_maxFiles files allowed. Remove a file first.',
        'সর্বোচ্চ $_maxFiles ফাইল অনুমোদিত। প্রথমে একটি ফাইল সরান।',
      ));
      return;
    }
    try {
      final selected = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'txt'],
      );
      if (selected == null) return;
      final bytes = await selected.readAsBytes();
      if (!mounted) return;

      final titleCtrl = TextEditingController(text: selected.name);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(GochanoLanguage.text('Upload Source', 'উৎস আপলোড')),
          content: TextField(
            controller: titleCtrl,
            decoration: InputDecoration(
              labelText: GochanoLanguage.text('Title', 'শিরোনাম'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(GochanoLanguage.text('Cancel', 'বাতিল')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(GochanoLanguage.text('Upload', 'আপলোড')),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;

      setState(() {
        _uploading = true;
        _error = '';
      });

      final materialId = await ApiService.uploadMaterial(
        bytes: bytes,
        fileName: selected.name,
        title: titleCtrl.text.trim().isNotEmpty ? titleCtrl.text.trim() : selected.name,
        visibility: 'private',
      );

      if (mounted) {
        final title = titleCtrl.text.trim().isNotEmpty ? titleCtrl.text.trim() : selected.name;
        setState(() {
          _uploading = false;
          _selectedMaterials.add({'id': materialId, 'title': title});
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(GochanoLanguage.text('File uploaded', 'ফাইল আপলোড হয়েছে'))),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _uploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(GochanoLanguage.text('Upload failed. Please try again.', 'আপলোড ব্যর্থ। আবার চেষ্টা করুন।'))),
        );
      }
    }
  }

  Future<void> _generate() async {
    final source = _sourceCtrl.text.trim();
    final hasMaterials = _selectedMaterials.isNotEmpty;
    final hasSource = source.isNotEmpty;

    if (!hasMaterials && !hasSource) {
      setState(() => _error = GochanoLanguage.text(
        'Please select source materials or enter source text.',
        'অনুগ্রহ করে উৎস উপকরণ নির্বাচন করুন বা উৎস লিখুন।',
      ));
      return;
    }

    // Validate text length
    if (source.length > _maxTextChars) {
      setState(() => _error = GochanoLanguage.text(
        'Source text exceeds $_maxTextChars characters (${source.length}). Please shorten it.',
        'উৎস লেখা $_maxTextChars অক্ষর অতিক্রম করেছে (${source.length})। অনুগ্রহ করে ছোট করুন।',
      ));
      return;
    }

    // Check quiz quota before calling API
    try {
      final usage = await ApiService.getAiUsage();
      final quizData = usage['quiz'] as Map<String, dynamic>? ?? {};
      final quizRemaining = quizData['remaining'] as int? ?? 0;
      if (quizRemaining <= 0) {
        setState(() => _error = GochanoLanguage.text(
          'AI Quiz limit reached. You have used all 3 quiz generations this month. Your limit resets on 1st of next month.',
          'AI কুইজ সীমা পৌঁছে গেছে। আপনি এই মাসে ৩টি কুইজ জেনারেশন ব্যবহার করেছেন। আপনার সীমা পরবর্তী মাসের ১ তারিখে রিসেট হবে।',
        ));
        return;
      }
    } catch (_) {
      // If quota check fails, proceed (backend will enforce)
    }

    setState(() {
      _busy = true;
      _error = '';
      _questions = [];
      _rawResult = '';
      _quizMode = false;
      _selectedAnswers.clear();
    });

    try {
      final sourceIds = _selectedMaterials
          .map((m) => m['id'] ?? '')
          .where((id) => id.isNotEmpty)
          .toList();

      final result = await ApiService.quizGenerate(
        source: source,
        sourceIds: sourceIds,
        topic: _topicCtrl.text.trim(),
        questionCount: _questionCount,
        difficulty: _difficulty,
        questionType: _questionType,
      );

      if (!mounted) return;
      final raw = result['raw'] as String? ?? '';
      final error = result['error'] as String?;
      final questions = result['quiz'] as List<dynamic>? ?? [];

      setState(() {
        _busy = false;
        if (error != null && error.isNotEmpty) {
          _error = error;
        }
        _rawResult = raw;
        _questions = questions
            .whereType<Map>()
            .map((q) => q.map((k, v) => MapEntry(k.toString(), v)))
            .toList();
      });

      // Enter quiz mode if questions were generated
      if (_questions.isNotEmpty) {
        _enterQuizMode();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = friendlyErrorMessage(e);
      });
    }
  }

  void _enterQuizMode() {
    setState(() {
      _quizMode = true;
      _selectedAnswers.clear();
      _quizStartedAt = DateTime.now();
    });
  }

  void _exitQuizMode() {
    setState(() {
      _quizMode = false;
      _selectedAnswers.clear();
      _quizStartedAt = null;
    });
  }

  Future<void> _submitQuiz() async {
    if (_submitting) return;

    // Check all questions are answered
    final unanswered = <int>[];
    for (var i = 0; i < _questions.length; i++) {
      if (!_selectedAnswers.containsKey(i) || _selectedAnswers[i]!.isEmpty) {
        unanswered.add(i + 1);
      }
    }

    if (unanswered.isNotEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(GochanoLanguage.text(
            'Please answer question ${unanswered.join(", ")}',
            'অনুগ্রহ করে প্রশ্ন ${unanswered.join(", ")} উত্তর দিন',
          )),
        ),
      );
      return;
    }

    setState(() => _submitting = true);

    // Calculate time spent
    final timeSpent = _quizStartedAt != null
        ? DateTime.now().difference(_quizStartedAt!).inSeconds
        : 0;

    // Build correct answers list
    final correctAnswers = _questions.map((q) {
      return q['correct']?.toString() ?? '';
    }).toList();

    // Build user answers list
    final userAnswers = List.generate(_questions.length, (i) {
      return _selectedAnswers[i] ?? '';
    });

    if (!mounted) return;

    // Navigate to result screen (which handles saving)
    Navigator.of(context).push(
      GochanoRoute.to(
        builder: (_) => QuizResultScreen(
          questions: _questions,
          userAnswers: userAnswers,
          correctAnswers: correctAnswers,
          difficulty: _difficulty,
          subjectId: _topicCtrl.text.trim(),
          timeSpentSeconds: timeSpent,
        ),
      ),
    ).then((_) {
      // Reset quiz mode when returning from results
      if (mounted) {
        _exitQuizMode();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return GochanoScaffold(
      padBody: false,
      appBar: GochanoAppBar(
        title: GochanoLanguage.text('Quiz Generator', 'কুইজ জেনারেটর'),
        actions: [
          if (!_quizMode)
            IconButton(
              onPressed: () {
                Navigator.of(context).push(
                  GochanoRoute.to(builder: (_) => const QuizHistoryScreen()),
                );
              },
              icon: const Icon(Icons.history_rounded),
              tooltip: GochanoLanguage.text('Quiz History', 'কুইজ ইতিহাস'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          GochanoSpacing.md,
          GochanoSpacing.sm,
          GochanoSpacing.md,
          120,
        ),
        children: [
          // Source Material Section (hidden in quiz mode)
          if (!_quizMode) ...[
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          GochanoLanguage.text('Source Material', 'উৎস উপকরণ'),
                          style: context.type.cardHeading,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _pickMaterials,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: Text(GochanoLanguage.text('Select', 'নির্বাচন')),
                      ),
                      const SizedBox(width: GochanoSpacing.xs),
                      TextButton.icon(
                        onPressed: _uploading ? null : _uploadSource,
                        icon: _uploading
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.upload_file_rounded, size: 18),
                        label: Text(_uploading
                            ? GochanoLanguage.text('Uploading…', 'আপলোড হচ্ছে…')
                            : GochanoLanguage.text('Upload', 'আপলোড')),
                      ),
                    ],
                  ),
                  const SizedBox(height: GochanoSpacing.xs),

                  // Source limits info
                  Container(
                    padding: const EdgeInsets.all(GochanoSpacing.sm),
                    decoration: BoxDecoration(
                      color: colors.surfaceVariant.withValues(alpha: 0.5),
                      borderRadius: GochanoRadius.mdAll,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info_outline_rounded, size: 14, color: colors.textSecondary),
                            const SizedBox(width: GochanoSpacing.xs),
                            Expanded(
                              child: Text(
                                GochanoLanguage.text(
                                  'Supported: PDF, DOC, DOCX, TXT, Notes',
                                  'সমর্থিত: PDF, DOC, DOCX, TXT, Notes',
                                ),
                                style: context.type.caption.copyWith(color: colors.textSecondary),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          GochanoLanguage.text(
                            'Limits: 10 PDF pages · 12,000 chars max · $_maxFiles files max',
                            'সীমা: ১০ PDF পৃষ্ঠা · ১২,০০০ অক্ষর সর্বোচ্চ · $_maxFiles ফাইল সর্বোচ্চ',
                          ),
                          style: context.type.caption.copyWith(color: colors.textTertiary, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: GochanoSpacing.sm),

                  // Selected materials chips
                  if (_selectedMaterials.isNotEmpty) ...[
                    Wrap(
                      spacing: GochanoSpacing.xs,
                      runSpacing: GochanoSpacing.xs,
                      children: _selectedMaterials.map((m) {
                        final id = m['id'] ?? '';
                        final title = m['title'] ?? id;
                        return Chip(
                          avatar: Icon(Icons.description_rounded, size: 16, color: context.colors.brand),
                          label: Text(
                            title.length > 24 ? '${title.substring(0, 24)}…' : title,
                            style: context.type.caption,
                          ),
                          deleteIcon: const Icon(Icons.close_rounded, size: 16),
                          onDeleted: () => _removeMaterial(id),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: GochanoSpacing.sm),
                  ],

                  // Manual text input
                  TextField(
                    controller: _sourceCtrl,
                    decoration: InputDecoration(
                      labelText: GochanoLanguage.text(
                        'Or paste source text',
                        'অথবা উৎস লেখা পেস্ট করুন',
                      ),
                      hintText: GochanoLanguage.text(
                        'Paste notes, textbook content, or topics…',
                        'নোট, পাঠ্যবই, বা বিষয় পেস্ট করুন…',
                      ),
                    ),
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 4),
                  _SourceLimitsHelper(textLength: _sourceCtrl.text.length, maxChars: _maxTextChars),
                ],
              ),
            ),

            const SizedBox(height: GochanoSpacing.sm),

            // Topic and settings
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
              busyLabel: GochanoLanguage.text(
                'AI is generating…',
                'এআই তৈরি করছে…',
              ),
              onPressed: _generate,
            ),
          ],

          // Error
          if (_error.isNotEmpty) ...[
            const SizedBox(height: GochanoSpacing.sm),
            AiErrorBanner(message: _error),
          ],

          // Questions — Quiz Mode (interactive)
          if (_questions.isNotEmpty && _quizMode) ...[
            const SizedBox(height: GochanoSpacing.md),
            Row(
              children: [
                Expanded(
                  child: Text(
                    GochanoLanguage.text(
                      'Answer all ${_questions.length} questions',
                      'সব ${_questions.length}টি প্রশ্নের উত্তর দিন',
                    ),
                    style: context.type.sectionHeading,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: colors.ai.withValues(alpha: 0.12),
                    borderRadius: GochanoRadius.smAll,
                  ),
                  child: Text(
                    '${_selectedAnswers.length}/${_questions.length}',
                    style: context.type.caption.copyWith(
                      color: colors.ai,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: GochanoSpacing.sm),
            for (var i = 0; i < _questions.length; i++)
              _QuizQuestionCard(
                index: i,
                question: _questions[i],
                selectedAnswer: _selectedAnswers[i],
                onAnswerSelected: (answer) {
                  setState(() => _selectedAnswers[i] = answer);
                },
              ),

            const SizedBox(height: GochanoSpacing.md),
            PrimaryButton(
              label: GochanoLanguage.text('Submit Quiz', 'কুইজ জমা দিন'),
              icon: Icons.check_circle_rounded,
              busy: _submitting,
              busyLabel: GochanoLanguage.text('Submitting…', 'জমা হচ্ছে…'),
              onPressed: _submitQuiz,
            ),

            const SizedBox(height: GochanoSpacing.sm),
            Center(
              child: TextButton(
                onPressed: _exitQuizMode,
                child: Text(
                  GochanoLanguage.text('Cancel Quiz', 'কুইজ বাতিল করুন'),
                  style: context.type.body.copyWith(color: colors.textSecondary),
                ),
              ),
            ),
          ],

          // Questions — Review Mode (show/hide answers, legacy)
          if (_questions.isNotEmpty && !_quizMode) ...[
            const SizedBox(height: GochanoSpacing.md),
            Row(
              children: [
                Expanded(
                  child: Text(
                    GochanoLanguage.text(
                      '${_questions.length} Questions Generated',
                      '${_questions.length}টি প্রশ্ন তৈরি হয়েছে',
                    ),
                    style: context.type.sectionHeading,
                  ),
                ),
                TextButton.icon(
                  onPressed: _enterQuizMode,
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: Text(GochanoLanguage.text('Start Quiz', 'কুইজ শুরু করুন')),
                ),
              ],
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

// Phase 3C: Interactive quiz question card with answer selection
class _QuizQuestionCard extends StatelessWidget {
  const _QuizQuestionCard({
    required this.index,
    required this.question,
    required this.selectedAnswer,
    required this.onAnswerSelected,
  });

  final int index;
  final Map<String, dynamic> question;
  final String? selectedAnswer;
  final ValueChanged<String> onAnswerSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = question['type']?.toString() ?? 'mcq';
    final options = (question['options'] as List<dynamic>?)?.cast<String>() ?? [];
    final questionText = question['question']?.toString() ?? '';

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
                    '${index + 1}',
                    style: context.type.caption.copyWith(
                      color: colors.ai,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: GochanoSpacing.sm),
                Expanded(
                  child: Text(
                    questionText,
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
                  child: _SelectableOption(
                    label: String.fromCharCode(65 + i),
                    text: options[i],
                    isSelected: selectedAnswer == options[i],
                    onTap: () => onAnswerSelected(options[i]),
                  ),
                ),
            ],
            if (type == 'short_answer') ...[
              const SizedBox(height: GochanoSpacing.sm),
              TextField(
                decoration: InputDecoration(
                  hintText: GochanoLanguage.text('Type your answer…', 'আপনার উত্তর লিখুন…'),
                ),
                maxLines: 3,
                onChanged: onAnswerSelected,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SelectableOption extends StatelessWidget {
  const _SelectableOption({
    required this.label,
    required this.text,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final String text;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: GochanoRadius.mdAll,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: GochanoSpacing.sm, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? colors.ai.withValues(alpha: 0.12)
              : colors.surfaceVariant,
          borderRadius: GochanoRadius.mdAll,
          border: Border.all(
            color: isSelected ? colors.ai : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? colors.ai : colors.surfaceVariant,
                border: isSelected ? null : Border.all(color: colors.border),
              ),
              alignment: Alignment.center,
              child: Text(
                label,
                style: context.type.caption.copyWith(
                  color: isSelected ? Colors.white : colors.textSecondary,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal,
                ),
              ),
            ),
            const SizedBox(width: GochanoSpacing.xs),
            Expanded(
              child: Text(text, style: context.type.body),
            ),
          ],
        ),
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

class _SourceLimitsHelper extends StatelessWidget {
  const _SourceLimitsHelper({required this.textLength, required this.maxChars});

  final int textLength;
  final int maxChars;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final over = textLength > maxChars;
    return Row(
      children: [
        Icon(
          over ? Icons.warning_rounded : Icons.text_fields_rounded,
          size: 12,
          color: over ? colors.error : colors.textTertiary,
        ),
        const SizedBox(width: 4),
        Text(
          '$textLength / $maxChars',
          style: context.type.caption.copyWith(
            color: over ? colors.error : colors.textTertiary,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
