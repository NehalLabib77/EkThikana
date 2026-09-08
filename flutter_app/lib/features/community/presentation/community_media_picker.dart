// Unified Community chat media picker — Emoji, Reactions, Stickers.
//
// A single modal bottom sheet with three tabs. Tapping the emoji button
// in the chat composer opens this picker. Returns the selected item via
// a discriminated union type.

import 'package:flutter/material.dart';

import '../../../core/design_system/gochano_colors.dart';
import '../../../core/design_system/gochano_spacing.dart';
import '../../../core/design_system/gochano_typography.dart';
import '../../../core/localization/gochano_language.dart';
import '../../focus_rewards/data/reward_service.dart';
import '../../focus_rewards/domain/level_helper.dart';
import '../../focus_rewards/domain/reward_model.dart';
import '../domain/animated_reaction_catalog.dart';
import '../domain/sticker_catalog.dart';

// ---------------------------------------------------------------------------
// Result types
// ---------------------------------------------------------------------------

/// Discriminated union for picker results.
sealed class MediaPickResult {
  const MediaPickResult();
}

class EmojiPick extends MediaPickResult {
  const EmojiPick(this.emoji);
  final String emoji;
}

class ReactionPick extends MediaPickResult {
  const ReactionPick(this.reaction);
  final AnimatedReaction reaction;
}

class StickerPick extends MediaPickResult {
  const StickerPick(this.sticker);
  final StickerItem sticker;
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

/// Shows the unified media picker. Returns the user's selection or `null`.
Future<MediaPickResult?> showMediaPicker(BuildContext context) {
  return showModalBottomSheet<MediaPickResult>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: true,
    builder: (_) => const _MediaPickerBody(),
  );
}

// ---------------------------------------------------------------------------
// Body
// ---------------------------------------------------------------------------

class _MediaPickerBody extends StatefulWidget {
  const _MediaPickerBody();

  @override
  State<_MediaPickerBody> createState() => _MediaPickerBodyState();
}

