// Phase 2 — "My Academic Health" entry on Profile.
//
// One line that answers "how are my studies going?" — the 0-100 score, the
// sentence the backend wrote to explain it, and the direction it is moving.
// The full breakdown lives one tap away; the card only carries the number
// worth showing on a settings list.
//
// Student-only by construction: Profile mounts it inside the `role ==
// 'student'` block, because every signal behind the score (quiz mastery,
// recorded mistakes, the study plan) belongs to the student who produced it.

import 'package:flutter/material.dart';

import '../../../core/design_system/gochano_art.dart';
import '../../../core/design_system/gochano_colors.dart';
import '../../../core/design_system/gochano_typography.dart';
import '../../../core/localization/gochano_language.dart';
import '../../../core/page_route.dart';
import '../../../services/api_service.dart';
import '../../../shared/widgets/gochano_controls.dart';
import '../../../shared/widgets/gochano_surfaces.dart';
import 'academic_health_screen.dart';

class AcademicHealthCard extends StatefulWidget {
  const AcademicHealthCard({super.key, this.healthFn});

  /// Read hook, injected in tests so the widget never opens a socket.
  final Future<Map<String, dynamic>> Function()? healthFn;

  @override
  State<AcademicHealthCard> createState() => _AcademicHealthCardState();
}

class _AcademicHealthCardState extends State<AcademicHealthCard> {
  Map<String, dynamic>? _health;
  bool _failed = false;

  Future<Map<String, dynamic>> Function() get _load =>
      widget.healthFn ?? ApiService.getAcademicHealth;

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
        _health = body;
        _failed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  void _open() {
    Navigator.of(context).push(
      GochanoRoute.to(
        builder: (_) => AcademicHealthScreen(healthFn: widget.healthFn),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final health = _health;
    final score = health == null ? null : _asInt(health['score']);
    final trend = _asMapOrNull(health?['trend']);
    final hasData = health == null ? false : health['hasData'] == true;

    final String summary;
    if (health == null) {
      summary = _failed
          ? GochanoLanguage.text(
              "Couldn't load right now — tap to try again.",
              'এখন লোড করা যায়নি — আবার চেষ্টা করুন।',
            )
          : GochanoLanguage.text(
              'Checking your academic health…',
              'একাডেমিক হেলথ দেখা হচ্ছে…',
            );
    } else if (!hasData) {
      summary = GochanoLanguage.text(
        'Not enough data yet — take a quiz or start a study session.',
        'এখনো যথেষ্ট তথ্য নেই — একটি কুইজ দিন।',
      );
    } else {
      summary = '${health['headline'] ?? ''}';
    }

    return AppCard(
      accent: colors.ai,
      child: GochanoListRow(
        illustration: GochanoArt.featureStudy,
        accent: colors.ai,
        title: GochanoLanguage.text(
          'My Academic Health',
          'আমার একাডেমিক হেলথ',
        ),
        subtitle: summary,
        onTap: _open,
        badge: _trendBadge(context, trend),
        metadata: health == null
            ? null
            : <String>[
                GochanoLanguage.text(
                  '${_asInt(health['coverage'] is List ? (health['coverage'] as List).length : 0)} of 4 signals measured',
                  'তথ্য পাওয়া গেছে',
                ),
              ],
        trailing: score == null
            ? Icon(
                Icons.chevron_right_rounded,
                size: 28,
                color: colors.textSecondary,
              )
            : _scoreDial(context, score),
      ),
    );
  }

  Widget? _trendBadge(BuildContext context, Map<String, dynamic>? trend) {
    if (trend == null) return null;
    final direction = '${trend['direction'] ?? 'new'}';
    if (direction == 'new') return null;

    final up = direction == 'up';
    final tone = up ? GochanoBadgeTone.success : GochanoBadgeTone.warning;
    final label = up
        ? GochanoLanguage.text('Improving', 'বাড়ছে')
        : (direction == 'down'
            ? GochanoLanguage.text('Slipping', 'কমছে')
            : GochanoLanguage.text('Steady', 'স্থির'));

    return GochanoBadge(
      label: label,
      tone: tone,
      icon: up
          ? Icons.trending_up_rounded
          : (direction == 'down'
              ? Icons.trending_down_rounded
              : Icons.trending_flat_rounded),
    );
  }

  Widget _scoreDial(BuildContext context, int score) {
    final colors = context.colors;
    final Color tone;
    if (score >= 85) {
      tone = colors.success;
    } else if (score >= 70) {
      tone = colors.info;
    } else if (score >= 55) {
      tone = colors.warning;
    } else {
      tone = colors.error;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$score',
          style: context.type.statisticSmall.copyWith(color: tone),
        ),
        Text('/ 100', style: context.type.caption),
      ],
    );
  }

  static int _asInt(dynamic value) => value is num ? value.toInt() : 0;

  static Map<String, dynamic>? _asMapOrNull(dynamic value) {
    if (value is! Map) return null;
    return Map<String, dynamic>.from(value);
  }
}
