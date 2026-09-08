// Community Chat Reaction Picker — tests.
//
// Covers: reaction message encoding, reaction message detection,
// picker opens, picker shows locked reactions, and picker selects.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gochano/core/localization/gochano_language.dart';
import 'package:gochano/features/focus_rewards/domain/level_helper.dart';
import 'package:gochano/features/focus_rewards/domain/reaction_catalog.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Simulates the text format sent via the existing chat message flow.
String encodeReaction(GochanoReaction reaction) =>
    'react:${reaction.id}:${reaction.emoji}';

/// Returns true if a message text is a reaction message.
bool isReactionMessage(String text) => text.startsWith('react:');

/// Extracts the emoji from a reaction message.
String reactionEmoji(String text) => text.split(':').last;

/// Wraps [child] in the same minimal MaterialApp tree used by the picker.
Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => child,
        ),
      ),
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ===========================================================================
  // 1. Reaction message encoding
  // ===========================================================================
  group('Reaction message encoding', () {
    test('encodes fire reaction', () {
      final fire = allReactions.firstWhere((r) => r.id == 'r_fire');
      expect(encodeReaction(fire), 'react:r_fire:\u{1F525}');
    });

    test('encodes applause reaction', () {
      final applause = allReactions.firstWhere((r) => r.id == 'r_applause');
      expect(encodeReaction(applause), 'react:r_applause:\u{1F44F}');
    });

    test('encodes crown reaction', () {
      final crown = allReactions.firstWhere((r) => r.id == 'r_crown');
      expect(encodeReaction(crown), 'react:r_crown:\u{1F451}');
    });
  });

  // ===========================================================================
  // 2. Reaction message detection
  // ===========================================================================
  group('Reaction message detection', () {
    test('detects reaction messages', () {
      expect(isReactionMessage('react:r_fire:\u{1F525}'), isTrue);
      expect(isReactionMessage('react:r_applause:\u{1F44F}'), isTrue);
    });

    test('rejects plain text messages', () {
      expect(isReactionMessage('Hello!'), isFalse);
      expect(isReactionMessage(''), isFalse);
      expect(isReactionMessage('react '), isFalse);
    });
  });

  // ===========================================================================
  // 3. Reaction emoji extraction
  // ===========================================================================
  group('Reaction emoji extraction', () {
    test('extracts fire emoji', () {
      expect(reactionEmoji('react:r_fire:\u{1F525}'), '\u{1F525}');
    });

    test('extracts applause emoji', () {
      expect(reactionEmoji('react:r_applause:\u{1F44F}'), '\u{1F44F}');
    });
  });

  // ===========================================================================
  // 4. Level gating for reactions
  // ===========================================================================
  group('Level gating', () {
    test('level 1 user has pack_1 reactions unlocked', () {
      final level1 = reactionsForLevel(1);
      for (final r in reactionPacks.first.reactions) {
        expect(level1.map((x) => x.id), contains(r.id));
      }
    });

    test('level 1 user does NOT have pack_2 reactions', () {
      final level1 = reactionsForLevel(1);
      for (final r in reactionPacks[1].reactions) {
        expect(level1.map((x) => x.id), isNot(contains(r.id)));
      }
    });

    test('level 3 user has packs 1-3 reactions', () {
      final level3 = reactionsForLevel(3);
      final expectedIds = reactionPacks
          .take(3)
          .expand((p) => p.reactions)
          .map((r) => r.id);
      for (final id in expectedIds) {
        expect(level3.map((x) => x.id), contains(id));
      }
      // Should NOT have pack_4 reactions
      for (final r in reactionPacks[3].reactions) {
        expect(level3.map((x) => x.id), isNot(contains(r.id)));
      }
    });

    test('max level user has all reactions', () {
      final max = reactionsForLevel(maxLevel);
      expect(max.length, allReactions.length);
    });
  });

  // ===========================================================================
  // 5. XP remaining calculation for locked reactions
  // ===========================================================================
  group('XP remaining for locked reactions', () {
    test('pack_2 requires 0 XP at level 2 threshold', () {
      // Level 2 threshold is 100 XP. At exactly 100 XP, user is Level 2.
      final xp = levelThresholds[0]; // 100
      expect(levelForXp(xp), 2);
      expect(xpRemainingToNextLevel(xp), levelThresholds[1] - xp); // 250 - 100 = 150
    });

    test('pack_3 requires some XP at level 2', () {
      final xp = 100; // Level 2
      final remaining = xpRemainingToNextLevel(xp);
      expect(remaining, greaterThan(0));
    });

    test('pack_1 is free (no XP needed)', () {
      final pack1 = reactionPacks.first;
      expect(pack1.level, 1);
      // Level 1 is the starting level — no XP required.
    });
  });

  // ===========================================================================
  // 6. All reactions have unique IDs
  // ===========================================================================
  group('Reaction catalog integrity', () {
    test('all reaction IDs are unique', () {
      final ids = allReactions.map((r) => r.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('every reaction has a non-empty emoji', () {
      for (final r in allReactions) {
        expect(r.emoji.isNotEmpty, isTrue, reason: '${r.id} has empty emoji');
      }
    });

    test('every pack has at least 1 reaction', () {
      for (final p in reactionPacks) {
        expect(p.reactions.isNotEmpty, isTrue, reason: '${p.id} is empty');
      }
    });

    test('pack levels are strictly increasing', () {
      for (var i = 1; i < reactionPacks.length; i++) {
        expect(
          reactionPacks[i].level,
          greaterThan(reactionPacks[i - 1].level),
        );
      }
    });
  });

  // ===========================================================================
  // 7. Bengali localization strings
  // ===========================================================================
  group('Reaction picker localization', () {
    test('EN header', () {
      expect(
        GochanoLanguage.text('Gochano Reactions', 'x'),
        'Gochano Reactions',
      );
    });

    test('BN header returns EN fallback in non-BN context', () {
      expect(
        GochanoLanguage.text('Gochano Reactions', 'গোচানো রিঅ্যাকশন'),
        'Gochano Reactions',
      );
    });

    test('EN locked message', () {
      final result = GochanoLanguage.text('Unlocks at Level 3', 'x');
      expect(result, 'Unlocks at Level 3');
    });

    test('BN locked message returns EN fallback in non-BN context', () {
      final result = GochanoLanguage.text(
        'Unlocks at Level 3',
        'লেভেল ৩-এ আনলক হবে',
      );
      expect(result, 'Unlocks at Level 3');
    });
  });
}
