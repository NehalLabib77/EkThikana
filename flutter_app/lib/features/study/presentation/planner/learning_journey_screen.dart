// Phase 8 — Your Learning Journey (the Academic Memory Timeline).
//
// Seven streams — exams, quiz scores, mistakes, weak topics, study hours,
// focus sessions and community activity — are collapsed by the backend into
// one dated timeline plus the improvement trends computed across the two
// halves of the last 90 days. The screen only renders: nothing on it is
// calculated here, and a student with no history gets a sentence instead of
// an empty chart.

import 'package:flutter/material.dart';

import '../../../../core/design_system/gochano_art.dart';
import '../../../../core/design_system/gochano_colors.dart';
import '../../../../core/design_system/gochano_spacing.dart';
import '../../../../core/design_system/gochano_typography.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../core/page_route.dart';
import '../../../../services/api_service.dart';
import '../../../../shared/widgets/ai_widgets.dart';
import '../../../../shared/widgets/gochano_controls.dart';
import '../../../../shared/widgets/gochano_surfaces.dart';
import '../../../profile/presentation/learning_brain_screen.dart';
import '../focus/focus_session_screen.dart';
import 'learning_personality_screen.dart';
import 'ziku_achievements_screen.dart';

/// The read hook, injected in tests so the screen never opens a socket.
typedef JourneyFn = Future<Map<String, dynamic>> Function();

class LearningJourneyScreen extends StatefulWidget {
  const LearningJourneyScreen({super.key, this.journeyFn});

  final JourneyFn? journeyFn;

  @override
  State<LearningJourneyScreen> createState() => _LearningJourneyScreenState();
}

class _LearningJourneyScreenState extends State<LearningJourneyScreen> {
  Map<String, dynamic>? _journey;
  String _error = '';
  bool _loading = true;

