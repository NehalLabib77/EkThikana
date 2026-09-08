// Centralized catalog of Gochano stickers.
//
// Stickers are larger visual messages sent as special text encodings.
// Each sticker has a stable ID, optional asset path (for when artwork
// arrives), and a fallback emoji for V1 rendering.
//
// V1 sticker packs are free (no level lock). The architecture supports
// future level-locked packs via [requiredLevel].

class StickerItem {
  const StickerItem({
    required this.id,
    required this.fallbackEmoji,
    required this.labelEn,
    required this.labelBn,
    required this.packId,
    this.assetPath,
    this.requiredLevel = 0,
  });

  final String id;
  final String? assetPath;
  final String fallbackEmoji;
  final String labelEn;
  final String labelBn;
  final String packId;

  /// Level required to use this sticker. 0 = free (always unlocked).
  final int requiredLevel;
}

class StickerPack {
  const StickerPack({
    required this.id,
    required this.labelEn,
    required this.labelBn,
    required this.stickers,
    this.requiredLevel = 0,
  });

  final String id;
  final String labelEn;
  final String labelBn;
  final List<StickerItem> stickers;
  final int requiredLevel;
}

/// All Gochano sticker packs.
const List<StickerPack> stickerPacks = [
  StickerPack(
    id: 'study',
    labelEn: 'Study',
    labelBn: 'পড়াশোনা',
    stickers: [
      StickerItem(
        id: 'sticker_study_keep_going',
        fallbackEmoji: '\u{1F4AA}',
        labelEn: 'Keep Going',
        labelBn: 'চালিয়ে যান',
        packId: 'study',
      ),
      StickerItem(
        id: 'sticker_focus_time',
        fallbackEmoji: '\u{23F0}',
        labelEn: 'Focus Time',
        labelBn: 'ফোকাস টাইম',
        packId: 'study',
      ),
      StickerItem(
        id: 'sticker_assignment_done',
        fallbackEmoji: '\u{2705}',
        labelEn: 'Assignment Done',
        labelBn: 'অ্যাসাইনমেন্ট শেষ',
        packId: 'study',
      ),
      StickerItem(
        id: 'sticker_lets_study',
        fallbackEmoji: '\u{1F4D6}',
        labelEn: "Let's Study",
        labelBn: 'চলো পড়ি',
        packId: 'study',
      ),
    ],
  ),
  StickerPack(
    id: 'celebration',
    labelEn: 'Celebration',
    labelBn: 'উদযাপন',
    stickers: [
      StickerItem(
        id: 'sticker_great_job',
        fallbackEmoji: '\u{1F389}',
        labelEn: 'Great Job',
        labelBn: 'দারুণ কাজ',
        packId: 'celebration',
      ),
      StickerItem(
        id: 'sticker_nice',
        fallbackEmoji: '\u{1F44F}',
        labelEn: 'Nice!',
        labelBn: 'ভালো!',
        packId: 'celebration',
      ),
      StickerItem(
        id: 'sticker_completed',
        fallbackEmoji: '\u{1F3C6}',
        labelEn: 'Completed',
        labelBn: 'সম্পন্ন',
        packId: 'celebration',
      ),
      StickerItem(
        id: 'sticker_proud_of_you',
        fallbackEmoji: '\u{1F60A}',
        labelEn: 'Proud of You',
        labelBn: 'গর্বিত',
        packId: 'celebration',
      ),
    ],
  ),
  StickerPack(
    id: 'reminder',
    labelEn: 'Reminder',
    labelBn: 'স্মারক',
    stickers: [
      StickerItem(
        id: 'sticker_study_now',
        fallbackEmoji: '\u{1F4D6}',
        labelEn: 'Study Now',
        labelBn: 'এখনই পড়ুন',
        packId: 'reminder',
      ),
      StickerItem(
        id: 'sticker_deadline_soon',
        fallbackEmoji: '\u{23F0}',
        labelEn: 'Deadline Soon',
        labelBn: 'শীঘ্রই সময়শেষ',
        packId: 'reminder',
      ),
      StickerItem(
        id: 'sticker_dont_forget',
        fallbackEmoji: '\u{1F4CC}',
        labelEn: "Don't Forget",
        labelBn: 'ভুবো না',
        packId: 'reminder',
      ),
    ],
  ),
];

/// Flat list of all stickers.
List<StickerItem> get allStickers =>
    stickerPacks.expand((p) => p.stickers).toList();

/// Lookup a sticker by its stable [id].
///
/// Returns `null` for unknown IDs — the caller should render a safe fallback.
StickerItem? lookupSticker(String id) {
  for (final pack in stickerPacks) {
    for (final s in pack.stickers) {
      if (s.id == id) return s;
    }
  }
  return null;
}
