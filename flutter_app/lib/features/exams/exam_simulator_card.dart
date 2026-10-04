// Phase 3 — the Real Exam Simulator entry card.
//
// Home is a list of student cards, so the simulator enters the app the same
// way everything else does: one card, one tap, no data to fetch (the setup
// screen is what talks to the server).

import 'package:flutter/material.dart';

import '../../core/design_system/gochano_art.dart';
import '../../core/design_system/gochano_colors.dart';
import '../../core/localization/gochano_language.dart';
import '../../core/page_route.dart';
import '../../shared/widgets/gochano_controls.dart';
import '../../shared/widgets/gochano_surfaces.dart';
import 'presentation/exam_setup_screen.dart';

class ExamSimulatorCard extends StatelessWidget {
  const ExamSimulatorCard({super.key, this.openSetup});

  /// Injected in widget tests so a tap never opens a route or a socket.
  final VoidCallback? openSetup;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return AppCard(
      accent: colors.study,
      child: GochanoListRow(
        illustration: GochanoArt.subjectPhysics,
        accent: colors.study,
        title: GochanoLanguage.text(
          'Real Exam Simulator',
          'পরীক্ষা হল সিমুলেটর',
        ),
        subtitle: GochanoLanguage.text(
          'A full paper, a real timer, no hints.',
          'পূর্ণ প্রশ্নপত্র, আসল টাইমার, সাহায্য নেই।',
        ),
        onTap: openSetup ??
            () => Navigator.of(context).push(
                  GochanoRoute.to(builder: (_) => const ExamSetupScreen()),
                ),
        metadata: <String>[
          GochanoLanguage.text('AI, uploaded or saved questions', 'এআই, আপলোড বা সংরক্ষিত প্রশ্ন'),
        ],
        trailing: Icon(
          Icons.chevron_right_rounded,
          size: 28,
          color: colors.textSecondary,
        ),
      ),
    );
  }
}
