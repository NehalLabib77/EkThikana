// Phase 4 — "Ziku Coach": today's study mission on Home (study mode).
//
// The first visible surface of the Study Coach, and deliberately the smallest
// one: greeting, the Academic Health number, today's priority with the reason
// behind it, the mission as a checklist, and one button that opens the full
// dashboard. The backend already decided all of it (`GET /api/coach/daily` is
// rule-based and cached per day), so this card only reads and renders.
//
// Read hook is injectable so tests never open a socket; a failed read degrades
// to a retry line rather than taking the Home screen down.

import 'package:flutter/material.dart';

import '../../../../core/design_system/gochano_art.dart';
import '../../../../core/design_system/gochano_colors.dart';
import '../../../../core/design_system/gochano_spacing.dart';
import '../../../../core/design_system/gochano_typography.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../core/page_route.dart';
import '../../../../services/api_service.dart';
import '../../../../shared/states/gochano_states.dart';
import '../../../../shared/widgets/gochano_controls.dart';
import '../../../../shared/widgets/gochano_surfaces.dart';
import 'coach_dashboard_screen.dart';

/// Reads the student's learning profile.
typedef CoachProfileFn = Future<Map<String, dynamic>> Function();

/// Reads today's study brief / mission.
typedef CoachBriefFn = Future<Map<String, dynamic>> Function();

/// Reads this week's academic report.
typedef CoachWeeklyFn = Future<Map<String, dynamic>> Function();

/// Greeting copy for the backend's `greetingKey`.
String coachGreeting(String key) {
  switch (key) {
    case 'afternoon':
      return GochanoLanguage.text('Good Afternoon', 'শুভ দুপুর');
    case 'evening':
      return GochanoLanguage.text('Good Evening', 'শুভ সন্ধ্যা');
    default:
      return GochanoLanguage.text('Good Morning', 'শুভ সকাল');
  }
}

/// The question the dashboard hands to Ziku, built from the live priority.
///
/// Mirrors `academicHealthZikuQuestion`: the student should never have to
/// retype what the coach just told them.
String coachZikuQuestion({String? topic, String? exam}) {
  final name = (topic ?? '').trim();
  if (name.isNotEmpty) {
    return GochanoLanguage.text(
      'How should I revise $name before my exam?',
      'পরীক্ষার আগে $name কীভাবে রিভাইজ করব?',
    );
  }
  final examName = (exam ?? '').trim();
  if (examName.isNotEmpty) {
    return GochanoLanguage.text(
      'What should I study today for $examName?',
      '$examName এর জন্য আজ কী পড়ব?',
    );
  }
  return GochanoLanguage.text('What should I study today?', 'আজ কী পড়ব?');
}

class ZikuCoachCard extends StatefulWidget {
  const ZikuCoachCard({super.key, this.briefFn, this.onOpenPlan});

  /// Read hook, injected in tests so the widget never opens a socket.
  final CoachBriefFn? briefFn;

  /// Switches the shell to a study tab (1 = Workspace, 2 = Plan) so a mission
  /// step that belongs there can hand the student back to the app shell.
  final ValueChanged<int>? onOpenPlan;

  @override
  State<ZikuCoachCard> createState() => _ZikuCoachCardState();
}

class _ZikuCoachCardState extends State<ZikuCoachCard> {
  Map<String, dynamic>? _brief;
  bool _failed = false;

