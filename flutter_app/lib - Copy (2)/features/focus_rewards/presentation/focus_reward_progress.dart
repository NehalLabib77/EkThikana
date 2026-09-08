// Compact reward progress section for the Focus screen.
//
// Displays level, XP, gem balance, progress bar, and next unlock preview.
// Appears above the Focus timer when no session is active.

import 'package:flutter/material.dart';

import '../../../core/design_system/gochano_colors.dart';
import '../../../core/design_system/gochano_spacing.dart';
import '../../../core/design_system/gochano_typography.dart';
import '../../../core/localization/gochano_language.dart';
import '../../../shared/widgets/gochano_surfaces.dart';
import '../domain/level_helper.dart';
import '../domain/reaction_catalog.dart';
import '../domain/reward_model.dart';

class FocusRewardProgress extends StatelessWidget {
  const FocusRewardProgress({super.key, required this.profile});

  final RewardProfile profile;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final level = levelForXp(profile.totalXp);
    final progress = progressToNextLevel(profile.totalXp);
    final remaining = xpRemainingToNextLevel(profile.totalXp);

    // Find the next reaction unlock level.
    String? nextUnlockLabel;
    String? nextUnlockEmoji;
    for (final pack in reactionPacks) {
      if (pack.level > level) {
        nextUnlockLabel = GochanoLanguage.text(
          'Unlocks at Level ${pack.level}',
          'Level ${pack.level} তে খুলে',
        );
        nextUnlockEmoji = pack.reactions.map((r) => r.emoji).join(' ');
        break;
      }
    }

    return AppCard(
      accent: colors.study,
      padding: const EdgeInsets.all(GochanoSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Level and Gems row
          Row(
            children: [
              Text(
                GochanoLanguage.text(
                  'Level $level',
                  'লেভেল $level',
                ),
                style: context.type.sectionHeading,
              ),
              const Spacer(),
              Icon(
                Icons.diamond_rounded,
                size: 18,
                color: colors.info,
              ),
              const SizedBox(width: GochanoSpacing.xxs),
              Text(
                '${profile.gems}',
                style: context.type.body.copyWith(
                  color: colors.info,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: GochanoSpacing.sm),

          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: colors.surfaceVariant,
              color: colors.study,
            ),
          ),
          const SizedBox(height: GochanoSpacing.xs),

          // XP details
          Row(
            children: [
              Text(
                '${profile.totalXp} XP',
                style: context.type.caption,
              ),
              const Spacer(),
              if (remaining > 0)
                Text(
                  GochanoLanguage.text(
                    '$remaining XP to Level ${level + 1}',
                    'Level ${level + 1} পেতে আরও $remaining XP',
                  ),
                  style: context.type.caption,
                )
              else
                Text(
                  GochanoLanguage.text('Max level', 'সর্বোচ্চ লেভেল'),
                  style: context.type.caption.copyWith(
                    color: colors.success,
                  ),
                ),
            ],
          ),

          // Next unlock preview
          if (nextUnlockLabel != null) ...[
            const SizedBox(height: GochanoSpacing.sm),
            Row(
              children: [
                Text(
                  GochanoLanguage.text('Next unlock: ', 'পরবর্তী আনলক: '),
                  style: context.type.caption.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                Text(
                  nextUnlockEmoji ?? '',
                  style: context.type.caption,
                ),
                const SizedBox(width: GochanoSpacing.xxs),
                Flexible(
                  child: Text(
                    nextUnlockLabel,
                    style: context.type.caption.copyWith(
                      color: colors.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
