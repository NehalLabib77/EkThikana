// Subject detail (spec §31).
//
// Subject identity at the top, then its materials with search and the two
// actions that matter here: Add material and Ask AI. Everything else is in
// each material row's own menu.

import 'package:flutter/material.dart';

import '../../../../core/design_system/gochano_art.dart';
import '../../../../core/design_system/gochano_colors.dart';
import '../../../../core/design_system/gochano_illustration.dart';
import '../../../../core/design_system/gochano_spacing.dart';
import '../../../../core/design_system/gochano_typography.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../core/page_route.dart';
import '../../../../shared/widgets/gochano_controls.dart';
import '../../../../shared/widgets/gochano_surfaces.dart';
import '../ai/ai_assistant_screen.dart';
import '../materials/materials_screen.dart';

class SubjectScreen extends StatelessWidget {
  const SubjectScreen({
    super.key,
    required this.subjectId,
    required this.subjectName,
    required this.semesterName,
  });

  final String subjectId;
  final String subjectName;
  final String semesterName;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return GochanoScaffold(
      padBody: false,
      appBar: GochanoAppBar(
        title: subjectName,
        subtitle: semesterName,
        actions: [
          IconActionButton(
            icon: Icons.auto_awesome_outlined,
            label: GochanoLanguage.text('Ask AI', 'এআই কে জিজ্ঞাসা'),
            accent: colors.ai,
            onPressed: () => Navigator.of(context).push(
              GochanoRoute.to(builder: (_) => const AiAssistantScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              GochanoSpacing.md,
              GochanoSpacing.xs,
              GochanoSpacing.md,
              0,
            ),
            child: AppCard(
              accent: colors.study,
              child: Row(
                children: [
                  GochanoIllustration(
                    GochanoArt.subjectIdFor(subjectName),
                    size: 44,
                    accent: colors.study,
                  ),
                  const SizedBox(width: GochanoSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(subjectName, style: context.type.sectionHeading),
                        Text(semesterName, style: context.type.caption),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // The material list is the same widget the library uses, filtered
          // to this subject — one implementation of search, sort, rename and
          // delete rather than two that can drift (spec §84).
          Expanded(child: MaterialsScreen(subjectFilter: subjectName)),
        ],
      ),
    );
  }
}
