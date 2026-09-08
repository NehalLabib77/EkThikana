// Compact reward display for the Profile screen.
//
// Shows Level, XP, and Gem balance in a compact row consistent with the
// existing Profile UI patterns.

import 'package:flutter/material.dart';

import '../../../core/design_system/gochano_colors.dart';
import '../../../core/design_system/gochano_spacing.dart';
import '../../../core/design_system/gochano_typography.dart';
import '../../../core/localization/gochano_language.dart';
import '../domain/level_helper.dart';
import '../domain/reaction_catalog.dart';
import '../domain/reward_model.dart';

class ProfileRewardSection extends StatelessWidget {
  const ProfileRewardSection({super.key, required this.profile});

  final RewardProfile profile;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final level = levelForXp(profile.totalXp);
    final unlockedCount = reactionsForLevel(level).length;
    final totalReactions = allReactions.length;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: GochanoSpacing.md,
        vertical: GochanoSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(GochanoRadius.lg),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          // Level
          _StatChip(
            icon: Icons.leaderboard_rounded,
            label: GochanoLanguage.text(
              'Level $level',
              'লেভেল $level',
            ),
            color: colors.study,
          ),
          const SizedBox(width: GochanoSpacing.sm),

          // XP
          _StatChip(
            icon: Icons.star_rounded,
            label: '${profile.totalXp} XP',
            color: colors.study,
          ),
          const SizedBox(width: GochanoSpacing.sm),

          // Gems
          _StatChip(
            icon: Icons.diamond_rounded,
            label: '${profile.gems}',
            color: colors.info,
          ),

          const Spacer(),

          // Unlocked reactions count
          if (totalReactions > 0)
            Text(
              GochanoLanguage.text(
                '$unlockedCount/$totalReactions',
                '$unlockedCount/$totalReactions',
              ),
              style: context.type.caption.copyWith(
                color: colors.textSecondary,
              ),
            ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: GochanoSpacing.xxs),
        Text(
          label,
          style: context.type.caption.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
