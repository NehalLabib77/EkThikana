// Phase 3 — the result screen: what the paper just proved.
//
// Everything here comes from the server's analysis payload: the score, the
// time verdict, the topics that failed, every wrong answer with its type
// and its spaced-repetition review dates, the live Academic Health read,
// and Ziku's three-day plan. Nothing is recomputed on the phone - the same
// numbers drive Academic Health and the mistake memory, so the three
// screens can never disagree.
//
// The AI paragraph is optional by design: it is generated on demand and
// cached on the result, so opening this screen twice never spends quota.
//
// Phase 6 addition: when a submit payload arrives on the real backend path,
// the screen kicks one background `coachRecalculate()` so the coach and the
// academic health profile rebuild from this attempt — the same contract the
// quiz result screen uses. It is fire-and-forget: a failure leaves the
// cached profile to expire on its own.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/design_system/gochano_colors.dart';
import '../../../core/design_system/gochano_spacing.dart';
import '../../../core/design_system/gochano_typography.dart';
import '../../../core/localization/gochano_language.dart';
import '../../../core/page_route.dart';
import '../../../features/profile/presentation/academic_health_screen.dart';
import '../../../features/profile/presentation/learning_brain_screen.dart';
import '../../../features/study/presentation/ai/ai_assistant_screen.dart';
import '../../../services/api_service.dart';
import '../../../shared/states/gochano_states.dart';
import '../../../shared/widgets/gochano_controls.dart';
import '../../../shared/widgets/gochano_surfaces.dart';
import '../exam_models.dart';
import '../exam_ui.dart';

class ExamResultScreen extends StatefulWidget {
  const ExamResultScreen({
    super.key,
    required this.examId,
    this.attemptId = '',
    this.result,
    this.analysisFn,
    this.autoSubmitted = false,
  });

  final String examId;
  final String attemptId;

  /// The submit response, so the score appears before the analysis call
  /// returns. The analysis payload then replaces it wholesale.
  final Map<String, dynamic>? result;
  final ExamAnalysisFn? analysisFn;
  final bool autoSubmitted;

  @override
  State<ExamResultScreen> createState() => _ExamResultScreenState();
}

