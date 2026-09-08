// Community chat reaction picker.
//
// Bottom sheet that presents Gochano-exclusive reactions from the
// centralized ReactionCatalog, grouped by pack. Locked reactions show
// a lock overlay and tapping them reveals how much XP is needed.

import 'package:flutter/material.dart';

import '../../../core/design_system/gochano_colors.dart';
import '../../../core/design_system/gochano_spacing.dart';
import '../../../core/design_system/gochano_typography.dart';
import '../../../core/localization/gochano_language.dart';
import '../../focus_rewards/data/reward_service.dart';
import '../../focus_rewards/domain/level_helper.dart';
import '../../focus_rewards/domain/reaction_catalog.dart';
import '../../focus_rewards/domain/reward_model.dart';

/// Shows the reaction picker. Returns the selected [GochanoReaction] if the
/// user picked an unlocked reaction, or `null` if they dismissed the sheet.
Future<GochanoReaction?> showReactionPicker(BuildContext context) {
  return showModalBottomSheet<GochanoReaction>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: true,
    builder: (_) => const _ReactionPickerBody(),
  );
}

class _ReactionPickerBody extends StatefulWidget {
  const _ReactionPickerBody();

  @override
  State<_ReactionPickerBody> createState() => _ReactionPickerBodyState();
}

class _ReactionPickerBodyState extends State<_ReactionPickerBody> {
  RewardProfile _profile = RewardProfile.empty();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final profile = await RewardService.readProfile();
      if (mounted) setState(() => _profile = profile);
    } catch (_) {
      // Default to empty (all locked except Level 1).
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final level = levelForXp(_profile.totalXp);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: GochanoSpacing.md,
          vertical: GochanoSpacing.sm,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Expanded(
                  child: Text(
                    GochanoLanguage.text(
                      'Gochano Reactions',
                      'গোচানো রিঅ্যাকশন',
                    ),
                    style: context.type.sectionHeading,
                  ),
                ),
                Text(
                  GochanoLanguage.text(
                    'Level $level',
                    'লেভেল $level',
                  ),
                  style: context.type.caption.copyWith(
                    color: colors.study,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: GochanoSpacing.sm),

            // Hint about normal emoji
            Text(
              GochanoLanguage.text(
                'Type normal emoji from your keyboard, or pick a Gochano reaction below.',
                'আপনার কীবোর্ড থেকে সাধারণ ইমোজি টাইপ করুন, অথবা নিচে থেকে গোচানো রিঅ্যাকশন বাছুন।',
              ),
              style: context.type.caption.copyWith(
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: GochanoSpacing.sm),

            // Reaction packs
            for (final pack in reactionPacks) ...[
              _PackSection(
                pack: pack,
                currentLevel: level,
                onReactionSelected: (reaction) {
                  Navigator.of(context).pop(reaction);
                },
                onLockedTap: (reaction) => _showLockedMessage(context, reaction, level),
              ),
              const SizedBox(height: GochanoSpacing.sm),
            ],

            const SizedBox(height: GochanoSpacing.xs),
          ],
        ),
      ),
    );
  }

  void _showLockedMessage(
    BuildContext context,
    GochanoReaction reaction,
    int currentLevel,
  ) {
    final remaining = xpRemainingToNextLevel(_profile.totalXp);
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(GochanoSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                reaction.emoji,
                style: const TextStyle(fontSize: 40),
              ),
              const SizedBox(height: GochanoSpacing.sm),
              Text(
                GochanoLanguage.text(
                  'Unlocks at Level ${reaction.requiredLevel}',
                  'লেভেল ${reaction.requiredLevel}-এ আনলক হবে',
                ),
                style: context.type.sectionHeading,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: GochanoSpacing.xs),
              Text(
                remaining > 0
                    ? GochanoLanguage.text(
                        'Earn $remaining more XP by completing Focus sessions.',
                        'ফোকাস সেশন সম্পন্ন করে আরও $remaining XP অর্জন করুন।',
                      )
                    : GochanoLanguage.text(
                        'Keep focusing to reach the next level.',
                        'পরবর্তী লেভেলে পৌঁছাতে ফোকাস চালিয়ে যান।',
                      ),
                style: context.type.bodySecondary,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: GochanoSpacing.lg),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(GochanoLanguage.text('OK', 'ঠিক আছে')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PackSection extends StatelessWidget {
  const _PackSection({
    required this.pack,
    required this.currentLevel,
    required this.onReactionSelected,
    required this.onLockedTap,
  });

  final ReactionPack pack;
  final int currentLevel;
  final ValueChanged<GochanoReaction> onReactionSelected;
  final ValueChanged<GochanoReaction> onLockedTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final packUnlocked = currentLevel >= pack.level;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Pack header
        Row(
          children: [
            Text(
              GochanoLanguage.text(
                'Level ${pack.level}',
                'লেভেল ${pack.level}',
              ),
              style: context.type.label.copyWith(
                color: packUnlocked ? colors.textPrimary : colors.textTertiary,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (!packUnlocked) ...[
              const SizedBox(width: GochanoSpacing.xxs),
              Icon(
                Icons.lock_rounded,
                size: 14,
                color: colors.textTertiary,
              ),
            ],
          ],
        ),
        const SizedBox(height: GochanoSpacing.xxs),

        // Reactions grid
        Row(
          children: [
            for (final reaction in pack.reactions) ...[
              Expanded(
                child: _ReactionTile(
                  reaction: reaction,
                  unlocked: packUnlocked,
                  onTap: () {
                    if (packUnlocked) {
                      onReactionSelected(reaction);
                    } else {
                      onLockedTap(reaction);
                    }
                  },
                ),
              ),
              if (reaction != pack.reactions.last)
                const SizedBox(width: GochanoSpacing.xs),
            ],
          ],
        ),
      ],
    );
  }
}

class _ReactionTile extends StatelessWidget {
  const _ReactionTile({
    required this.reaction,
    required this.unlocked,
    required this.onTap,
  });

  final GochanoReaction reaction;
  final bool unlocked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Semantics(
      button: true,
      enabled: unlocked,
      label: unlocked
          ? GochanoLanguage.text(
              'Send ${reaction.label} reaction',
              '${reaction.label} রিঅ্যাকশন পাঠান',
            )
          : GochanoLanguage.text(
              'Locked — unlocks at Level ${reaction.requiredLevel}',
              'লকড — লেভেল ${reaction.requiredLevel}-এ আনলক হবে',
            ),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: unlocked
                ? colors.surface
                : colors.surfaceVariant.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(GochanoRadius.md),
            border: Border.all(
              color: unlocked ? colors.border : colors.surfaceVariant,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Emoji
              Text(
                reaction.emoji,
                style: TextStyle(
                  fontSize: 28,
                  color: unlocked ? null : Colors.grey,
                ),
              ),

              // Lock indicator
              if (!unlocked)
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: colors.border),
                    ),
                    child: Icon(
                      Icons.lock_rounded,
                      size: 10,
                      color: colors.textTertiary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
