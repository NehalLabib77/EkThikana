// Centralized catalog of Gochano-exclusive animated reactions.
//
// Each reaction has a stable ID for message encoding, a fallback emoji for
// rendering when animated assets are not yet available, and a requiredLevel
// for gating. When animated asset artwork is provided, set [assetPath] and
// the renderer will prefer it over [fallbackEmoji].

class AnimatedReaction {
  const AnimatedReaction({
    required this.id,
    required this.fallbackEmoji,
    required this.labelEn,
    required this.labelBn,
    required this.requiredLevel,
    required this.packId,
    this.assetPath,
  });

  final String id;
  final String? assetPath;
  final String fallbackEmoji;
  final String labelEn;
  final String labelBn;
  final int requiredLevel;
  final String packId;
}

class AnimatedReactionPack {
  const AnimatedReactionPack({
    required this.id,
    required this.level,
    required this.reactions,
  });

  final String id;
  final int level;
  final List<AnimatedReaction> reactions;
}

/// All Gochano-exclusive animated reaction packs.
///
/// Asset artwork is not yet available — [AnimatedReaction.assetPath] is `null`
/// and the renderer falls back to [AnimatedReaction.fallbackEmoji].
/// When animated .webp/.gif assets are added to `assets/reactions/`,
/// set the corresponding [assetPath] values.
const List<AnimatedReactionPack> animatedReactionPacks = [
  AnimatedReactionPack(
    id: 'apack_1',
    level: 1,
    reactions: [
      AnimatedReaction(
        id: 'g_applause',
        fallbackEmoji: '\u{1F44F}',
        labelEn: 'Applause',
        labelBn: 'করতালি',
        requiredLevel: 1,
        packId: 'apack_1',
      ),
      AnimatedReaction(
        id: 'g_thumbsup',
        fallbackEmoji: '\u{1F44D}',
        labelEn: 'Thumbs Up',
        labelBn: 'ভালো',
        requiredLevel: 1,
        packId: 'apack_1',
      ),
      AnimatedReaction(
        id: 'g_smile',
        fallbackEmoji: '\u{1F642}',
        labelEn: 'Smile',
        labelBn: 'হাসি',
        requiredLevel: 1,
        packId: 'apack_1',
      ),
    ],
  ),
  AnimatedReactionPack(
    id: 'apack_2',
    level: 2,
    reactions: [
      AnimatedReaction(
        id: 'g_focus_fire',
        fallbackEmoji: '\u{1F525}',
        labelEn: 'Focus Fire',
        labelBn: 'ফোকাস ফায়ার',
        requiredLevel: 2,
        packId: 'apack_2',
      ),
      AnimatedReaction(
        id: 'g_strong',
        fallbackEmoji: '\u{1F4AA}',
        labelEn: 'Strong',
        labelBn: 'শক্তিশালী',
        requiredLevel: 2,
        packId: 'apack_2',
      ),
      AnimatedReaction(
        id: 'g_sparkles',
        fallbackEmoji: '\u{2728}',
        labelEn: 'Sparkles',
        labelBn: 'স্পার্কল',
        requiredLevel: 2,
        packId: 'apack_2',
      ),
    ],
  ),
  AnimatedReactionPack(
    id: 'apack_3',
    level: 3,
    reactions: [
      AnimatedReaction(
        id: 'g_study_brain',
        fallbackEmoji: '\u{1F9E0}',
        labelEn: 'Study Brain',
        labelBn: 'পড়াশোনার মস্তিষ্ক',
        requiredLevel: 3,
        packId: 'apack_3',
      ),
      AnimatedReaction(
        id: 'g_goal_hit',
        fallbackEmoji: '\u{1F3AF}',
        labelEn: 'Goal Hit',
        labelBn: 'লক্ষ্য হিট',
        requiredLevel: 3,
        packId: 'apack_3',
      ),
      AnimatedReaction(
        id: 'g_books',
        fallbackEmoji: '\u{1F4DA}',
        labelEn: 'Books',
        labelBn: 'বই',
        requiredLevel: 3,
        packId: 'apack_3',
      ),
    ],
  ),
  AnimatedReactionPack(
    id: 'apack_4',
    level: 4,
    reactions: [
      AnimatedReaction(
        id: 'g_rocket',
        fallbackEmoji: '\u{1F680}',
        labelEn: 'Rocket',
        labelBn: 'রকেট',
        requiredLevel: 4,
        packId: 'apack_4',
      ),
      AnimatedReaction(
        id: 'g_champion',
        fallbackEmoji: '\u{1F3C6}',
        labelEn: 'Champion',
        labelBn: 'চ্যাম্পিয়ন',
        requiredLevel: 4,
        packId: 'apack_4',
      ),
      AnimatedReaction(
        id: 'g_lightning',
        fallbackEmoji: '\u{26A1}',
        labelEn: 'Lightning',
        labelBn: 'বিদ্যুৎ',
        requiredLevel: 4,
        packId: 'apack_4',
      ),
    ],
  ),
  AnimatedReactionPack(
    id: 'apack_5',
    level: 5,
    reactions: [
      AnimatedReaction(
        id: 'g_crown',
        fallbackEmoji: '\u{1F451}',
        labelEn: 'Crown',
        labelBn: 'মুকুট',
        requiredLevel: 5,
        packId: 'apack_5',
      ),
      AnimatedReaction(
        id: 'g_star',
        fallbackEmoji: '\u{1F31F}',
        labelEn: 'Star',
        labelBn: 'তারা',
        requiredLevel: 5,
        packId: 'apack_5',
      ),
      AnimatedReaction(
        id: 'g_gem',
        fallbackEmoji: '\u{1F48E}',
        labelEn: 'Gem',
        labelBn: 'গেম',
        requiredLevel: 5,
        packId: 'apack_5',
      ),
    ],
  ),
];

/// Flat list of all animated reactions.
List<AnimatedReaction> get allAnimatedReactions =>
    animatedReactionPacks.expand((p) => p.reactions).toList();

/// Lookup an animated reaction by its stable [id].
///
/// Returns `null` for unknown IDs — the caller should render a safe fallback.
AnimatedReaction? lookupAnimatedReaction(String id) {
  for (final pack in animatedReactionPacks) {
    for (final r in pack.reactions) {
      if (r.id == id) return r;
    }
  }
  return null;
}
