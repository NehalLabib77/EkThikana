// Community — study groups (spec §70, §71).
//
// A note on scope
// ---------------
// Gochano's Community is **study groups**, not a social feed. There is no
// posts/comments backend in this project — no endpoints, no Firestore
// collection — so this screen does not pretend otherwise (spec §90: do not
// fake features, do not show "Coming Soon"). What exists and works is: create
// a group, join by invite code, share resources, chat when the group admin
// enables it, and see who is in it.
//
// That is also what spec §70 actually asks for: academic, student-focused,
// with the content dominant and no follower counts or engagement tricks.

import 'package:flutter/material.dart';

import '../../../core/design_system/gochano_spacing.dart';
import '../../../core/localization/gochano_language.dart';
import '../../../shared/widgets/gochano_surfaces.dart';
import '../../../widgets/language_toggle.dart';
import 'community_view.dart';
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