  CoachBriefFn get _load => widget.briefFn ?? ApiService.coachDailyBrief;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    try {
      final body = await _load();
      if (!mounted) return;
      setState(() {
        _brief = body;
        _failed = false;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _brief = null;
        _failed = true;
        _readError = err;
      });
    }
  }

  void _open() {
    Navigator.of(context).push(
      GochanoRoute.to(
        builder: (_) => CoachDashboardScreen(
          dailyFn: widget.briefFn,
          onOpenPlan: widget.onOpenPlan,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final brief = _brief;

    if (brief == null) {
      return AppCard(
        accent: colors.ai,
        child: GochanoListRow(
          illustration: GochanoArt.featureAi,
          accent: colors.ai,
          title: GochanoLanguage.text('Ziku Coach', 'জিকু কোচ'),
          subtitle: _failed
              ? friendlyErrorMessage(_lastError)
              : GochanoLanguage.text(
                  'Reading today\u2019s study mission…',
                  'আজকের পড়ার মিশন পড়া হচ্ছে…',
                ),
          onTap: _failed ? _read : null,
        ),
      );
    }

    final priority = _asMap(brief['priority']);
    final mission = _asList(brief['mission']);
    final exam = _asMap(brief['exam']);
    final topic = '${priority?['topic'] ?? ''}';
    final why = '${brief['why'] ?? ''}';
    final score = _asInt(brief['healthScore']);
    final hasData = brief['hasData'] == true;

    return AppCard(
      accent: colors.ai,
      onTap: _open,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, size: 20, color: colors.ai),
              const SizedBox(width: GochanoSpacing.xs),
              Expanded(
                child: Text(
                  GochanoLanguage.text('Ziku Coach', 'জিকু কোচ'),
                  style: context.type.cardHeading,
                ),
              ),
              if (hasData)
                GochanoBadge(
                  label: GochanoLanguage.text(
                    'Health $score%',
                    'হেলথ $score%',
                  ),
                  tone: _scoreBadgeTone(score),
                  icon: Icons.health_and_safety_rounded,
                ),
            ],
          ),
          const SizedBox(height: GochanoSpacing.xs),
          Text(
            [
              coachGreeting('${brief['greetingKey'] ?? ''}'),
              if (exam != null)
                GochanoLanguage.text(
                  '${exam['title'] ?? ''} · ${_asInt(exam['daysRemaining'])} days left',
                  '${exam['title'] ?? ''} · ${_asInt(exam['daysRemaining'])} দিন বাকি',
                ),
            ].join(' · '),
            style: context.type.caption,
          ),
          if (topic.isNotEmpty || why.isNotEmpty) ...[
            const SizedBox(height: GochanoSpacing.sm),
            Text(
              GochanoLanguage.text('Today\u2019s Priority', 'আজকের অগ্রাধিকার'),
              style: context.type.label.copyWith(color: colors.textTertiary),
            ),
            if (topic.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                topic,
                style: context.type.sectionHeading.copyWith(color: colors.ai),
              ),
            ],
            if (why.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                GochanoLanguage.text('Why: $why', 'কেন: $why'),
                style: context.type.caption,
              ),
            ],
          ],
          if (mission.isNotEmpty) ...[
            const SizedBox(height: GochanoSpacing.sm),
            Text(
              GochanoLanguage.text('Today\u2019s Mission', 'আজকের মিশন'),
              style: context.type.label.copyWith(color: colors.textTertiary),
            ),
            const SizedBox(height: GochanoSpacing.xs),
            for (final step in mission) _MissionLine(step: step),
          ],
          const SizedBox(height: GochanoSpacing.sm),
          PrimaryButton(
            label: GochanoLanguage.text('Start Mission', 'মিশন শুরু করুন'),
            icon: Icons.play_arrow_rounded,
            onPressed: _open,
          ),
        ],
      ),
    );
  }

  Object? get _lastError => _failed ? _readError : null;

  Object? _readError;

  static GochanoBadgeTone _scoreBadgeTone(int score) {
    if (score >= 85) return GochanoBadgeTone.success;
    if (score >= 70) return GochanoBadgeTone.info;
    if (score >= 55) return GochanoBadgeTone.warning;
    return GochanoBadgeTone.error;
  }

  static int _asInt(dynamic value) => value is num ? value.toInt() : 0;

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

/// One mission step: a tick, the title, and how long the coach budgeted.
class _MissionLine extends StatelessWidget {
  const _MissionLine({required this.step});

  final Map<String, dynamic> step;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final minutes = step['minutes'] is num ? (step['minutes'] as num).toInt() : 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: GochanoSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.check_circle_outline_rounded,
            size: 18,
            color: colors.ai,
          ),
          const SizedBox(width: GochanoSpacing.xs),
          Expanded(
            child: Text(
              '${step['title'] ?? ''}',
              style: context.type.bodySecondary,
            ),
          ),
          if (minutes > 0)
            Text(
              GochanoLanguage.text(
                '$minutes min',
                '$minutes মিনিট',
              ),
              style: context.type.caption,
            ),
        ],
      ),
    );
  }
}