  JourneyFn get _read => widget.journeyFn ?? ApiService.zikuJourney;

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
        _journey = body;
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
        title: GochanoLanguage.text('Your Learning Journey', 'আপনার লার্নিং যাত্রা'),
        subtitle: GochanoLanguage.text(
          'Everything you have logged, in one line',
          'যা যা লগ করেছেন, এক জায়গায়',
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
    if (_journey == null) {
      if (_loading) {
        return AiLoadingState(
          message: GochanoLanguage.text(
            'Reading your journey…',
            'আপনার যাত্রা পড়া হচ্ছে…',
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

    final journey = _journey!;
    if (journey['hasData'] != true) {
      return AiEmptyState(
        icon: Icons.route_rounded,
        accent: context.colors.ai,
        title: GochanoLanguage.text(
          'Your journey starts with one entry',
          'আপনার যাত্রা শুরু হবে একটি এন্ট্রি দিয়ে',
        ),
        message: GochanoLanguage.text(
          'Log a quiz, a focus block or a mistake and the timeline, the trends '
          'and the milestones all fill themselves in.',
          'একটি কুইজ, একটি ফোকাস ব্লক বা একটি ভুল লগ করুন — টাইমলাইন, ট্রেন্ড ও '
          'মাইলফলক নিজে থেকেই ভরে যাবে।',
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: GochanoSpacing.scrollBody,
        children: [
          _headlineCard(context, journey),
          const SizedBox(height: GochanoSpacing.sm),
          _statRow(context, journey),
          const SizedBox(height: GochanoSpacing.md),
          if (_trends(journey).isNotEmpty) ...[
            _trendsSection(context, journey),
            const SizedBox(height: GochanoSpacing.md),
          ],
          _timelineSection(context, journey),
          if (_weak(journey).isNotEmpty) ...[
            const SizedBox(height: GochanoSpacing.md),
            _weakSection(context, journey),
          ],
          const SizedBox(height: GochanoSpacing.md),
          _crossLinks(context),
          const SizedBox(height: GochanoSpacing.lg),
        ],
      ),
    );
  }

  Widget _headlineCard(BuildContext context, Map<String, dynamic> journey) {
    final colors = context.colors;
    final improving = _asInt(journey['improving']);
    final declining = _asInt(journey['declining']);

    return AppCard(
      accent: colors.ai,
      semanticLabel: 'Learning journey summary',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: GochanoSpacing.xs,
            runSpacing: GochanoSpacing.xxs,
            children: [
              GochanoBadge(
                label: GochanoLanguage.text(
                  '${_asInt(journey['spanDays'])} day window',
                  '${_asInt(journey['spanDays'])} দিনের উইন্ডো',
                ),
                tone: GochanoBadgeTone.info,
                icon: Icons.date_range_rounded,
              ),
              if (improving > 0)
                GochanoBadge(
                  label: GochanoLanguage.text(
                    '$improving trend(s) up',
                    '$improving ট্রেন্ড এগিয়েছে',
                  ),
                  tone: GochanoBadgeTone.success,
                  icon: Icons.trending_up_rounded,
                ),
              if (declining > 0)
                GochanoBadge(
                  label: GochanoLanguage.text(
                    '$declining to watch',
                    '$declining লক্ষ্য রাখুন',
                  ),
                  tone: GochanoBadgeTone.warning,
                  icon: Icons.trending_down_rounded,
                ),
            ],
          ),
          const SizedBox(height: GochanoSpacing.sm),
          Text('${journey['headline'] ?? ''}', style: context.type.body),
          const SizedBox(height: GochanoSpacing.xs),
          Text(
            GochanoLanguage.text(
              '${journey['windowStart'] ?? ''} → ${journey['windowEnd'] ?? ''}',
              '${journey['windowStart'] ?? ''} → ${journey['windowEnd'] ?? ''}',
            ),
            style: context.type.caption,
          ),
        ],
      ),
    );
  }

  Widget _statRow(BuildContext context, Map<String, dynamic> journey) {
    final colors = context.colors;
    final streams = _asMap(journey['streams']);

    return Row(
      children: [
        Expanded(
          child: StatCard(
            compact: true,
            label: GochanoLanguage.text('Active days', 'সক্রিয় দিন'),
            value: '${_asInt(_asMap(journey['stats'])?['daysActive'])}',
            caption: GochanoLanguage.text(
              'in this window',
              'এই উইন্ডোতে',
            ),
            icon: Icon(Icons.event_available_rounded, size: 16, color: colors.brand),
            accent: colors.brand,
          ),
        ),
        const SizedBox(width: GochanoSpacing.sm),
        Expanded(
          child: StatCard(
            compact: true,
            label: GochanoLanguage.text('Study hours', 'পড়ার ঘণ্টা'),
            value: '${_num(streams?['studyHours'])}h',
            caption: GochanoLanguage.text(
              '${_asInt(streams?['focusSessions'])} focus session(s)',
              '${_asInt(streams?['focusSessions'])} ফোকাস সেশন',
            ),
            icon: Icon(Icons.timer_outlined, size: 16, color: colors.study),
            accent: colors.study,
          ),
        ),
        const SizedBox(width: GochanoSpacing.sm),
        Expanded(
          child: StatCard(
            compact: true,
            label: GochanoLanguage.text('Streak', 'স্ট্রিক'),
            value: '${_asInt(_asMap(journey['stats'])?['focusStreak'])}',
            caption: GochanoLanguage.text(
              'days of deep work',
              'দিন ধরে গভীর পড়া',
            ),
            icon: Icon(Icons.local_fire_department_rounded, size: 16, color: colors.warning),
            accent: colors.warning,
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // improvement trends
  // -------------------------------------------------------------------------

  List<Map<String, dynamic>> _trends(Map<String, dynamic> journey) =>
      _asList(journey['trends']);

  Widget _trendsSection(BuildContext context, Map<String, dynamic> journey) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: GochanoLanguage.text('Improvement trends', 'উন্নতির ট্রেন্ড'),
          subtitle: GochanoLanguage.text(
            'The first half of the window against the second',
            'উইন্ডোর প্রথমার্ধ বনাম দ্বিতীয়ার্ধ',
          ),
        ),
        CardGroup(
          children: [
            for (final trend in _trends(journey)) _trendRow(context, trend),
          ],
        ),
      ],
    );
  }

  Widget _trendRow(BuildContext context, Map<String, dynamic> trend) {
    final colors = context.colors;
    final improving = trend['improving'];
    final higherIsBetter = trend['higherIsBetter'] != false;
    final first = _numOrNull(trend['first']);
    final last = _numOrNull(trend['last']);
    final delta = _numOrNull(trend['delta']);
    final unit = '${trend['unit'] ?? ''}';

    final Color tone;
    if (improving == true) {
      tone = colors.success;
    } else if (improving == false) {
      tone = colors.error;
    } else {
      tone = colors.textTertiary;
    }

    final IconData icon;
    if (improving == true) {
      icon = Icons.trending_up_rounded;
    } else if (improving == false) {
      icon = Icons.trending_down_rounded;
    } else {
      icon = Icons.trending_flat_rounded;
    }

    final String range;
    if (first == null || last == null) {
      range = GochanoLanguage.text(
        'Not enough history yet',
        'এখনো যথেষ্ট ইতিহাস নেই',
      );
    } else {
      range = GochanoLanguage.text(
        '$first → $last $unit',
        '$first → $last $unit',
      );
    }

    return GochanoListRow(
      illustration: GochanoArt.featurePlanner,
      accent: tone,
      title: '${trend['label'] ?? ''}',
      subtitle: range,
      metadata: [
        if (delta != null)
          GochanoLanguage.text(
            '${delta > 0 ? '+' : ''}$delta $unit',
            '${delta > 0 ? '+' : ''}$delta $unit',
          ),
        GochanoLanguage.text(
          higherIsBetter ? 'higher is better' : 'lower is better',
          higherIsBetter ? 'বেশি ভালো' : 'কম ভালো',
        ),
      ],
      trailing: Icon(icon, size: 20, color: tone),
    );
  }

  // -------------------------------------------------------------------------
  // timeline
  // -------------------------------------------------------------------------

  List<Map<String, dynamic>> _events(Map<String, dynamic> journey) =>
      _asList(journey['timeline']);

  Widget _timelineSection(BuildContext context, Map<String, dynamic> journey) {
    final events = _events(journey);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: GochanoLanguage.text('Timeline', 'টাইমলাইন'),
          subtitle: GochanoLanguage.text(
            'Showing ${events.length} of ${_asInt(journey['timelineCount'])} '
            'entries, newest first',
            'সর্বশেষ আগে ${_asInt(journey['timelineCount'])} এন্ট্রির মধ্যে '
            '${events.length}টি দেখানো হচ্ছে',
          ),
        ),
        CardGroup(
          children: [for (final event in events) _eventRow(context, event)],
        ),
      ],
    );
  }

