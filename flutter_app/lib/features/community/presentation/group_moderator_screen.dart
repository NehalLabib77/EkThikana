// Phase 7 - Ziku, the group's AI moderator (spec 7.2), plus the group's
// Learning Points (spec 7.6).
//
// One screen, six jobs, chosen with a chip bar rather than a tab bar so
// the switcher stays usable at 320dp and never needs a ticker:
//
//   ask       ask Ziku anything about the group's material
//   moderate  put two competing answers in front of it for a verdict
//   topics    let it propose what the group should discuss next
//   quiz      have it write a revision quiz, then take it
//   insights  hot chapters, weak topics, and the group's counts
//   points    the group's own Learning Points leaderboard
//
// Every AI call is injectable (`askFn`, `moderateFn`, ...) so the screen
// can be exercised without a network; each section loads on first display.

import 'package:flutter/material.dart';

import '../../../core/design_system/gochano_art.dart';
import '../../../core/design_system/gochano_colors.dart';
import '../../../core/design_system/gochano_spacing.dart';
import '../../../core/design_system/gochano_typography.dart';
import '../../../core/localization/gochano_language.dart';
import '../../../services/api_service.dart';
import '../../../shared/states/gochano_states.dart';
import '../../../shared/widgets/gochano_controls.dart';
import '../../../shared/widgets/gochano_surfaces.dart';
import '../domain/community_models.dart';
import 'community_labels.dart';

class GroupModeratorScreen extends StatefulWidget {
  const GroupModeratorScreen({
    super.key,
    required this.groupId,
    this.groupName = '',
    this.askFn,
    this.moderateFn,
    this.topicsFn,
    this.quizFn,
    this.attemptFn,
    this.quizzesFn,
    this.insightsFn,
    this.leaderboardFn,
    this.initialSection = 'ask',
  });

  final String groupId;
  final String groupName;

  final CommunityZikuAskFn? askFn;
  final CommunityZikuModerateFn? moderateFn;
  final CommunityZikuTopicsFn? topicsFn;
  final CommunityZikuQuizFn? quizFn;
  final CommunityAttemptQuizFn? attemptFn;
  final CommunityQuizzesFn? quizzesFn;
  final CommunityInsightsFn? insightsFn;
  final CommunityLeaderboardFn? leaderboardFn;
  final String initialSection;

  @override
  State<GroupModeratorScreen> createState() => _GroupModeratorScreenState();
}

class _GroupModeratorScreenState extends State<GroupModeratorScreen> {
  late String _section;

  @override
  void initState() {
    super.initState();
    _section = widget.initialSection;
  }

  @override
  Widget build(BuildContext context) {
    return GochanoScaffold(
      appBar: GochanoAppBar(
        title: GochanoLanguage.text('Ziku Moderator', 'জিকু মডারেটর'),
        subtitle: widget.groupName.isEmpty
            ? GochanoLanguage.text(
                'Your group’s assistant',
                'আপনার গ্রুপের সহকারী',
              )
            : widget.groupName,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilterChipBar<String>(
            options: kModeratorSections,
            selected: _section,
            onSelected: (value) => setState(() => _section = value),
            labelOf: moderatorSectionLabel,
          ),
          const SizedBox(height: GochanoSpacing.sm),
          Expanded(child: _buildSection(context)),
        ],
      ),
    );
  }

  Widget _buildSection(BuildContext context) {
    switch (_section) {
      case 'moderate':
        return _ModerateSection(groupId: widget.groupId, fn: widget.moderateFn);
      case 'topics':
        return _TopicsSection(groupId: widget.groupId, fn: widget.topicsFn);
      case 'quiz':
        return _QuizSection(
          groupId: widget.groupId,
          quizFn: widget.quizFn,
          attemptFn: widget.attemptFn,
          quizzesFn: widget.quizzesFn,
        );
      case 'insights':
        return _InsightsSection(groupId: widget.groupId, fn: widget.insightsFn);
      case 'points':
        return _PointsSection(
          groupId: widget.groupId,
          fn: widget.leaderboardFn,
        );
      default:
        return _AskSection(groupId: widget.groupId, fn: widget.askFn);
    }
  }
}

// ---------------------------------------------------------------------------
// Ask Ziku
// ---------------------------------------------------------------------------

class _AskSection extends StatefulWidget {
  const _AskSection({required this.groupId, this.fn});

  final String groupId;
  final CommunityZikuAskFn? fn;

  @override
  State<_AskSection> createState() => _AskSectionState();
}

