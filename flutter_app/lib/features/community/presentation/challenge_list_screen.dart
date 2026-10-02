// Phase 7 - Exam Challenge Mode (spec 7.4).
//
// The Community tab's "Challenges" segment: the challenges I am part of,
// the invite code I share, the code a classmate gives me, and the entry
// point into a timed head-to-head run.
//
// Grading, the clock and the opponent's result all live on the server;
// this file only picks a paper, shares a code, and hands off to
// `ChallengeTakeScreen` for the run itself.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/design_system/gochano_art.dart';
import '../../../core/design_system/gochano_colors.dart';
import '../../../core/design_system/gochano_illustration.dart';
import '../../../core/design_system/gochano_spacing.dart';
import '../../../core/design_system/gochano_typography.dart';
import '../../../core/localization/gochano_language.dart';
import '../../../core/page_route.dart';
import '../../../services/api_service.dart';
import '../../../shared/states/gochano_states.dart';
import '../../../shared/widgets/gochano_controls.dart';
import '../../../shared/widgets/gochano_surfaces.dart';
import '../domain/community_models.dart';
import 'challenge_take_screen.dart';
import 'community_labels.dart';

/// The body of the Community "Challenges" segment. No scaffold, no app bar.
class ChallengeListView extends StatefulWidget {
  const ChallengeListView({
    super.key,
    this.challengesFn,
    this.joinFn,
    this.declineFn,
    this.createFn,
    this.examsFn,
    this.startFn,
    this.submitFn,
  });

  final CommunityChallengeListFn? challengesFn;
  final CommunityJoinChallengeFn? joinFn;
  final CommunityDeclineChallengeFn? declineFn;
  final CommunityCreateChallengeFn? createFn;
  final CommunityExamsFn? examsFn;
  final CommunityStartChallengeFn? startFn;
  final CommunitySubmitChallengeFn? submitFn;

  @override
  State<ChallengeListView> createState() => _ChallengeListViewState();
}

class _ChallengeListViewState extends State<ChallengeListView> {
  List<ChallengeEntry> _items = const <ChallengeEntry>[];
  bool _loading = true;
  String? _error;

