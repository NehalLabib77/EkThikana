// Community body — the three study-community segments without their own
// scaffold or app bar (spec 7.1, 7.3, 7.4).
//
// Extracted so it can be reused as a Study top tab and as the standalone
// CommunityScreen.  The original CommunityScreen wraps this in its own
// GochanoScaffold; StudyScreen embeds it directly in a TabBarView.
//
// Segments:
//   groups       study groups (Firestore stream, the Phase 1 surface)
//   questions    the Question Bank (spec 7.3) + Learning Points (7.6)
//   challenges   exam challenges (spec 7.4)
//
// The default segment is `groups` and it loads from Firestore exactly as
// before, so opening Community never costs an API call. The other two are
// built only once selected, and every loader on them is injectable for
// tests.

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
import '../domain/community_models.dart';
import 'challenge_list_screen.dart';
import 'community_labels.dart';
import 'group_actions.dart' show showGroupActionsSheet;
import 'group_detail_screen.dart';
import 'question_bank_screen.dart';

class CommunityView extends StatefulWidget {
  const CommunityView({
    super.key,
    this.initialSegment = 'groups',
    this.postsFn,
    this.leaderboardFn,
    this.createPostFn,
    this.postDetailFn,
    this.challengesFn,
  });

  /// Which segment to open on. Tests use it to reach the API-backed
  /// segments without touching Firestore.
  final String initialSegment;

  final CommunityPostsFn? postsFn;
  final CommunityLeaderboardFn? leaderboardFn;
  final CommunityCreatePostFn? createPostFn;
  final CommunityPostFn? postDetailFn;
  final CommunityChallengeListFn? challengesFn;

  @override
  State<CommunityView> createState() => _CommunityViewState();
}

class _CommunityViewState extends State<CommunityView> {
  late String _segment;

  @override
  void initState() {
    super.initState();
    _segment = widget.initialSegment;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            GochanoSpacing.md,
            GochanoSpacing.sm,
            GochanoSpacing.md,
            GochanoSpacing.xs,
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                for (final value in kCommunitySegments)
                  ButtonSegment(
                    value: value,
                    label: Text(communitySegmentLabel(value)),
                  ),
              ],
              selected: {_segment},
              onSelectionChanged: (selection) =>
                  setState(() => _segment = selection.first),
            ),
          ),
        ),
        Expanded(child: _buildSegment(context)),
      ],
    );
  }

  Widget _buildSegment(BuildContext context) {
    switch (_segment) {
      case 'questions':
        return QuestionBankView(
          postsFn: widget.postsFn,
          leaderboardFn: widget.leaderboardFn,
          createPostFn: widget.createPostFn,
          postDetailFn: widget.postDetailFn,
        );
      case 'challenges':
        return ChallengeListView(challengesFn: widget.challengesFn);
      default:
        return _buildGroups(context);
    }
  }

  Widget _buildGroups(BuildContext context) {
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
