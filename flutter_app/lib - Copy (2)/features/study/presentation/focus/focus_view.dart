// Focus session (spec §41).
//
// Distraction-free by construction: when a session is running the screen is
// the elapsed time, the goal, and the three controls. No motion, no
// decoration — spec §41 says "Do not add motion effects", and a timer is
// exactly the place a designer is tempted to.
//
// The elapsed number is computed locally from the session's start time and a
// one-second ticker, but the *authoritative* total is whatever the backend
// returns on pause/finish — it is the side that knows about run/pause cycles
// across devices.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/design_system/gochano_art.dart';
import '../../../../core/design_system/gochano_colors.dart';
import '../../../../core/design_system/gochano_illustration.dart';
import '../../../../core/design_system/gochano_spacing.dart';
import '../../../../core/design_system/gochano_typography.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../features/focus_rewards/data/reward_service.dart';
import '../../../../features/focus_rewards/domain/reward_model.dart';
import '../../../../features/focus_rewards/presentation/focus_reward_progress.dart';
import '../../../../features/focus_rewards/presentation/session_completion_dialog.dart';
import '../../../../services/study_service.dart';
import '../../../../shared/states/gochano_states.dart';
import '../../../../shared/widgets/gochano_controls.dart';
import '../../../../shared/widgets/gochano_surfaces.dart';

class FocusView extends StatefulWidget {
  const FocusView({super.key});

  @override
  State<FocusView> createState() => _FocusViewState();
}

