// Static guards for the Home "Quick actions" redesign (spec §27, §86).
//
// The Home quick-actions grid must:
//
//   * show the five documented actions (Ask AI, Add expense, Add task,
//     Scan prescription, Find a route) so the dashboard keeps the same
//     surface it always advertised;
//   * default to a *compact* four-up layout, not the previous three-up
//     104px-tall one — the redesign brief was "compact rounded card",
//     4-column grid;
//   * hide any overflow behind a See more toggle rather than dropping
//     the fifth action from the surface entirely (spec §86 — no
//     duplicate CTAs, no silently deleted affordances);
//   * localize "See more" / "See less" in English and Bangla, because
//     every other label in `_QuickActions` is bilingual.
//
// Everything below is a string-level guard so it runs without an emulator.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  final homeScreen =
      _read('lib/features/home/presentation/home_screen.dart');

  group('Quick Actions redesign', () {
    test('keeps the five documented actions wired', () {
      // Each of the five documented actions must still be present — the
      // redesign only changed the grid, not the surface.
      const expected = [
        'AiAssistantScreen',
        'showAddExpenseSheet',
        'showAddTaskSheet',
        'PrescriptionScanScreen',
        'CommuteScreen',
      ];
      for (final symbol in expected) {
        expect(
          homeScreen.contains(symbol),
          isTrue,
          reason: 'Quick Actions no longer wires $symbol',
        );
      }
    });

    test('uses a 4-column grid at normal phone width', () {
      // The redesign asked for "4-column grid". The grid is wrapped in a
      // LayoutBuilder that must branch on width — confirm we did not just
      // keep the legacy 2-vs-3 split.
      expect(
        RegExp(r'columns\s*=\s*constraints\.maxWidth\s*>=\s*380\s*\?\s*4\s*:')
            .hasMatch(homeScreen),
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
      expect(match, isNotNull,
          reason: 'Quick Actions grid must declare a finite mainAxisExtent');
      final value = int.parse(match!.group(1)!);
      expect(value, greaterThan(0));
      expect(value, lessThan(104),
          reason: 'Tile height must be smaller than the old 104px layout');
    });

    test('shows a See more / See less toggle for overflow', () {
      expect(
        homeScreen.contains("GochanoLanguage.text('See more', 'আরো দেখুন')"),
        isTrue,
        reason: 'Quick Actions must localize the See more label',
      );
      expect(
        homeScreen.contains("GochanoLanguage.text('See less', 'কম দেখুন')"),
        isTrue,
        reason: 'Quick Actions must localize the See less label',
      );
      expect(
        homeScreen.contains('_expanded = !_expanded'),
        isTrue,
        reason: 'Quick Actions must toggle _expanded on tap',
      );
    });

    test('never silently drops the fifth action', () {
      // The fifth action (Find a route) must remain in the actions list so
      // it can still be revealed by the toggle.
      expect(
        homeScreen.contains("GochanoArt.featureCommute"),
        isTrue,
        reason: 'Find-a-route tile must still be in the action list',
      );
      expect(
        homeScreen.contains('GochanoLanguage.text(\'Find a route\''),
        isTrue,
        reason: 'Find-a-route label must still be in the action list',
      );
    });
  });
}