  Widget _eventRow(BuildContext context, Map<String, dynamic> event) {
    final colors = context.colors;
    final tone = switch ('${event['tone'] ?? ''}') {
      'positive' => colors.success,
      'negative' => colors.error,
      _ => colors.info,
    };
    final unit = '${event['unit'] ?? ''}';
    final value = _numOrNull(event['value']);

    final String trailing;
    if (value == null) {
      trailing = '';
    } else if (unit == 'percent') {
      trailing = '${_num(value)}%';
    } else if (unit == 'minutes') {
      trailing = GochanoLanguage.text('${_num(value)}m', '${_num(value)} মিনিট');
    } else if (unit == 'hours') {
      trailing = GochanoLanguage.text('${_num(value)}h', '${_num(value)} ঘণ্টা');
    } else {
      trailing = _num(value).toString();
    }

    return GochanoListRow(
      illustration: GochanoArt.featureStudy,
      accent: tone,
      title: '${event['title'] ?? ''}',
      subtitle: '${event['detail'] ?? ''}',
      metadata: ['${event['dayKey'] ?? ''}'],
      trailing: trailing.isEmpty
          ? null
          : Text(
              trailing,
              style: context.type.statisticSmall.copyWith(color: tone),
            ),
    );
  }

  // -------------------------------------------------------------------------
  // weak topics + links to the rest of the Personal OS
  // -------------------------------------------------------------------------