class _FocusViewState extends State<FocusView>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  final _label = TextEditingController();

  FocusSession? _active;
  List<FocusSession> _history = const [];

  Timer? _ticker;
  DateTime? _sessionEndAt;
  int _displaySeconds = 0;

  int _plannedMinutes = 25;
  bool _loading = true;
  bool _busy = false;
  String _error = '';

  RewardProfile _rewardProfile = RewardProfile.empty();
  StreamSubscription<RewardProfile>? _rewardSub;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    GochanoLanguage.current.addListener(_onLanguageChange);
    _load();
    _rewardSub = RewardService.profileStream().listen((profile) {
      if (mounted) setState(() => _rewardProfile = profile);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    GochanoLanguage.current.removeListener(_onLanguageChange);
    _rewardSub?.cancel();
    _ticker?.cancel();
    _label.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _sessionEndAt != null) {
      _recalcFromEndAt();
    }
  }

  void _onLanguageChange() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final sessions = await StudyService.list();
      if (!mounted) return;
      final running = sessions.where((s) => s.status == 'running').firstOrNull;
      final paused = sessions.where((s) => s.status == 'paused').firstOrNull;
      final activeSession = running ?? paused;
      setState(() {
        _loading = false;
        _history = sessions.where((s) => s.status != 'running').toList();
        _active = activeSession;
      });
      if (activeSession != null) _adoptSession(activeSession);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyErrorMessage(error);
      });
    }
  }

  /// Syncs local ticking state to a session returned by the backend.
  ///
  /// If a timer is already running for the same session, this preserves
  /// the existing `_sessionEndAt` and does NOT reset the countdown.
  void _adoptSession(FocusSession session) {
    final sameSession = _active?.id == session.id && _sessionEndAt != null;

    _ticker?.cancel();

    if (session.status == 'running') {
      if (sameSession) {
        // Timer already running for this session — keep the existing endAt.
        // Recalculate display seconds from the authoritative endAt.
        _recalcFromEndAt();
      } else {
        // New session or returning from background: derive endAt from
        // remaining time.  This prevents drift if the widget was idle.
        final remaining = (session.plannedMinutes * 60) - session.elapsedSeconds;
        _sessionEndAt = DateTime.now().add(Duration(seconds: remaining > 0 ? remaining : 0));
        _recalcFromEndAt();
      }
      _startTicker();
    } else {
      // Paused or other non-running state: show accumulated time, no ticker.
      _sessionEndAt = null;
      _displaySeconds = session.elapsedSeconds;
    }
    setState(() => _active = session);
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _recalcFromEndAt();
    });
  }

  /// Recalculate `_displaySeconds` from `_sessionEndAt`. This is the single
  /// source of truth for an active running session.
  void _recalcFromEndAt() {
    final endAt = _sessionEndAt;
    if (endAt == null) return;
    final remaining = endAt.difference(DateTime.now()).inSeconds;
    setState(() {
      _displaySeconds = remaining > 0 ? remaining : 0;
    });
    // Auto-complete when timer hits zero.
    if (remaining <= 0 && _active != null && _active!.status == 'running') {
      _ticker?.cancel();
      _finishSession();
    }
  }

  Future<void> _finishSession() async {
    final session = _active;
    if (session == null) return;
    await _run(() => StudyService.patch(session.id, 'complete'));
  }

  Future<void> _run(Future<FocusSession> Function() action) async {
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final session = await action();
      if (!mounted) return;
      setState(() => _busy = false);
      if (session.isActive) {
        _adoptSession(session);
      } else {
        _ticker?.cancel();
        _sessionEndAt = null;
        final wasCompleted = session.status == 'completed';
        final completedSession = _active;
        setState(() => _active = null);
        await _load();
        // Grant reward exactly once per session. The backend's idempotency
        // check (sourceSessionId) prevents double-granting, and we only
        // call this when transitioning from active -> completed.
        if (wasCompleted && completedSession != null && mounted) {
          await _grantReward(completedSession);
        }
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = friendlyErrorMessage(error);
      });
    }
  }

  Future<void> _grantReward(FocusSession session) async {
    try {
      final result = await RewardService.grantFocusReward(
        focusSessionId: session.id,
        plannedMinutes: session.plannedMinutes,
        sessionLabel: session.label,
      );
      if (!mounted) return;
      if (context.mounted) {
        await showRewardCompletionSheet(
          context,
          result: result,
          plannedMinutes: session.plannedMinutes,
        );
      }
    } catch (error) {
      // Reward failure should not crash the app. Show a subtle error.
      if (mounted) {
        setState(() {
          _error = friendlyErrorMessage(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) {
      return StaticLoadingState(
        message: GochanoLanguage.text(
          'Loading focus sessions…',
          'ফোকাস সেশন লোড হচ্ছে…',
        ),
      );
    }

    final active = _active;
    return ListView(
      padding: GochanoSpacing.scrollBody,
      children: [
        if (active == null) ...[
          FocusRewardProgress(profile: _rewardProfile),
          const SizedBox(height: GochanoSpacing.sm),
          _buildStart(context),
        ] else
          _buildActive(context, active),
        if (_error.isNotEmpty) ...[
          const SizedBox(height: GochanoSpacing.md),
          ErrorState(compact: true, message: _error, onRetry: _load),
        ],
        if (_history.isNotEmpty) ...[
          SectionHeader(
            title: GochanoLanguage.text('Recent sessions', 'সাম্প্রতিক সেশন'),
          ),
          CardGroup(
            children: [
              for (final group in groupSessions(_history))
                GochanoListRow(
                  illustration: GochanoArt.featureFocus,
                  accent: context.colors.study,
                  title: group.label,
                  metadata: [
                    _durationLabel(group.totalSeconds),
                    _dayLabel(group.latestDayKey),
                  ],
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildStart(BuildContext context) {
    final colors = context.colors;

    return Column(
      children: [
        const SizedBox(height: GochanoSpacing.lg),
        Center(
          child: GochanoIllustration(
            GochanoArt.featureFocus,
            size: GochanoSizes.illustrationEmpty,
            accent: colors.study,
          ),
        ),
        const SizedBox(height: GochanoSpacing.md),
        Text(
          GochanoLanguage.text('Ready to focus', 'ফোকাস করতে প্রস্তুত'),
          style: context.type.sectionHeading,
        ),
        const SizedBox(height: GochanoSpacing.xs),
        Text(
          GochanoLanguage.text(
            'Pick what you are working on and how long.',
            'কী নিয়ে কাজ করছেন এবং কতক্ষণ, তা বেছে নিন।',
          ),
          style: context.type.bodySecondary,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: GochanoSpacing.lg),
        TextField(
          controller: _label,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: GochanoLanguage.text(
              'What are you studying?',
              'কী পড়ছেন?',
            ),
            hintText: GochanoLanguage.text(
              'Operating Systems chapter 4',
              'অপারেটিং সিস্টেম অধ্যায় ৪',
            ),
          ),
        ),
        const SizedBox(height: GochanoSpacing.md),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            GochanoLanguage.text('Session length', 'সেশনের দৈর্ঘ্য'),
            style: context.type.label,
          ),
        ),
        const SizedBox(height: GochanoSpacing.xs),
        Wrap(
          spacing: GochanoSpacing.xs,
          children: [
            for (final minutes in const [15, 25, 45, 60])
              ChoiceChip(
                selected: _plannedMinutes == minutes,
                onSelected: (_) => setState(() => _plannedMinutes = minutes),
                label: Text(
                  GochanoLanguage.text('$minutes min', '$minutes মিনিট'),
                ),
              ),
          ],
        ),
        const SizedBox(height: GochanoSpacing.lg),
        PrimaryButton(
          label: GochanoLanguage.text('Start focus', 'ফোকাস শুরু'),
          icon: Icons.play_arrow_rounded,
          busy: _busy,
          onPressed: () => _run(
            () => StudyService.start(
              label: _label.text.trim(),
              plannedMinutes: _plannedMinutes,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActive(BuildContext context, FocusSession session) {
    final colors = context.colors;
    final planned = session.plannedMinutes * 60;
    final progress = planned <= 0
        ? null
        : (_displaySeconds / planned).clamp(0.0, 1.0);
    final paused = session.status == 'paused';

    return AppCard(
      accent: colors.study,
      padding: const EdgeInsets.all(GochanoSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            session.label.isEmpty
                ? GochanoLanguage.text('Focus session', 'ফোকাস সেশন')
                : session.label,
            style: context.type.sectionHeading,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: GochanoSpacing.md),
          Text(
            _clock(_displaySeconds),
            style: context.type.display.copyWith(fontSize: 52),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: GochanoSpacing.xs),
          Text(
            GochanoLanguage.text(
              'of ${session.plannedMinutes} min',
              '${session.plannedMinutes} মিনিটের মধ্যে',
            ),
            style: context.type.caption,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: GochanoSpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: colors.surfaceVariant,
              color: colors.study,
            ),
          ),
          if (paused) ...[
            const SizedBox(height: GochanoSpacing.sm),
            Center(
              child: GochanoBadge(
                label: GochanoLanguage.text('Paused', 'বিরতি'),
                icon: Icons.pause_rounded,
              ),
            ),
          ],
          const SizedBox(height: GochanoSpacing.lg),
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  label: paused
                      ? GochanoLanguage.text('Resume', 'চালু')
                      : GochanoLanguage.text('Pause', 'বিরতি'),
                  icon: paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  onPressed: _busy
                      ? null
                      : () => _run(
                          () => StudyService.patch(
                            session.id,
                            paused ? 'resume' : 'pause',
                          ),
                        ),
                ),
              ),
              const SizedBox(width: GochanoSpacing.xs),
              Expanded(
                child: PrimaryButton(
                  label: GochanoLanguage.text('Finish', 'শেষ'),
                  icon: Icons.check_rounded,
                  busy: _busy,
                  onPressed: () =>
                      _run(() => StudyService.patch(session.id, 'complete')),
                ),
              ),
            ],
          ),
          const SizedBox(height: GochanoSpacing.xs),
          TextButton(
            onPressed: _busy
                ? null
                : () => _run(() => StudyService.patch(session.id, 'cancel')),
            child: Text(GochanoLanguage.text('Cancel session', 'সেশন বাতিল')),
          ),
        ],
      ),
    );
  }
}

String _clock(int seconds) {
  final minutes = seconds ~/ 60;
  final rest = seconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:${rest.toString().padLeft(2, '0')}';
}

String _durationLabel(int seconds) {
  final minutes = seconds ~/ 60;
  final secs = seconds % 60;
  if (minutes == 0) {
    return GochanoLanguage.text('$secs sec', '$secs সেকেন্ড');
  }
  return GochanoLanguage.text(
    '$minutes min $secs sec',
    '$minutes মিনিট $secs সেকেন্ড',
  );
}

String _dayLabel(String dayKey) {
  final parsed = DateTime.tryParse(dayKey);
  if (parsed == null) return dayKey;
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${parsed.day} ${months[parsed.month - 1]}';
}

/// Groups focus sessions by normalized study name, summing elapsed time.
///
/// - Trims whitespace, case-insensitive grouping
/// - Blank/legacy names → "Focus session"
/// - Sum valid elapsedSeconds for same-name sessions
/// - Use latest dayKey for date display
class SessionGroup {
  const SessionGroup({
    required this.label,
    required this.totalSeconds,
    required this.latestDayKey,
  });
  final String label;
  final int totalSeconds;
  final String latestDayKey;
}

List<SessionGroup> groupSessions(List<FocusSession> sessions) {
  final map = <String, SessionGroup>{};
  for (final s in sessions) {
    final normalized = s.label.trim();
    final key = normalized.isEmpty ? '' : normalized.toLowerCase();
    final displayLabel = normalized.isEmpty
        ? GochanoLanguage.text('Focus session', 'ফোকাস সেশন')
        : normalized;

    final existing = map[key];
    if (existing == null) {
      map[key] = SessionGroup(
        label: displayLabel,
        totalSeconds: s.elapsedSeconds,
        latestDayKey: s.dayKey,
      );
    } else {
      // Use the later dayKey for display.
      final laterDay = s.dayKey.compareTo(existing.latestDayKey) > 0
          ? s.dayKey
          : existing.latestDayKey;
      map[key] = SessionGroup(
        label: existing.label,
        totalSeconds: existing.totalSeconds + s.elapsedSeconds,
        latestDayKey: laterDay,
      );
    }
  }
  final groups = map.values.toList()
    ..sort((a, b) => b.totalSeconds.compareTo(a.totalSeconds));
  return groups;
}
