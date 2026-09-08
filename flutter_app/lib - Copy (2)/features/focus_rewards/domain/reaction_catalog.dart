// Centralized catalog of Gochano-exclusive reactions.
//
// Normal phone keyboard emoji remain unrestricted. This catalog only
// applies to Gochano reaction packs that appear in a dedicated picker.
// Each reaction has a requiredLevel — users below that level see a
// dimmed/locked state.

class GochanoReaction {
  const GochanoReaction({
    required this.id,
    required this.emoji,
    required this.label,
    required this.requiredLevel,
    required this.packId,
  });

  final String id;
  final String emoji;
  final String label;
  final int requiredLevel;
  final String packId;
}

class ReactionPack {
  const ReactionPack({
    required this.id,
    required this.level,
    required this.reactions,
  });

  final String id;
  final int level;
  final List<GochanoReaction> reactions;
}

/// All Gochano-exclusive reaction packs.
const List<ReactionPack> reactionPacks = [
  ReactionPack(
    id: 'pack_1',
    level: 1,
    reactions: [
      GochanoReaction(
        id: 'r_applause',
        emoji: '\u{1F44F}',
        label: 'Applause',
        requiredLevel: 1,
        packId: 'pack_1',
      ),
      GochanoReaction(
        id: 'r_thumbsup',
        emoji: '\u{1F44D}',
        label: 'Thumbs Up',
        requiredLevel: 1,
        packId: 'pack_1',
      ),
      GochanoReaction(
        id: 'r_smile',
        emoji: '\u{1F642}',
        label: 'Smile',
        requiredLevel: 1,
        packId: 'pack_1',
      ),
    ],
  ),
  ReactionPack(
    id: 'pack_2',
    level: 2,
    reactions: [
      GochanoReaction(
        id: 'r_fire',
        emoji: '\u{1F525}',
        label: 'Fire',
        requiredLevel: 2,
        packId: 'pack_2',
      ),
      GochanoReaction(
        id: 'r_muscle',
        emoji: '\u{1F4AA}',
        label: 'Strong',
        requiredLevel: 2,
        packId: 'pack_2',
      ),
      GochanoReaction(
        id: 'r_sparkles',
        emoji: '\u{2728}',
        label: 'Sparkles',
        requiredLevel: 2,
        packId: 'pack_2',
      ),
    ],
  ),
  ReactionPack(
    id: 'pack_3',
    level: 3,
    reactions: [
      GochanoReaction(
        id: 'r_target',
        emoji: '\u{1F3AF}',
        label: 'Target',
        requiredLevel: 3,
        packId: 'pack_3',
      ),
      GochanoReaction(
        id: 'r_brain',
        emoji: '\u{1F9E0}',
        label: 'Brain',
        requiredLevel: 3,
        packId: 'pack_3',
      ),
      GochanoReaction(
        id: 'r_books',
        emoji: '\u{1F4DA}',
        label: 'Books',
        requiredLevel: 3,
        packId: 'pack_3',
      ),
    ],
  ),
  ReactionPack(
    id: 'pack_4',
    level: 4,
    reactions: [
      GochanoReaction(
        id: 'r_rocket',
        emoji: '\u{1F680}',
        label: 'Rocket',
        requiredLevel: 4,
        packId: 'pack_4',
      ),
      GochanoReaction(
        id: 'r_lightning',
        emoji: '\u{26A1}',
        label: 'Lightning',
        requiredLevel: 4,
        packId: 'pack_4',
      ),
      GochanoReaction(
        id: 'r_trophy',
        emoji: '\u{1F3C6}',
        label: 'Trophy',
        requiredLevel: 4,
        packId: 'pack_4',
      ),
    ],
  ),
  ReactionPack(
    id: 'pack_5',
    level: 5,
    reactions: [
      GochanoReaction(
        id: 'r_gem',
        emoji: '\u{1F48E}',
        label: 'Gem',
        requiredLevel: 5,
        packId: 'pack_5',
      ),
      GochanoReaction(
        id: 'r_crown',
        emoji: '\u{1F451}',
        label: 'Crown',
        requiredLevel: 5,
        packId: 'pack_5',
      ),
      GochanoReaction(
        id: 'r_star',
        emoji: '\u{1F31F}',
        label: 'Star',
        requiredLevel: 5,
        packId: 'pack_5',
      ),
    ],
  ),
];

/// All individual reactions flattened from all packs.
List<GochanoReaction> get allReactions =>
    reactionPacks.expand((p) => p.reactions).toList();

/// Reactions available at a given [level].
List<GochanoReaction> reactionsForLevel(int level) =>
    allReactions.where((r) => r.requiredLevel <= level).toList();

/// Reactions unlocked by reaching [newLevel] that were not available at
/// [oldLevel]. Returns an empty list if no new reactions were unlocked.
List<GochanoReaction> newlyUnlockedReactions(int oldLevel, int newLevel) {
  if (newLevel <= oldLevel) return const [];
  return allReactions
      .where((r) => r.requiredLevel > oldLevel && r.requiredLevel <= newLevel)
      .toList();
}