  CommunityChallengeListFn get _list =>
      widget.challengesFn ?? ApiService.listChallenges;
  CommunityJoinChallengeFn get _join =>
      widget.joinFn ?? ApiService.joinChallenge;
  CommunityDeclineChallengeFn get _decline =>
      widget.declineFn ?? ApiService.declineChallenge;
  CommunityCreateChallengeFn get _create =>
      widget.createFn ?? ApiService.createChallenge;
  CommunityExamsFn get _examsFn => widget.examsFn ?? ApiService.listExams;

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
    try {
      final payload = await _list();
      final rows = ((payload['challenges'] as List?) ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(ChallengeEntry.fromJson)
          .toList();
      if (!mounted) return;
      setState(() {
        _items = rows;
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

  Future<void> _copyCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    showGochanoMessage(
      context,
      GochanoLanguage.text('Invite code copied.', 'ইনভাইট কোড কপি হয়েছে।'),
    );
  }

  Future<void> _run(
    Future<Map<String, dynamic>> Function() action, {
    bool reload = true,
  }) async {
    try {
      await action();
      if (reload) await _load();
    } catch (error) {
      if (!mounted) return;
      showGochanoMessage(context, friendlyErrorMessage(error), isError: true);
    }
  }

  Future<void> _start(ChallengeEntry entry) async {
    await Navigator.of(context).push(
      GochanoRoute.to(
        builder: (_) => ChallengeTakeScreen(
          challengeId: entry.id,
          startFn: widget.startFn,
          submitFn: widget.submitFn,
        ),
      ),
    );
    if (!mounted) return;
    await _load();
  }

  Future<void> _joinWithCode() async {
    final code = await showChallengeJoinSheet(context, join: _join);
    if (code == null || !mounted) return;
    await _load();
  }

  Future<void> _newChallenge() async {
    final created = await showNewChallengeSheet(
      context,
      createFn: _create,
      examsFn: _examsFn,
    );
    if (created == null || !mounted) return;
    await _load();
    if (!mounted) return;
    showGochanoMessage(
      context,
      GochanoLanguage.text(
        'Challenge ready. Share code ${created.inviteCode} with your rival.',
        'চ্যালেঞ্জ প্রস্তুত। প্রতিদ্বন্দ্বীকে ${created.inviteCode} কোড দিন।',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            GochanoSpacing.md,
            GochanoSpacing.sm,
            GochanoSpacing.md,
            GochanoSpacing.xs,
          ),
          child: Wrap(
            spacing: GochanoSpacing.sm,
            runSpacing: GochanoSpacing.xs,
            children: [
              PrimaryButton(
                label: GochanoLanguage.text('New challenge', 'নতুন চ্যালেঞ্জ'),
                icon: Icons.add_rounded,
                expand: false,
                onPressed: _newChallenge,
              ),
              SecondaryButton(
                label: GochanoLanguage.text('Join with code', 'কোড দিয়ে যোগ'),
                icon: Icons.password_rounded,
                expand: false,
                onPressed: _joinWithCode,
              ),
            ],
          ),
        ),
        Expanded(child: _buildBody(context)),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return StaticLoadingState(
        compact: true,
        message: GochanoLanguage.text(
          'Loading challenges…',
          'চ্যালেঞ্জ লোড হচ্ছে…',
        ),
      );
    }
    if (_error != null) {
      return ErrorState(compact: true, message: _error!, onRetry: _load);
    }
    if (_items.isEmpty) {
      return EmptyState(
        compact: true,
        illustration: GochanoArt.featureCommunity,
        accent: context.colors.community,
        title: GochanoLanguage.text(
          'No challenges yet',
          'এখনো কোনো চ্যালেঞ্জ নেই',
        ),
        message: GochanoLanguage.text(
          'Pick one of your saved papers, get a code, and challenge a '
              'classmate to the same set of questions.',
          'আপনার সংরক্ষিত পেপার থেকে একটি বেছে নিন, কোড নিন, এবং সমান '
              'প্রশ্নে সহপাঠীকে চ্যালেঞ্জ করুন।',
        ),
        actionLabel: GochanoLanguage.text('New challenge', 'নতুন চ্যালেঞ্জ'),
        onAction: _newChallenge,
        secondaryActionLabel: GochanoLanguage.text(
          'Join with code',
          'কোড দিয়ে যোগ',
        ),
        onSecondaryAction: _joinWithCode,
      );
    }

    return ListView(
      padding: GochanoSpacing.scrollBody,
      children: [
        SectionHeader(
          title: GochanoLanguage.text('Challenges', 'চ্যালেঞ্জ'),
          subtitle: GochanoLanguage.text(
            'Same paper, same clock, compared on accuracy.',
            'একই পেপার, একই সময়, নির্ভুলতায় তুলনা।',
          ),
        ),
        for (final entry in _items) _card(context, entry),
      ],
    );
  }

  Widget _card(BuildContext context, ChallengeEntry entry) {
    final colors = context.colors;
    final type = context.type;
    final rival = entry.myRole == 'challenger'
        ? entry.opponentName
        : entry.challengerName;

    return Padding(
      padding: const EdgeInsets.only(bottom: GochanoSpacing.sm),
      child: AppCard(
        accent: colors.community,
        semanticLabel: entry.title,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GochanoIllustrationTile(
                  GochanoArt.featureCommunity,
                  accent: colors.community,
                  plateSize: 40,
                ),
                const SizedBox(width: GochanoSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        entry.title,
                        style: type.cardHeading,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        rival.isEmpty
                            ? GochanoLanguage.text(
                                'Waiting for a classmate',
                                'সহপাঠীর অপেক্ষায়',
                              )
                            : GochanoLanguage.text(
                                'Against $rival',
                                '$rival এর বিরুদ্ধে',
                              ),
                        style: type.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: GochanoSpacing.xs),
                GochanoBadge(
                  label: challengeStatusLabel(entry.status),
                  tone: _statusTone(entry.status),
                ),
              ],
            ),
            const SizedBox(height: GochanoSpacing.sm),
            Wrap(
              spacing: GochanoSpacing.xxs,
              runSpacing: GochanoSpacing.xxs,
              children: [
                GochanoBadge(
                  label: GochanoLanguage.text(
                    '${entry.questionCount} questions',
                    '${entry.questionCount}টি প্রশ্ন',
                  ),
                  icon: Icons.help_outline_rounded,
                ),
                GochanoBadge(
                  label: GochanoLanguage.text(
                    '${entry.timeLimitMinutes} min',
                    '${entry.timeLimitMinutes} মিনিট',
                  ),
                  icon: Icons.timer_outlined,
                ),
                if (entry.isFinished && entry.myScore != null)
                  GochanoBadge(
                    label: GochanoLanguage.text(
                      'You ${entry.myScore} · rival ${entry.opponentScore ?? 0}',
                      'আপনি ${entry.myScore} · প্রতিদ্বন্দ্বী ${entry.opponentScore ?? 0}',
                    ),
                    tone: GochanoBadgeTone.brand,
                    icon: Icons.emoji_events_outlined,
                  ),
              ],
            ),
            if (entry.status == 'pending' && entry.inviteCode.isNotEmpty) ...[
              const SizedBox(height: GochanoSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      GochanoLanguage.text('Invite code', 'ইনভাইট কোড'),
                      style: type.caption,
                    ),
                  ),
                  Text(entry.inviteCode, style: type.cardHeading),
                  const SizedBox(width: GochanoSpacing.xs),
                  IconActionButton(
                    icon: Icons.copy_rounded,
                    label: GochanoLanguage.text(
                      'Copy invite code',
                      'ইনভাইট কোড কপি',
                    ),
                    accent: colors.community,
                    onPressed: () => _copyCode(entry.inviteCode),
                  ),
                ],
              ),
            ],
            if (entry.status == 'pending' || entry.status == 'accepted') ...[
              const SizedBox(height: GochanoSpacing.sm),
              Wrap(
                spacing: GochanoSpacing.xs,
                children: [
                  if (entry.status == 'accepted')
                    PrimaryButton(
                      label: GochanoLanguage.text('Start', 'শুরু'),
                      icon: Icons.play_arrow_rounded,
                      expand: false,
                      onPressed: () => _start(entry),
                    ),
                  if (entry.status != 'completed')
                    SecondaryButton(
                      label: entry.status == 'pending'
                          ? GochanoLanguage.text('Cancel', 'বাতিল')
                          : GochanoLanguage.text('Decline', 'প্রত্যাখ্যান'),
                      expand: false,
                      onPressed: () => _run(() => _decline(entry.id)),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  GochanoBadgeTone _statusTone(String status) {
    switch (status) {
      case 'pending':
        return GochanoBadgeTone.warning;
      case 'accepted':
        return GochanoBadgeTone.info;
      case 'completed':
        return GochanoBadgeTone.success;
      default:
        return GochanoBadgeTone.error;
    }
  }
}

/// Accept a classmate's invite code. Returns the code only if the join
/// succeeded, so the caller can reload straight after.
Future<String?> showChallengeJoinSheet(
  BuildContext context, {
  required CommunityJoinChallengeFn join,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
      ),
      child: _JoinForm(join: join),
    ),
  );
}

class _JoinForm extends StatefulWidget {
  const _JoinForm({required this.join});

  final CommunityJoinChallengeFn join;

  @override
  State<_JoinForm> createState() => _JoinFormState();
}

class _JoinFormState extends State<_JoinForm> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _code.text.trim();
    if (code.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.join(code);
      if (!mounted) return;
      Navigator.of(context).pop(code);
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
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          GochanoSpacing.lg,
          GochanoSpacing.xs,
          GochanoSpacing.lg,
          GochanoSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              GochanoLanguage.text('Join a challenge', 'চ্যালেঞ্জে যোগ দিন'),
              style: context.type.sectionHeading,
            ),
            const SizedBox(height: GochanoSpacing.md),
            TextField(
              controller: _code,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: GochanoLanguage.text('Invite code', 'ইনভাইট কোড'),
                hintText: 'AB12CD',
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: GochanoSpacing.xs),
              Text(
                _error!,
                style: context.type.bodySecondary.copyWith(color: colors.error),
              ),
            ],
            const SizedBox(height: GochanoSpacing.md),
            PrimaryButton(
              label: GochanoLanguage.text('Join', 'যোগ দিন'),
              busy: _busy,
              onPressed: _busy ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}

/// Pick one of your saved papers, set the length, and send the challenge.
/// Returns the created challenge so the caller can show its invite code.
Future<ChallengeEntry?> showNewChallengeSheet(
  BuildContext context, {
  required CommunityCreateChallengeFn createFn,
  required CommunityExamsFn examsFn,
}) {
  return showModalBottomSheet<ChallengeEntry>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
      ),
      child: _NewChallengeForm(createFn: createFn, examsFn: examsFn),
    ),
  );
}

