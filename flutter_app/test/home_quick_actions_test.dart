// Static guards for the Home "Quick actions" redesign (spec §27, §86).
//
// The Home quick-actions grid must:
//
//   * show the four Step 2 actions (Ask AI, Add expense, Medicine,
//     CommuteBD);
//   * default to a *compact* four-up layout, not the previous three-up
//     104px-tall one — the redesign brief was "compact rounded card",
//     4-column grid;
//   * fit all four actions without an expand/collapse affordance;
//
// Everything below is a string-level guard so it runs without an emulator.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  final homeScreen = _read('lib/features/home/presentation/home_screen.dart');

  group('Quick Actions redesign', () {
    test('keeps exactly the four Step 2 actions wired', () {
      const expected = [
        'AiAssistantScreen',
        'showAddExpenseSheet',
        "GochanoLanguage.text('Medicine'",
        'CommuteScreen',
      ];
      for (final symbol in expected) {
        expect(
          homeScreen.contains(symbol),
          isTrue,
          reason: 'Quick Actions no longer wires $symbol',
        );
      }
      expect(homeScreen, isNot(contains('Add task')));
      expect(homeScreen, isNot(contains('Scan prescription')));
    });

    test('uses a 4-column grid at normal phone width', () {
      // The redesign asked for "4-column grid". The grid now uses
      // MediaQuery to determine column count — confirm we did not just
      // keep the legacy 2-vs-3 split.
      expect(
        RegExp(
          r'(screenWidth|constraints\.maxWidth)\s*>=\s*380\s*\?\s*4\s*:',
        ).hasMatch(homeScreen),
        isTrue,
        reason:
            'Quick Actions grid must pick 4 columns on a normal phone width',
      );
    });

    test('tile height dropped from 104 to a compact value', () {
      // The previous layout was 104px; the redesign asked for a compact
      // tile. Any value strictly below 104 counts as compact, but it must
      // be a finite, non-zero number — a zero mainAxisExtent would collapse
      // the tiles to nothing.
      final match = RegExp(r'mainAxisExtent:\s*(\d+)').firstMatch(homeScreen);
      expect(
        match,
        isNotNull,
        reason: 'Quick Actions grid must declare a finite mainAxisExtent',
      );
      final value = int.parse(match!.group(1)!);
      expect(value, greaterThan(0));
      expect(
        value,
        lessThan(104),
        reason: 'Tile height must be smaller than the old 104px layout',
      );
    });

    test('does not expose an expand/collapse affordance', () {
      expect(homeScreen, isNot(contains('_expanded')));
      expect(homeScreen, isNot(contains("'See more'")));
      expect(homeScreen, isNot(contains("'See less'")));
    });
  });
}
