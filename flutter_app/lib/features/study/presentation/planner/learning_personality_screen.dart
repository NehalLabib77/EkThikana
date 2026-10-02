// Phase 8 — Student Learning Profile.
//
// The five answers a coach needs before saying anything: when this student
// works, how they learn, what they are strong at, what to watch, and the
// evidence behind every one of those claims. Everything here is computed
// server-side (`/api/ziku/profile`); this screen is a reader.

import 'package:flutter/material.dart';

import '../../../../core/design_system/gochano_art.dart';
import '../../../../core/design_system/gochano_colors.dart';
import '../../../../core/design_system/gochano_spacing.dart';
import '../../../../core/design_system/gochano_typography.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../services/api_service.dart';
import '../../../../shared/widgets/ai_widgets.dart';
import '../../../../shared/widgets/gochano_controls.dart';
import '../../../../shared/widgets/gochano_surfaces.dart';

/// The read hook, injected in tests so the screen never opens a socket.
typedef PersonalityFn = Future<Map<String, dynamic>> Function();

class LearningPersonalityScreen extends StatefulWidget {
  const LearningPersonalityScreen({super.key, this.profileFn});

  final PersonalityFn? profileFn;

  @override
  State<LearningPersonalityScreen> createState() =>
      _LearningPersonalityScreenState();
}

class _LearningPersonalityScreenState extends State<LearningPersonalityScreen> {
  Map<String, dynamic>? _profile;
  String _error = '';
  bool _loading = true;

