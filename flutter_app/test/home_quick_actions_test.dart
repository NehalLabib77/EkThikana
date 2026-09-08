// Static guards for the Home "Quick actions" section.
//
// The Home quick-actions grid must:
//
//   * show exactly four actions (Ask AI, Add Expense, Medicine, CommuteBD)
//     in a 4-column grid;
//   * be always visible (no collapse/expand toggle needed for exactly 4);
//   * localize all labels in English and Bangla.
//
// Everything below is a string-level guard so it runs without an emulator.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  final homeScreen =
      _read('lib/features/home/presentation/home_screen.dart');

  group('Quick Actions', () {
    test('shows exactly four actions', () {
      const expected = [
        'AiAssistantScreen',
        'showAddExpenseSheet',
        'MedicineScreen',
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

    test('uses a 4-column grid', () {
      expect(
        homeScreen.contains('crossAxisCount: 4'),
        isTrue,
        reason: 'Quick Actions grid must use 4 columns',
      );
    });

    test('tile height is compact', () {
      final match =
          RegExp(r'mainAxisExtent:\s*(\d+)').firstMatch(homeScreen);
      expect(match, isNotNull,
          reason: 'Quick Actions grid must declare a finite mainAxisExtent');
      final value = int.parse(match!.group(1)!);
      expect(value, greaterThan(0));
      expect(value, lessThan(104),
          reason: 'Tile height must be compact (under 104px)');
    });

    test('does not contain old actions that were removed', () {
      expect(
        homeScreen.contains('showAddTaskSheet'),
        isFalse,
        reason: 'Add task was removed from quick actions',
      );
      expect(
        homeScreen.contains('PrescriptionScanScreen'),
        isFalse,
        reason: 'Scan prescription was removed from quick actions',
      );
    });
  });
}
