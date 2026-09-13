// Static guards for the Home Quick Actions removal (spec §27, §86).
//
// Home Quick Access was removed. These tests verify it is absent from the
// Home screen. Workspace Quick Access is tested separately in
// study_rebuild_test.dart and profile_structure_test.dart.
//
// Everything below is a string-level guard so it runs without an emulator.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  final homeScreen = _read('lib/features/home/presentation/home_screen.dart');

  group('Home Quick Actions removed', () {
    test('does not contain _QuickActions widget class', () {
      expect(homeScreen, isNot(contains('class _QuickActions')));
    });

    test('does not contain _QuickActionsState class', () {
      expect(homeScreen, isNot(contains('class _QuickActionsState')));
    });

    test('does not reference AiAssistantScreen', () {
      expect(homeScreen, isNot(contains('AiAssistantScreen')));
    });

    test('does not reference showAddExpenseSheet', () {
      expect(homeScreen, isNot(contains('showAddExpenseSheet')));
    });

    test('does not mount _QuickActions in build method', () {
      expect(homeScreen, isNot(contains('_QuickActions(')));
    });
  });
}
