// Community — study groups, the Question Bank and exam challenges
// (spec §70, §71, Phase 7).
//
// A note on scope
// ---------------
// Gochano's Community is **academic**, not a social feed. There are no
// followers, no reactions-as-vanity-metrics and no engagement tricks
// (spec §90: do not fake features, do not show "Coming Soon"). What exists
// and works is: create a group, join by invite code, share resources, chat
// when the group admin enables it, see who is in it, ask and answer
// questions for Learning Points (spec 7.3 / 7.6), challenge a classmate
// with one of your own papers (spec 7.4), and put Ziku in front of a
// disagreement inside the group (spec 7.2).
//
// That is also what spec §70 actually asks for: academic, student-focused,
// with the content dominant and no follower counts.

import 'package:flutter/material.dart';

import '../../../core/design_system/gochano_spacing.dart';
import '../../../core/localization/gochano_language.dart';
import '../../../shared/widgets/gochano_surfaces.dart';
import '../../../widgets/language_toggle.dart';
import 'community_view.dart';
import 'ai_community_feed_screen.dart';
import 'group_actions.dart';

class CommunityScreen extends StatelessWidget {
  const CommunityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GochanoScaffold(
      padBody: false,
      appBar: GochanoAppBar(
        title: GochanoLanguage.text('Community', 'কমিউনিটি'),
        subtitle: GochanoLanguage.text(
          'Study together, share materials',
          'একসাথে পড়ুন, উপকরণ শেয়ার করুন',
        ),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome_outlined),
            tooltip: GochanoLanguage.text('AI Community', 'এআই কমিউনিটি'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AiCommunityFeedScreen()),
            ),
          ),
          IconButton(
            key: const ValueKey('community_header_new_group_button'),
            icon: const Icon(Icons.group_add_rounded),
            tooltip: GochanoLanguage.text('Group options', 'গ্রুপ অপশন'),
            onPressed: () => showGroupActionsSheet(context),
          ),
          const LanguageToggle(),
          const SizedBox(width: GochanoSpacing.xs),
        ],
      ),
      // Universal Quick Add FAB is provided by GochanoShell.
      // No local floatingActionButton here to avoid overlap.
      body: const CommunityView(),
    );
  }
}
