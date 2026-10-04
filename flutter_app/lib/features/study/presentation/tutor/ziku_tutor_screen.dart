// Phase 12 — Ziku Socratic AI Tutor Screen.
//
// An interactive, personalized Socratic tutoring interface:
// - Diagnostic questions to assess student understanding
// - Step-by-step reasoning evaluation with constructive feedback
// - 3-level progressive hint ladder
// - Seamless escape hatch ("Explain Instead" / "answerটা বলে দাও")
// - Mode switching (Socratic, Explain, Practice, Exam Prep)
// - Final mastery estimation and study summary

import 'package:flutter/material.dart';

import '../../../../core/design_system/gochano_colors.dart';
import '../../../../core/design_system/gochano_spacing.dart';
import '../../../../core/design_system/gochano_typography.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../services/api_service.dart';
import '../../../../shared/widgets/gochano_controls.dart';
import '../../../../shared/widgets/gochano_surfaces.dart';
import '../ai/ziku_markdown_text.dart';

typedef TutorStartSessionFn = Future<Map<String, dynamic>> Function({
  required String subject,
  required String topic,
  String? concept,
  String mode,
});

typedef TutorRespondFn = Future<Map<String, dynamic>> Function({
  required String sessionId,
  required String response,
});

typedef TutorRequestHintFn = Future<Map<String, dynamic>> Function({
  required String sessionId,
});

typedef TutorSwitchModeFn = Future<Map<String, dynamic>> Function({
  required String sessionId,
  required String mode,
});

typedef TutorCompleteSessionFn = Future<Map<String, dynamic>> Function({
  required String sessionId,
});

enum _DialogueType {
  question,
  studentAnswer,
  evaluation,
  hint,
  explanation,
  summary,
}

class _DialogueMessage {
  _DialogueMessage({
    required this.type,
    required this.text,
    this.metadata,
  });

  final _DialogueType type;
  final String text;
  final Map<String, dynamic>? metadata;
}

class ZikuTutorScreen extends StatefulWidget {
  const ZikuTutorScreen({
    super.key,
    this.initialSubject = 'Physics',
    this.initialTopic = 'Optics',
    this.initialConcept,
    this.initialMode = 'socratic',
    this.materialId,
    String? subject,
    String? topic,
    this.startSessionFn,
    this.respondFn,
    this.hintFn,
    this.switchModeFn,
    this.completeFn,
  })  : _paramSubject = subject,
        _paramTopic = topic;

  final String initialSubject;
  final String initialTopic;
  final String? initialConcept;
  final String initialMode;
  final String? materialId;
  final String? _paramSubject;
  final String? _paramTopic;

  final Function? startSessionFn;
  final TutorRespondFn? respondFn;
  final TutorRequestHintFn? hintFn;
  final TutorSwitchModeFn? switchModeFn;
  final TutorCompleteSessionFn? completeFn;

  @override
  State<ZikuTutorScreen> createState() => _ZikuTutorScreenState();
}