  PersonalityFn get _read => widget.profileFn ?? ApiService.zikuProfile;

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
      final body = await _read();
      if (!mounted) return;
      setState(() {
        _profile = body;
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

  @override
  Widget build(BuildContext context) {
    return GochanoScaffold(
      appBar: GochanoAppBar(
        title: GochanoLanguage.text(
          'Student Learning Profile',
          'শিক্ষার্থীর লার্নিং প্রোফাইল',
        ),
        subtitle: GochanoLanguage.text(
          'How you actually study, in five answers',
          'আপনার পড়ার প্রকৃত ধরন, পাঁচটি উত্তরে',
        ),
        actions: [
          IconActionButton(
            icon: Icons.refresh_rounded,
            label: GochanoLanguage.text('Refresh', 'রিফ্রেশ'),
            onPressed: _refresh,
          ),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_profile == null) {
      if (_loading) {
        return AiLoadingState(
          message: GochanoLanguage.text(
            'Reading your profile…',
            'আপনার প্রোফাইল পড়া হচ্ছে…',
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

    final profile = _profile!;
    final personality =
        _asMap(profile['personality']) ?? const <String, dynamic>{};
    final evidence = _asMap(profile['evidence']) ?? const <String, dynamic>{};

    if (profile['hasData'] != true) {
      return AiEmptyState(
        icon: Icons.psychology_alt_rounded,
        accent: context.colors.ai,
        title: GochanoLanguage.text(
          'No study history yet',
          'এখনো কোনো পড়ার ইতিহাস নেই',
        ),
        message: GochanoLanguage.text(
          'Take a quiz or finish a focus block. The preferred time, the '
          'learning style and the strong and weak sides fill themselves in.',
          'একটি কুইজ দিন বা একটি ফোকাস ব্লক শেষ করুন। পছন্দের সময়, লার্নিং স্টাইল ও '
          'শক্ত-দুর্বল দিক নিজে থেকেই ভরবে।',
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: GochanoSpacing.scrollBody,
        children: [
          _labelCard(context, profile),
          const SizedBox(height: GochanoSpacing.sm),
          _preferredTimeCard(context, personality),
          const SizedBox(height: GochanoSpacing.sm),
          _styleCard(context, personality),
          const SizedBox(height: GochanoSpacing.md),
          _strengthsWatchouts(context, personality),
          const SizedBox(height: GochanoSpacing.md),
          _evidenceSection(context, evidence),
          const SizedBox(height: GochanoSpacing.md),
          _subjectsSection(context, personality),
          const SizedBox(height: GochanoSpacing.lg),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // identity: the label this profile earned
  // -------------------------------------------------------------------------

  Widget _labelCard(BuildContext context, Map<String, dynamic> profile) {
    final colors = context.colors;
    final health = _asInt(profile['healthScore']);

    return AppCard(
      accent: colors.ai,
      semanticLabel: 'Learning profile summary',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${profile['label'] ?? ''}',
            style: context.type.cardHeading.copyWith(color: colors.ai),
          ),
          const SizedBox(height: GochanoSpacing.sm),
          Wrap(
            spacing: GochanoSpacing.xs,
            runSpacing: GochanoSpacing.xxs,
            children: [
              GochanoBadge(
                label: GochanoLanguage.text(
                  'Health score $health',
                  'হেলথ স্কোর $health',
                ),
                tone: health >= 70
                    ? GochanoBadgeTone.success
                    : GochanoBadgeTone.warning,
                icon: Icons.favorite_outline_rounded,
              ),
              GochanoBadge(
                label: GochanoLanguage.text(
                  '${profile['student'] ?? ''}',
                  '${profile['student'] ?? ''}',
                ),
                tone: GochanoBadgeTone.neutral,
                icon: Icons.person_outline_rounded,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _preferredTimeCard(BuildContext context, Map<String, dynamic> personality) {
    final colors = context.colors;
    final preferred = _asMap(personality['preferredStudyTime']);
    final share = _asInt(preferred?['sharePct']);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.wb_twilight_rounded, size: 18, color: colors.brand),
              const SizedBox(width: GochanoSpacing.xs),
              Expanded(
                child: Text(
                  GochanoLanguage.text(
                    'Preferred study time',
                    'পছন্দের পড়ার সময়',
                  ),
                  style: context.type.label,
                ),
              ),
              GochanoBadge(
                label: GochanoLanguage.text(
                  '$share%',
                  '$share%',
                ),
                tone: share > 0 ? GochanoBadgeTone.brand : GochanoBadgeTone.neutral,
              ),
            ],
          ),
          const SizedBox(height: GochanoSpacing.xs),
          Text('${preferred?['label'] ?? ''}', style: context.type.cardHeading),
          const SizedBox(height: GochanoSpacing.xs),
          Text(
            '${preferred?['evidence'] ?? ''}',
            style: context.type.bodySecondary,
          ),
          const SizedBox(height: GochanoSpacing.xs),
          Text(
            GochanoLanguage.text(
              '${_asInt(preferred?['sessions'])} finished session(s)',
              '${_asInt(preferred?['sessions'])}টি শেষ করা সেশন',
            ),
            style: context.type.caption,
          ),
        ],
      ),
    );
  }

  Widget _styleCard(BuildContext context, Map<String, dynamic> personality) {
    final colors = context.colors;
    final style = _asMap(personality['learningStyle']);

    return AppCard(
      accent: colors.study,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            GochanoLanguage.text('Learning style', 'লার্নিং স্টাইল'),
            style: context.type.label,
          ),
          const SizedBox(height: GochanoSpacing.xs),
          Text('${style?['label'] ?? ''}', style: context.type.cardHeading),
          const SizedBox(height: GochanoSpacing.xs),
          Text('${style?['why'] ?? ''}', style: context.type.body),
        ],
      ),
    );
  }

  Widget _strengthsWatchouts(BuildContext context, Map<String, dynamic> personality) {
    final colors = context.colors;
    final strengths = _strings(personality['strengths']);
    final watchouts = _strings(personality['watchouts']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: GochanoLanguage.text('Strengths and watch-outs', 'শক্তি ও সতর্কতা'),
        ),
        CardGroup(
          children: [
            for (final item in strengths)
              GochanoListRow(
                illustration: GochanoArt.featureProfile,
                accent: colors.success,
                title: item,
                subtitle: GochanoLanguage.text('Strength', 'শক্তি'),
                trailing: Icon(Icons.check_circle_rounded,
                    size: 18, color: colors.success),
              ),
            for (final item in watchouts)
              GochanoListRow(
                illustration: GochanoArt.featureProfile,
                accent: colors.warning,
                title: item,
                subtitle: GochanoLanguage.text('Watch out', 'সতর্কতা'),
                trailing: Icon(Icons.visibility_outlined,
                    size: 18, color: colors.warning),
              ),
          ],
        ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // evidence + subjects
  // -------------------------------------------------------------------------

  Widget _evidenceSection(
    BuildContext context,
    Map<String, dynamic> evidence,
  ) {
    final colors = context.colors;
    final rows = <(String, String, String)>[
      (
        GochanoLanguage.text('Quizzes taken', 'দেওয়া কুইজ'),
        '${_asInt(evidence['quizzes'])}',
        GochanoLanguage.text(
          'average ${evidence['quizAverage'] == null ? '—' : '${_asInt(evidence['quizAverage'])}%'}',
          'গড় ${evidence['quizAverage'] == null ? '—' : '${_asInt(evidence['quizAverage'])}%'}',
        ),
      ),
      (
        GochanoLanguage.text('Focus this week', 'এই সপ্তাহের ফোকাস'),
        '${_asInt(evidence['focusMinutes'])}m',
        GochanoLanguage.text(
          '${_asInt(evidence['focusConsistency'])}% consistency',
          '${_asInt(evidence['focusConsistency'])}% ধারাবাহিকতা',
        ),
      ),
      (
        GochanoLanguage.text('Deep-work streak', 'গভীর পড়ার স্ট্রিক'),
        '${_asInt(evidence['focusStreak'])}',
        GochanoLanguage.text(
          '${_asInt(evidence['averageSessionMinutes'])}m average session',
          '${_asInt(evidence['averageSessionMinutes'])} মিনিট গড় সেশন',
        ),
      ),
      (
        GochanoLanguage.text('Mistakes logged', 'লগ করা ভুল'),
        '${_asInt(evidence['mistakes'])}',
        GochanoLanguage.text(
          '${_asInt(evidence['repeatedMistakes'])} repeated, '
          '${_asInt(evidence['revisionDue'])} due',
          '${_asInt(evidence['repeatedMistakes'])} পুনরাবৃত্ত, '
          '${_asInt(evidence['revisionDue'])} বাকি',
        ),
      ),
      (
        GochanoLanguage.text('Practice exams', 'প্র্যাকটিস পরীক্ষা'),
        '${_asInt(evidence['practiceExams'])}',
        GochanoLanguage.text(
          '${_asInt(evidence['communityPosts'])} group post(s), '
          '${_asInt(evidence['communityPoints'])} points',
          '${_asInt(evidence['communityPosts'])} গ্রুপ পোস্ট, '
          '${_asInt(evidence['communityPoints'])} পয়েন্ট',
        ),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: GochanoLanguage.text('Evidence', 'প্রমাণ'),
          subtitle: GochanoLanguage.text(
            'Every claim above is counted from these numbers',
            'উপরের প্রতিটি দাবি এই সংখ্যা থেকেই গোনা',
          ),
        ),
        CardGroup(
          children: [
            for (final row in rows)
              GochanoListRow(
                illustration: GochanoArt.featureStudy,
                accent: colors.ai,
                title: row.$1,
                subtitle: row.$3,
                trailing: Text(
                  row.$2,
                  style: context.type.statisticSmall.copyWith(color: colors.ai),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _subjectsSection(BuildContext context, Map<String, dynamic> personality) {
    final colors = context.colors;
    final strong = _asList(personality['strongSubjects']);
    final weak = _asList(personality['weakSubjects']);

    if (strong.isEmpty && weak.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: GochanoLanguage.text(
            personality['subjectKind'] == 'topic' ? 'Strong and weak topics' : 'Strong and weak subjects',
            personality['subjectKind'] == 'topic'
                ? 'শক্ত ও দুর্বল টপিক'
                : 'শক্ত ও দুর্বল বিষয়',
          ),
        ),
        CardGroup(
          children: [
            for (final subject in strong)
              GochanoListRow(
                illustration: GochanoArt.subjectGeneric,
                accent: colors.success,
                title: '${subject['name'] ?? ''}',
                subtitle: GochanoLanguage.text(
                  '${_asInt(subject['attempts'])} attempt(s)',
                  '${_asInt(subject['attempts'])} বার চেষ্টা',
                ),
                trailing: Text(
                  '${_num(subject['average'])}%',
                  style: context.type.statisticSmall
                      .copyWith(color: colors.success),
                ),
              ),
            for (final subject in weak)
              GochanoListRow(
                illustration: GochanoArt.subjectGeneric,
                accent: colors.warning,
                title: '${subject['name'] ?? ''}',
                subtitle: GochanoLanguage.text(
                  '${_asInt(subject['attempts'])} attempt(s)',
                  '${_asInt(subject['attempts'])} বার চেষ্টা',
                ),
                trailing: Text(
                  '${_num(subject['average'])}%',
                  style: context.type.statisticSmall
                      .copyWith(color: colors.warning),
                ),
              ),
          ],
        ),
      ],
    );
  }

  static int _asInt(dynamic value) => value is num ? value.toInt() : 0;

  static num _num(dynamic value) => value is num ? value : 0;

  static Map<String, dynamic>? _asMap(dynamic value) {
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

  static List<String> _strings(dynamic value) {
    if (value is! List) return <String>[];
    return [
      for (final entry in value)
        if (entry is String && entry.trim().isNotEmpty) entry,
    ];
  }
}
