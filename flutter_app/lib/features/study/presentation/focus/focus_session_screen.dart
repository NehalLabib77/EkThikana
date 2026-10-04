// Phase 5 — "Ziku Focus": the deep-work timer.
//
// One session, one screen: say what this block covers, count a 25-minute
// block down, pause and resume, then finish. Every write goes through the
// focus engine (`POST /api/focus/start` + `PATCH /api/study/focus/{id}` +
// `POST /api/focus/complete`), which is the same `focus_sessions` store the
// rest of the app already reads — this screen adds no tracking system of
// its own.
//
// The completion card shows what the server decided (per-session score,
// rolling Focus Score, smart nudge), never a client-side invention. Read
// hooks are injectable so tests never open a socket; a failed read degrades
// to a retry line rather than taking the screen down.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/design_system/gochano_art.dart';
import '../../../../core/design_system/gochano_colors.dart';
import '../../../../core/design_system/gochano_spacing.dart';
import '../../../../core/design_system/gochano_typography.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../services/api_service.dart';
import '../../../../shared/states/gochano_states.dart';
import '../../../../shared/widgets/gochano_controls.dart';
import '../../../../shared/widgets/gochano_surfaces.dart';

/// Starts a block on the focus engine.
typedef FocusStartFn = Future<Map<String, dynamic>> Function({
  String label,
  int plannedMinutes,
  String subject,
  String topic,
});

/// Pause / resume a live block (legacy PATCH route, same store).
typedef FocusPatchFn = Future<Map<String, dynamic>> Function(
  String focusId,
  String action,
);

/// Finishes a block; returns the session plus the fresh `today` snapshot.
typedef FocusCompleteFn = Future<Map<String, dynamic>> Function(
  String focusId, {
  String? subject,
  String? topic,
});

/// Reads today's minutes, score, streak and nudge.
typedef FocusTodayFn = Future<Map<String, dynamic>> Function();

/// `25:00`-style clock used by the timer and its tests.
String focusClock(int seconds) {
  final safe = seconds < 0 ? 0 : seconds;
  final minutes = (safe ~/ 60).toString().padLeft(2, '0');
  final rest = (safe % 60).toString().padLeft(2, '0');
  return '$minutes:$rest';
}

/// The backend's score band, kept in sync with `focus_service.SCORE_BANDS`.
String focusBandLabel(String? band) {
  switch (band) {
    case 'excellent':
      return GochanoLanguage.text('Deep focus streak', 'গভীর ফোকাসের স্ট্রিক');
    case 'developing':
      return GochanoLanguage.text('Solid rhythm', 'স্থির ছন্দ');
    default:
      return GochanoLanguage.text('Needs structure', 'কাঠামো দরকার');
  }
}

GochanoBadgeTone focusBandTone(String? band) {
  switch (band) {
    case 'excellent':
      return GochanoBadgeTone.success;
    case 'developing':
      return GochanoBadgeTone.info;
    case 'needs_structure':
      return GochanoBadgeTone.warning;
    default:
      return GochanoBadgeTone.neutral;
  }
}

enum _Phase { idle, running, paused, done }

class FocusSessionScreen extends StatefulWidget {
  const FocusSessionScreen({
    super.key,
    this.initialSubject = '',
    this.initialTopic = '',
    this.plannedMinutes = 25,
    this.sessionId,
    this.startFn,
    this.patchFn,
    this.completeFn,
    this.todayFn,
  });

  /// Subject shown in the finished session (re-tagged on complete).
  final String initialSubject;

  /// What this block covers — the mission step, a weak area, anything.
  final String initialTopic;

  /// Block length in minutes. The engine plans for 25 by default.
  final int plannedMinutes;

  /// Resume a session the Home card found still running.
  final String? sessionId;

  final FocusStartFn? startFn;
  final FocusPatchFn? patchFn;
  final FocusCompleteFn? completeFn;
  final FocusTodayFn? todayFn;

  @override
  State<FocusSessionScreen> createState() => _FocusSessionScreenState();
}

class _FocusSessionScreenState extends State<FocusSessionScreen> {
  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _topicController = TextEditingController();

  FocusStartFn get _start => widget.startFn ?? ApiService.focusEngineStart;
  FocusPatchFn get _patch => widget.patchFn ?? ApiService.patchFocus;
  FocusCompleteFn get _complete =>
      widget.completeFn ?? ApiService.focusEngineComplete;
  FocusTodayFn get _readToday => widget.todayFn ?? ApiService.focusEngineToday;

  _Phase _phase = _Phase.idle;
  Timer? _timer;

  String? _sessionId;
  late int _totalSeconds;
  int _remaining = 0;
  bool _busy = false;

  Map<String, dynamic>? _today;
  Map<String, dynamic>? _result;
  Object? _error;
  Object? _todayError;

