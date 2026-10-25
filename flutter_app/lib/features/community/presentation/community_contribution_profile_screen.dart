import 'package:flutter/material.dart';

import '../../../core/design_system/app_design_system.dart';
import '../../../core/design_system/gochano_art.dart';
import '../../../core/localization/gochano_language.dart';
import '../../../shared/states/gochano_states.dart';
import '../../../shared/widgets/gochano_surfaces.dart';
import 'community_intelligence_api_service.dart';

class CommunityContributionProfileScreen extends StatelessWidget {
  const CommunityContributionProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return GochanoScaffold(
      padBody: false,
      appBar: GochanoAppBar(
        title: GochanoLanguage.text('Contribution Profile', 'অবদান প্রোফাইল'),
        subtitle: GochanoLanguage.text(
          'Learning Points & Community Leaderboard',
          'লার্নিং পয়েন্টস এবং কমিউনিটি লিডারবোর্ড',
        ),
      ),
      body: AppPageBackground(
        gradient: AppGradients.academicHealth,
        child: FutureBuilder<Map<String, dynamic>>(
          future: CommunityIntelligenceApiService.leaderboard(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return StaticLoadingState(
                message: GochanoLanguage.text(
                  'Loading contribution leaderboard…',
                  'অবদান লিডারবোর্ড লোড হচ্ছে…',
                ),
              );
            }
            if (snapshot.hasError) {
              return ErrorState(
                message: friendlyErrorMessage(snapshot.error),
              );
            }
            final entries = (snapshot.data?['entries'] as List?) ??
                (snapshot.data?['leaderboard'] as List?) ??
                const [];

            return ListView(
              padding: GochanoSpacing.scrollBody,
              children: [
                // Info banner card
                AppCard(
                  accent: colors.brand,
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: colors.brand.withValues(alpha: 0.12),
                          borderRadius: GochanoRadius.mdAll,
                        ),
                        child: Icon(
                          Icons.military_tech_rounded,
                          color: colors.brand,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: GochanoSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              GochanoLanguage.text('Learning Points', 'লার্নিং পয়েন্টস'),
                              style: context.type.cardHeading.copyWith(color: colors.brand),
                            ),
                            const SizedBox(height: GochanoSpacing.xxs),
                            Text(
                              GochanoLanguage.text(
                                'Earn points from helpful answers (+3), accepted solutions (+5), useful notes (+10), and quizzes.',
                                'সহায়ক উত্তর (+৩), গৃহীত সমাধান (+৫), দরকারী নোট (+১০) ও কুইজ থেকে পয়েন্ট অর্জন করুন।',
                              ),
                              style: context.type.caption,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: GochanoSpacing.md),

                SectionHeader(
                  title: GochanoLanguage.text('Top Contributors', 'সেরা অবদানকারী'),
                  subtitle: GochanoLanguage.text('Community ranking', 'কমিউনিটি র‍্যাংকিং'),
                ),

                if (entries.isEmpty)
                  EmptyState(
                    illustration: GochanoArt.featureCommunity,
                    title: GochanoLanguage.text('No rankings yet', 'এখনো কোনো র‍্যাংকিং নেই'),
                    message: GochanoLanguage.text(
                      'Start answering questions to appear here.',
                      'এখানে আসতে প্রশ্নের উত্তর দেওয়া শুরু করুন।',
                    ),
                  )
                else
                  for (final raw in entries.take(25)) ...[
                    _buildContributorRow(context, raw as Map),
                    const SizedBox(height: GochanoSpacing.xs),
                  ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildContributorRow(BuildContext context, Map raw) {
    final colors = context.colors;
    final rank = raw['rank']?.toString() ?? '';
    final name = (raw['displayName'] ?? raw['name'] ?? 'Student').toString();
    final points = raw['points'] ?? 0;

    Color rankColor = colors.textSecondary;
    Color rankBg = colors.surfaceVariant;
    if (rank == '1') {
      rankColor = AppGradients.amberAccent;
      rankBg = AppGradients.amberSoft;
    } else if (rank == '2') {
      rankColor = AppGradients.slateText;
      rankBg = AppGradients.slateBorder;
    } else if (rank == '3') {
      rankColor = AppGradients.orangeDark;
      rankBg = AppGradients.orangeSoft;
    }

    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: GochanoSpacing.md,
        vertical: GochanoSpacing.sm,
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: rankBg,
              shape: BoxShape.circle,
            ),
            child: Text(
              rank.isEmpty ? '#' : rank,
              style: context.type.body.copyWith(
                fontWeight: FontWeight.bold,
                color: rankColor,
              ),
            ),
          ),
          const SizedBox(width: GochanoSpacing.sm),
          Expanded(
            child: Text(
              name,
              style: context.type.cardHeading,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: GochanoSpacing.sm,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: colors.brand.withValues(alpha: 0.1),
              borderRadius: GochanoRadius.xlAll,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.stars_rounded, size: 14, color: colors.brand),
                const SizedBox(width: 4),
                Text(
                  '$points pts',
                  style: context.type.caption.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colors.brand,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
