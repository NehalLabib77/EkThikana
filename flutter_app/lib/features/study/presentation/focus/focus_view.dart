// Focus history (spec §41) — how a pile of run/pause/cancel rows becomes a
// list a student can read.
//
// The backend stores one row per session, so a subject worked across ten
// sessions arrives as ten rows. [groupSessions] folds them into one line per
// study name: same name (trimmed, case-insensitive) sums its seconds and keeps
// the most recent day. Durations are already coerced to 0 when corrupt by
// `FocusSession.fromJson`, so a poisoned legacy row cannot dominate the list.
//
// Sessions that are still running are excluded — their total is still moving.

import 'package:flutter/material.dart';

import '../../../../core/design_system/gochano_art.dart';
import '../../../../core/design_system/gochano_colors.dart';
import '../../../../core/design_system/gochano_spacing.dart';
import '../../../../core/design_system/gochano_typography.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../services/api_service.dart';
import '../../../../services/study_service.dart';
import '../../../../shared/widgets/ai_widgets.dart';
import '../../../../shared/widgets/gochano_controls.dart';
import '../../../../shared/widgets/gochano_surfaces.dart';

class FocusView extends StatefulWidget {
  const FocusView({super.key, this.listFn});

  /// Read hook, injected in tests so the view never opens a socket.
  final Future<List<FocusSession>> Function({int days})? listFn;

  @override
  State<FocusView> createState() => _FocusViewState();
}

class _FocusViewState extends State<FocusView> {
  List<FocusSession> _history = const <FocusSession>[];
  bool _loading = true;
  String _error = '';

  Future<List<FocusSession>> Function({int days}) get _read =>
      widget.listFn ?? _fromApi;

  static Future<List<FocusSession>> _fromApi({int days = 30}) async {
    final rows = await ApiService.listFocus(days: days);
    return [
      for (final row in rows)
        if (row is Map) FocusSession.fromJson(Map<String, dynamic>.from(row)),
    ];
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final rows = await _read(days: 30);
      if (!mounted) return;
      setState(() {
        _history = rows;
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
    if (_loading) {
      return AiLoadingState(
        message: GochanoLanguage.text(
          'Reading your focus history…',
          'আপনার ফোকাস ইতিহাস পড়া হচ্ছে…',
        ),
      );
    }

    if (_error.isNotEmpty) {
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
                onPressed: _load,
              ),
            ],
          ),
        ),
      );
    }

    final groups = groupSessions(_history);
    if (groups.isEmpty) {
      return AiEmptyState(
        icon: Icons.timer_outlined,
        title: GochanoLanguage.text(
          'No deep work yet',
          'এখনো গভীর পড়া হয়নি',
        ),
        message: GochanoLanguage.text(
          'Start a 25-minute session — finished sessions are grouped here by '
          'subject.',
          '২৫ মিনিটের সেশন শুরু করুন — শেষ হওয়া সেশন বিষয় অনুযায়ী এখানে দেখা যাবে।',
        ),
      );
    }

    final totalMinutes =
        groups.fold<int>(0, (sum, g) => sum + g.totalSeconds) ~/ 60;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: GochanoSpacing.scrollBody,
        children: [
          SectionHeader(
            title: GochanoLanguage.text(
              'Recent focus sessions',
              'সাম্প্রতিক ফোকাস সেশন',
            ),
            subtitle: GochanoLanguage.text(
              '$totalMinutes minutes across ${groups.length} subjects',
              '$totalMinutes মিনিট, ${groups.length}টি বিষয়',
            ),
          ),
          CardGroup(
            children: [for (final group in groups) _groupRow(context, group)],
          ),
          const SizedBox(height: GochanoSpacing.lg),
        ],
      ),
    );
  }

  Widget _groupRow(BuildContext context, SessionGroup group) {
    final minutes = group.totalSeconds ~/ 60;

    return GochanoListRow(
      illustration: GochanoArt.featureStudy,
      accent: context.colors.study,
      title: group.label,
      subtitle: GochanoLanguage.text(
        'Last on ${group.latestDayKey}',
        'সর্বশেষ ${group.latestDayKey}',
      ),
      metadata: [
        GochanoLanguage.text('$minutes min', '$minutes মিনিট'),
      ],
      trailing: Text(
        '$minutes',
        style: context.type.statisticSmall.copyWith(color: context.colors.study),
      ),
    );
  }
}

/// One grouped row of the focus history.
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

/// Folds sessions that share a study name into a single row.
///
/// - trims whitespace and ignores case when deciding "same name";
/// - a blank name becomes `Focus session`;
/// - sums `elapsedSeconds` (corrupt rows already read as 0);
/// - keeps the latest `dayKey` for display;
/// - skips sessions that are still running;
/// - returns the biggest groups first.
List<SessionGroup> groupSessions(List<FocusSession> sessions) {
  final byName = <String, SessionGroup>{};

  for (final session in sessions) {
    if (session.status == 'running') continue;

    final trimmed = session.label.trim();
    final key = trimmed.toLowerCase();
    final existing = byName[key];

    if (existing == null) {
      byName[key] = SessionGroup(
        label: trimmed.isEmpty
            ? GochanoLanguage.text('Focus session', 'ফোকাস সেশন')
            : trimmed,
        totalSeconds: session.elapsedSeconds,
        latestDayKey: session.dayKey,
      );
      continue;
    }

    byName[key] = SessionGroup(
      label: existing.label,
      totalSeconds: existing.totalSeconds + session.elapsedSeconds,
      latestDayKey: session.dayKey.compareTo(existing.latestDayKey) > 0
          ? session.dayKey
          : existing.latestDayKey,
    );
  }

  return byName.values.toList()
    ..sort((a, b) => b.totalSeconds.compareTo(a.totalSeconds));
}
