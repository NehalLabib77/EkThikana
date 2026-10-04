// Phase 7 - the timed run of an Exam Challenge (spec 7.4).
//
// The server starts the clock and serves redacted questions (no answer
// key, no explanation), grades on submit, and only then reveals both
// participants' results. This screen owns the wall clock, the answer
// collection and the hand-off - never the scoring.

import 'dart:async';

import 'package:flutter/material.dart';

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

class ChallengeTakeScreen extends StatefulWidget {
  const ChallengeTakeScreen({
    super.key,
    required this.challengeId,
    this.startFn,
    this.submitFn,
  });

  final String challengeId;
  final CommunityStartChallengeFn? startFn;
  final CommunitySubmitChallengeFn? submitFn;

  @override
  State<ChallengeTakeScreen> createState() => _ChallengeTakeScreenState();
}

class _ChallengeTakeScreenState extends State<ChallengeTakeScreen> {
  List<Map<String, dynamic>> _questions = const <Map<String, dynamic>>[];
  List<dynamic> _answers = const <dynamic>[];
  Map<String, dynamic>? _result;
  int _remaining = 0;
  int _limit = 0;
  Timer? _timer;
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  CommunityStartChallengeFn get _start =>
      widget.startFn ?? ApiService.startChallenge;
  CommunitySubmitChallengeFn get _submitFn =>
      widget.submitFn ?? ApiService.submitChallenge;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _open() async {
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      final payload = await _start(widget.challengeId);
      final questions = ((payload['questions'] as List?) ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .toList();
      final limit = _asInt(payload['timeLimitSeconds']);
      if (questions.isEmpty) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = GochanoLanguage.text(
            'This challenge has no questions left to run.',
            'এই চ্যালেঞ্জে আর কোনো প্রশ্ন নেই।',
          );
        });
        return;
      }
      if (!mounted) return;
      setState(() {
        _questions = questions;
        _answers = List<dynamic>.filled(questions.length, '');
        _limit = limit;
        _remaining = limit;
        _loading = false;
      });
      if (limit > 0) _startClock();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyErrorMessage(error);
      });
    }
  }

  void _startClock() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _onSecond());
  }

  void _onSecond() {
    if (!mounted || _submitting) return;
    setState(() => _remaining -= 1);
    if (_remaining <= 0) {
      _timer?.cancel();
      _submit();
    }
  }

  int _answeredCount() =>
      _answers.where((answer) => '$answer'.trim().isNotEmpty).length;

  Future<void> _submit() async {
    if (_submitting || _loading) return;
    _timer?.cancel();
    setState(() => _submitting = true);
    try {
      final spent = _limit > 0 ? (_limit - _remaining).clamp(0, _limit) : 0;
      final payload = await _submitFn(
        widget.challengeId,
        answers: _answers,
        durationSeconds: spent,
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
    return GochanoScaffold(
      padBody: false,
      appBar: GochanoAppBar(
        title: GochanoLanguage.text('Challenge', 'চ্যালেঞ্জ'),
        subtitle: GochanoLanguage.text(
          'Same clock for both players.',
          'দুজনের জন্যই একই ঘড়ি।',
        ),
        automaticallyImplyLeading: !_submitting,
      ),
      bottomBar: _bottomBar(),
      body: _buildBody(context),
    );
  }

  Widget? _bottomBar() {
    if (_loading || _error != null || _questions.isEmpty) return null;
    if (_result != null) {
      return PrimaryButton(
        label: GochanoLanguage.text('Done', 'হয়েছে'),
        onPressed: () => Navigator.of(context).pop(),
      );
    }
    return PrimaryButton(
      label: GochanoLanguage.text('Submit answers', 'উত্তর জমা দিন'),
      busy: _submitting,
      busyLabel: GochanoLanguage.text('Scoring.', 'মূল্যায়ন হচ্ছে।'),
      onPressed: _submitting ? null : _submit,
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return StaticLoadingState(
        message: GochanoLanguage.text(
          'Starting your challenge…',
          'আপনার চ্যালেঞ্জ শুরু হচ্ছে…',
        ),
      );
    }
    if (_error != null && _questions.isEmpty) {
      return ErrorState(message: _error!, onRetry: _open);
    }
    final result = _result;
    if (result != null) return _resultView(context, result);

    final colors = context.colors;
    final type = context.type;
    final urgent = _limit > 0 && _remaining <= 60;

    return ListView(
      padding: const EdgeInsets.only(bottom: GochanoSpacing.xl),
      children: [
        if (_error != null)
          Padding(
            padding: GochanoSpacing.page,
            child: AppCard(
              accent: colors.error,
              child: Text(_error!, style: type.bodySecondary),
            ),
          ),
        Padding(
          padding: GochanoSpacing.page,
          child: AppCard(
            accent: urgent ? colors.error : colors.community,
            child: Row(
              children: [
                Icon(
                  Icons.timer_outlined,
                  size: GochanoSizes.iconLg,
                  color: urgent ? colors.error : colors.community,
                ),
                const SizedBox(width: GochanoSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        GochanoLanguage.text('Time left', 'বাকি সময়'),
                        style: type.caption,
                      ),
                      Semantics(
                        liveRegion: true,
                        label: GochanoLanguage.text(
                          'Time left $_clock()',
                          'বাকি সময় $_clock()',
                        ),
                        child: Text(
                          _clock(),
                          style: type.statistic.copyWith(
                            color: urgent ? colors.error : null,
                          ),
                        ),
                      ),
                      Text(
                        GochanoLanguage.text(
                          '${_answeredCount()} of ${_questions.length} answered',
                          '${_questions.length}টির মধ্যে ${_answeredCount()} উত্তর দেওয়া হয়েছে',
                        ),
                        style: type.caption,
                      ),
                    ],
                  ),
                ),
                GochanoBadge(
                  label: GochanoLanguage.text(
                    '${_questions.length} questions',
                    '${_questions.length}টি প্রশ্ন',
                  ),
                  tone: GochanoBadgeTone.brand,
                ),
              ],
            ),
          ),
        ),
        for (var i = 0; i < _questions.length; i++)
          _questionCard(context, i, _questions[i]),
      ],
    );
  }

  Widget _questionCard(
    BuildContext context,
    int index,
    Map<String, dynamic> question,
  ) {
    final type = context.type;
    final options = ((question['options'] as List?) ?? const <dynamic>[])
        .map((option) => '$option')
        .toList();
    final isChoice = options.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        GochanoSpacing.md,
        0,
        GochanoSpacing.md,
        GochanoSpacing.sm,
      ),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                GochanoBadge(
                  label: GochanoLanguage.text(
                    'Question ${index + 1}',
                    'প্রশ্ন ${index + 1}',
                  ),
                  tone: GochanoBadgeTone.brand,
                ),
                const SizedBox(width: GochanoSpacing.xs),
                if ('${question['topic'] ?? ''}'.isNotEmpty)
                  GochanoBadge(label: '${question['topic']}'),
              ],
            ),
            const SizedBox(height: GochanoSpacing.sm),
            Text('${question['question'] ?? ''}', style: type.body),
            const SizedBox(height: GochanoSpacing.sm),
            if (isChoice)
              for (var o = 0; o < options.length; o++)
                _optionTile(context, index, o, '${_letterOf(o)}. ${options[o]}')
            else
              TextField(
                key: ValueKey<String>('challenge_q$index'),
                textCapitalization: TextCapitalization.sentences,
                minLines: 1,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: GochanoLanguage.text('Your answer', 'আপনার উত্তর'),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (value) => _answers[index] = value,
              ),
          ],
        ),
      ),
    );
  }

  Widget _optionTile(
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

  Widget _resultView(BuildContext context, Map<String, dynamic> result) {
    final colors = context.colors;
    final type = context.type;
    final mine = result['myResult'] is Map
        ? Map<String, dynamic>.from(result['myResult'] as Map)
        : <String, dynamic>{};
    final theirs = result['opponentResult'] is Map
        ? Map<String, dynamic>.from(result['opponentResult'] as Map)
        : <String, dynamic>{};

    return ListView(
      padding: GochanoSpacing.scrollBody,
      children: [
        SectionHeader(
          title: GochanoLanguage.text('Result', 'ফলাফল'),
          subtitle: challengeStatusLabel('${result['status'] ?? ''}'),
        ),
        AppCard(
          accent: colors.community,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      GochanoLanguage.text('You', 'আপনি'),
                      style: type.cardHeading,
                    ),
                  ),
                  GochanoBadge(
                    label: GochanoLanguage.text(
                      '${mine['score'] ?? 0} / ${mine['total'] ?? 0}',
                      '${mine['score'] ?? 0} / ${mine['total'] ?? 0} নম্বর',
                    ),
                    tone: GochanoBadgeTone.brand,
                    icon: Icons.emoji_events_outlined,
                  ),
                ],
              ),
              const SizedBox(height: GochanoSpacing.xs),
              Text(
                GochanoLanguage.text(
                  'Accuracy ${mine['accuracy'] ?? 0}% · ${mine['durationSeconds'] ?? 0}s',
                  'নির্ভুলতা ${mine['accuracy'] ?? 0}% · ${mine['durationSeconds'] ?? 0} সেকেন্ড',
                ),
                style: type.bodySecondary,
              ),
              const SizedBox(height: GochanoSpacing.sm),
              Wrap(
                spacing: GochanoSpacing.xxs,
                runSpacing: GochanoSpacing.xxs,
                children: [
                  for (final entry in _topicScores(mine))
                    GochanoBadge(
                      label: '${entry.$1}: ${entry.$2}',
                      tone: entry.$3
                          ? GochanoBadgeTone.success
                          : GochanoBadgeTone.warning,
                    ),
                ],
              ),
            ],
          ),
        ),
        if (theirs.isNotEmpty) ...[
          const SizedBox(height: GochanoSpacing.sm),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        GochanoLanguage.text('Rival', 'প্রতিদ্বন্দ্বী'),
                        style: type.cardHeading,
                      ),
                    ),
                    GochanoBadge(
                      label: GochanoLanguage.text(
                        '${theirs['score'] ?? 0} / ${theirs['total'] ?? 0}',
                        '${theirs['score'] ?? 0} / ${theirs['total'] ?? 0} নম্বর',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: GochanoSpacing.xs),
                Text(_comparison(mine, theirs), style: type.bodySecondary),
              ],
            ),
          ),
        ] else
          Padding(
            padding: const EdgeInsets.only(top: GochanoSpacing.sm),
            child: Text(
              GochanoLanguage.text(
                'Your rival has not finished yet - the comparison appears '
                    'when both of you have submitted.',
                'আপনার প্রতিদ্বন্দ্বী এখনো শেষ করেননি - দুজনেই জমা দিলে তুলনা '
                    'দেখা যাবে।',
              ),
              style: type.caption,
            ),
          ),
      ],
    );
  }

  String _comparison(Map<String, dynamic> mine, Map<String, dynamic> theirs) {
    final myScore = _asInt(mine['score']);
    final theirScore = _asInt(theirs['score']);
    if (myScore > theirScore) {
      return GochanoLanguage.text('You lead.', 'আপনি এগিয়ে আছেন।');
    }
    if (myScore < theirScore) {
      return GochanoLanguage.text(
        'Your rival leads.',
        'প্রতিদ্বন্দ্বী এগিয়ে।',
      );
    }
    return GochanoLanguage.text('Level for now.', 'এখন বরাবর।');
  }

  List<(String, String, bool)> _topicScores(Map<String, dynamic> result) {
    final raw = result['topicScores'];
    if (raw is! Map) return const <(String, String, bool)>[];
    final rows = <(String, String, bool)>[];
    raw.forEach((key, value) {
      if (value is Map) {
        final correct = _asInt(value['correct']);
        final total = _asInt(value['total']);
        rows.add(('$key', '$correct/$total', correct >= total));
      }
    });
    return rows;
  }

  String _clock() {
    final seconds = _remaining < 0 ? 0 : _remaining;
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    return '${'$minutes'.padLeft(2, '0')}:${'$rest'.padLeft(2, '0')}';
  }

  static String _letterOf(int index) => String.fromCharCode(65 + index);

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}') ?? 0;
  }
}