class _AskSectionState extends State<_AskSection> {
  final _question = TextEditingController();
  String? _answer;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _question.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    final text = _question.text.trim();
    if (text.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final ask = widget.fn ?? ApiService.groupZikuAsk;
    try {
      final payload = await ask(widget.groupId, text);
      if (!mounted) return;
      setState(() {
        _answer = '${payload['answer'] ?? ''}';
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = friendlyErrorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ListView(
      padding: GochanoSpacing.scrollBody,
      children: [
        SectionHeader(
          title: GochanoLanguage.text('Ask Ziku', 'জিকুকে জিজ্ঞাসা'),
          subtitle: GochanoLanguage.text(
            'It answers from your group’s own questions and material.',
            'আপনার গ্রুপের নিজের প্রশ্ন ও উপকরণ থেকে উত্তর দেয়।',
          ),
        ),
        TextField(
          controller: _question,
          minLines: 3,
          maxLines: 6,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: GochanoLanguage.text('Your question', 'আপনার প্রশ্ন'),
            hintText: GochanoLanguage.text(
              'Why does the derivative vanish here?',
              'কেন এখানে ডেরিভেটিভ শূন্য হয়?',
            ),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: GochanoSpacing.sm),
        PrimaryButton(
          label: GochanoLanguage.text('Ask Ziku', 'জিকুকে জিজ্ঞাসা'),
          busy: _busy,
          busyLabel: GochanoLanguage.text('Thinking.', 'ভাবছে।'),
          onPressed: _busy ? null : _ask,
        ),
        if (_error != null) ...[
          const SizedBox(height: GochanoSpacing.xs),
          Text(
            _error!,
            style: context.type.bodySecondary.copyWith(color: colors.error),
          ),
        ],
        if (_answer != null) ...[
          const SizedBox(height: GochanoSpacing.md),
          AppCard(
            accent: colors.ai,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                GochanoBadge(
                  label: GochanoLanguage.text('Ziku', 'জিকু'),
                  tone: GochanoBadgeTone.brand,
                  icon: Icons.auto_awesome_outlined,
                ),
                const SizedBox(height: GochanoSpacing.sm),
                Text(_answer!, style: context.type.body),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Moderate two competing answers
// ---------------------------------------------------------------------------

class _ModerateSection extends StatefulWidget {
  const _ModerateSection({required this.groupId, this.fn});

  final String groupId;
  final CommunityZikuModerateFn? fn;

  @override
  State<_ModerateSection> createState() => _ModerateSectionState();
}

class _ModerateSectionState extends State<_ModerateSection> {
  final _claimA = TextEditingController();
  final _claimB = TextEditingController();
  String? _analysis;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _claimA.dispose();
    _claimB.dispose();
    super.dispose();
  }

  Future<void> _compare() async {
    final a = _claimA.text.trim();
    final b = _claimB.text.trim();
    if (a.isEmpty || b.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final moderate = widget.fn ?? ApiService.groupZikuModerate;
    try {
      final payload = await moderate(widget.groupId, claimA: a, claimB: b);
      if (!mounted) return;
      setState(() {
        _analysis = '${payload['analysis'] ?? ''}';
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = friendlyErrorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ListView(
      padding: GochanoSpacing.scrollBody,
      children: [
        SectionHeader(
          title: GochanoLanguage.text('Moderate', 'মডারেট'),
          subtitle: GochanoLanguage.text(
            'Put both sides in. Ziku judges the reasoning, not the writer.',
            'দুই পক্ষ লিখুন। জিকু যুক্তি দেখে, লেখককে দেখে নয়।',
          ),
        ),
        TextField(
          controller: _claimA,
          minLines: 2,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: GochanoLanguage.text(
              'Student A says',
              'শিক্ষার্থী এ বলেছে',
            ),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: GochanoSpacing.sm),
        TextField(
          controller: _claimB,
          minLines: 2,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: GochanoLanguage.text(
              'Student B says',
              'শিক্ষার্থী বি বলেছে',
            ),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: GochanoSpacing.sm),
        PrimaryButton(
          label: GochanoLanguage.text('Compare', 'তুলনা করুন'),
          busy: _busy,
          busyLabel: GochanoLanguage.text('Comparing.', 'তুলনা হচ্ছে।'),
          onPressed: _busy ? null : _compare,
        ),
        if (_error != null) ...[
          const SizedBox(height: GochanoSpacing.xs),
          Text(
            _error!,
            style: context.type.bodySecondary.copyWith(color: colors.error),
          ),
        ],
        if (_analysis != null) ...[
          const SizedBox(height: GochanoSpacing.md),
          AppCard(
            accent: colors.ai,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                GochanoBadge(
                  label: GochanoLanguage.text('Verdict', 'রায়'),
                  tone: GochanoBadgeTone.brand,
                  icon: Icons.balance_rounded,
                ),
                const SizedBox(height: GochanoSpacing.sm),
                Text(_analysis!, style: context.type.body),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Suggested discussion topics
// ---------------------------------------------------------------------------

class _TopicsSection extends StatefulWidget {
  const _TopicsSection({required this.groupId, this.fn});

  final String groupId;
  final CommunityZikuTopicsFn? fn;

  @override
  State<_TopicsSection> createState() => _TopicsSectionState();
}

class _TopicsSectionState extends State<_TopicsSection> {
  List<Map<String, dynamic>> _topics = const <Map<String, dynamic>>[];
  String _source = '';
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _busy = true;
      _error = null;
    });
    final topics = widget.fn ?? ApiService.groupZikuTopics;
    try {
      final payload = await topics(widget.groupId);
      final rows = ((payload['topics'] as List?) ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .toList();
      if (!mounted) return;
      setState(() {
        _topics = rows;
        _source = '${payload['source'] ?? ''}';
        _loading = false;
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _busy = false;
        _error = friendlyErrorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (_loading) {
      return StaticLoadingState(
        message: GochanoLanguage.text(
          'Reading the group…',
          'গ্রুপ পড়া হচ্ছে…',
        ),
      );
    }
    if (_error != null) {
      return ErrorState(
        compact: true,
        message: _error!,
        onRetry: _load,
        title: GochanoLanguage.text(
          'Nothing to discuss yet',
          'এখনো আলোচনার কিছু নেই',
        ),
      );
    }
    if (_topics.isEmpty) {
      return EmptyState(
        compact: true,
        illustration: GochanoArt.featureGroups,
        title: GochanoLanguage.text(
          'Nothing to discuss yet',
          'এখনো আলোচনার কিছু নেই',
        ),
        message: GochanoLanguage.text(
          'Ask a few questions first and Ziku will suggest where to go.',
          'আগে কয়েকটি প্রশ্ন করুন, তারপর জিকু পরামর্শ দেবে।',
        ),
        actionLabel: GochanoLanguage.text('Refresh', 'নতুন করে'),
        onAction: _load,
      );
    }
    return ListView(
      padding: GochanoSpacing.scrollBody,
      children: [
        SectionHeader(
          title: GochanoLanguage.text('Discussion topics', 'আলোচনা টপিক'),
          subtitle: GochanoLanguage.text(
            'Based on this group’s hot chapters and weak topics.',
            'গ্রুপের জনপ্রিয় অধ্যায় ও দুর্বল টপিকের ভিত্তিতে।',
          ),
          action: PrimaryButton(
            label: GochanoLanguage.text('Refresh', 'নতুন করে'),
            icon: Icons.refresh_rounded,
            expand: false,
            busy: _busy,
            onPressed: _busy ? null : _load,
          ),
        ),
        if (_source.isNotEmpty) ...[
          GochanoBadge(
            label: _source == 'ai'
                ? GochanoLanguage.text('From Ziku', 'জিকু থেকে')
                : GochanoLanguage.text('From group signal', 'গ্রুপ সংকেত থেকে'),
            tone: GochanoBadgeTone.info,
          ),
          const SizedBox(height: GochanoSpacing.sm),
        ],
        for (final topic in _topics)
          Padding(
            padding: const EdgeInsets.only(bottom: GochanoSpacing.sm),
            child: AppCard(
              accent: colors.ai,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${topic['title'] ?? ''}',
                    style: context.type.cardHeading,
                  ),
                  const SizedBox(height: GochanoSpacing.xs),
                  Text(
                    '${topic['reason'] ?? ''}',
                    style: context.type.bodySecondary,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Group quiz written and taken through Ziku
// ---------------------------------------------------------------------------

class _QuizSection extends StatefulWidget {
  const _QuizSection({
    required this.groupId,
    this.quizFn,
    this.attemptFn,
    this.quizzesFn,
  });

  final String groupId;
  final CommunityZikuQuizFn? quizFn;
  final CommunityAttemptQuizFn? attemptFn;
  final CommunityQuizzesFn? quizzesFn;

  @override
  State<_QuizSection> createState() => _QuizSectionState();
}

class _QuizSectionState extends State<_QuizSection> {
  final _topic = TextEditingController();
  final _count = TextEditingController(text: '5');
  List<Map<String, dynamic>> _questions = const <Map<String, dynamic>>[];
  List<dynamic> _answers = const <dynamic>[];
  List<Map<String, dynamic>> _saved = const <Map<String, dynamic>>[];
  String _quizId = '';
  Map<String, dynamic>? _result;
  bool _generating = false;
  bool _submitting = false;
  bool _loadingSaved = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  @override
  void dispose() {
    _topic.dispose();
    _count.dispose();
    super.dispose();
  }

  Future<void> _loadSaved() async {
    final list = widget.quizzesFn ?? ApiService.listGroupQuizzes;
    try {
      final payload = await list(widget.groupId);
      final rows = ((payload['quizzes'] as List?) ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .toList();
      if (!mounted) return;
      setState(() {
        _saved = rows;
        _loadingSaved = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingSaved = false);
    }
  }

  Future<void> _generate() async {
    if (_generating) return;
    setState(() {
      _generating = true;
      _error = null;
      _result = null;
    });
    final generate = widget.quizFn ?? ApiService.groupZikuQuiz;
    try {
      final payload = await generate(
        widget.groupId,
        topic: _topic.text.trim(),
        questionCount: int.tryParse(_count.text.trim()) ?? 5,
      );
      final questions = ((payload['questions'] as List?) ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .toList();
      final problem = '${payload['error'] ?? ''}';
      if (!mounted) return;
      setState(() {
        _quizId = '${payload['quizId'] ?? ''}';
        _questions = questions;
        _answers = List<dynamic>.filled(questions.length, '');
        _generating = false;
        _error = problem.isEmpty ? null : problem;
      });
      if (questions.isNotEmpty) _loadSaved();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _generating = false;
        _error = friendlyErrorMessage(error);
      });
    }
  }

  Future<void> _submitAttempt() async {
    if (_submitting || _quizId.isEmpty) return;
    setState(() => _submitting = true);
    final attempt = widget.attemptFn ?? ApiService.attemptGroupQuiz;
    try {
      final payload = await attempt(
        widget.groupId,
        _quizId,
        answers: _answers,
        durationSeconds: 0,
      );
      if (!mounted) return;
      setState(() {
        _result = payload;
        _submitting = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = friendlyErrorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: GochanoSpacing.scrollBody,
      children: [
        SectionHeader(
          title: GochanoLanguage.text('Group quiz', 'গ্রুপ কুইজ'),
          subtitle: GochanoLanguage.text(
            'Ziku writes it from your weak topics; the server grades it.',
            'জিকু দুর্বল টপিক থেকে লেখে; সার্ভার মূল্যায়ন করে।',
          ),
        ),
        TextField(
          controller: _topic,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: GochanoLanguage.text(
              'Topic (optional)',
              'টপিক (ঐচ্ছিক)',
            ),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: GochanoSpacing.sm),
        TextField(
          controller: _count,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: GochanoLanguage.text('Questions', 'প্রশ্ন'),
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: GochanoSpacing.sm),
        PrimaryButton(
          label: GochanoLanguage.text('Generate quiz', 'কুইজ তৈরি করুন'),
          busy: _generating,
          busyLabel: GochanoLanguage.text('Writing.', 'লিখছে।'),
          onPressed: _generating ? null : _generate,
        ),
        if (_error != null) ...[
          const SizedBox(height: GochanoSpacing.xs),
          Text(
            _error!,
            style: context.type.bodySecondary.copyWith(
              color: context.colors.error,
            ),
          ),
        ],
        if (_questions.isNotEmpty) ...[
          const SizedBox(height: GochanoSpacing.md),
          for (var i = 0; i < _questions.length; i++)
            _question(context, i, _questions[i]),
          const SizedBox(height: GochanoSpacing.sm),
          if (_result == null)
            PrimaryButton(
              label: GochanoLanguage.text('Submit answers', 'উত্তর জমা দিন'),
              busy: _submitting,
              onPressed: _submitting ? null : _submitAttempt,
            )
          else
            _scoreCard(context),
        ],
        if (!_loadingSaved && _saved.isNotEmpty) ...[
          SectionHeader(
            title: GochanoLanguage.text('Saved quizzes', 'সংরক্ষিত কুইজ'),
            subtitle: GochanoLanguage.text(
              'Written for this group before.',
              'আগে এই গ্রুপের জন্য লেখা।',
            ),
          ),
          for (final quiz in _saved)
            Padding(
              padding: const EdgeInsets.only(bottom: GochanoSpacing.xs),
              child: AppCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: GochanoSpacing.md,
                  vertical: GochanoSpacing.sm,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${quiz['title'] ?? ''}',
                        style: context.type.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    GochanoBadge(
                      label: GochanoLanguage.text(
                        '${quiz['attemptCount'] ?? 0} taken',
                        '${quiz['attemptCount'] ?? 0} বার দেওয়া',
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _question(BuildContext context, int index, Map<String, dynamic> q) {
    final options = ((q['options'] as List?) ?? const <dynamic>[])
        .map((option) => '$option')
        .toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: GochanoSpacing.sm),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            GochanoBadge(
              label: GochanoLanguage.text(
                'Question ${index + 1}',
                'প্রশ্ন ${index + 1}',
              ),
              tone: GochanoBadgeTone.brand,
            ),
            const SizedBox(height: GochanoSpacing.sm),
            Text('${q['question'] ?? ''}', style: context.type.body),
            const SizedBox(height: GochanoSpacing.sm),
            for (var o = 0; o < options.length; o++)
              _option(context, index, o, options[o]),
          ],
        ),
      ),
    );
  }

  Widget _option(
    BuildContext context,
    int questionIndex,
    int optionIndex,
    String label,
  ) {
    final colors = context.colors;
    final selected = '${_answers[questionIndex]}' == '$optionIndex';
    return Padding(
      padding: const EdgeInsets.only(bottom: GochanoSpacing.xs),
      child: Material(
        color: selected ? colors.brandSoft : colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: GochanoRadius.mdAll,
          side: BorderSide(
            color: selected ? colors.brand : colors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => setState(() => _answers[questionIndex] = '$optionIndex'),
          child: Padding(
            padding: const EdgeInsets.all(GochanoSpacing.sm),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: GochanoSizes.iconMd,
                  color: selected ? colors.brand : colors.textTertiary,
                ),
                const SizedBox(width: GochanoSpacing.sm),
                Expanded(child: Text(label, style: context.type.body)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _scoreCard(BuildContext context) {
    final result = _result ?? const <String, dynamic>{};
    return AppCard(
      accent: context.colors.success,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          GochanoBadge(
            label: GochanoLanguage.text('Scored', 'মূল্যায়ন হয়েছে'),
            tone: GochanoBadgeTone.success,
            icon: Icons.check_circle_rounded,
          ),
          const SizedBox(height: GochanoSpacing.sm),
          Text(
            GochanoLanguage.text(
              '${result['score'] ?? 0} / ${result['total'] ?? 0} correct · ${result['accuracy'] ?? 0}%',
              '${result['score'] ?? 0} / ${result['total'] ?? 0} সঠিক · ${result['accuracy'] ?? 0}%',
            ),
            style: context.type.sectionHeading,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Group insights
// ---------------------------------------------------------------------------

class _InsightsSection extends StatefulWidget {
  const _InsightsSection({required this.groupId, this.fn});

  final String groupId;
  final CommunityInsightsFn? fn;

  @override
  State<_InsightsSection> createState() => _InsightsSectionState();
}

class _InsightsSectionState extends State<_InsightsSection> {
  Map<String, dynamic> _data = const <String, dynamic>{};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final insights = widget.fn ?? ApiService.groupInsights;
    try {
      final payload = await insights(widget.groupId);
      if (!mounted) return;
      setState(() {
        _data = payload;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyErrorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return StaticLoadingState(
        message: GochanoLanguage.text(
          'Reading the group…',
          'গ্রুপ পড়া হচ্ছে…',
        ),
      );
    }
    if (_error != null) {
      return ErrorState(message: _error!, onRetry: _load);
    }
    final hot = ((_data['hotChapters'] as List?) ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>();
    final weak = ((_data['weakTopics'] as List?) ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>();

    return ListView(
      padding: GochanoSpacing.scrollBody,
      children: [
        SectionHeader(
          title: GochanoLanguage.text('Group signals', 'গ্রুপ সংকেত'),
          subtitle: GochanoLanguage.text(
            'What the group is asking, and where it keeps losing marks.',
            'গ্রুপ কী জিজ্ঞাসা করছে, কোথায় বারবার নম্বর হারাচ্ছে।',
          ),
        ),
        Wrap(
          spacing: GochanoSpacing.xs,
          runSpacing: GochanoSpacing.xs,
          children: [
            GochanoBadge(
              label: GochanoLanguage.text(
                '${_data['questionCount'] ?? 0} questions',
                '${_data['questionCount'] ?? 0}টি প্রশ্ন',
              ),
              icon: Icons.help_outline_rounded,
            ),
            GochanoBadge(
              label: GochanoLanguage.text(
                '${_data['quizCount'] ?? 0} quiz attempts',
                '${_data['quizCount'] ?? 0}টি কুইজ চেষ্টা',
              ),
              icon: Icons.assignment_turned_in_outlined,
            ),
          ],
        ),
        SectionHeader(
          title: GochanoLanguage.text('Hot chapters', 'জনপ্রিয় অধ্যায়'),
        ),
        if (hot.isEmpty)
          _line(context, GochanoLanguage.text('None yet.', 'এখনো নেই।'))
        else
          for (final row in hot)
            _line(context, '${row['chapter'] ?? ''} · ${row['count'] ?? 0}'),
        SectionHeader(
          title: GochanoLanguage.text('Weak topics', 'দুর্বল টপিক'),
        ),
        if (weak.isEmpty)
          _line(
            context,
            GochanoLanguage.text(
              'No weak spot showing yet.',
              'এখনো কোনো দুর্বলতা দেখা যায়নি।',
            ),
          )
        else
          for (final row in weak)
            _line(context, '${row['topic'] ?? ''} · ${row['accuracy'] ?? 0}%'),
      ],
    );
  }

  Widget _line(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(bottom: GochanoSpacing.xs),
    child: Text(text, style: context.type.body),
  );
}

// ---------------------------------------------------------------------------
// The group's Learning Points
// ---------------------------------------------------------------------------

class _PointsSection extends StatefulWidget {
  const _PointsSection({required this.groupId, this.fn});

  final String groupId;
  final CommunityLeaderboardFn? fn;

  @override
  State<_PointsSection> createState() => _PointsSectionState();
}

class _PointsSectionState extends State<_PointsSection> {
  List<Map<String, dynamic>> _entries = const <Map<String, dynamic>>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final leaderboard = widget.fn ?? ApiService.leaderboard;
    try {
      final payload = await leaderboard(
        scope: 'group',
        groupId: widget.groupId,
      );
      final rows = ((payload['entries'] as List?) ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .toList();
      if (!mounted) return;
      setState(() {
        _entries = rows;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyErrorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return StaticLoadingState(
        message: GochanoLanguage.text('Loading points…', 'পয়েন্ট লোড হচ্ছে…'),
      );
    }
    if (_error != null) {
      return ErrorState(message: _error!, onRetry: _load);
    }
    if (_entries.isEmpty) {
      return EmptyState(
        compact: true,
        illustration: GochanoArt.featureGroups,
        title: GochanoLanguage.text('No points yet', 'এখনো কোনো পয়েন্ট নেই'),
        message: GochanoLanguage.text(
          'Answer, accept, and share notes to earn the group’s first '
              'Learning Points.',
          'উত্তর দিন, গ্রহণ করুন, নোট শেয়ার করুন - গ্রুপের প্রথম লার্নিং '
              'পয়েন্ট অর্জন করুন।',
        ),
      );
    }
    return ListView(
      padding: GochanoSpacing.scrollBody,
      children: [
        SectionHeader(
          title: GochanoLanguage.text('Learning Points', 'লার্নিং পয়েন্ট'),
          subtitle: GochanoLanguage.text(
            'Only this group’s own contributors.',
            'শুধু এই গ্রুপের অবদানকারীরা।',
          ),
        ),
        for (var i = 0; i < _entries.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: GochanoSpacing.xs),
            child: AppCard(
              padding: const EdgeInsets.symmetric(
                horizontal: GochanoSpacing.md,
                vertical: GochanoSpacing.sm,
              ),
              child: Row(
                children: [
                  Text('${i + 1}', style: context.type.cardHeading),
                  const SizedBox(width: GochanoSpacing.sm),
                  Expanded(
                    child: Text(
                      '${_entries[i]['displayName'] ?? ''}',
                      style: context.type.body,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  GochanoBadge(
                    label: GochanoLanguage.text(
                      '${_entries[i]['points'] ?? 0} points',
                      '${_entries[i]['points'] ?? 0} পয়েন্ট',
                    ),
                    tone: GochanoBadgeTone.brand,
                    icon: Icons.emoji_events_outlined,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
