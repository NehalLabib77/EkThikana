import 'package:flutter/material.dart';

import '../../../core/design_system/app_design_system.dart';
import '../../../core/design_system/gochano_art.dart';
import '../../../core/localization/gochano_language.dart';
import '../../../shared/states/gochano_states.dart';
import '../../../shared/widgets/gochano_controls.dart';
import '../../../shared/widgets/gochano_surfaces.dart';
import 'community_intelligence_api_service.dart';
import 'community_contribution_profile_screen.dart';

class AiCommunityFeedScreen extends StatefulWidget {
  const AiCommunityFeedScreen({super.key});

  @override
  State<AiCommunityFeedScreen> createState() => _AiCommunityFeedScreenState();
}

class _AiCommunityFeedScreenState extends State<AiCommunityFeedScreen> {
  late Future<Map<String, dynamic>> _feed;

  @override
  void initState() {
    super.initState();
    _feed = CommunityIntelligenceApiService.feed();
  }

  Future<void> _askQuestion() async {
    final title = TextEditingController();
    final body = TextEditingController();
    final colors = context.colors;

    final submitted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text(
          GochanoLanguage.text('Ask Learning Community', 'লার্নিং কমিউনিটিতে জিজ্ঞাসা করুন'),
          style: context.type.sectionHeading,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: title,
              decoration: InputDecoration(
                labelText: GochanoLanguage.text('Question Title', 'প্রশ্নের শিরোনাম'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: GochanoSpacing.sm),
            TextField(
              controller: body,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: GochanoLanguage.text('Explain what you are stuck on', 'কোথায় আটকে গেছেন বুঝিয়ে বলুন'),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(GochanoLanguage.text('Cancel', 'বাতিল')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: colors.brand),
            onPressed: () => Navigator.pop(context, true),
            child: Text(GochanoLanguage.text('Post Question', 'প্রশ্ন পোস্ট করুন')),
          ),
        ],
      ),
    );
    if (submitted != true ||
        (title.text.trim().isEmpty && body.text.trim().isEmpty)) {
      return;
    }
    await CommunityIntelligenceApiService.askQuestion(
      title: title.text.trim(),
      body: body.text.trim(),
    );
    if (mounted) setState(() => _feed = CommunityIntelligenceApiService.feed());
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return GochanoScaffold(
      padBody: false,
      appBar: GochanoAppBar(
        title: GochanoLanguage.text('AI Community Feed', 'এআই কমিউনিটি ফিড'),
        subtitle: GochanoLanguage.text(
          'Personalized questions and peer study',
          'ব্যক্তিগত প্রশ্ন ও সহপাঠীদের পড়াশোনা',
        ),
        actions: [
          IconButton(
            onPressed: _askQuestion,
            icon: const Icon(Icons.add_comment_rounded),
            tooltip: GochanoLanguage.text('Ask the community', 'কমিউনিটিতে জিজ্ঞাসা করুন'),
          ),
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const CommunityContributionProfileScreen(),
              ),
            ),
            icon: const Icon(Icons.workspace_premium_rounded),
            tooltip: GochanoLanguage.text('Contribution profile', 'অবদান প্রোফাইল'),
          ),
        ],
      ),
      body: AppPageBackground(
        gradient: AppGradients.communityHub,
        child: FutureBuilder<Map<String, dynamic>>(
          future: _feed,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return StaticLoadingState(
                message: GochanoLanguage.text(
                  'Loading community feed…',
                  'কমিউনিটি ফিড লোড হচ্ছে…',
                ),
              );
            }
            if (snapshot.hasError) {
              return ErrorState(
                message: friendlyErrorMessage(snapshot.error),
                onRetry: () => setState(() => _feed = CommunityIntelligenceApiService.feed()),
              );
            }
            final posts = (snapshot.data?['posts'] as List?) ?? const [];
            if (posts.isEmpty) {
              return EmptyState(
                illustration: GochanoArt.featureCommunity,
                title: GochanoLanguage.text('No learning posts yet', 'এখনো কোনো পোস্ট নেই'),
                message: GochanoLanguage.text(
                  'Be the first to post a study question.',
                  'পড়াশোনার প্রশ্ন পোস্ট করা প্রথম ব্যক্তি হন।',
                ),
                actionLabel: GochanoLanguage.text('Ask a Question', 'প্রশ্ন করুন'),
                onAction: _askQuestion,
              );
            }
            return ListView.builder(
              padding: GochanoSpacing.scrollBody,
              itemCount: posts.length,
              itemBuilder: (context, index) {
                final post = Map<String, dynamic>.from(posts[index] as Map);
                final postTitle = post['title']?.toString().isNotEmpty == true
                    ? post['title'].toString()
                    : post['body'].toString();
                final subject = post['subject']?.toString() ?? 'General';
                final chapter = post['chapter']?.toString() ?? 'General';
                final difficulty = post['difficulty']?.toString() ?? 'medium';
                final isRelated = post['relatedToYourLearning'] == true;

                return Padding(
                  padding: const EdgeInsets.only(bottom: GochanoSpacing.sm),
                  child: AppCard(
                    accent: isRelated ? colors.ai : colors.community,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: GochanoSpacing.xs,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: (isRelated ? colors.ai : colors.community)
                                    .withValues(alpha: 0.12),
                                borderRadius: GochanoRadius.smAll,
                              ),
                              child: Text(
                                subject,
                                style: context.type.caption.copyWith(
                                  color: isRelated ? colors.ai : colors.community,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: GochanoSpacing.xs),
                            Text(
                              '• $chapter',
                              style: context.type.caption,
                            ),
                            const Spacer(),
                            if (isRelated)
                              GochanoBadge(
                                label: GochanoLanguage.text('For You', 'আপনার জন্য'),
                                tone: GochanoBadgeTone.brand,
                              )
                            else
                              GochanoBadge(
                                label: difficulty,
                                tone: GochanoBadgeTone.info,
                              ),
                          ],
                        ),
                        const SizedBox(height: GochanoSpacing.xs),
                        Text(
                          postTitle,
                          style: context.type.cardHeading,
                        ),
                        if (post['body'] != null &&
                            post['title'] != null &&
                            post['title'].toString().isNotEmpty &&
                            post['body'].toString().isNotEmpty) ...[
                          const SizedBox(height: GochanoSpacing.xxs),
                          Text(
                            post['body'].toString(),
                            style: context.type.bodySecondary,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