class _NewChallengeForm extends StatefulWidget {
  const _NewChallengeForm({required this.createFn, required this.examsFn});

  final CommunityCreateChallengeFn createFn;
  final CommunityExamsFn examsFn;

  @override
  State<_NewChallengeForm> createState() => _NewChallengeFormState();
}

class _NewChallengeFormState extends State<_NewChallengeForm> {
  final _count = TextEditingController(text: '10');
  final _minutes = TextEditingController(text: '15');
  List<Map<String, dynamic>> _exams = const <Map<String, dynamic>>[];
  String? _examId;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadExams();
  }

  @override
  void dispose() {
    _count.dispose();
    _minutes.dispose();
    super.dispose();
  }

  Future<void> _loadExams() async {
    try {
      final payload = await widget.examsFn();
      final rows = ((payload['exams'] as List?) ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .toList();
      if (!mounted) return;
      setState(() {
        _exams = rows;
        _examId = rows.isEmpty ? null : '${rows.first['examId'] ?? ''}';
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

  Future<void> _submit() async {
    final examId = _examId ?? '';
    if (examId.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final payload = await widget.createFn(
        examId: examId,
        questionCount: int.tryParse(_count.text.trim()) ?? 10,
        timeLimitMinutes: int.tryParse(_minutes.text.trim()) ?? 15,
      );
      if (!mounted) return;
      Navigator.of(context).pop(ChallengeEntry.fromJson(payload));
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
    final type = context.type;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          GochanoSpacing.lg,
          GochanoSpacing.xs,
          GochanoSpacing.lg,
          GochanoSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              GochanoLanguage.text('New challenge', 'নতুন চ্যালেঞ্জ'),
              style: type.sectionHeading,
            ),
            const SizedBox(height: GochanoSpacing.md),
            if (_loading)
              StaticLoadingState(
                compact: true,
                message: GochanoLanguage.text(
                  'Loading your papers…',
                  'আপনার পেপার লোড হচ্ছে…',
                ),
              )
            else if (_exams.isEmpty)
              Text(
                GochanoLanguage.text(
                  'Save a paper first - challenges are built from your own '
                      'questions.',
                  'আগে একটি পেপার সংরক্ষণ করুন - চ্যালেঞ্জ আপনার নিজের '
                      'প্রশ্ন থেকে তৈরি হয়।',
                ),
                style: type.bodySecondary,
              )
            else ...[
              Text(GochanoLanguage.text('Paper', 'পেপার'), style: type.caption),
              const SizedBox(height: GochanoSpacing.xs),
              for (final exam in _exams) _examTile(context, exam),
              const SizedBox(height: GochanoSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _count,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: GochanoLanguage.text('Questions', 'প্রশ্ন'),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: GochanoSpacing.sm),
                  Expanded(
                    child: TextField(
                      controller: _minutes,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: GochanoLanguage.text('Minutes', 'মিনিট'),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: GochanoSpacing.xs),
              Text(
                _error!,
                style: type.bodySecondary.copyWith(color: colors.error),
              ),
            ],
            const SizedBox(height: GochanoSpacing.md),
            PrimaryButton(
              label: GochanoLanguage.text('Send challenge', 'চ্যালেঞ্জ পাঠান'),
              busy: _busy,
              busyLabel: GochanoLanguage.text('Sending.', 'পাঠানো হচ্ছে।'),
              onPressed: _busy || _examId == null ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }

  Widget _examTile(BuildContext context, Map<String, dynamic> exam) {
    final examId = '${exam['examId'] ?? ''}';
    final selected = examId == _examId;
    final colors = context.colors;
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
          onTap: () => setState(() => _examId = examId),
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
                Expanded(
                  child: Text(
                    '${exam['title'] ?? ''}',
                    style: context.type.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                GochanoBadge(
                  label: GochanoLanguage.text(
                    '${exam['questionCount'] ?? 0} questions',
                    '${exam['questionCount'] ?? 0}টি প্রশ্ন',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
