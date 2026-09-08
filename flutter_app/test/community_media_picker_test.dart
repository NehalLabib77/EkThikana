// Community media picker — catalog + encoding + level unlock tests.

import 'package:flutter_test/flutter_test.dart';

import 'package:gochano/features/community/domain/animated_reaction_catalog.dart';
import 'package:gochano/features/community/domain/sticker_catalog.dart';
import 'package:gochano/features/focus_rewards/domain/level_helper.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String encodeGreact(AnimatedReaction r) => 'greact:${r.id}';
String encodeSticker(StickerItem s) => 'sticker:${s.id}';
bool isGreact(String text) => text.startsWith('greact:');
bool isSticker(String text) => text.startsWith('sticker:');
String greactId(String text) => text.substring(7);
String stickerId(String text) => text.substring(8);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ===========================================================================
  // 1. Animated reaction catalog integrity
  // ===========================================================================
  group('AnimatedReactionCatalog', () {
    test('all reaction IDs are unique', () {
      final ids = allAnimatedReactions.map((r) => r.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('every reaction has a non-empty fallbackEmoji', () {
      for (final r in allAnimatedReactions) {
        expect(r.fallbackEmoji.isNotEmpty, isTrue, reason: '${r.id} empty emoji');
      }
    });

    test('every reaction has non-empty EN and BN labels', () {
      for (final r in allAnimatedReactions) {
        expect(r.labelEn.isNotEmpty, isTrue, reason: '${r.id} empty EN');
        expect(r.labelBn.isNotEmpty, isTrue, reason: '${r.id} empty BN');
      }
    });

    test('every pack has at least 1 reaction', () {
      for (final p in animatedReactionPacks) {
        expect(p.reactions.isNotEmpty, isTrue, reason: '${p.id} empty');
      }
    });

    test('pack levels are strictly increasing', () {
      for (var i = 1; i < animatedReactionPacks.length; i++) {
        expect(
          animatedReactionPacks[i].level,
          greaterThan(animatedReactionPacks[i - 1].level),
        );
      }
    });

    test('lookupAnimatedReaction finds existing reaction', () {
      final r = lookupAnimatedReaction('g_focus_fire');
      expect(r, isNotNull);
      expect(r!.id, 'g_focus_fire');
      expect(r.fallbackEmoji, '\u{1F525}');
    });

    test('lookupAnimatedReaction returns null for unknown ID', () {
      expect(lookupAnimatedReaction('nonexistent'), isNull);
      expect(lookupAnimatedReaction('greact:focus_fire'), isNull);
    });

    test('all reactions start with g_ prefix', () {
      for (final r in allAnimatedReactions) {
        expect(r.id.startsWith('g_'), isTrue, reason: '${r.id} missing g_ prefix');
      }
    });

    test('requiredLevel is between 1 and 5', () {
      for (final r in allAnimatedReactions) {
        expect(r.requiredLevel, greaterThanOrEqualTo(1));
        expect(r.requiredLevel, lessThanOrEqualTo(5));
      }
    });
  });

  // ===========================================================================
  // 2. Sticker catalog integrity
  // ===========================================================================
  group('StickerCatalog', () {
    test('all sticker IDs are unique', () {
      final ids = allStickers.map((s) => s.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('every sticker has a non-empty fallbackEmoji', () {
      for (final s in allStickers) {
        expect(s.fallbackEmoji.isNotEmpty, isTrue, reason: '${s.id} empty emoji');
      }
    });

    test('every sticker has non-empty EN and BN labels', () {
      for (final s in allStickers) {
        expect(s.labelEn.isNotEmpty, isTrue, reason: '${s.id} empty EN');
        expect(s.labelBn.isNotEmpty, isTrue, reason: '${s.id} empty BN');
      }
    });

    test('every pack has at least 1 sticker', () {
      for (final p in stickerPacks) {
        expect(p.stickers.isNotEmpty, isTrue, reason: '${p.id} empty');
      }
    });

    test('lookupSticker finds existing sticker', () {
      final s = lookupSticker('sticker_great_job');
      expect(s, isNotNull);
      expect(s!.id, 'sticker_great_job');
    });

    test('lookupSticker returns null for unknown ID', () {
      expect(lookupSticker('nonexistent'), isNull);
      expect(lookupSticker('sticker:fake'), isNull);
    });

    test('all sticker IDs start with sticker_', () {
      for (final s in allStickers) {
        expect(s.id.startsWith('sticker_'), isTrue, reason: '${s.id} missing prefix');
      }
    });

    test('V1 stickers are free (requiredLevel = 0)', () {
      for (final s in allStickers) {
        expect(s.requiredLevel, 0, reason: '${s.id} should be free in V1');
      }
    });

    test('3 packs exist: study, celebration, reminder', () {
      expect(stickerPacks.length, 3);
      expect(stickerPacks.map((p) => p.id), containsAll(['study', 'celebration', 'reminder']));
    });
  });

  // ===========================================================================
  // 3. Message encoding
  // ===========================================================================
  group('Message encoding', () {
    test('greact encoding', () {
      final r = lookupAnimatedReaction('g_focus_fire')!;
      expect(encodeGreact(r), 'greact:g_focus_fire');
    });

    test('sticker encoding', () {
      final s = lookupSticker('sticker_great_job')!;
      expect(encodeSticker(s), 'sticker:sticker_great_job');
    });

    test('greact detection', () {
      expect(isGreact('greact:g_focus_fire'), isTrue);
      expect(isGreact('sticker:sticker_great_job'), isFalse);
      expect(isGreact('Hello!'), isFalse);
    });

    test('sticker detection', () {
      expect(isSticker('sticker:sticker_great_job'), isTrue);
      expect(isSticker('greact:g_focus_fire'), isFalse);
      expect(isSticker('Hello!'), isFalse);
    });

    test('greact ID extraction', () {
      expect(greactId('greact:g_focus_fire'), 'g_focus_fire');
    });

    test('sticker ID extraction', () {
      expect(stickerId('sticker:sticker_great_job'), 'sticker_great_job');
    });
  });

  // ===========================================================================
  // 4. Level-based unlock
  // ===========================================================================
  group('Level unlock', () {
    test('level 1 user has pack 1 reactions unlocked', () {
      final pack1 = animatedReactionPacks.first;
      expect(1 >= pack1.level, isTrue);
    });

    test('level 1 user does NOT have pack 2 reactions', () {
      final pack2 = animatedReactionPacks[1];
      expect(1 >= pack2.level, isFalse);
    });

    test('level 3 user has packs 1-3 reactions', () {
      for (var i = 0; i < 3; i++) {
        expect(3 >= animatedReactionPacks[i].level, isTrue);
      }
      expect(3 >= animatedReactionPacks[3].level, isFalse);
    });

    test('max level user has all reactions', () {
      for (final pack in animatedReactionPacks) {
        expect(maxLevel >= pack.level, isTrue);
      }
    });
  });

  // ===========================================================================
  // 5. XP remaining calculation (specific reaction threshold)
  // ===========================================================================
  group('XP remaining for specific reaction', () {
    test('level 2 reaction needs XP from level 2 threshold', () {
      // User at 50 XP (Level 1). Reaction requires Level 2.
      // Level 2 threshold is 100. Remaining = 100 - 50 = 50.
      final requiredXp = levelThresholds[1 - 1]; // 100
      final remaining = (requiredXp - 50).clamp(0, 99999);
      expect(remaining, 50);
    });

    test('level 3 reaction needs XP from level 3 threshold', () {
      // User at 100 XP (Level 2). Reaction requires Level 3.
      // Level 3 threshold is 250. Remaining = 250 - 100 = 150.
      final requiredXp = levelThresholds[2 - 1]; // 250
      final remaining = (requiredXp - 100).clamp(0, 99999);
      expect(remaining, 150);
    });

    test('user at exact threshold has 0 remaining', () {
      final requiredXp = levelThresholds[2 - 1]; // 250
      final remaining = (requiredXp - 250).clamp(0, 99999);
      expect(remaining, 0);
    });

    test('user above threshold has 0 remaining (clamped)', () {
      final requiredXp = levelThresholds[1 - 1]; // 100
      final remaining = (requiredXp - 200).clamp(0, 99999);
      expect(remaining, 0);
    });
  });

  // ===========================================================================
  // 6. Unknown ID safe fallback
  // ===========================================================================
  group('Safe fallback', () {
    test('unknown greact ID returns null', () {
      expect(lookupAnimatedReaction('g_nonexistent'), isNull);
    });

    test('unknown sticker ID returns null', () {
      expect(lookupSticker('sticker_nonexistent'), isNull);
    });

    test('greact prefix in sticker lookup does not match', () {
      expect(lookupSticker('greact:g_focus_fire'), isNull);
    });

    test('sticker prefix in greact lookup does not match', () {
      expect(lookupAnimatedReaction('sticker:sticker_great_job'), isNull);
    });
  });

  // ===========================================================================
  // 7. No arbitrary asset paths accepted
  // ===========================================================================
  group('Security — no arbitrary paths', () {
    test('all animated reaction IDs are registered', () {
      final testIds = ['g_focus_fire', 'g_champion', 'g_study_brain', 'g_crown'];
      for (final id in testIds) {
        expect(lookupAnimatedReaction(id), isNotNull, reason: '$id must be registered');
      }
    });

    test('all sticker IDs are registered', () {
      final testIds = [
        'sticker_great_job',
        'sticker_study_keep_going',
        'sticker_deadline_soon',
      ];
      for (final id in testIds) {
        expect(lookupSticker(id), isNotNull, reason: '$id must be registered');
      }
    });

    test('fake path-based IDs are rejected', () {
      expect(lookupAnimatedReaction('assets/reactions/fake.webp'), isNull);
      expect(lookupSticker('assets/stickers/fake.png'), isNull);
    });
  });

  // ===========================================================================
  // 8. EN/BN labels
  // ===========================================================================
  group('EN/BN labels', () {
    test('animated reaction has EN and BN', () {
      final r = lookupAnimatedReaction('g_focus_fire')!;
      expect(r.labelEn, 'Focus Fire');
      expect(r.labelBn, 'ফোকাস ফায়ার');
    });

    test('sticker has EN and BN', () {
      final s = lookupSticker('sticker_great_job')!;
      expect(s.labelEn, 'Great Job');
      expect(s.labelBn, 'দারুণ কাজ');
    });

    test('sticker pack has EN and BN', () {
      final pack = stickerPacks.firstWhere((p) => p.id == 'study');
      expect(pack.labelEn, 'Study');
      expect(pack.labelBn, 'পড়াশোনা');
    });
  });
}
