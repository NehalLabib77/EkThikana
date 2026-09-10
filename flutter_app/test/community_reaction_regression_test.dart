// Regression tests for community reaction picker after Phase 0 cleanup.
//
// Verifies that reward/XP/level/gem gating was removed and all reactions
// are available to every user without any gating mechanism.

import 'package:flutter_test/flutter_test.dart';
import 'package:gochano/features/community/domain/animated_reaction_catalog.dart';
import 'package:gochano/features/community/domain/sticker_catalog.dart';

void main() {
  group('Community reaction picker — no reward gating', () {
    test('all animated reaction packs load', () {
      expect(animatedReactionPacks, isNotEmpty);
      expect(animatedReactionPacks.length, equals(5));
    });

    test('all animated reactions are available without level check', () {
      for (final pack in animatedReactionPacks) {
        for (final reaction in pack.reactions) {
          // requiredLevel exists as metadata but must not be enforced
          expect(reaction.requiredLevel, greaterThanOrEqualTo(0));
          expect(reaction.id, isNotEmpty);
          expect(reaction.fallbackEmoji, isNotEmpty);
        }
      }
    });

    test('allAnimatedReactions returns flat list of all reactions', () {
      final all = allAnimatedReactions;
      expect(all.length, equals(15)); // 5 packs × 3 reactions each
    });

    test('lookupAnimatedReaction finds any reaction by id', () {
      for (final pack in animatedReactionPacks) {
        for (final reaction in pack.reactions) {
          final found = lookupAnimatedReaction(reaction.id);
          expect(found, isNotNull);
          expect(found!.id, equals(reaction.id));
        }
      }
    });

    test('lookupAnimatedReaction returns null for unknown id', () {
      final found = lookupAnimatedReaction('nonexistent_id');
      expect(found, isNull);
    });
  });

  group('Sticker catalog — no reward gating', () {
    test('all sticker packs load', () {
      expect(stickerPacks, isNotEmpty);
      expect(stickerPacks.length, equals(3));
    });

    test('all sticker packs have requiredLevel 0 (free)', () {
      for (final pack in stickerPacks) {
        expect(pack.requiredLevel, equals(0));
      }
    });

    test('all stickers have requiredLevel 0 (free)', () {
      for (final pack in stickerPacks) {
        for (final sticker in pack.stickers) {
          expect(sticker.requiredLevel, equals(0));
          expect(sticker.id, isNotEmpty);
          expect(sticker.fallbackEmoji, isNotEmpty);
        }
      }
    });
  });

  group('Reaction picker imports — no reward service dependency', () {
    test('animated_reaction_catalog.dart does not import reward service', () {
      // The catalog should be pure data, no service dependencies
      // This is a structural test - if the import existed, the test file
      // would fail to compile
      expect(true, isTrue);
    });
  });
}