class _ZikuTutorScreenState extends State<ZikuTutorScreen> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  String? _sessionId;
  late String _currentMode;
  late String _subject;
  late String _topic;
  String? _concept;

  bool _loading = false;
  bool _submitting = false;
  bool _completed = false;
  String? _error;

  int _step = 1;
  int _hintsUsed = 0;
  double _understandingLevel = 0.0;
  double _masteryScore = 0.0;
  String? _masteryBand;

  final List<_DialogueMessage> _messages = [];

  Future<Map<String, dynamic>> _callStartSession({
    required String subject,
    required String topic,
    String? concept,
    required String mode,
    String? materialId,
  }) async {
    if (widget.startSessionFn != null) {
      final fn = widget.startSessionFn!;
      try {
        final dynamic res = await (fn as dynamic)(
          subject: subject,
          topic: topic,
          concept: concept,
          mode: mode,
          materialId: materialId,
        );
        return res as Map<String, dynamic>;
      } catch (_) {
        final dynamic res = await (fn as dynamic)(
          subject: subject,
          topic: topic,
          concept: concept,
          mode: mode,
        );
        return res as Map<String, dynamic>;
      }
    }
    return ApiService.tutorStartSession(
      subject: subject,
      topic: topic,
      concept: concept,
      mode: mode,
      materialId: materialId,
    );
  }

  TutorRespondFn get _respondFn =>
      widget.respondFn ?? ApiService.tutorRespond;
  TutorRequestHintFn get _hintFn =>
      widget.hintFn ?? ApiService.tutorRequestHint;
  TutorSwitchModeFn get _switchFn =>
      widget.switchModeFn ?? ApiService.tutorSwitchMode;
  TutorCompleteSessionFn get _completeFn =>
      widget.completeFn ?? ApiService.tutorCompleteSession;

  @override
  void initState() {
    super.initState();
    _currentMode = widget.initialMode;
    _subject = widget._paramSubject ?? widget.initialSubject;
    _topic = widget._paramTopic ?? widget.initialTopic;
    _concept = widget.initialConcept;
    _initializeSession();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _initializeSession() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await _callStartSession(
        subject: _subject,
        topic: _topic,
        concept: _concept,
        mode: _currentMode,
        materialId: widget.materialId,
      );

      final sessionId = res['sessionId']?.toString() ?? '';
      final mode = res['mode']?.toString() ?? _currentMode;
      final step = (res['step'] as num?)?.toInt() ?? 1;
      final question = res['question']?.toString() ?? '';
      final underLevel = (res['understandingLevel'] as num?)?.toDouble() ?? 0.0;
      final mastery = (res['masteryScore'] as num?)?.toDouble() ?? 0.0;

      if (!mounted) return;

      setState(() {
        _sessionId = sessionId;
        _currentMode = mode;
        _step = step;
        _understandingLevel = underLevel;
        _masteryScore = mastery;
        _loading = false;
        if (question.isNotEmpty) {
          _messages.add(
            _DialogueMessage(
              type: _DialogueType.question,
              text: question,
            ),
          );
        }
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _submitAnswer() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _sessionId == null || _submitting || _completed) return;

    _inputController.clear();
    setState(() {
      _submitting = true;
      _messages.add(
        _DialogueMessage(
          type: _DialogueType.studentAnswer,
          text: text,
        ),
      );
    });
    _scrollToBottom();

    try {
      final res = await _respondFn(
        sessionId: _sessionId!,
        response: text,
      );

      final mode = res['mode']?.toString() ?? _currentMode;
      final step = (res['step'] as num?)?.toInt() ?? _step;
      final underLevel = (res['understandingLevel'] as num?)?.toDouble() ?? _understandingLevel;
      final mastery = (res['masteryScore'] as num?)?.toDouble() ?? _masteryScore;
      final hints = (res['hintsUsed'] as num?)?.toInt() ?? _hintsUsed;
      final isCompleted = res['completed'] == true;
      final directExp = res['directExplanation']?.toString();
      final nextQ = res['nextQuestion']?.toString();

      Map<String, dynamic>? evalData;
      if (res['evaluation'] is Map) {
        evalData = Map<String, dynamic>.from(res['evaluation'] as Map);
      }

      if (!mounted) return;

      setState(() {
        _currentMode = mode;
        _step = step;
        _understandingLevel = underLevel;
        _masteryScore = mastery;
        _hintsUsed = hints;
        _completed = isCompleted;

        // Feedback / Evaluation
        if (evalData != null && evalData['feedback'] != null && evalData['feedback'].toString().isNotEmpty) {
          _messages.add(
            _DialogueMessage(
              type: _DialogueType.evaluation,
              text: evalData['feedback'].toString(),
              metadata: evalData,
            ),
          );
        }

        // Direct explanation if student requested escape
        if (directExp != null && directExp.isNotEmpty) {
          _messages.add(
            _DialogueMessage(
              type: _DialogueType.explanation,
              text: directExp,
            ),
          );
        }

        // Next question
        if (nextQ != null && nextQ.isNotEmpty && !isCompleted) {
          _messages.add(
            _DialogueMessage(
              type: _DialogueType.question,
              text: nextQ,
            ),
          );
        }

        // Summary if completed
        if (isCompleted && res['summary'] is Map) {
          final summaryMap = Map<String, dynamic>.from(res['summary'] as Map);
          _messages.add(
            _DialogueMessage(
              type: _DialogueType.summary,
              text: summaryMap['overview']?.toString() ?? 'Session Complete',
              metadata: summaryMap,
            ),
          );
        }

        _submitting = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _onHint() async {
    if (_sessionId == null || _submitting || _completed) return;

    setState(() => _submitting = true);
    try {
      final res = await _hintFn(sessionId: _sessionId!);
      final hint = res['hint']?.toString() ?? '';
      final hintLevel = (res['hintLevel'] as num?)?.toInt() ?? 1;
      final hints = (res['hintsUsed'] as num?)?.toInt() ?? (_hintsUsed + 1);

      if (!mounted) return;
      setState(() {
        _hintsUsed = hints;
        _submitting = false;
        if (hint.isNotEmpty) {
          _messages.add(
            _DialogueMessage(
              type: _DialogueType.hint,
              text: hint,
              metadata: {'hintLevel': hintLevel},
            ),
          );
        }
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _onSwitchMode(String newMode) async {
    if (_sessionId == null || _submitting || _currentMode == newMode) return;

    setState(() => _submitting = true);
    try {
      final res = await _switchFn(
        sessionId: _sessionId!,
        mode: newMode,
      );

      final mode = res['mode']?.toString() ?? newMode;
      final prompt = res['prompt']?.toString() ?? '';

      if (!mounted) return;
      setState(() {
        _currentMode = mode;
        _submitting = false;
        if (prompt.isNotEmpty) {
          _messages.add(
            _DialogueMessage(
              type: mode == 'explain'
                  ? _DialogueType.explanation
                  : _DialogueType.question,
              text: prompt,
            ),
          );
        }
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _onCompleteSession() async {
    if (_sessionId == null || _submitting || _completed) return;

    setState(() => _submitting = true);
    try {
      final res = await _completeFn(sessionId: _sessionId!);
      final isCompleted = res['status'] == 'completed';
      final mastery = (res['masteryScore'] as num?)?.toDouble() ?? _masteryScore;
      final band = res['masteryBand']?.toString();

      Map<String, dynamic>? summaryMap;
      if (res['summary'] is Map) {
        summaryMap = Map<String, dynamic>.from(res['summary'] as Map);
      }

      if (!mounted) return;
      setState(() {
        _completed = isCompleted;
        _masteryScore = mastery;
        _masteryBand = band;
        _submitting = false;

        if (summaryMap != null) {
          _messages.add(
            _DialogueMessage(
              type: _DialogueType.summary,
              text: summaryMap['overview']?.toString() ?? 'Session Complete',
              metadata: summaryMap,
            ),
          );
        }
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.toString();
      });
    }
  }

  String _modeLabel(String mode) {
    switch (mode) {
      case 'explain':
        return GochanoLanguage.text('Direct Explanation', 'সরাসরি ব্যাখ্যা');
      case 'practice':
        return GochanoLanguage.text('Practice MCQ', 'অনুশীলন');
      case 'exam_prep':
        return GochanoLanguage.text('Exam Prep', 'পরীক্ষা প্রস্তুতি');
      case 'socratic':
      default:
        return GochanoLanguage.text('Socratic Tutor', 'সক্রেটিক টিউটর');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return GochanoScaffold(
      padBody: false,
      appBar: GochanoAppBar(
        title: GochanoLanguage.text('Ziku Tutor', 'জিকু টিউটর'),
        subtitle: '$_subject • $_topic',
        actions: [
          PopupMenuButton<String>(
            key: const ValueKey('tutor_mode_dropdown'),
            tooltip: GochanoLanguage.text('Change mode', 'মোড পরিবর্তন'),
            icon: Icon(Icons.tune_rounded, color: colors.textSecondary),
            onSelected: _onSwitchMode,
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'socratic',
                child: Text(GochanoLanguage.text('Socratic Mode', 'সক্রেটিক মোড')),
              ),
              PopupMenuItem(
                value: 'explain',
                child: Text(GochanoLanguage.text('Direct Explanation', 'সরাসরি ব্যাখ্যা')),
              ),
              PopupMenuItem(
                value: 'practice',
                child: Text(GochanoLanguage.text('Practice Mode', 'অনুশীলন মোড')),
              ),
              PopupMenuItem(
                value: 'exam_prep',
                child: Text(GochanoLanguage.text('Exam Prep', 'পরীক্ষা প্রস্তুতি')),
              ),
            ],
          ),
          if (!_completed)
            TextButton(
              key: const ValueKey('tutor_finish_button'),
              onPressed: _submitting ? null : _onCompleteSession,
              child: Text(
                GochanoLanguage.text('Finish', 'সমাপ্ত'),
                style: type.button.copyWith(color: colors.brand),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildProgressBanner(colors, type),
            if (_error != null) _buildErrorBanner(colors, type),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _buildDialogueStream(colors, type),
            ),
            if (!_completed) ...[
              _buildQuickActions(colors, type),
              _buildInputArea(colors, type),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildProgressBanner(GochanoColors colors, GochanoTypography type) {
    final pct = (_understandingLevel * 100).clamp(0, 100).toInt();

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: GochanoSpacing.md,
        vertical: GochanoSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          bottom: BorderSide(color: colors.border.withValues(alpha: 0.5)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.brandSoft,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _modeLabel(_currentMode),
                  style: type.caption.copyWith(
                    color: colors.brand,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: GochanoSpacing.sm),
              Text(
                '${GochanoLanguage.text("Step", "ধাপ")} $_step',
                style: type.caption.copyWith(color: colors.textSecondary),
              ),
              const Spacer(),
              if (_hintsUsed > 0) ...[
                Icon(Icons.lightbulb_outline, size: 14, color: colors.warning),
                const SizedBox(width: 4),
                Text(
                  '$_hintsUsed ${GochanoLanguage.text("hints", "ইঙ্গিত")}',
                  style: type.caption.copyWith(color: colors.textSecondary),
                ),
                const SizedBox(width: GochanoSpacing.sm),
              ],
              Text(
                '$pct% ${GochanoLanguage.text("Understanding", "ধারণা")}',
                key: const ValueKey('tutor_progress_text'),
                style: type.caption.copyWith(
                  fontWeight: FontWeight.bold,
                  color: pct >= 70 ? colors.success : colors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              key: const ValueKey('tutor_progress_bar'),
              value: _understandingLevel.clamp(0.05, 1.0),
              minHeight: 4,
              backgroundColor: colors.border.withValues(alpha: 0.3),
              valueColor: AlwaysStoppedAnimation<Color>(
                pct >= 70 ? colors.success : colors.brand,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(GochanoColors colors, GochanoTypography type) {
    return Container(
      padding: const EdgeInsets.all(GochanoSpacing.sm),
      color: colors.errorSoft,
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: colors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _error!,
              style: type.caption.copyWith(color: colors.error),
            ),
          ),
          IconButton(
            tooltip: GochanoLanguage.text('Dismiss error', 'বাতিল করুন'),
            icon: const Icon(Icons.close, size: 16),
            onPressed: () => setState(() => _error = null),
          ),

        ],
      ),
    );
  }

  Widget _buildDialogueStream(GochanoColors colors, GochanoTypography type) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(GochanoSpacing.md),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final msg = _messages[index];
        switch (msg.type) {
          case _DialogueType.question:
            return _buildQuestionCard(msg.text, colors, type);
          case _DialogueType.studentAnswer:
            return _buildStudentAnswerBubble(msg.text, colors, type);
          case _DialogueType.evaluation:
            return _buildEvaluationCard(msg.text, msg.metadata, colors, type);
          case _DialogueType.hint:
            return _buildHintCard(msg.text, msg.metadata, colors, type);
          case _DialogueType.explanation:
            return _buildExplanationCard(msg.text, colors, type);
          case _DialogueType.summary:
            return _buildSummaryCard(msg.text, msg.metadata, colors, type);
        }
      },
    );
  }

  Widget _buildQuestionCard(String text, GochanoColors colors, GochanoTypography type) {
    return Padding(
      padding: const EdgeInsets.only(bottom: GochanoSpacing.md),
      child: AppCard(
        accent: colors.brand,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: colors.brandSoft,
                  child: Icon(Icons.school, size: 14, color: colors.brand),
                ),
                const SizedBox(width: 8),
                Text(
                  'Ziku AI Tutor',
                  style: type.cardHeading.copyWith(color: colors.brand),
                ),
              ],
            ),
            const SizedBox(height: GochanoSpacing.xs),
            ZikuMarkdownText(
              text,
              key: const ValueKey('tutor_question_text'),
            ),

          ],
        ),
      ),
    );
  }

  Widget _buildStudentAnswerBubble(String text, GochanoColors colors, GochanoTypography type) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(
          bottom: GochanoSpacing.md,
          left: 48,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: GochanoSpacing.md,
          vertical: GochanoSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: colors.brand.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.brand.withValues(alpha: 0.3)),
        ),
        child: Text(
          text,
          style: type.body,
        ),
      ),
    );
  }

  Widget _buildEvaluationCard(
    String feedback,
    Map<String, dynamic>? meta,
    GochanoColors colors,
    GochanoTypography type,
  ) {
    final misconception = meta?['misconception']?.toString();
    final missingList = (meta?['missingConcepts'] as List?) ?? const [];

    return Padding(
      padding: const EdgeInsets.only(bottom: GochanoSpacing.md),
      child: AppCard(
        accent: colors.info,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.psychology_outlined, size: 16, color: colors.info),
                const SizedBox(width: 6),
                Text(
                  GochanoLanguage.text('Feedback & Evaluation', 'মতামত ও মূল্যায়ন'),
                  style: type.cardHeading.copyWith(color: colors.info),
                ),
              ],
            ),
            const SizedBox(height: GochanoSpacing.xs),
            ZikuMarkdownText(feedback),
            if (misconception != null && misconception.isNotEmpty) ...[
              const SizedBox(height: GochanoSpacing.xs),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colors.warningSoft,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 16, color: colors.warning),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${GochanoLanguage.text("Misconception detected:", "ভুল ধারণা:")} $misconception',
                        style: type.caption.copyWith(color: colors.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (missingList.isNotEmpty) ...[
              const SizedBox(height: GochanoSpacing.xs),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final item in missingList)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: colors.surfaceVariant,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: colors.border),
                      ),
                      child: Text(
                        item.toString(),
                        style: type.caption.copyWith(color: colors.textSecondary),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHintCard(
    String hintText,
    Map<String, dynamic>? meta,
    GochanoColors colors,
    GochanoTypography type,
  ) {
    final level = meta?['hintLevel'] ?? 1;

    return Padding(
      padding: const EdgeInsets.only(bottom: GochanoSpacing.md),
      child: AppCard(
        key: const ValueKey('tutor_hint_card'),
        accent: colors.warning,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lightbulb, size: 18, color: colors.warning),
                const SizedBox(width: 8),
                Text(
                  '${GochanoLanguage.text("Hint", "ইঙ্গিত")} $level',
                  style: type.cardHeading.copyWith(color: colors.warning),
                ),
              ],
            ),
            const SizedBox(height: GochanoSpacing.xs),
            ZikuMarkdownText(hintText),
          ],
        ),
      ),
    );
  }

  Widget _buildExplanationCard(
    String explanation,
    GochanoColors colors,
    GochanoTypography type,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: GochanoSpacing.md),
      child: AppCard(
        key: const ValueKey('tutor_explanation_card'),
        accent: colors.study,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.menu_book_rounded, size: 18, color: colors.study),
                const SizedBox(width: 8),
                Text(
                  GochanoLanguage.text('Concept Explanation', 'ধারণার বিশদ ব্যাখ্যা'),
                  style: type.cardHeading.copyWith(color: colors.study),
                ),
              ],
            ),
            const SizedBox(height: GochanoSpacing.xs),
            ZikuMarkdownText(explanation),
          ],
        ),
      ),
    );
  }


  Widget _buildSummaryCard(
    String overview,
    Map<String, dynamic>? summary,
    GochanoColors colors,
    GochanoTypography type,
  ) {
    final mastered = (summary?['conceptsMastered'] as List?) ?? const [];
    final review = (summary?['conceptsToReview'] as List?) ?? const [];
    final nextAction = summary?['recommendedNextAction']?.toString();
    final band = _masteryBand ?? summary?['masteryBand']?.toString() ?? 'Medium';

    return Padding(
      padding: const EdgeInsets.only(bottom: GochanoSpacing.lg),
      child: AppCard(
        key: const ValueKey('tutor_summary_card'),
        accent: colors.success,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.workspace_premium_rounded, size: 22, color: colors.success),
                const SizedBox(width: 8),
                Text(
                  GochanoLanguage.text('Session Complete', 'টিউটরিং সম্পন্ন'),
                  style: type.sectionHeading.copyWith(color: colors.success),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: colors.successSoft,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    band,
                    style: type.caption.copyWith(
                      color: colors.success,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: GochanoSpacing.sm),
            Text(overview, style: type.body),
            if (mastered.isNotEmpty) ...[
              const SizedBox(height: GochanoSpacing.sm),
              Text(
                '✓ ${GochanoLanguage.text("Mastered Concepts:", "যেসব ধারণা আয়ত্ত হয়েছে:")}',
                style: type.caption.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colors.success,
                ),
              ),
              const SizedBox(height: 4),
              for (final c in mastered)
                Padding(
                  padding: const EdgeInsets.only(left: 12, bottom: 2),
                  child: Text('• $c', style: type.bodySecondary),
                ),
            ],
            if (review.isNotEmpty) ...[
              const SizedBox(height: GochanoSpacing.sm),
              Text(
                '! ${GochanoLanguage.text("Needs Further Review:", "পুনরায় পড়া প্রয়োজন:")}',
                style: type.caption.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colors.warning,
                ),
              ),
              const SizedBox(height: 4),
              for (final c in review)
                Padding(
                  padding: const EdgeInsets.only(left: 12, bottom: 2),
                  child: Text('• $c', style: type.bodySecondary),
                ),
            ],
            if (nextAction != null && nextAction.isNotEmpty) ...[
              const SizedBox(height: GochanoSpacing.sm),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colors.surfaceVariant,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(Icons.next_plan_outlined, size: 16, color: colors.brand),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${GochanoLanguage.text("Next Action:", "পরবর্তী করণীয়:")} $nextAction',
                        style: type.caption.copyWith(color: colors.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: GochanoSpacing.md),
            PrimaryButton(
              key: const ValueKey('tutor_return_button'),
              label: GochanoLanguage.text('Return to Study', 'পড়াশোনায় ফিরুন'),
              icon: Icons.check,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions(GochanoColors colors, GochanoTypography type) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: GochanoSpacing.md,
        vertical: 4,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            SecondaryButton(
              key: const ValueKey('tutor_hint_button'),
              label: GochanoLanguage.text('💡 Hint', '💡 ইঙ্গিত'),
              expand: false,
              onPressed: _submitting ? null : _onHint,
            ),
            const SizedBox(width: 8),
            SecondaryButton(
              key: const ValueKey('tutor_explain_button'),
              label: GochanoLanguage.text('📖 Explain Instead', '📖 বুঝিয়ে দাও'),
              expand: false,
              onPressed: _submitting
                  ? null
                  : () => _onSwitchMode('explain'),
            ),
            const SizedBox(width: 8),
            SecondaryButton(
              key: const ValueKey('tutor_practice_button'),
              label: GochanoLanguage.text('🎯 Practice', '🎯 অনুশীলন'),
              expand: false,
              onPressed: _submitting
                  ? null
                  : () => _onSwitchMode('practice'),
            ),

          ],
        ),
      ),
    );
  }

  Widget _buildInputArea(GochanoColors colors, GochanoTypography type) {
    return Container(
      padding: const EdgeInsets.all(GochanoSpacing.sm),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          top: BorderSide(color: colors.border.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              key: const ValueKey('tutor_input_field'),
              controller: _inputController,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _submitAnswer(),
              decoration: InputDecoration(
                hintText: GochanoLanguage.text(
                  'Write your reasoning or answer...',
                  'তোমার ধারণা বা উত্তর লেখো...',
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                filled: true,
                fillColor: colors.surfaceVariant,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(color: colors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(color: colors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(color: colors.brand, width: 1.5),
                ),
              ),
            ),
          ),
          const SizedBox(width: GochanoSpacing.xs),
          IconButton(
            key: const ValueKey('tutor_send_button'),
            tooltip: GochanoLanguage.text('Send response', 'উত্তর পাঠান'),
            icon: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(Icons.send_rounded, color: colors.brand),
            onPressed: _submitting ? null : _submitAnswer,
          ),

        ],
      ),
    );
  }
}
