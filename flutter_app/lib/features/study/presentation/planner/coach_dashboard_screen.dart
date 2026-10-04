// Phase 4 — Coach Dashboard: everything Ziku sees about one student today.
//
// The screen is a *reader*, never an analyser. Every number on it is produced
// by the backend in one of three payloads:
//
//   profile  → who the student is (weak/strong topics, focus habits, readiness)
//   daily    → today's mission (priority, why, up to 4 steps)
//   weekly   → the 7-day report (time, movement, one recommendation + AI text)
//
// The mission is the point of the screen, so it sits first: each step that has
// a real destination gets an action button that goes there, and a step whose
// destination does not exist in the app yet (a focus block) is shown as a plan
// rather than a dead link. The weekly narrative is loaded separately: it is the
// only part that can fail (AI quota) and it must never take the rest down.

import 'dart:async';

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
import '../ai/ai_assistant_screen.dart';
import '../ai/quiz_generator_screen.dart';
import '../focus/focus_session_screen.dart';
import 'learning_journey_screen.dart';
import 'learning_personality_screen.dart';
import 'ziku_achievements_screen.dart';
import 'ziku_coach_card.dart';

/// Phase 8 — the Personal OS reads. Both are decorations on top of a working
/// dashboard: when either fails the mission stays exactly as it was.
typedef ZikuBriefFn = Future<Map<String, dynamic>> Function();
typedef ZikuActionFn = Future<Map<String, dynamic>> Function();

class CoachDashboardScreen extends StatefulWidget {
  const CoachDashboardScreen({
    super.key,
    this.profileFn,
    this.dailyFn,
    this.weeklyFn,
    this.briefFn,
    this.actionFn,
    this.onOpenPlan,
  });

  /// Read hooks, injected in tests so the screen never opens a socket.
  final CoachProfileFn? profileFn;
  final CoachBriefFn? dailyFn;
  final CoachWeeklyFn? weeklyFn;

  /// Phase 8 — the AI daily brief and the next best action. Absent → the
  /// default hits the API and a failure simply hides those two cards.
  final ZikuBriefFn? briefFn;
  final ZikuActionFn? actionFn;

  /// Hands a step that lives in the study shell back to the app shell
  /// (1 = Workspace, 2 = Plan). Absent → those steps show no button.
  final ValueChanged<int>? onOpenPlan;

  @override
  State<CoachDashboardScreen> createState() => _CoachDashboardScreenState();
}

class _CoachDashboardScreenState extends State<CoachDashboardScreen> {
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _daily;
  Map<String, dynamic>? _weekly;
  Map<String, dynamic>? _brief;
  Map<String, dynamic>? _action;
  bool _loading = true;
  String _error = '';
  String _weeklyError = '';