  @override
  void initState() {
    super.initState();
    final minutes = widget.plannedMinutes < 1 ? 1 : widget.plannedMinutes;
    _totalSeconds = minutes * 60;
    _remaining = _totalSeconds;
    _subjectController.text = widget.initialSubject;
    _topicController.text = widget.initialTopic;
    _loadToday();
    final resumed = widget.sessionId;
    if (resumed != null && resumed.isNotEmpty) {
      _sessionId = resumed;
      _phase = _Phase.running;
      _startTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _subjectController.dispose();
    _topicController.dispose();
    super.dispose();
  }

  Future<void> _loadToday() async {
    try {
      final body = await _readToday();
      if (!mounted) return;
      setState(() {
        _today = body;
        _todayError = null;
      });
    } catch (err) {
      // Non-blocking: the timer still works without the snapshot.
      if (!mounted) return;
      setState(() => _todayError = err);
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _onSecond());
  }

  void _onSecond() {
    if (_remaining <= 0) {
      _timer?.cancel();
      return;
    }
    setState(() {
      _remaining -= 1;
      if (_remaining == 0) _timer?.cancel();
    });
  }

  Future<void> _startSession() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final body = await _start(
        label: _topicController.text.trim(),
        plannedMinutes: widget.plannedMinutes,
        subject: _subjectController.text.trim(),
        topic: _topicController.text.trim(),
      );
      if (!mounted) return;
      final id = '${body['id'] ?? ''}';
      setState(() {
        _sessionId = id.isEmpty ? null : id;
        _phase = _Phase.running;
        _busy = false;
        _remaining = _totalSeconds;
      });
      if (id.isNotEmpty) _startTimer();
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = err;
      });
    }
  }

  Future<void> _togglePause() async {
    final id = _sessionId;
    if (id == null || _busy) return;
    final resuming = _phase == _Phase.paused;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _patch(id, resuming ? 'resume' : 'pause');
      if (!mounted) return;
      setState(() {
        _phase = resuming ? _Phase.running : _Phase.paused;
        _busy = false;
      });
      if (resuming) {
        _startTimer();
      } else {
        _timer?.cancel();
      }
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = err;
      });
    }
  }

  Future<void> _finish() async {
    final id = _sessionId;
    if (id == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final body = await _complete(
        id,
        subject: _subjectController.text.trim(),
        topic: _topicController.text.trim(),
      );
      if (!mounted) return;
      _timer?.cancel();
      final today = body['today'];
      setState(() {
        _result = body;
        if (today is Map) _today = Map<String, dynamic>.from(today);
        _phase = _Phase.done;
        _busy = false;
      });
      await _loadToday();
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = err;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_phase == _Phase.done) return _buildDone(context);

    return GochanoScaffold(
      appBar: GochanoAppBar(
        title: GochanoLanguage.text('Ziku Focus', 'জিকু ফোকাস'),
        subtitle: _today == null
            ? null
            : GochanoLanguage.text(
                '${_asInt(_today!['minutes'])}/'
                '${_asInt(_today!['goalMinutes'])} min today',
                'আজ ${_asInt(_today!['minutes'])}/'
                    '${_asInt(_today!['goalMinutes'])} মিনিট',
              ),
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          accent: colors.study,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _blockTitle,
                style: type.cardHeading,
                semanticsLabel: _blockTitle,
              ),
              const SizedBox(height: GochanoSpacing.xs),
              Text(
                _phase == _Phase.paused
                    ? GochanoLanguage.text('Paused', 'বিরতি চলছে')
                    : _remaining == 0 && _phase == _Phase.running
                        ? GochanoLanguage.text(
                            'Time is up — finish when ready',
                            'সময় শেষ — প্রস্তুত হলে শেষ করুন',
                          )
                        : GochanoLanguage.text(
                            '${widget.plannedMinutes} minute block',
                            '${widget.plannedMinutes} মিনিটের ব্লক',
                          ),
                style: type.caption,
              ),
              const SizedBox(height: GochanoSpacing.sm),
              Semantics(
                label: GochanoLanguage.text(
                  'Time left in this block',
                  'এই ব্লকের বাকি সময়',
                ),
                child: Text(
                  focusClock(_remaining),
                  style: type.display.copyWith(color: colors.study),
                ),
              ),
              const SizedBox(height: GochanoSpacing.sm),
              LinearProgressIndicator(
                value: _totalSeconds == 0
                    ? 0
                    : (_totalSeconds - _remaining) / _totalSeconds,
                minHeight: 8,
                color: colors.study,
                backgroundColor: colors.surfaceVariant,
                semanticsLabel: GochanoLanguage.text(
                  'Block progress',
                  'ব্লকের অগ্রগতি',
                ),
              ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: GochanoSpacing.sm),
          Text(
            friendlyErrorMessage(_error),
            style: type.bodySecondary.copyWith(color: colors.error),
          ),
        ],
        if (_phase == _Phase.idle) ...[
          const SizedBox(height: GochanoSpacing.sm),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _subjectController,
                  decoration: InputDecoration(
                    labelText: GochanoLanguage.text('Subject', 'বিষয়'),
                    hintText: GochanoLanguage.text(
                      'Physics, English…',
                      'পদার্থবিজ্ঞান, ইংরেজি…',
                    ),
                  ),
                ),
                const SizedBox(height: GochanoSpacing.sm),
                TextField(
                  controller: _topicController,
                  decoration: InputDecoration(
                    labelText: GochanoLanguage.text('Topic', 'টপিক'),
                    hintText: GochanoLanguage.text(
                      'What this block covers',
                      'এই ব্লকে যা পড়বেন',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (_todayError != null) ...[
          const SizedBox(height: GochanoSpacing.sm),
          Text(
            friendlyErrorMessage(_todayError),
            style: type.caption.copyWith(color: colors.textTertiary),
          ),
        ],
        if (_today != null) ...[
          const SizedBox(height: GochanoSpacing.sm),
          _TodayFacts(today: _today!),
        ],
        if (_today?['nudge'] is Map) ...[
          const SizedBox(height: GochanoSpacing.sm),
          GochanoListRow(
            illustration: GochanoArt.featureAi,
            accent: colors.ai,
            title: GochanoLanguage.text('Ziku says', 'জিকু বলছে'),
            subtitle: '${(_today!['nudge'] as Map)['message'] ?? ''}',
          ),
        ],
        const Spacer(),
        _controls(context),
        const SizedBox(height: GochanoSpacing.xs),
      ],
    );
  }

  Widget _controls(BuildContext context) {
    switch (_phase) {
      case _Phase.idle:
        return PrimaryButton(
          label: GochanoLanguage.text('Start Session', 'সেশন শুরু করুন'),
          icon: Icons.play_arrow_rounded,
          busy: _busy,
          onPressed: _busy ? null : _startSession,
        );
      case _Phase.running:
        return Row(
          children: [
            Expanded(
              child: SecondaryButton(
                label: GochanoLanguage.text('Pause', 'বিরতি'),
                icon: Icons.pause_rounded,
                onPressed: _busy ? null : _togglePause,
              ),
            ),
            const SizedBox(width: GochanoSpacing.sm),
            Expanded(
              child: PrimaryButton(
                label: GochanoLanguage.text('Finish', 'শেষ করুন'),
                icon: Icons.check_rounded,
                busy: _busy,
                onPressed: _busy ? null : _finish,
              ),
            ),
          ],
        );
      case _Phase.paused:
        return Row(
          children: [
            Expanded(
              child: PrimaryButton(
                label: GochanoLanguage.text('Resume', 'চালিয়ে যান'),
                icon: Icons.play_arrow_rounded,
                busy: _busy,
                onPressed: _busy ? null : _togglePause,
              ),
            ),
            const SizedBox(width: GochanoSpacing.sm),
            Expanded(
              child: SecondaryButton(
                label: GochanoLanguage.text('Finish', 'শেষ করুন'),
                icon: Icons.check_rounded,
                onPressed: _busy ? null : _finish,
              ),
            ),
          ],
        );
      case _Phase.done:
        return const SizedBox.shrink();
    }
  }

  Widget _buildDone(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final result = _result ?? const <String, dynamic>{};
    final today = _today ?? const <String, dynamic>{};
    final minutes = (_asInt(result['accumulatedSeconds']) / 60).round();
    final sessionScore = result['focusScore'] is num
        ? (result['focusScore'] as num).toInt()
        : null;
    final score = today['score'] is Map
        ? Map<String, dynamic>.from(today['score'] as Map)
        : null;
    final nudge = today['nudge'] is Map
        ? Map<String, dynamic>.from(today['nudge'] as Map)
        : null;

    return GochanoScaffold(
      appBar: GochanoAppBar(
        title: GochanoLanguage.text('Ziku Focus', 'জিকু ফোকাস'),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppCard(
              accent: colors.success,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.check_circle_rounded,
                        color: colors.success,
                        size: 22,
                      ),
                      const SizedBox(width: GochanoSpacing.xs),
                      Expanded(
                        child: Text(
                          GochanoLanguage.text(
                            'Session finished',
                            'সেশন শেষ',
                          ),
                          style: type.sectionHeading,
                        ),
                      ),
                      if (sessionScore != null)
                        GochanoBadge(
                          label: GochanoLanguage.text(
                            'Score $sessionScore',
                            'স্কোর $sessionScore',
                          ),
                          tone: sessionScore >= 80
                              ? GochanoBadgeTone.success
                              : sessionScore >= 55
                                  ? GochanoBadgeTone.info
                                  : GochanoBadgeTone.warning,
                          icon: Icons.bolt_rounded,
                        ),
                    ],
                  ),
                  const SizedBox(height: GochanoSpacing.sm),
                  Text(
                    GochanoLanguage.text(
                      '$minutes min focused',
                      '$minutes মিনিট মনোযোগ দিয়েছেন',
                    ),
                    style: type.bodySecondary,
                  ),
                  if (score != null) ...[
                    const SizedBox(height: GochanoSpacing.xs),
                    Row(
                      children: [
                        GochanoBadge(
                          label: GochanoLanguage.text(
                            'Focus score ${_asInt(score['value'])}',
                            'ফোকাস স্কোর ${_asInt(score['value'])}',
                          ),
                          tone: focusBandTone('${score['band'] ?? ''}'),
                          icon: Icons.insights_rounded,
                        ),
                        const SizedBox(width: GochanoSpacing.xs),
                        Flexible(
                          child: Text(
                            focusBandLabel('${score['band'] ?? ''}'),
                            style: type.caption,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      GochanoLanguage.text(
                        'Last 7 days · ${score['activeDays'] ?? 0} active days',
                        'গত ৭ দিন · ${_asInt(score['activeDays'])} দিনে পড়া',
                      ),
                      style: type.caption.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (nudge != null) ...[
              const SizedBox(height: GochanoSpacing.sm),
              AppCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.auto_awesome_rounded,
                      size: 18,
                      color: colors.ai,
                    ),
                    const SizedBox(width: GochanoSpacing.xs),
                    Expanded(
                      child: Text(
                        '${nudge['message'] ?? ''}',
                        style: type.bodySecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: GochanoSpacing.sm),
            PrimaryButton(
              label: GochanoLanguage.text('Done', 'হয়ে গেছে'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }

  String get _blockTitle {
    final topic = _topicController.text.trim();
    if (topic.isNotEmpty) return topic;
    final subject = _subjectController.text.trim();
    if (subject.isNotEmpty) return subject;
    return GochanoLanguage.text('Deep work block', 'গভীর কাজের ব্লক');
  }

  static int _asInt(dynamic value) => value is num ? value.toInt() : 0;
}

/// Today's minutes vs goal, the rolling score and the streak — the same
/// numbers the Home card shows, so the two never disagree.
class _TodayFacts extends StatelessWidget {
  const _TodayFacts({required this.today});

  final Map<String, dynamic> today;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final score = today['score'] is Map
        ? Map<String, dynamic>.from(today['score'] as Map)
        : null;
    final weekly = today['weekly'] is Map
        ? Map<String, dynamic>.from(today['weekly'] as Map)
        : null;

    return Row(
      children: [
        Expanded(
          child: StatCard(
            compact: true,
            label: GochanoLanguage.text('Today', 'আজ'),
            value: '${_asInt(today['minutes'])}/${_asInt(today['goalMinutes'])}',
            caption: GochanoLanguage.text('minutes', 'মিনিট'),
            icon: Icon(Icons.timelapse_rounded, size: 16, color: colors.study),
            accent: colors.study,
          ),
        ),
        const SizedBox(width: GochanoSpacing.sm),
        Expanded(
          child: StatCard(
            compact: true,
            label: GochanoLanguage.text('Focus score', 'ফোকাস স্কোর'),
            value: score == null ? '—' : '${_asInt(score['value'])}',
            caption: score == null
                ? GochanoLanguage.text(
                    'no finished session yet',
                    'এখনো কোনো সেশন শেষ হয়নি',
                  )
                : focusBandLabel('${score['band'] ?? ''}'),
            icon: Icon(Icons.my_location_rounded, size: 16, color: colors.ai),
            accent: colors.ai,
          ),
        ),
        const SizedBox(width: GochanoSpacing.sm),
        Expanded(
          child: StatCard(
            compact: true,
            label: GochanoLanguage.text('Streak', 'স্ট্রিক'),
            value: '${_asInt(today['streakDays'])}',
            caption: weekly == null
                ? GochanoLanguage.text('days', 'দিন')
                : GochanoLanguage.text(
                    '${_asInt(weekly['consistencyPct'])}% this week',
                    'এই সপ্তাহে ${_asInt(weekly['consistencyPct'])}%',
                  ),
            icon: Icon(
              Icons.local_fire_department_rounded,
              size: 16,
              color: colors.warning,
            ),
            accent: colors.warning,
          ),
        ),
      ],
    );
  }

  static int _asInt(dynamic value) => value is num ? value.toInt() : 0;
}
