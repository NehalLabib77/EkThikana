// Community chat reaction picker.
//
// Bottom sheet that presents Gochano-exclusive reactions from the
// centralized AnimatedReactionCatalog, grouped by pack.

import 'package:flutter/material.dart';

import '../../../core/design_system/gochano_colors.dart';
import '../../../core/design_system/gochano_spacing.dart';
import '../../../core/design_system/gochano_typography.dart';
import '../../../core/localization/gochano_language.dart';
import '../domain/animated_reaction_catalog.dart';

/// Shows the reaction picker. Returns the selected [AnimatedReaction] if the
/// user picked a reaction, or `null` if they dismissed the sheet.
Future<AnimatedReaction?> showReactionPicker(BuildContext context) {
  return showModalBottomSheet<AnimatedReaction>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: true,
    builder: (_) => const _ReactionPickerBody(),
  );
}

class _ReactionPickerBody extends StatelessWidget {
  const _ReactionPickerBody();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

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
            for (final pack in animatedReactionPacks) ...[
              _PackSection(
                pack: pack,
                onReactionSelected: (reaction) {
                  Navigator.of(context).pop(reaction);
                },
              ),
              const SizedBox(height: GochanoSpacing.sm),
            ],

            const SizedBox(height: GochanoSpacing.xs),
          ],
        ),
      ),
    );
  }
}

class _PackSection extends StatelessWidget {
  const _PackSection({
    required this.pack,
    required this.onReactionSelected,
  });

  final AnimatedReactionPack pack;
  final ValueChanged<AnimatedReaction> onReactionSelected;

  @override
  Widget build(BuildContext context) {
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
                fontWeight: FontWeight.w600,
              ),
            ),
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
                  onTap: () => onReactionSelected(reaction),
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
    required this.onTap,
  });

  final AnimatedReaction reaction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Semantics(
      button: true,
      label: GochanoLanguage.text(
        'Send ${reaction.labelEn} reaction',
        '${reaction.labelBn} রিঅ্যাকশন পাঠান',
      ),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(GochanoRadius.md),
            border: Border.all(color: colors.border),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Emoji
              Text(
                reaction.fallbackEmoji,
                style: const TextStyle(fontSize: 28),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
