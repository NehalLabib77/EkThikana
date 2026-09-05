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
import '../../../../services/study_service.dart';
import '../../../../shared/states/gochano_states.dart';
import '../../../../shared/widgets/gochano_controls.dart';
import '../../../../shared/widgets/gochano_surfaces.dart';

class FocusView extends StatefulWidget {
  const FocusView({super.key});

  @override
  State<FocusView> createState() => _FocusViewState();
}

class _FocusViewState extends State<FocusView> {
  final _label = TextEditingController();

  FocusSession? _active;
  List<FocusSession> _history = const [];

  Timer? _ticker;
  DateTime? _runningSince;
  int _baseSeconds = 0;
  int _displaySeconds = 0;

  int _plannedMinutes = 25;
  bool _loading = true;
  bool _busy = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _label.dispose();
    super.dispose();
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
        // Include completed, cancelled, AND paused sessions in history for
        // grouped display. Only "running" sessions are excluded from history
        // — they have live ticking time that should not be double-counted.
        // Paused sessions appear in BOTH _active (for resume/finish controls)
        // AND _history (for grouped time display).
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
  void _adoptSession(FocusSession session) {
    _ticker?.cancel();
    _baseSeconds = session.elapsedSeconds;
    _displaySeconds = _baseSeconds;

    if (session.status == 'running') {
      _runningSince = DateTime.now();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        final since = _runningSince;
        if (since == null) return;
        setState(() {
          _displaySeconds =
              _baseSeconds + DateTime.now().difference(since).inSeconds;
        });
      });
    } else {
      _runningSince = null;
    }
    setState(() => _active = session);
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
        _runningSince = null;
        setState(() => _active = null);
        await _load();
      }
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
        if (active == null) _buildStart(context) else _buildActive(context, active),
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
            labelText: GochanoLanguage.text('What are you studying?', 'কী পড়ছেন?'),
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
                  onPressed: () => _run(
                    () => StudyService.patch(session.id, 'complete'),
                  ),
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
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
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
    final key = normalized.isEmpty
        ? ''
        : normalized.toLowerCase();
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
