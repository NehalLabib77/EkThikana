// Phase 1 — My Learning Brain (AI Mistake Memory).
//
// Everything a wrong answer turned into, on one screen: what is due for
// revision, what the student keeps missing, and which topics need work.
// Ziku's explanation is a field of the mistake record itself, so a takeaway
// never travels to a different page from the question that produced it.

import 'package:flutter/material.dart';

import '../../../core/design_system/gochano_art.dart';
import '../../../core/design_system/gochano_colors.dart';
import '../../../core/design_system/gochano_spacing.dart';
import '../../../core/design_system/gochano_typography.dart';
import '../../../core/localization/gochano_language.dart';
import '../../../services/api_service.dart';
import '../../../shared/widgets/ai_widgets.dart';
import '../../../shared/widgets/gochano_controls.dart';
import '../../../shared/widgets/gochano_surfaces.dart';

class LearningBrainScreen extends StatefulWidget {
  const LearningBrainScreen({super.key});

  @override
  State<LearningBrainScreen> createState() => _LearningBrainScreenState();
}

class _LearningBrainScreenState extends State<LearningBrainScreen> {
  Map<String, dynamic>? _brain;
  String _error = '';
  bool _loading = true;
  bool _busy = false;
  String _note = '';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final body = await ApiService.getLearningBrain();
      if (!mounted) return;
      setState(() {
        _brain = body;
        _loading = false;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _error = err.toString();
        _loading = false;
      });
    }
  }

  Future<void> _analyse() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = '';
      _note = '';
    });
    try {
      final result = await ApiService.analyzeMistakes();
      if (!mounted) return;
      final analysed = _asInt(result['analyzed']);
      setState(() {
        _busy = false;
        _note = analysed > 0
            ? GochanoLanguage.text(
                'Ziku explained $analysed mistakes.',
                'জিকু $analysed টি ভুল ব্যাখ্যা করেছে।',
              )
            : GochanoLanguage.text(
                'Nothing new to explain yet.',
                'নতুন কিছু ব্যাখ্যা করার নেই।',
              );
      });
      await _refresh();
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = err.toString();
      });
    }
  }

  Future<void> _markRevised(String mistakeId) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await ApiService.reviewMistake(mistakeId);
      if (!mounted) return;
      setState(() => _busy = false);
      await _refresh();
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = err.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GochanoScaffold(
      appBar: GochanoAppBar(
        title: GochanoLanguage.text('My Learning Brain', 'আমার লার্নিং ব্রেইন'),
        subtitle: GochanoLanguage.text(
          'Mistakes you are turning into marks',
          'ভুল থেকে নম্বর তৈরির পথ',
        ),
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_brain == null) {
      if (_loading) {
        return AiLoadingState(
          message: GochanoLanguage.text(
            'Reading your mistakes…',
            'আপনার ভুল পড়া হচ্ছে…',
          ),
        );
      }
      return Center(
        child: Padding(
          padding: GochanoSpacing.scrollBody,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AiErrorBanner(message: _error),
              const SizedBox(height: GochanoSpacing.sm),
              SecondaryButton(
                label: GochanoLanguage.text('Try again', 'আবার চেষ্টা করুন'),
                icon: Icons.refresh_rounded,
                onPressed: _refresh,
              ),
            ],
          ),
        ),
      );
    }

    final brain = _brain!;
    final total = _asInt(brain['totalMistakes']);
    if (total == 0) {
      return ListView(
        padding: GochanoSpacing.scrollBody,
        children: [
          if (_error.isNotEmpty) ...[
            AiErrorBanner(message: _error),
            const SizedBox(height: GochanoSpacing.sm),
          ],
          AiEmptyState(
            icon: Icons.psychology_alt_rounded,
            title: GochanoLanguage.text(
              'No mistakes recorded yet',
              'এখনো কোনো ভুল সংরক্ষিত হয়নি',
            ),
            message: GochanoLanguage.text(
              'Wrong answers from quizzes and rescued exams are saved here '
              'automatically, then explained by Ziku.',
              'কুইজ ও এক্সাম রেসকিউয় ভুল উত্তর এখানে স্বয়ংক্রিয়ভাবে সংরক্ষিত হয়, '
              'তারপর জিকু ব্যাখ্যা করে।',
            ),
          ),
        ],
      );
    }

    final pending = _asInt(brain['pendingAnalysis']);
    final due = _asList(brain['revisionDue']);
    final repeated = _asList(brain['repeatedMistakes']);
    final weakTopics = _asList(brain['weakTopics']);
    final subjects = _asList(brain['subjectBreakdown']);

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: GochanoSpacing.scrollBody,
        children: [
          if (_error.isNotEmpty) ...[
            AiErrorBanner(message: _error),
            const SizedBox(height: GochanoSpacing.sm),
          ],
          _stats(context, brain),
          if (pending > 0 || _note.isNotEmpty) ...[
            const SizedBox(height: GochanoSpacing.sm),
            _analysisBlock(context, pending: pending),
          ],
          if (due.isNotEmpty) ...[
            const SizedBox(height: GochanoSpacing.md),
            SectionHeader(
              title: GochanoLanguage.text(
                'Due for revision',
                'পুনরাবৃত্তির সময়',
              ),
              subtitle: GochanoLanguage.text(
                'Missed once already — clear these first',
                'একবার ভুল হয়েছে — আগে গুলো পরিষ্কার করুন',
              ),
            ),
            CardGroup(
              children: [
                for (final item in due)
                  _mistakeRow(context, item, showReview: true),
              ],
            ),
          ],
          if (weakTopics.isNotEmpty) ...[
            const SizedBox(height: GochanoSpacing.md),
            SectionHeader(
              title: GochanoLanguage.text(
                'Topics to strengthen',
                'শক্তিশালী করার টপিক',
              ),
              subtitle: GochanoLanguage.text(
                'From quiz mastery and recorded mistakes',
                'কুইজ দক্ষতা ও সংরক্ষিত ভুল থেকে',
              ),
            ),
            CardGroup(
              children: [
                for (final item in weakTopics) _weakTopicRow(context, item),
              ],
            ),
          ],
          if (repeated.isNotEmpty) ...[
            const SizedBox(height: GochanoSpacing.md),
            SectionHeader(
              title: GochanoLanguage.text('Repeated mistakes', 'পুনরাবৃত্ত ভুল'),
              subtitle: GochanoLanguage.text(
                'The same answer going wrong more than once',
                'একই উত্তর একাধিকবার ভুল হচ্ছে',
              ),
            ),
            CardGroup(
              children: [
                for (final item in repeated)
                  _mistakeRow(context, item, showReview: false),
              ],
            ),
          ],
          if (subjects.isNotEmpty) ...[
            const SizedBox(height: GochanoSpacing.md),
            SectionHeader(
              title: GochanoLanguage.text('By subject', 'বিষয় অনুযায়ী'),
            ),
            CardGroup(
              children: [
                for (final item in subjects)
                  GochanoListRow(
                    illustration: GochanoArt.subjectGeneric,
                    title: '${item['subjectId'] ?? ''}',
                    subtitle: GochanoLanguage.text(
                      '${_asInt(item['mistakes'])} mistakes · '
                      '${_asInt(item['occurrences'])} answers wrong',
                      '${_asInt(item['mistakes'])} ভুল',
                    ),
                    accent: context.colors.info,
                  ),
              ],
            ),
          ],
          const SizedBox(height: GochanoSpacing.lg),
        ],
      ),
    );
  }

  Widget _stats(BuildContext context, Map<String, dynamic> brain) {
    final colors = context.colors;

    return Row(
      children: [
        Expanded(
          child: StatCard(
            compact: true,
            label: GochanoLanguage.text('Remembered', 'মনে রাখা'),
            value: '${_asInt(brain['totalMistakes'])}',
            caption: GochanoLanguage.text(
              '${_asInt(brain['totalOccurrences'])} wrong answers',
              '${_asInt(brain['totalOccurrences'])} ভুল',
            ),
            icon: Icon(
              Icons.psychology_alt_rounded,
              size: 16,
              color: colors.brand,
            ),
            accent: colors.brand,
          ),
        ),
        const SizedBox(width: GochanoSpacing.sm),
        Expanded(
          child: StatCard(
            compact: true,
            label: GochanoLanguage.text('Repeated', 'পুনরাবৃত্ত'),
            value: '${_asInt(brain['repeatedCount'])}',
            icon: Icon(
              Icons.repeat_rounded,
              size: 16,
              color: colors.warning,
            ),
            accent: colors.warning,
          ),
        ),
        const SizedBox(width: GochanoSpacing.sm),
        Expanded(
          child: StatCard(
            compact: true,
            label: GochanoLanguage.text('Due today', 'আজ বাকি'),
            value: '${_asInt(brain['revisionDueCount'])}',
            icon: Icon(
              Icons.event_available_rounded,
              size: 16,
              color: colors.error,
            ),
            accent: colors.error,
          ),
        ),
      ],
    );
  }

  Widget _analysisBlock(BuildContext context, {required int pending}) {
    final colors = context.colors;

    return AppCard(
      accent: colors.ai,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _note.isNotEmpty
                ? _note
                : GochanoLanguage.text(
                    '$pending mistakes are waiting for an explanation.',
                    '$pending টি ভুল ব্যাখ্যার অপেক্ষায়।',
                  ),
            style: context.type.bodySecondary,
          ),
          const SizedBox(height: GochanoSpacing.sm),
          PrimaryButton(
            label: GochanoLanguage.text('Explain with Ziku', 'জিকু দিয়ে ব্যাখ্যা'),
            icon: Icons.auto_awesome_rounded,
            busy: _busy,
            busyLabel: GochanoLanguage.text('Explaining…', 'ব্যাখ্যা হচ্ছে…'),
            onPressed: pending > 0 ? _analyse : null,
          ),
        ],
      ),
    );
  }

  Widget _mistakeRow(
    BuildContext context,
    Map<String, dynamic> item, {
    required bool showReview,
  }) {
    final analysis = _asMapOrNull(item['analysis']);
    final conceptGap = analysis == null ? '' : '${analysis['conceptGap'] ?? ''}';
    final missed = _asInt(item['occurrences']);
    final metadata = <String>[
      GochanoLanguage.text('Missed $missed times', '$missed বার ভুল'),
      GochanoLanguage.text(
        'Next review ${item['nextReviewDate'] ?? ''}',
        'পরবর্তী ${item['nextReviewDate'] ?? ''}',
      ),
      if (conceptGap.trim().isNotEmpty) conceptGap,
    ];

    return GochanoListRow(
      illustration: GochanoArt.featureStudy,
      accent: context.colors.warning,
      title: '${item['topic'] ?? ''}',
      subtitle: '${item['question'] ?? ''}',
      metadata: metadata,
      badge: analysis == null
          ? null
          : GochanoBadge(
              label: GochanoLanguage.text('Explained', 'ব্যাখ্যা করা'),
              tone: GochanoBadgeTone.success,
              icon: Icons.auto_awesome_rounded,
            ),
      trailing: showReview
          ? TextButton(
              onPressed: _busy
                  ? null
                  : () => _markRevised('${item['id'] ?? ''}'),
              child: Text(
                GochanoLanguage.text('Mark revised', 'পড়া শেষ'),
              ),
            )
          : null,
    );
  }

  Widget _weakTopicRow(BuildContext context, Map<String, dynamic> item) {
    final average = item['averageScore'];
    final recommendation = '${item['recommendation'] ?? ''}';
    final metadata = <String>[
      GochanoLanguage.text(
        '${_asInt(item['mistakes'])} mistakes',
        '${_asInt(item['mistakes'])} ভুল',
      ),
      if (average is num)
        GochanoLanguage.text('Quiz average ${average.round()}%', 'গড় ${average.round()}%'),
      if (recommendation.trim().isNotEmpty) recommendation,
    ];

    return GochanoListRow(
      illustration: GochanoArt.subjectGeneric,
      accent: context.colors.error,
      title: '${item['topic'] ?? ''}',
      metadata: metadata,
    );
  }

  static int _asInt(dynamic value) => value is num ? value.toInt() : 0;

  static Map<String, dynamic>? _asMapOrNull(dynamic value) {
    if (value is! Map) return null;
    return Map<String, dynamic>.from(value);
  }

  static List<Map<String, dynamic>> _asList(dynamic value) {
    if (value is! List) return <Map<String, dynamic>>[];
    return [
      for (final entry in value)
        if (entry is Map) Map<String, dynamic>.from(entry),
    ];
  }
}