class _MediaPickerBodyState extends State<_MediaPickerBody>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  RewardProfile _profile = RewardProfile.empty();

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _loadProfile();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await RewardService.readProfile();
      if (mounted) setState(() => _profile = profile);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final level = levelForXp(_profile.totalXp);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // --- Handle ---
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: GochanoSpacing.xs),
            decoration: BoxDecoration(
              color: colors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // --- Tabs ---
          TabBar(
            controller: _tabCtrl,
            labelPadding: const EdgeInsets.symmetric(horizontal: 4),
            tabs: [
              Tab(text: GochanoLanguage.text('Emoji', 'ইমোজি')),
              Tab(text: GochanoLanguage.text('Reactions', 'রিঅ্যাকশন')),
              Tab(text: GochanoLanguage.text('Stickers', 'স্টিকার')),
            ],
          ),

          // --- Tab content ---
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.45,
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _EmojiTab(onSelected: (e) => Navigator.of(context).pop(EmojiPick(e))),
                _ReactionTab(
                  currentLevel: level,
                  profile: _profile,
                  onSelected: (r) => Navigator.of(context).pop(ReactionPick(r)),
                ),
                _StickerTab(
                  currentLevel: level,
                  onSelected: (s) => Navigator.of(context).pop(StickerPick(s)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Emoji tab — lightweight standard emoji grid
// ---------------------------------------------------------------------------

/// Curated emoji categories for the Study context.
const Map<String, List<String>> _emojiCategories = {
  'Smileys': [
    '\u{1F60A}', '\u{1F604}', '\u{1F60E}', '\u{1F913}',
    '\u{1F60C}', '\u{1F622}', '\u{1F631}', '\u{1F914}',
    '\u{1F92F}', '\u{1F609}', '\u{1F60D}', '\u{1F970}',
  ],
  'Study': [
    '\u{1F4DA}', '\u{1F4D6}', '\u{270D}\u{FE0F}', '\u{1F4DD}',
    '\u{1F4AF}', '\u{1F4A4}', '\u{1F4BB}', '\u{1F9E0}',
    '\u{23F0}', '\u{1F514}', '\u{1F4A1}', '\u{2728}',
  ],
  'Celebration': [
    '\u{1F389}', '\u{1F38A}', '\u{1F388}', '\u{1F381}',
    '\u{1F973}', '\u{1F60E}', '\u{1F3C6}', '\u{1F44F}',
    '\u{1F382}', '\u{1F386}', '\u{2B50}', '\u{1F31F}',
  ],
  'Hearts': [
    '\u{2764}\u{FE0F}', '\u{1F49B}', '\u{1F49A}', '\u{1F499}',
    '\u{1F5A4}', '\u{1F90D}', '\u{1F90E}', '\u{1F49C}',
    '\u{1F9E1}', '\u{2764}\u{FE0F}\u{200D}\u{1F525}', '\u{1F494}', '\u{1F495}',
  ],
  'Hands': [
    '\u{1F44D}', '\u{1F44E}', '\u{1F44B}', '\u{1F64C}',
    '\u{1F525}', '\u{1F4AA}', '\u{270A}', '\u{1F91C}',
    '\u{1F91B}', '\u{1F44F}', '\u{1F64F}', '\u{1F91F}',
  ],
};

class _EmojiTab extends StatelessWidget {
  const _EmojiTab({required this.onSelected});
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ListView(
      padding: const EdgeInsets.all(GochanoSpacing.sm),
      children: [
        for (final entry in _emojiCategories.entries) ...[
          Text(entry.key, style: context.type.label.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: GochanoSpacing.xxs),
          Wrap(
            spacing: 2,
            runSpacing: 2,
            children: [
              for (final emoji in entry.value)
                GestureDetector(
                  onTap: () => onSelected(emoji),
                  child: Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(GochanoRadius.sm),
                    ),
                    child: Text(emoji, style: const TextStyle(fontSize: 24)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: GochanoSpacing.sm),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Reactions tab — level-gated animated reactions
// ---------------------------------------------------------------------------

class _ReactionTab extends StatelessWidget {
  const _ReactionTab({
    required this.currentLevel,
    required this.profile,
    required this.onSelected,
  });

  final int currentLevel;
  final RewardProfile profile;
  final ValueChanged<AnimatedReaction> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ListView(
      padding: const EdgeInsets.all(GochanoSpacing.sm),
      children: [
        // Level indicator
        Row(
          children: [
            Text(
              GochanoLanguage.text('Reactions', 'রিঅ্যাকশন'),
              style: context.type.label.copyWith(fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            Text(
              GochanoLanguage.text('Level $currentLevel', 'লেভেল $currentLevel'),
              style: context.type.caption.copyWith(
                color: colors.study,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: GochanoSpacing.sm),

        for (final pack in animatedReactionPackets) ...[
          _AnimatedPackSection(
            pack: pack,
            currentLevel: currentLevel,
            profile: profile,
            onSelected: onSelected,
          ),
          const SizedBox(height: GochanoSpacing.sm),
        ],
      ],
    );
  }
}

List<AnimatedReactionPack> get animatedReactionPackets => animatedReactionPacks;

class _AnimatedPackSection extends StatelessWidget {
  const _AnimatedPackSection({
    required this.pack,
    required this.currentLevel,
    required this.profile,
    required this.onSelected,
  });

  final AnimatedReactionPack pack;
  final int currentLevel;
  final RewardProfile profile;
  final ValueChanged<AnimatedReaction> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final unlocked = currentLevel >= pack.level;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              GochanoLanguage.text(
                'Level ${pack.level}',
                'লেভেল ${pack.level}',
              ),
              style: context.type.label.copyWith(
                color: unlocked ? colors.textPrimary : colors.textTertiary,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (!unlocked) ...[
              const SizedBox(width: GochanoSpacing.xxs),
              Icon(Icons.lock_rounded, size: 14, color: colors.textTertiary),
            ],
          ],
        ),
        const SizedBox(height: GochanoSpacing.xxs),
        Row(
          children: [
            for (final reaction in pack.reactions) ...[
              Expanded(
                child: _AnimatedReactionTile(
                  reaction: reaction,
                  unlocked: unlocked,
                  onTap: () {
                    if (unlocked) {
                      onSelected(reaction);
                    } else {
                      _showLocked(context, reaction);
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

  void _showLocked(BuildContext context, AnimatedReaction reaction) {
    final requiredXp = levelThresholds[reaction.requiredLevel - 2];
    final remaining = (requiredXp - profile.totalXp).clamp(0, 99999);
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(GochanoSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(reaction.fallbackEmoji, style: const TextStyle(fontSize: 40)),
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
                GochanoLanguage.text(
                  'Earn $remaining more XP by completing Focus sessions.',
                  'ফোকাস সেশন সম্পন্ন করে আরও $remaining XP অর্জন করুন।',
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

class _AnimatedReactionTile extends StatelessWidget {
  const _AnimatedReactionTile({
    required this.reaction,
    required this.unlocked,
    required this.onTap,
  });

  final AnimatedReaction reaction;
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
              'Send ${reaction.labelEn} reaction',
              '${reaction.labelBn} রিঅ্যাকশন পাঠান',
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
              Text(
                reaction.fallbackEmoji,
                style: TextStyle(
                  fontSize: 28,
                  color: unlocked ? null : Colors.grey,
                ),
              ),
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
                    child: Icon(Icons.lock_rounded, size: 10, color: colors.textTertiary),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stickers tab
// ---------------------------------------------------------------------------

class _StickerTab extends StatelessWidget {
  const _StickerTab({
    required this.currentLevel,
    required this.onSelected,
  });

  final int currentLevel;
  final ValueChanged<StickerItem> onSelected;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(GochanoSpacing.sm),
      children: [
        for (final pack in stickerPacks) ...[
          Text(
            GochanoLanguage.text(pack.labelEn, pack.labelBn),
            style: context.type.label.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: GochanoSpacing.xxs),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: GochanoSpacing.xs,
              crossAxisSpacing: GochanoSpacing.xs,
              childAspectRatio: 1,
            ),
            itemCount: pack.stickers.length,
            itemBuilder: (context, i) {
              final sticker = pack.stickers[i];
              final locked = sticker.requiredLevel > 0 &&
                  currentLevel < sticker.requiredLevel;
              return _StickerTile(
                sticker: sticker,
                locked: locked,
                onTap: () {
                  if (!locked) onSelected(sticker);
                },
              );
            },
          ),
          const SizedBox(height: GochanoSpacing.sm),
        ],
      ],
    );
  }
}

class _StickerTile extends StatelessWidget {
  const _StickerTile({
    required this.sticker,
    required this.locked,
    required this.onTap,
  });

  final StickerItem sticker;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      enabled: !locked,
      label: locked
          ? GochanoLanguage.text(
              'Locked sticker',
              'লকড স্টিকার',
            )
          : GochanoLanguage.text(
              'Send ${sticker.labelEn} sticker',
              '${sticker.labelBn} স্টিকার পাঠান',
            ),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: locked
                ? colors.surfaceVariant.withValues(alpha: 0.5)
                : colors.surface,
            borderRadius: BorderRadius.circular(GochanoRadius.md),
            border: Border.all(
              color: locked ? colors.surfaceVariant : colors.border,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    sticker.fallbackEmoji,
                    style: TextStyle(
                      fontSize: 36,
                      color: locked ? Colors.grey : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    GochanoLanguage.text(sticker.labelEn, sticker.labelBn),
                    style: context.type.caption.copyWith(
                      color: locked ? colors.textTertiary : colors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
              if (locked)
                Positioned(
                  right: 4,
                  top: 4,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: colors.border),
                    ),
                    child: Icon(Icons.lock_rounded, size: 10, color: colors.textTertiary),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