  CoachProfileFn get _readProfile =>
      widget.profileFn ?? ApiService.coachProfile;
  CoachBriefFn get _readDaily => widget.dailyFn ?? ApiService.coachDailyBrief;
  CoachWeeklyFn get _readWeekly =>
      widget.weeklyFn ?? ApiService.coachWeeklyReport;
  ZikuBriefFn get _readBrief => widget.briefFn ?? ApiService.zikuBrief;
  ZikuActionFn get _readAction =>
      widget.actionFn ?? ApiService.zikuNextBestAction;

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
      final profile = await _readProfile();
      final daily = await _readDaily();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _daily = daily;
        _loading = false;
      });
      unawaited(_loadWeekly());
      unawaited(_loadBrief());
      unawaited(_loadAction());
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _error = err.toString();
        _loading = false;
      });
    }
  }

  /// The weekly report is a decoration on top of a working screen: it fails
  /// loudly inline and the mission stays usable.
  Future<void> _loadWeekly() async {
    setState(() => _weeklyError = '');
    try {
      final body = await _readWeekly();
      if (!mounted) return;
      setState(() => _weekly = body);
    } catch (err) {
      if (!mounted) return;
      setState(() => _weeklyError = err.toString());
    }
  }

  /// Phase 8 — the AI daily brief. Fails silently: the two cards it feeds
  /// simply do not appear, and nothing else on this screen changes.
  Future<void> _loadBrief() async {
    try {
      final body = await _readBrief();
      if (!mounted) return;
      setState(() => _brief = body);
    } catch (_) {
      // The Personal OS is an addition, never a dependency.
    }
  }

  /// Phase 8 — the next best action. Same contract as [_loadBrief].
  Future<void> _loadAction() async {
    try {
      final body = await _readAction();
      if (!mounted) return;
      setState(() => _action = body);
    } catch (_) {
      // The ranked recommendation is an addition, never a dependency.
    }
  }

  @override
  Widget build(BuildContext context) {
    return GochanoScaffold(
      appBar: GochanoAppBar(
        title: GochanoLanguage.text('My AI Coach', 'আমার এআই কোচ'),
        subtitle: GochanoLanguage.text(
          'What Ziku sees today',
          'জিকু যা দেখছে আজ',
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
            'Reading your learning profile…',
            'আপনার লার্নিং প্রোফাইল পড়া হচ্ছে…',
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
    final daily = _daily ?? <String, dynamic>{};
    final hasData = profile['hasData'] == true;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: GochanoSpacing.scrollBody,
        children: [
          if (_error.isNotEmpty) ...[
            AiErrorBanner(message: _error),
            const SizedBox(height: GochanoSpacing.sm),
          ],
          if (!hasData)
            AiEmptyState(
              icon: Icons.auto_awesome_rounded,
              title: GochanoLanguage.text(
                'Ziku has nothing to coach yet',
                'জিকু এখনো কিছু বলতে পারেনি',
              ),
              message: GochanoLanguage.text(
                'Take one quiz or log one mistake — the profile, the mission '
                    'and the weekly report all start from there.',
                'একটি কুইজ দিন বা একটি ভুল রেখে দিন — প্রোফাইল, মিশন ও সাপ্তাহিক '
                    'রিপোর্ট সবই এখান থেকে শুরু হয়।',
              ),
            )
          else ...[
            _scoreCard(context, profile),
            const SizedBox(height: GochanoSpacing.sm),
            _todayStats(context, profile),
          ],
          const SizedBox(height: GochanoSpacing.md),
          _missionSection(context, daily, profile),
          const SizedBox(height: GochanoSpacing.md),
          ..._topicSections(context, profile),
          const SizedBox(height: GochanoSpacing.md),
          _patternSection(context, profile),
          const SizedBox(height: GochanoSpacing.md),
          _improvementSection(context, profile),
          const SizedBox(height: GochanoSpacing.md),
          _weeklySection(context),
          const SizedBox(height: GochanoSpacing.md),
          _personalOsSection(context),
          const SizedBox(height: GochanoSpacing.md),
          _askZikuCard(context, profile),
          const SizedBox(height: GochanoSpacing.lg),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 1. how am I doing
  // -------------------------------------------------------------------------

  Widget _scoreCard(BuildContext context, Map<String, dynamic> profile) {
    final colors = context.colors;
    final score = _asInt(profile['healthScore']);
    final trend = _asMap(profile['trend']);
    final readiness = _asIntOrNull(profile['examReadiness']);
    final pattern = _asMap(profile['studyPattern']) ?? <String, dynamic>{};
    final tone = _toneFor(context, score);

    final String? deltaLabel;
    final direction = '${trend?['direction'] ?? ''}';
    if (direction.isEmpty || direction == 'new') {
      deltaLabel = null;
    } else {
      final delta = _asInt(trend?['delta']);
      deltaLabel = delta > 0
          ? GochanoLanguage.text(
              '+$delta since yesterday',
              'গতকালের চেয়ে +$delta',
            )
          : delta < 0
          ? GochanoLanguage.text(
              '$delta since yesterday',
              'গতকালের চেয়ে $delta',
            )
          : GochanoLanguage.text('Same as yesterday', 'গতকালের মতোই');
    }

    return AppCard(
      accent: colors.ai,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '$score',
                style: context.type.display.copyWith(color: tone),
                semanticsLabel: GochanoLanguage.text(
                  'Academic Health $score out of 100',
                  'একাডেমিক হেলথ $score / ১০০',
                ),
              ),
              const SizedBox(width: GochanoSpacing.xs),
              Text('/ 100', style: context.type.bodySecondary),
              const Spacer(),
              if (readiness != null)
                GochanoBadge(
                  label: GochanoLanguage.text(
                    'Exam ready $readiness%',
                    'পরীক্ষার প্রস্তুতি $readiness%',
                  ),
                  tone: readiness >= 70
                      ? GochanoBadgeTone.success
                      : readiness >= 50
                      ? GochanoBadgeTone.warning
                      : GochanoBadgeTone.error,
                  icon: Icons.flag_rounded,
                ),
            ],
          ),
          if (deltaLabel != null) ...[
            const SizedBox(height: GochanoSpacing.xs),
            Text(deltaLabel, style: context.type.caption),
          ],
          const SizedBox(height: GochanoSpacing.sm),
          Text('${profile['healthHeadline'] ?? ''}', style: context.type.body),
          if ('${profile['healthGrade'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              GochanoLanguage.text(
                'Grade ${profile['healthGrade']} · '
                    '${_asInt(pattern['studyDays'])} study days this week',
                'গ্রেড ${profile['healthGrade']} · এই সপ্তাহে '
                    '${_asInt(pattern['studyDays'])} দিন পড়া',
              ),
              style: context.type.caption,
            ),
          ],
        ],
      ),
    );
  }

  Widget _todayStats(BuildContext context, Map<String, dynamic> profile) {
    final colors = context.colors;
    final readiness = _asIntOrNull(profile['examReadiness']);

    return Row(
      children: [
        Expanded(
          child: StatCard(
            compact: true,
            label: GochanoLanguage.text('Exam readiness', 'পরীক্ষার প্রস্তুতি'),
            value: readiness == null ? '—' : '$readiness%',
            caption: GochanoLanguage.text(
              profile['upcomingExam'] == null
                  ? 'No exam planned'
                  : '${_asInt(_asMap(profile['upcomingExam'])?['daysRemaining'])} days to go',
              profile['upcomingExam'] == null
                  ? 'কোনো পরীক্ষা নেই'
                  : '${_asInt(_asMap(profile['upcomingExam'])?['daysRemaining'])} দিন বাকি',
            ),
            icon: Icon(Icons.flag_rounded, size: 16, color: colors.info),
            accent: colors.info,
          ),
        ),
        const SizedBox(width: GochanoSpacing.sm),
        Expanded(
          child: StatCard(
            compact: true,
            label: GochanoLanguage.text('Repeated', 'পুনরাবৃত্ত'),
            value: '${_asInt(profile['repeatedMistakes'])}',
            caption: GochanoLanguage.text(
              '${_asInt(profile['totalMistakes'])} mistakes on file',
              'মোট ${_asInt(profile['totalMistakes'])} ভুল',
            ),
            icon: Icon(
              Icons.error_outline_rounded,
              size: 16,
              color: colors.error,
            ),
            accent: colors.error,
          ),
        ),
        const SizedBox(width: GochanoSpacing.sm),
        Expanded(
          child: StatCard(
            compact: true,
            label: GochanoLanguage.text('Revision due', 'রিভিশন বাকি'),
            value: '${_asInt(profile['revisionDue'])}',
            caption: GochanoLanguage.text(
              '${_asInt(profile['quizAverage'])}% quiz average',
              'কুইজ গড় ${_asInt(profile['quizAverage'])}%',
            ),
            icon: Icon(
              Icons.menu_book_rounded,
              size: 16,
              color: colors.warning,
            ),
            accent: colors.warning,
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // 2. what to do today
  // -------------------------------------------------------------------------

  Widget _missionSection(
    BuildContext context,
    Map<String, dynamic> daily,
    Map<String, dynamic> profile,
  ) {
    final colors = context.colors;
    final priority = _asMap(daily['priority']);
    final mission = _asList(daily['mission']);
    final exam = _asMap(daily['exam'] ?? profile['upcomingExam']);
    final topic = '${priority?['topic'] ?? ''}';
    final why = '${daily['why'] ?? priority?['why'] ?? ''}';
    final reasons = _asStrings(priority?['reasons']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: GochanoLanguage.text('Today\u2019s mission', 'আজকের মিশন'),
          subtitle: GochanoLanguage.text(
            'Built from your mistakes, quizzes and exam date',
            'আপনার ভুল, কুইজ ও পরীক্ষার তারিখ থেকে তৈরি',
          ),
        ),
        AppCard(
          accent: colors.ai,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (exam != null)
                Text(
                  GochanoLanguage.text(
                    '${exam['title'] ?? ''} · ${_asInt(exam['daysRemaining'])} days left',
                    '${exam['title'] ?? ''} · ${_asInt(exam['daysRemaining'])} দিন বাকি',
                  ),
                  style: context.type.caption.copyWith(color: colors.warning),
                ),
              if (exam != null) const SizedBox(height: GochanoSpacing.xs),
              if (topic.isNotEmpty) ...[
                Text(
                  GochanoLanguage.text(
                    'Priority: $topic',
                    'অগ্রাধিকার: $topic',
                  ),
                  style: context.type.sectionHeading.copyWith(color: colors.ai),
                ),
                const SizedBox(height: 2),
              ],
              if (why.isNotEmpty)
                Text(
                  GochanoLanguage.text(why, why),
                  style: context.type.bodySecondary,
                ),
              if (reasons.isNotEmpty) ...[
                const SizedBox(height: GochanoSpacing.xs),
                Wrap(
                  spacing: GochanoSpacing.xs,
                  runSpacing: GochanoSpacing.xxs,
                  children: [
                    for (final reason in reasons)
                      GochanoBadge(
                        label: reason,
                        tone: GochanoBadgeTone.neutral,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        if (mission.isNotEmpty) ...[
          const SizedBox(height: GochanoSpacing.sm),
          CardGroup(
            children: [for (final step in mission) _missionRow(context, step)],
          ),
        ],
        if (mission.isEmpty)
          AppCard(
            child: Text(
              GochanoLanguage.text(
                'No mission today — take a quiz so the coach can build one.',
                'আজ কোনো মিশন নেই — একটি কুইজ দিন।',
              ),
              style: context.type.bodySecondary,
            ),
          ),
      ],
    );
  }

  Widget _missionRow(BuildContext context, Map<String, dynamic> step) {
    final action = '${step['action'] ?? step['key'] ?? ''}';
    final target = '${step['target'] ?? ''}';
    final colors = context.colors;
    final minutes = _asIntOrNull(step['minutes']);

    return GochanoListRow(
      illustration: GochanoArt.featurePlanner,
      accent: colors.ai,
      title: '${step['title'] ?? ''}',
      subtitle: '${step['detail'] ?? ''}',
      metadata: [
        if (minutes != null && minutes > 0)
          GochanoLanguage.text('$minutes min', '$minutes মিনিট'),
        if ('${step['priority'] ?? ''}' == 'high')
          GochanoLanguage.text('High priority', 'জরুরি'),
      ],
      trailing: _missionAction(context, action, target),
    );
  }

  /// The button a step deserves — only where a real destination exists.
  Widget? _missionAction(BuildContext context, String action, String target) {
    final colors = context.colors;

    if (action == 'review') {
      return IconActionButton(
        icon: Icons.menu_book_rounded,
        label: GochanoLanguage.text('Review', 'রিভিশন'),
        accent: colors.ai,
        onPressed: () => Navigator.of(
          context,
        ).push(GochanoRoute.to(builder: (_) => const LearningBrainScreen())),
      );
    }
    if (action == 'quiz') {
      return IconActionButton(
        icon: Icons.quiz_rounded,
        label: GochanoLanguage.text('Start quiz', 'কুইজ শুরু'),
        accent: colors.brand,
        onPressed: () => Navigator.of(context).push(
          GochanoRoute.to(
            builder: (_) => QuizGeneratorScreen(
              initialTopic: target.isEmpty ? null : target,
            ),
          ),
        ),
      );
    }
    if (action == 'rescue') {
      if (widget.onOpenPlan == null) return null;
      return IconActionButton(
        icon: Icons.calendar_month_rounded,
        label: GochanoLanguage.text('Open plan', 'প্লান খুলুন'),
        accent: colors.warning,
        onPressed: () => _handOffToShell(context),
      );
    }
    if (action == 'focus') {
      // Phase 5 — the block the coach budgets finally has a home: the
      // timer screen, started with whatever topic the step was built from.
      return IconActionButton(
        icon: Icons.timer_rounded,
        label: GochanoLanguage.text('Start focus', 'ফোকাস শুরু'),
        accent: colors.study,
        onPressed: () => Navigator.of(context).push(
          GochanoRoute.to(
            builder: (_) => FocusSessionScreen(initialTopic: target),
          ),
        ),
      );
    }
    return null;
  }

  void _handOffToShell(BuildContext context) {
    final openPlan = widget.onOpenPlan;
    if (openPlan == null) return;
    Navigator.of(context).pop();
    openPlan(2);
  }

  // -------------------------------------------------------------------------
  // 3. why: the topics behind the mission
  // -------------------------------------------------------------------------

  List<Widget> _topicSections(
    BuildContext context,
    Map<String, dynamic> profile,
  ) {
    final weak = _asList(profile['weakTopics']);
    final strong = _asList(profile['strongTopics']);
    final out = <Widget>[];

    if (weak.isNotEmpty) {
      out.addAll([
        SectionHeader(
          title: GochanoLanguage.text('Weak topics', 'দুর্বল টপিক'),
          subtitle: GochanoLanguage.text(
            'Ranked by repeated mistakes, overdue revision and quiz score',
            'পুনরাবৃত্ত ভুল, রিভিশন ও কুইজ স্কোর অনুযায়ী',
          ),
        ),
        CardGroup(children: [for (final item in weak) _weakRow(context, item)]),
        const SizedBox(height: GochanoSpacing.md),
      ]);
    }

    if (strong.isNotEmpty) {
      out.addAll([
        SectionHeader(
          title: GochanoLanguage.text('Strong topics', 'শক্তিশালী টপিক'),
          subtitle: GochanoLanguage.text(
            'Topics you can leave alone this week',
            'এই সপ্তাহে এগুলো এড়িয়ে যাওয়া যায়',
          ),
        ),
        CardGroup(
          children: [
            for (final item in strong)
              GochanoListRow(
                illustration: GochanoArt.subjectGeneric,
                accent: context.colors.success,
                title: '${item['topic'] ?? ''}',
                subtitle: GochanoLanguage.text(
                  'Mastery over ${_asInt(item['attempts'])} attempt(s)',
                  '${_asInt(item['attempts'])} বার চেষ্টায় দক্ষতা',
                ),
                trailing: Text(
                  _asIntOrNull(item['averageScore']) == null
                      ? '—'
                      : '${_asInt(item['averageScore'])}%',
                  style: context.type.statisticSmall.copyWith(
                    color: context.colors.success,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: GochanoSpacing.md),
      ]);
    }

    return out;
  }

  Widget _weakRow(BuildContext context, Map<String, dynamic> item) {
    final colors = context.colors;
    final priority = '${item['priority'] ?? 'medium'}';
    final quizAverage = _asIntOrNull(item['quizAverage']);
    final reasons = _asStrings(item['reasons']);

    final metadata = <String>[
      if (quizAverage != null)
        GochanoLanguage.text('Quiz $quizAverage%', 'কুইজ $quizAverage%'),
      if (_asInt(item['occurrences']) > 0)
        GochanoLanguage.text(
          '${_asInt(item['occurrences'])} misses',
          '${_asInt(item['occurrences'])} বার ভুল',
        ),
      if (_asInt(item['repeated']) > 0)
        GochanoLanguage.text(
          '${_asInt(item['repeated'])} repeated',
          '${_asInt(item['repeated'])} পুনরাবৃত্ত',
        ),
      if (_asInt(item['due']) > 0)
        GochanoLanguage.text(
          '${_asInt(item['due'])} due',
          '${_asInt(item['due'])} বাকি',
        ),
      if (reasons.isNotEmpty) reasons.first,
    ];

    return GochanoListRow(
      illustration: GochanoArt.subjectGeneric,
      accent: priority == 'high' ? colors.error : colors.warning,
      title: '${item['topic'] ?? ''}',
      subtitle: '${item['action'] ?? ''}',
      metadata: metadata,
      badge: priority == 'high'
          ? GochanoBadge(
              label: GochanoLanguage.text('High', 'জরুরি'),
              tone: GochanoBadgeTone.error,
              icon: Icons.priority_high_rounded,
            )
          : priority == 'medium'
          ? GochanoBadge(
              label: GochanoLanguage.text('Medium', 'মাঝারি'),
              tone: GochanoBadgeTone.warning,
            )
          : null,
    );
  }

  // -------------------------------------------------------------------------
  // 4. patterns + movement
  // -------------------------------------------------------------------------

  Widget _patternSection(BuildContext context, Map<String, dynamic> profile) {
    final colors = context.colors;
    final pattern = _asMap(profile['studyPattern']) ?? <String, dynamic>{};
    final focusScore = _asIntOrNull(pattern['averageFocusScore']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: GochanoLanguage.text('Study pattern', 'পড়ার ধরন'),
          subtitle: GochanoLanguage.text('Last 7 days', 'গত ৭ দিন'),
        ),
        Row(
          children: [
            Expanded(
              child: StatCard(
                compact: true,
                label: GochanoLanguage.text('Deep work', 'গভীর পড়া'),
                value: '${_asInt(pattern['weekMinutes'])}m',
                caption: GochanoLanguage.text(
                  '${_asInt(profile['averageFocusTime'])}m per study day',
                  'পড়ার দিনে ${_asInt(profile['averageFocusTime'])} মিনিট',
                ),
                icon: Icon(Icons.timer_outlined, size: 16, color: colors.study),
                accent: colors.study,
              ),
            ),
            const SizedBox(width: GochanoSpacing.sm),
            Expanded(
              child: StatCard(
                compact: true,
                label: GochanoLanguage.text('Study days', 'পড়ার দিন'),
                value: '${_asInt(pattern['studyDays'])}',
                caption: GochanoLanguage.text(
                  'of the last 7',
                  'গত ৭ দিনের মধ্যে',
                ),
                icon: Icon(
                  Icons.calendar_today_rounded,
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
                label: GochanoLanguage.text('Focus score', 'ফোকাস স্কোর'),
                value: focusScore == null ? '—' : '$focusScore',
                caption: GochanoLanguage.text(
                  'today ${_asInt(pattern['todayMinutes'])}m',
                  'আজ ${_asInt(pattern['todayMinutes'])} মিনিট',
                ),
                icon: Icon(
                  Icons.my_location_rounded,
                  size: 16,
                  color: colors.ai,
                ),
                accent: colors.ai,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _improvementSection(
    BuildContext context,
    Map<String, dynamic> profile,
  ) {
    final colors = context.colors;
    final trend = _asMap(profile['trend']);
    final movement = _asList(_asMap(_weekly)?['improvement']);
    final direction = '${trend?['direction'] ?? ''}';
    final delta = _asInt(trend?['delta']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: GochanoLanguage.text(
            'Recent improvement',
            'সাম্প্রতিক উন্নতি',
          ),
          subtitle: GochanoLanguage.text(
            'What moved since yesterday and this week',
            'গতকাল ও এই সপ্তাহে যা এগিয়েছে',
          ),
        ),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (direction.isEmpty || direction == 'new')
                    Text(
                      GochanoLanguage.text(
                        'Not enough days yet to show a trend',
                        'ট্রেন্ড দেখানোর মতো দিন হয়নি',
                      ),
                      style: context.type.bodySecondary,
                    )
                  else ...[
                    Icon(
                      delta >= 0
                          ? Icons.trending_up_rounded
                          : Icons.trending_down_rounded,
                      size: 20,
                      color: delta >= 0 ? colors.success : colors.error,
                    ),
                    const SizedBox(width: GochanoSpacing.xs),
                    Expanded(
                      child: Text(
                        delta > 0
                            ? GochanoLanguage.text(
                                'Academic Health is up $delta point(s)',
                                'একাডেমিক হেলথ $delta পয়েন্ট এগিয়েছে',
                              )
                            : delta < 0
                            ? GochanoLanguage.text(
                                'Academic Health is down ${-delta} point(s)',
                                'একাডেমিক হেলথ ${-delta} পয়েন্ট পিছিয়েছে',
                              )
                            : GochanoLanguage.text(
                                'Academic Health is holding steady',
                                'একাডেমিক হেলথ একই আছে',
                              ),
                        style: context.type.bodySecondary,
                      ),
                    ),
                  ],
                ],
              ),
              if (movement.isNotEmpty) ...[
                const SizedBox(height: GochanoSpacing.sm),
                for (final item in movement)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: GochanoSpacing.xxs,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${item['label'] ?? item['key'] ?? ''}',
                            style: context.type.caption,
                          ),
                        ),
                        Text(
                          '${_asInt(item['delta']) > 0 ? '+' : ''}${_asInt(item['delta'])}',
                          style: context.type.statisticSmall.copyWith(
                            color: _asInt(item['delta']) > 0
                                ? colors.success
                                : colors.error,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // 5. the weekly report (the only AI-authored part)
  // -------------------------------------------------------------------------

  Widget _weeklySection(BuildContext context) {
    final colors = context.colors;
    final weekly = _weekly;

    if (weekly == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: GochanoLanguage.text('This week', 'এই সপ্তাহ')),
          if (_weeklyError.isNotEmpty) ...[
            AiErrorBanner(message: _weeklyError),
            const SizedBox(height: GochanoSpacing.sm),
            SecondaryButton(
              label: GochanoLanguage.text('Retry report', 'আবার রিপোর্ট'),
              icon: Icons.refresh_rounded,
              expand: false,
              onPressed: _loadWeekly,
            ),
          ] else
            AiLoadingState(
              message: GochanoLanguage.text(
                'Writing this week\u2019s report…',
                'এই সপ্তাহের রিপোর্ট লেখা হচ্ছে…',
              ),
            ),
        ],
      );
    }

    final scoreDelta = _asIntOrNull(weekly['scoreDelta']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: GochanoLanguage.text('This week', 'এই সপ্তাহ'),
          subtitle: GochanoLanguage.text(
            '${weekly['weekStart'] ?? ''} onward · ${_asInt(weekly['studyMinutes'])} minutes studied',
            '${weekly['weekStart'] ?? ''} থেকে · ${_asInt(weekly['studyMinutes'])} মিনিট পড়া',
          ),
        ),
        AppCard(
          accent: colors.ai,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (weekly['aiGenerated'] == true)
                    GochanoBadge(
                      label: GochanoLanguage.text(
                        'Written by Ziku',
                        'জিকু লেখা',
                      ),
                      tone: GochanoBadgeTone.brand,
                      icon: Icons.auto_awesome_rounded,
                    ),
                  if (scoreDelta != null) ...[
                    const SizedBox(width: GochanoSpacing.xs),
                    GochanoBadge(
                      label: GochanoLanguage.text(
                        '${scoreDelta > 0 ? '+' : ''}$scoreDelta score',
                        '${scoreDelta > 0 ? '+' : ''}$scoreDelta স্কোর',
                      ),
                      tone: scoreDelta >= 0
                          ? GochanoBadgeTone.success
                          : GochanoBadgeTone.warning,
                      icon: scoreDelta >= 0
                          ? Icons.trending_up_rounded
                          : Icons.trending_down_rounded,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: GochanoSpacing.sm),
              Text('${weekly['narrative'] ?? ''}', style: context.type.body),
              const SizedBox(height: GochanoSpacing.sm),
              Text(
                GochanoLanguage.text('Next step', 'পরবর্তী পদক্ষেপ'),
                style: context.type.label.copyWith(color: colors.textTertiary),
              ),
              const SizedBox(height: 2),
              Text(
                '${weekly['recommendation'] ?? ''}',
                style: context.type.bodySecondary,
              ),
            ],
          ),
        ),
        const SizedBox(height: GochanoSpacing.sm),
        Row(
          children: [
            Expanded(
              child: StatCard(
                compact: true,
                label: GochanoLanguage.text('Studied', 'পড়া'),
                value: '${_asInt(weekly['studyMinutes'])}m',
                caption: GochanoLanguage.text(
                  '${_asInt(weekly['studyDays'])} days',
                  '${_asInt(weekly['studyDays'])} দিন',
                ),
                icon: Icon(Icons.timer_outlined, size: 16, color: colors.study),
                accent: colors.study,
              ),
            ),
            const SizedBox(width: GochanoSpacing.sm),
            Expanded(
              child: StatCard(
                compact: true,
                label: GochanoLanguage.text('Quiz average', 'কুইজ গড়'),
                value: '${_asInt(weekly['quizAverage'])}%',
                caption: GochanoLanguage.text(
                  'focus ${_asIntOrNull(weekly['focusScore']) ?? '—'}',
                  'ফোকাস ${_asIntOrNull(weekly['focusScore']) ?? '—'}',
                ),
                icon: Icon(Icons.quiz_rounded, size: 16, color: colors.brand),
                accent: colors.brand,
              ),
            ),
            const SizedBox(width: GochanoSpacing.sm),
            Expanded(
              child: StatCard(
                compact: true,
                label: GochanoLanguage.text('Mistakes', 'ভুল'),
                value: '${_asInt(weekly['mistakes'])}',
                caption: GochanoLanguage.text(
                  '${_asInt(weekly['repeatedMistakes'])} repeated',
                  '${_asInt(weekly['repeatedMistakes'])} পুনরাবৃত্ত',
                ),
                icon: Icon(
                  Icons.error_outline_rounded,
                  size: 16,
                  color: colors.error,
                ),
                accent: colors.error,
              ),
            ),
          ],
        ),
        if ('${weekly['weakArea'] ?? ''}'.isNotEmpty) ...[
          const SizedBox(height: GochanoSpacing.sm),
          Text(
            GochanoLanguage.text(
              'Weakest this week: ${weekly['weakArea']} — ${weekly['weakReason'] ?? ''}',
              'এই সপ্তাহে সবচেয়ে দুর্বল: ${weekly['weakArea']} — ${weekly['weakReason'] ?? ''}',
            ),
            style: context.type.caption,
          ),
        ],
      ],
    );
  }

  // -------------------------------------------------------------------------
  // 6. the Personal OS: journey, profile and scoreboard
  // -------------------------------------------------------------------------

  /// Phase 8 — three doors into the Personal OS plus the two payloads Ziku
  /// builds from the same history: the daily brief and the ranked next
  /// action. The doors always render; the cards render only when their read
  /// succeeded, so a failed Phase 8 call leaves this section as three rows.
  Widget _personalOsSection(BuildContext context) {
    final colors = context.colors;
    final brief = _brief;
    final action = _asMap(_action?['action']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: GochanoLanguage.text('Personal OS', 'পার্সোনাল ওএস'),
          subtitle: GochanoLanguage.text(
            'Your journey, your profile and your scoreboard',
            'আপনার যাত্রা, প্রোফাইল ও স্কোরবোর্ড',
          ),
        ),
        if (brief != null) ...[
          _briefCard(context, brief),
          const SizedBox(height: GochanoSpacing.sm),
        ],
        if (action != null) ...[
          _actionCard(context, action, _asList(_action?['alternatives'])),
          const SizedBox(height: GochanoSpacing.sm),
        ],
        CardGroup(
          children: [
            GochanoListRow(
              illustration: GochanoArt.featurePlanner,
              accent: colors.brand,
              title: GochanoLanguage.text(
                'Your Learning Journey',
                'আপনার লার্নিং যাত্রা',
              ),
              subtitle: GochanoLanguage.text(
                '90 days of exams, quizzes, mistakes and focus in one line',
                '৯০ দিনের পরীক্ষা, কুইজ, ভুল ও ফোকাস এক লাইনে',
              ),
              trailing: Icon(
                Icons.chevron_right_rounded,
                color: colors.textTertiary,
              ),
              onTap: () => Navigator.of(context).push(
                GochanoRoute.to(builder: (_) => const LearningJourneyScreen()),
              ),
            ),
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
              trailing: Icon(
                Icons.chevron_right_rounded,
                color: colors.textTertiary,
              ),
              onTap: () => Navigator.of(context).push(
                GochanoRoute.to(
                  builder: (_) => const LearningPersonalityScreen(),
                ),
              ),
            ),
            GochanoListRow(
              illustration: GochanoArt.featureCalendar,
              accent: colors.success,
              title: GochanoLanguage.text('Achievements', 'অর্জন'),
              subtitle: GochanoLanguage.text(
                'MCQ milestones, consistency, improvement and contribution',
                'এমসিকু মাইলফলক, ধারাবাহিকতা, উন্নতি ও অবদান',
              ),
              trailing: Icon(
                Icons.chevron_right_rounded,
                color: colors.textTertiary,
              ),
              onTap: () => Navigator.of(context).push(
                GochanoRoute.to(builder: (_) => const ZikuAchievementsScreen()),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _briefCard(BuildContext context, Map<String, dynamic> brief) {
    final colors = context.colors;
    final morning = _asMap(brief['morning']) ?? <String, dynamic>{};
    final evening = _asMap(brief['evening']) ?? <String, dynamic>{};
    final health = _asMap(morning['academicHealth']);
    final tomorrow = _asMap(evening['tomorrow']);
    final reflection = '${evening['reflection'] ?? ''}';
    final phase = '${brief['phase'] ?? ''}';

    return AppCard(
      accent: colors.brand,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.wb_sunny_outlined, size: 18, color: colors.warning),
              const SizedBox(width: GochanoSpacing.xs),
              Expanded(
                child: Text(
                  GochanoLanguage.text(
                    'Ziku\u2019s daily brief',
                    'জিকুর দৈনিক ব্রিফ',
                  ),
                  style: context.type.label,
                ),
              ),
              GochanoBadge(
                label: phase == 'evening'
                    ? GochanoLanguage.text('Evening', 'সন্ধ্যা')
                    : GochanoLanguage.text('Morning', 'সকাল'),
                tone: phase == 'evening'
                    ? GochanoBadgeTone.info
                    : GochanoBadgeTone.warning,
                icon: phase == 'evening'
                    ? Icons.nights_stay_outlined
                    : Icons.wb_sunny_outlined,
              ),
            ],
          ),
          const SizedBox(height: GochanoSpacing.xs),
          if ('${morning['why'] ?? ''}'.isNotEmpty)
            Text('${morning['why'] ?? ''}', style: context.type.body),
          const SizedBox(height: GochanoSpacing.xs),
          Wrap(
            spacing: GochanoSpacing.xs,
            runSpacing: GochanoSpacing.xxs,
            children: [
              if (health?['score'] != null)
                GochanoBadge(
                  label: GochanoLanguage.text(
                    'Health ${_asInt(health?['score'])}',
                    'হেলথ ${_asInt(health?['score'])}',
                  ),
                  tone: GochanoBadgeTone.success,
                  icon: Icons.favorite_outline_rounded,
                ),
              GochanoBadge(
                label: GochanoLanguage.text(
                  '${_asInt(morning['missionCount'])} step mission',
                  '${_asInt(morning['missionCount'])} ধাপের মিশন',
                ),
                tone: GochanoBadgeTone.neutral,
                icon: Icons.checklist_rounded,
              ),
            ],
          ),
          if ('${evening['summary'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: GochanoSpacing.xs),
            Text(
              '${evening['summary'] ?? ''}',
              style: context.type.bodySecondary,
            ),
          ],
          if (reflection.isNotEmpty) ...[
            const SizedBox(height: GochanoSpacing.xs),
            Text(reflection, style: context.type.bodySecondary),
          ],
          if (tomorrow != null && '${tomorrow['title'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: GochanoSpacing.xs),
            Text(
              GochanoLanguage.text(
                'Tomorrow: ${tomorrow['title']}',
                'আগামীকাল: ${tomorrow['title']}',
              ),
              style: context.type.caption.copyWith(color: colors.brand),
            ),
          ],
        ],
      ),
    );
  }

  Widget _actionCard(
    BuildContext context,
    Map<String, dynamic> action,
    List<Map<String, dynamic>> alternatives,
  ) {
    final colors = context.colors;
    final minutes = _asIntOrNull(action['minutes']);
    final score = _numOrNull(action['score']);
    final target = '${action['target'] ?? ''}';
    final destination = '${action['destination'] ?? ''}';

    return AppCard(
      accent: colors.ai,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bolt_rounded, size: 18, color: colors.ai),
              const SizedBox(width: GochanoSpacing.xs),
              Expanded(
                child: Text(
                  GochanoLanguage.text('Next best action', 'পরবর্তী সেরা কাজ'),
                  style: context.type.label,
                ),
              ),
              GochanoBadge(
                label: '${action['source'] ?? ''}',
                tone: GochanoBadgeTone.brand,
              ),
            ],
          ),
          const SizedBox(height: GochanoSpacing.xs),
          Text('${action['title'] ?? ''}', style: context.type.cardHeading),
          const SizedBox(height: 2),
          Text('${action['detail'] ?? ''}', style: context.type.bodySecondary),
          const SizedBox(height: GochanoSpacing.xs),
          Wrap(
            spacing: GochanoSpacing.xs,
            runSpacing: GochanoSpacing.xxs,
            children: [
              if (minutes != null)
                GochanoBadge(
                  label: GochanoLanguage.text('$minutes min', '$minutes মিনিট'),
                  tone: GochanoBadgeTone.neutral,
                  icon: Icons.timer_outlined,
                ),
              if (score != null)
                GochanoBadge(
                  label: GochanoLanguage.text(
                    'Score ${_num(score)}',
                    'স্কোর ${_num(score)}',
                  ),
                  tone: GochanoBadgeTone.neutral,
                  icon: Icons.speed_rounded,
                ),
            ],
          ),
          if (destination.isNotEmpty)
            _missionAction(context, destination, target) ??
                const SizedBox.shrink(),
          if (alternatives.isNotEmpty) ...[
            const SizedBox(height: GochanoSpacing.xs),
            Text(
              GochanoLanguage.text(
                'Also considered: ${alternatives.map((item) => item['title']).take(2).join(' · ')}',
                'অন্য বিকল্প: ${alternatives.map((item) => item['title']).take(2).join(' · ')}',
              ),
              style: context.type.caption,
            ),
          ],
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 7. hand the numbers back to Ziku
  // -------------------------------------------------------------------------

  Widget _askZikuCard(BuildContext context, Map<String, dynamic> profile) {
    final colors = context.colors;
    final weak = _asList(profile['weakTopics']);
    final exam = _asMap(profile['upcomingExam']);

    return AppCard(
      accent: colors.ai,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            GochanoLanguage.text('Ask Ziku', 'জিকুকে জিজ্ঞেস করুন'),
            style: context.type.cardHeading,
          ),
          const SizedBox(height: 2),
          Text(
            GochanoLanguage.text(
              'Ziku already reads this profile and today\u2019s mission, so the '
                  'answer starts where this screen ends.',
              'জিকু এই প্রোফাইল ও আজকের মিশন পড়েছে — উত্তর এখান থেকেই শুরু হবে।',
            ),
            style: context.type.caption,
          ),
          const SizedBox(height: GochanoSpacing.sm),
          SecondaryButton(
            label: GochanoLanguage.text('Open Ziku', 'জিকু খুলুন'),
            icon: Icons.auto_awesome_rounded,
            expand: false,
            onPressed: () => Navigator.of(context).push(
              GochanoRoute.to(
                builder: (_) => AiAssistantScreen(
                  prefilledQuestion: coachZikuQuestion(
                    topic: weak.isEmpty ? null : '${weak.first['topic'] ?? ''}',
                    exam: exam == null ? null : '${exam['title'] ?? ''}',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Color _toneFor(BuildContext context, int score) {
    final colors = context.colors;
    if (score >= 85) return colors.success;
    if (score >= 70) return colors.info;
    if (score >= 55) return colors.warning;
    return colors.error;
  }

  static int _asInt(dynamic value) => value is num ? value.toInt() : 0;

  static int? _asIntOrNull(dynamic value) =>
      value is num ? value.toInt() : null;

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

  /// Backend reason lists are plain sentences, not objects.
  static List<String> _asStrings(dynamic value) {
    if (value is! List) return <String>[];
    return [
      for (final entry in value)
        if (entry != null && entry.toString().trim().isNotEmpty)
          entry.toString().trim(),
    ];
  }
}