  List<Map<String, dynamic>> _weak(Map<String, dynamic> journey) =>
      _asList(journey['weakTopics']);

  Widget _weakSection(BuildContext context, Map<String, dynamic> journey) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: GochanoLanguage.text('Weak topics', 'দুর্বল টপিক'),
          subtitle: GochanoLanguage.text(
            'Refreshed from the same profile the coach reads',
            'কোচ যে প্রোফাইল পড়ে সেটি থেকেই রিফ্রেশ হয়',
          ),
        ),
        CardGroup(
          children: [
            for (final topic in _weak(journey))
              GochanoListRow(
                illustration: GochanoArt.subjectGeneric,
                accent: colors.warning,
                title: '${topic['topic'] ?? ''}',
                subtitle: GochanoLanguage.text(
                  '${_asInt(topic['mistakes'])} mistake(s), '
                  '${_asInt(topic['repeated'])} repeated, '
                  '${_asInt(topic['due'])} due',
                  '${_asInt(topic['mistakes'])} ভুল, '
                  '${_asInt(topic['repeated'])} পুনরাবৃত্ত, '
                  '${_asInt(topic['due'])} বাকি',
                ),
                trailing: Text(
                  topic['quizAverage'] == null
                      ? '—'
                      : '${_asInt(topic['quizAverage'])}%',
                  style: context.type.statisticSmall.copyWith(
                    color: colors.warning,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _crossLinks(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: GochanoLanguage.text('The rest of your Personal OS', 'আপনার পার্সোনাল ওএস'),
        ),
        CardGroup(
          children: [
            GochanoListRow(
              illustration: GochanoArt.featureProfile,
              accent: colors.ai,
              title: GochanoLanguage.text(
                'Student Learning Profile',
                'শিক্ষার্থীর লার্নিং প্রোফাইল',
              ),
              subtitle: GochanoLanguage.text(
                'Preferred study time, learning style, strong and weak sides',
                'পছন্দের পড়ার সময়, লার্নিং স্টাইল, শক্ত ও দুর্বল দিক',
              ),
              onTap: () => Navigator.of(context).push(
                GochanoRoute.to(builder: (_) => const LearningPersonalityScreen()),
              ),
            ),
            GochanoListRow(
              illustration: GochanoArt.featureCalendar,
              accent: colors.brand,
              title: GochanoLanguage.text('Achievements', 'অর্জন'),
              subtitle: GochanoLanguage.text(
                'MCQ milestones, consistency, improvement and contribution',
                'এমসিকু মাইলফলক, ধারাবাহিকতা, উন্নতি ও অবদান',
              ),
              onTap: () => Navigator.of(context).push(
                GochanoRoute.to(builder: (_) => const ZikuAchievementsScreen()),
              ),
            ),
            GochanoListRow(
              illustration: GochanoArt.featureStudy,
              accent: colors.warning,
              title: GochanoLanguage.text('Revision queue', 'রিভিশন সারি'),
              subtitle: GochanoLanguage.text(
                'The mistakes this journey keeps surfacing',
                'এই যাত্রা যে ভুলগুলো বারবার ফেরত আনে',
              ),
              onTap: () => Navigator.of(context).push(
                GochanoRoute.to(builder: (_) => const LearningBrainScreen()),
              ),
            ),
            GochanoListRow(
              illustration: GochanoArt.featurePlanner,
              accent: colors.study,
              title: GochanoLanguage.text('Start a focus block', 'ফোকাস ব্লক শুরু'),
              subtitle: GochanoLanguage.text(
                'Bank the minutes this timeline counts',
                'এই টাইমলাইন যে মিনিট গুনে সেগুলো জমা করুন',
              ),
              onTap: () => Navigator.of(context).push(
                GochanoRoute.to(builder: (_) => const FocusSessionScreen()),
              ),
            ),
          ],
        ),
      ],
    );
  }

  static int _asInt(dynamic value) => value is num ? value.toInt() : 0;

  static num _num(dynamic value) => value is num ? value : 0;

  static num? _numOrNull(dynamic value) => value is num ? value : null;

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
}
