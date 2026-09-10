import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gochano/core/navigation.dart';

void main() {
  group('StudentArea enum', () {
    test('defines exactly 5 student bottom-nav destinations', () {
      expect(StudentArea.values.length, 5);
    });

    test('order is Today, Study, Money, Commute, Community', () {
      expect(StudentArea.today.tabIndex, 0);
      expect(StudentArea.study.tabIndex, 1);
      expect(StudentArea.money.tabIndex, 2);
      expect(StudentArea.commute.tabIndex, 3);
      expect(StudentArea.community.tabIndex, 4);
    });

    test('count constant matches values length', () {
      expect(StudentArea.count, StudentArea.values.length);
    });
  });

  group('StudyTab enum', () {
    test('workspace is index 0', () {
      expect(StudyTab.workspace.tabIndex, 0);
    });

    test('plan is index 1', () {
      expect(StudyTab.plan.tabIndex, 1);
    });
  });

  group('Navigation source regression', () {
    test('tasks shortcut opens Study → Plan (initialTab: 1)', () {
      // The tasks "See All" shortcut must open StudyScreen with Plan tab.
      // Regression: if this changes, the shortcut will show Workspace instead
      // of Plan, breaking the student workflow.
      final shellSource = File(
        'lib/features/shell/presentation/gochano_shell.dart',
      ).readAsStringSync();
      expect(shellSource, contains('StudyScreen(initialTab: _studyTab)'));
    });

    test('materials shortcut opens Study → Workspace via onOpenStudyTab', () {
      // The materials "See All" shortcut must call onOpenStudyTab with 0.
      final homeSource = File(
        'lib/features/home/presentation/home_screen.dart',
      ).readAsStringSync();
      expect(homeSource, contains('onOpenStudyTab'));
    });

    test('task tap opens Study → Plan via onOpenStudyTab', () {
      // Tapping the schedule card in Today should open Study → Plan.
      final homeSource = File(
        'lib/features/home/presentation/home_screen.dart',
      ).readAsStringSync();
      expect(homeSource, contains('StudyTab.plan.tabIndex'));
    });

    test('shell uses StudyTab enum from navigation.dart', () {
      final shellSource = File(
        'lib/features/shell/presentation/gochano_shell.dart',
      ).readAsStringSync();
      expect(shellSource, contains("import '../../../core/navigation.dart'"));
      expect(shellSource, contains('StudentArea.study.tabIndex'));
    });

    test('home screen declares onOpenStudyTab callback', () {
      final homeSource = File(
        'lib/features/home/presentation/home_screen.dart',
      ).readAsStringSync();
      expect(homeSource, contains('required this.onOpenStudyTab'));
      expect(homeSource, contains('final ValueChanged<int> onOpenStudyTab'));
    });
  });
}