class _ExamResultScreenState extends State<ExamResultScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _aiBusy = false;
  String? _error;

  ExamAnalysisFn get _analysis =>
      widget.analysisFn ?? ApiService.getExamAnalysis;

  bool _coachFired = false;

  @override
  void initState() {
    super.initState();
    if (widget.result != null) {
      _data = Map<String, dynamic>.from(widget.result!);
      _loading = false;
      _recalcCoach();
    }
    _load();
  }

  /// Spec 6.8 — this attempt just changed the mistake memory and the
  /// academic health, so rebuild the coach's cached profile in the
  /// background. Real backend only, at most once per screen, errors
  /// ignored (see the quiz result screen for the same pattern).
  void _recalcCoach() {
    if (_coachFired || widget.analysisFn != null) return;
    _coachFired = true;
    unawaited(
      ApiService.coachRecalculate().catchError(
        (Object _) => <String, dynamic>{},
      ),
    );
  }

  Future<void> _load({bool withAi = false}) async {
    if (withAi) setState(() => _aiBusy = true);
    try {
      final body = await _analysis(
        widget.examId,
        attemptId: widget.attemptId.isEmpty ? null : widget.attemptId,
        withAi: withAi,
      );
      if (!mounted) return;
      setState(() {
        _data = body;
        _loading = false;
        _aiBusy = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _aiBusy = false;
        if (_data == null) _error = friendlyErrorMessage(error);
      });
    }
  }

  Future<void> _askZiku() async {
    final prompt = _str('zikuPrompt');
    if (prompt.isEmpty) return;
    await Navigator.of(context).push(
      GochanoRoute.to(
        builder: (_) => AiAssistantScreen(prefilledQuestion: prompt),
      ),
    );
  }

  void _openHealth() {
    Navigator.of(context).push(
      GochanoRoute.to(builder: (_) => const AcademicHealthScreen()),
    );
  }

  void _openBrain() {
    Navigator.of(context).push(
      GochanoRoute.to(builder: (_) => const LearningBrainScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;

    if (data == null) {
      return GochanoScaffold(
        appBar: GochanoAppBar(
          title: GochanoLanguage.text('Result', 'ফলাফল'),
        ),
        body: _error == null
            ? examLoading(
                _loading
                    ? GochanoLanguage.text(
                        'Scoring your paper…',
                        'প্রশ্নপত্র মূল্যায়ন হচ্ছে…',
                      )
                    : GochanoLanguage.text(
                        'Loading your result…',
                        'ফলাফল লোড হচ্ছে…',
                      ),
              )
            : Column(
                children: [
                  examErrorBox(context, _error!),
                  const SizedBox(height: GochanoSpacing.md),
                  SecondaryButton(
                    label: GochanoLanguage.text('Try again', 'আবার চেষ্টা করুন'),
                    onPressed: () => _load(),
                  ),
                ],
              ),
      );
    }

    final type = context.type;
    final colors = context.colors;
    final score = examDouble(data['score']);
    final total = examDouble(data['totalMarks']);
    final percentage = examDouble(data['percentage']);
    final accuracy = examDouble(data['accuracy']);
    final timeLabel = '${data['timeManagementLabel'] ?? ''}';
    final tone = _timeTone('${data['timeManagement'] ?? ''}');

    return GochanoScaffold(
      appBar: GochanoAppBar(
        title: GochanoLanguage.text('Result', 'ফলাফল'),
        subtitle: _str('subject').isEmpty ? null : _str('subject'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          if (widget.autoSubmitted) ...[
            examErrorBox(
              context,
              GochanoLanguage.text(
                'Time ran out - your answers were submitted automatically.',
                'সময় শেষ - আপনার উত্তরগুলো স্বয়ংক্রিয়ভাবে জমা হয়েছে।',
              ),
            ),
            const SizedBox(height: GochanoSpacing.md),
          ],
          AppCard(
            accent: tone,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${score.round()} / ${total.round()}',
                  style: type.display.copyWith(color: tone),
                ),
                const SizedBox(height: GochanoSpacing.xs),
                GochanoBadge(
                  label: timeLabel.isEmpty
                      ? GochanoLanguage.text('Scored', 'ফলাফল')
                      : timeLabel,
                  tone: timeLabel == 'Good'
                      ? GochanoBadgeTone.success
                      : timeLabel == 'Needs work'
                          ? GochanoBadgeTone.error
                          : GochanoBadgeTone.warning,
                ),
                const SizedBox(height: GochanoSpacing.sm),
                ExamStatLine(
                  label: GochanoLanguage.text('Percentage', 'শতাংশ'),
                  value: '${percentage.round()}%',
                ),
                ExamStatLine(
                  label: GochanoLanguage.text('Accuracy', 'নির্ভুলতা'),
                  value: '${accuracy.round()}%',
                  tone: colors.success,
                ),
                ExamStatLine(
                  label: GochanoLanguage.text('Correct', 'সঠিক'),
                  value: '${examInt(data['correctCount'])}',
                  tone: colors.success,
                ),
                ExamStatLine(
                  label: GochanoLanguage.text('Wrong', 'ভুল'),
                  value: '${examInt(data['wrongCount'])}',
                  tone: colors.error,
                ),
                ExamStatLine(
                  label: GochanoLanguage.text('Skipped', 'বাদ'),
                  value: '${examInt(data['skippedCount'])}',
                  tone: colors.textSecondary,
                ),
                ExamStatLine(
                  label: GochanoLanguage.text('Time used', 'ব্যবহৃত সময়'),
                  value: examDurationLabel(examInt(data['timeSpentSeconds'])),
                ),
                if ('${data['timeManagementDetail'] ?? ''}'.isNotEmpty) ...[
                  const SizedBox(height: GochanoSpacing.xs),
                  Text(
                    '${data['timeManagementDetail']}',
                    style: type.caption,
                  ),
                ],
              ],
            ),
          ),
          SectionHeader(
            title: GochanoLanguage.text('Weak topics', 'দুর্বল টপিক'),
          ),
          ..._weakTopicRows(context),
          SectionHeader(
            title: GochanoLanguage.text('Mistakes saved', 'সংরক্ষিত ভুল'),
          ),
          ..._mistakeSection(context),
          SectionHeader(
            title: GochanoLanguage.text("Ziku's 3-day plan", 'জিকুর ৩ দিনের পরিকল্পনা'),
          ),
          ..._zikuSection(context),
          SectionHeader(
            title: GochanoLanguage.text('Academic health', 'একাডেমিক হেলথ'),
          ),
          ..._healthSection(context),
          const SizedBox(height: GochanoSpacing.md),
          PrimaryButton(
            label: GochanoLanguage.text('Ask Ziku', 'জিকুকে জিজ্ঞাসা'),
            icon: Icons.auto_awesome_rounded,
            onPressed: _askZiku,
          ),
          const SizedBox(height: GochanoSpacing.sm),
          SecondaryButton(
            label: GochanoLanguage.text(
              'Open Academic Health',
              'একাডেমিক হেলথ খুলুন',
            ),
            icon: Icons.favorite_outline_rounded,
            onPressed: _openHealth,
          ),
          const SizedBox(height: GochanoSpacing.sm),
          SecondaryButton(
            label: GochanoLanguage.text(
              'Open Learning Brain',
              'লার্নিং ব্রেইন খুলুন',
            ),
            icon: Icons.psychology_rounded,
            onPressed: _openBrain,
          ),
          const SizedBox(height: GochanoSpacing.xl),
        ],
      ),
    );
  }

  List<Widget> _weakTopicRows(BuildContext context) {
    final details = examMapList(_data?['weakTopicDetails']);
    if (details.isEmpty) {
      return [
        AppCard(
          child: Text(
            GochanoLanguage.text(
              'No weak topic in this paper - keep the streak going.',
              'এই প্রশ্নপত্রে কোনো দুর্বল টপিক নেই - ভালো চলছে।',
            ),
            style: context.type.bodySecondary,
          ),
        ),
      ];
    }

    return [
      for (final row in details)
        Padding(
          padding: const EdgeInsets.only(bottom: GochanoSpacing.xs),
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${row['topic'] ?? ''}',
                        style: context.type.cardHeading,
                      ),
                    ),
                    GochanoBadge(
                      label: '${examInt(row['accuracy'])}%',
                      tone: examInt(row['accuracy']) < 40
                          ? GochanoBadgeTone.error
                          : GochanoBadgeTone.warning,
                    ),
                  ],
                ),
                const SizedBox(height: GochanoSpacing.xs),
                Text(
                  '${row['action'] ?? ''}',
                  style: context.type.bodySecondary,
                ),
              ],
            ),
          ),
        ),
    ];
  }

  List<Widget> _mistakeSection(BuildContext context) {
    final colors = context.colors;
    final saved = _asMap(_data?['mistakesSaved']);
    final types = examMapList(_data?['mistakeTypes']);
    final mistakes = examMapList(_data?['mistakes']);
    final pending = examInt(saved['pendingAnalysis']);
    final repeat = examInt(saved['repeated']);

    if (examInt(_data?['mistakeCount']) == 0) {
      return [
        AppCard(
          child: Text(
            GochanoLanguage.text(
              'Zero mistakes - this paper is clean.',
              'কোনো ভুল নেই - দারুণ হয়েছে।',
            ),
            style: context.type.bodySecondary,
          ),
        ),
      ];
    }

    return [
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: GochanoSpacing.xs,
              runSpacing: GochanoSpacing.xs,
              children: [
                for (final row in types)
                  GochanoBadge(
                    label: '${row['label'] ?? row['type'] ?? ''} · ${examInt(row['count'])}',
                    tone: GochanoBadgeTone.neutral,
                  ),
              ],
            ),
            const SizedBox(height: GochanoSpacing.sm),
            ExamStatLine(
              label: GochanoLanguage.text('Saved to mistake memory', 'ভুলের স্মৃতিতে সংরক্ষিত'),
              value: '${examInt(saved['saved'])}',
              tone: colors.success,
            ),
            ExamStatLine(
              label: GochanoLanguage.text('New mistakes', 'নতুন ভুল'),
              value: '${examInt(saved['new'])}',
            ),
            ExamStatLine(
              label: GochanoLanguage.text('Repeated mistakes', 'পুনরাবৃত্ত ভুল'),
              value: '$repeat',
              tone: repeat > 0 ? colors.error : null,
            ),
            if (pending > 0)
              Text(
                GochanoLanguage.text(
                  '$pending mistakes still waiting for AI analysis.',
                  '$pending টি ভুলের বিশ্লেষণ বাকি আছে।',
                ),
                style: context.type.caption,
              ),
          ],
        ),
      ),
      const SizedBox(height: GochanoSpacing.sm),
      for (final row in mistakes.take(6))
        Padding(
          padding: const EdgeInsets.only(bottom: GochanoSpacing.xs),
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${row['question'] ?? ''}',
                  style: context.type.body,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: GochanoSpacing.xs),
                ExamStatLine(
                  label: GochanoLanguage.text('Your answer', 'আপনার উত্তর'),
                  value: '${row['userAnswer'] ?? ''}'.isEmpty
                      ? GochanoLanguage.text('Skipped', 'বাদ')
                      : '${row['userAnswer']}',
                  tone: colors.error,
                ),
                ExamStatLine(
                  label: GochanoLanguage.text('Correct answer', 'সঠিক উত্তর'),
                  value: '${row['correctAnswer'] ?? ''}',
                  tone: colors.success,
                ),
                if ('${row['explanation'] ?? ''}'.isNotEmpty) ...[
                  const SizedBox(height: GochanoSpacing.xs),
                  Text('${row['explanation']}', style: context.type.bodySecondary),
                ],
                const SizedBox(height: GochanoSpacing.xs),
                Wrap(
                  spacing: GochanoSpacing.xs,
                  children: [
                    for (final date in _asStringList(row['reviewDates']))
                      GochanoBadge(
                        label: date,
                        tone: GochanoBadgeTone.info,
                        icon: Icons.event_repeat_rounded,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
    ];
  }

  List<Widget> _zikuSection(BuildContext context) {
    final plan = _asMap(_data?['zikuPlan']);
    final days = examMapList(plan['days']);
    final analysis = _str('zikuAnalysis');
    final hasAi = _data?['hasAiAnalysis'] == true;

    return [
      if (plan.isNotEmpty)
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if ('${plan['headline'] ?? ''}'.isNotEmpty) ...[
                Text('${plan['headline']}', style: context.type.cardHeading),
                const SizedBox(height: GochanoSpacing.sm),
              ],
              for (final day in days)
                ExamStatLine(
                  label: 'Day ${examInt(day['day'])}',
                  value: '${day['focus'] ?? ''}',
                ),
              if (examInt(plan['daysRemaining']) > 0)
                Text(
                  GochanoLanguage.text(
                    '${examInt(plan['daysRemaining'])} days to your exam.',
                    'পরীক্ষা আর ${examInt(plan['daysRemaining'])} দিন বাকি।',
                  ),
                  style: context.type.caption,
                ),
            ],
          ),
        ),
      const SizedBox(height: GochanoSpacing.sm),
      if (hasAi && analysis.isNotEmpty)
        AppCard(
          child: Text(analysis, style: context.type.body),
        )
      else if (_aiBusy)
        examLoading(
          GochanoLanguage.text('Ziku is writing your plan…', 'জিকু পরিকল্পনা লিখছে…'),
        )
      else
        SecondaryButton(
          label: GochanoLanguage.text(
            'Ask Ziku to analyse this paper',
            'জিকুকে এই প্রশ্নপত্র বিশ্লেষণ করতে বলুন',
          ),
          icon: Icons.auto_awesome_rounded,
          onPressed: () => _load(withAi: true),
        ),
    ];
  }

  List<Widget> _healthSection(BuildContext context) {
    final health = _asMap(_data?['health']);
    if (health.isEmpty) return const <Widget>[];

    return [
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExamStatLine(
              label: GochanoLanguage.text('Health score', 'হেলথ স্কোর'),
              value: '${examInt(health['score'])} / 100',
              tone: context.colors.info,
            ),
            if ('${health['understandingDetail'] ?? ''}'.isNotEmpty)
              ExamStatLine(
                label: GochanoLanguage.text('Understanding', 'বোঝাপড়া'),
                value: '${health['understandingDetail']}',
              ),
            if ('${health['examReadinessDetail'] ?? ''}'.isNotEmpty)
              ExamStatLine(
                label: GochanoLanguage.text('Exam readiness', 'পরীক্ষার প্রস্তুতি'),
                value: '${health['examReadinessDetail']}',
              ),
            if ('${health['headline'] ?? ''}'.isNotEmpty) ...[
              const SizedBox(height: GochanoSpacing.xs),
              Text('${health['headline']}', style: context.type.bodySecondary),
            ],
          ],
        ),
      ),
      const SizedBox(height: GochanoSpacing.sm),
    ];
  }

  Color _timeTone(String status) {
    final colors = context.colors;
    switch (status) {
      case 'good':
        return colors.success;
      case 'poor':
        return colors.error;
      default:
        return colors.warning;
    }
  }

  Map<String, dynamic> _asMap(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  String _str(String key) => '${_data?[key] ?? ''}';

  List<String> _asStringList(dynamic value) {
    if (value is! List) return const <String>[];
    return value.map((item) => '$item').toList();
  }
}
