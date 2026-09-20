// Community body — the groups list without its own scaffold or app bar.
//
// Extracted so it can be reused as a Study top tab and as the standalone
// CommunityScreen.  The original CommunityScreen wraps this in its own
// GochanoScaffold; StudyScreen embeds it directly in a TabBarView.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/design_system/gochano_art.dart';
import '../../../core/design_system/gochano_colors.dart';
import '../../../core/design_system/gochano_illustration.dart';
import '../../../core/design_system/gochano_spacing.dart';
import '../../../core/design_system/gochano_typography.dart';
import '../../../core/localization/gochano_language.dart';
import '../../../core/page_route.dart';
import '../../../services/firestore_service.dart';
import '../../../shared/states/gochano_states.dart';
import '../../../shared/widgets/gochano_controls.dart';
import '../../../shared/widgets/gochano_surfaces.dart';
import 'group_actions.dart' show showGroupActionsSheet;
import 'group_detail_screen.dart';

class CommunityView extends StatelessWidget {
  const CommunityView({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirestoreService.myGroups(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return StaticLoadingState(
            message: GochanoLanguage.text(
              'Loading your groups…',
              'আপনার গ্রুপ লোড হচ্ছে…',
            ),
          );
        }
        if (snapshot.hasError) {
          return ErrorState(message: friendlyErrorMessage(snapshot.error));
        }

        final groups = [...?snapshot.data?.docs]
          ..sort(
            (a, b) => (a.data()['name']?.toString() ?? '').compareTo(
              b.data()['name']?.toString() ?? '',
            ),
          );

        if (groups.isEmpty) {
          return EmptyState(
            illustration: GochanoArt.featureGroups,
            title: GochanoLanguage.text(
              'No study groups yet',
              'এখনো কোনো স্টাডি গ্রুপ নেই',
            ),
            message: GochanoLanguage.text(
              'Create a group for your class, or join one with an invite '
                  'code from a classmate.',
              'আপনার ক্লাসের জন্য একটি গ্রুপ তৈরি করুন, অথবা সহপাঠীর '
                  'ইনভাইট কোড দিয়ে যোগ দিন।',
            ),
            actionLabel: GochanoLanguage.text('New group', 'নতুন গ্রুপ'),
            onAction: () => showGroupActionsSheet(context),
          );
        }

        return ListView.builder(
          padding: GochanoSpacing.scrollBody,
          itemCount: groups.length,
          itemBuilder: (context, i) => Padding(
            padding: const EdgeInsets.only(bottom: GochanoSpacing.sm),
            child: _GroupCard(doc: groups[i]),
          ),
        );
      },
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.doc});

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final data = doc.data();
    final name = data['name']?.toString() ?? '';
    final description = data['description']?.toString() ?? '';
    final members = ((data['memberIds'] as List?) ?? const []).length;
    final chatEnabled = data['chatEnabled'] == true;

    return AppCard(
      accent: colors.community,
      onTap: () => Navigator.of(context).push(
        GochanoRoute.to(
          builder: (_) => GroupDetailScreen(groupId: doc.id, groupName: name),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              GochanoIllustrationTile(
                GochanoArt.featureGroups,
                accent: colors.community,
                plateSize: 48,
              ),
              const SizedBox(width: GochanoSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(name, style: context.type.sectionHeading),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: context.type.bodySecondary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: GochanoSpacing.sm),
          Wrap(
            spacing: GochanoSpacing.xxs,
            children: [
              GochanoBadge(
                label: GochanoLanguage.text(
                  members == 1 ? '1 member' : '$members members',
                  '$members জন সদস্য',
                ),
                icon: Icons.people_outline_rounded,
              ),
              if (chatEnabled)
                GochanoBadge(
                  label: GochanoLanguage.text('Chat on', 'চ্যাট চালু'),
                  tone: GochanoBadgeTone.info,
                  icon: Icons.chat_bubble_outline_rounded,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
