// Phase 1 — "My Learning Brain" entry on Profile.
//
// The card carries the three numbers a student acts on — how many mistakes
// are remembered, how many are repeating, how many are due today — and opens
// the full screen. It is student-only: the mistake memory belongs to the
// person who made the mistakes, and a teacher's Profile never shows it.

import 'package:flutter/material.dart';

import '../../../core/design_system/gochano_art.dart';
import '../../../core/design_system/gochano_colors.dart';
import '../../../core/localization/gochano_language.dart';
import '../../../core/page_route.dart';
import '../../../services/api_service.dart';
import '../../../shared/widgets/gochano_controls.dart';
import '../../../shared/widgets/gochano_surfaces.dart';
import 'learning_brain_screen.dart';

class LearningBrainCard extends StatefulWidget {
  const LearningBrainCard({super.key});

  @override
  State<LearningBrainCard> createState() => _LearningBrainCardState();
}

class _LearningBrainCardState extends State<LearningBrainCard> {
  Map<String, dynamic>? _brain;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final body = await ApiService.getLearningBrain();
      if (!mounted) return;
      setState(() {
        _brain = body;
        _failed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  void _open() {
    Navigator.of(
      context,
    ).push(GochanoRoute.to(builder: (_) => const LearningBrainScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final brain = _brain;
    final total = brain == null ? 0 : _asInt(brain['totalMistakes']);
    final due = brain == null ? 0 : _asInt(brain['revisionDueCount']);
    final repeated = brain == null ? 0 : _asInt(brain['repeatedCount']);
    final pending = brain == null ? 0 : _asInt(brain['pendingAnalysis']);

    final String summary;
    if (brain == null) {
      summary = _failed
          ? GochanoLanguage.text(
              "Couldn't load right now — tap to try again.",
              'এখন লোড করা যায়নি — আবার চেষ্টা করুন।',
            )
          : GochanoLanguage.text(
              'Checking your saved mistakes…',
              'সংরক্ষিত ভুল দেখা হচ্ছে…',
            );
    } else if (total == 0) {
      summary = GochanoLanguage.text(
        'Nothing recorded yet — wrong answers land here after a quiz.',
        'এখনো কিছু নেই — কুইজের ভুল এখানে জমা হবে।',
      );
    } else {
      summary = GochanoLanguage.text(
        '$total remembered · $repeated repeating · $due due today',
        '$total ভুল · $due টি আজ পুনরাবৃত্তির অপেক্ষায়',
      );
    }

    return AppCard(
      accent: colors.ai,
      child: GochanoListRow(
        illustration: GochanoArt.featureAi,
        accent: colors.ai,
        title: GochanoLanguage.text('My Learning Brain', 'আমার লার্নিং ব্রেইন'),
        subtitle: summary,
        onTap: _open,
        badge: (brain != null && due > 0)
            ? GochanoBadge(
                label: GochanoLanguage.text('$due due', '$due আজ'),
                tone: GochanoBadgeTone.warning,
                icon: Icons.event_available_rounded,
              )
            : null,
        metadata: (brain != null && pending > 0)
            ? <String>[
                GochanoLanguage.text(
                  '$pending waiting for Ziku',
                  '$pending টি জিকুর অপেক্ষায়',
                ),
              ]
            : null,
        trailing: Icon(
          Icons.chevron_right_rounded,
          size: 28,
          color: colors.textSecondary,
        ),
      ),
    );
  }

  static int _asInt(dynamic value) => value is num ? value.toInt() : 0;
}
