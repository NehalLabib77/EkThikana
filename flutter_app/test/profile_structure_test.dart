// Guards the Profile screen's shape and the Home quick actions.
//
// Both were redesigned, and both have properties that a later edit could
// undo without anything failing to compile:
//
//   * Data export is gone from Profile. The endpoint still exists and is
//     still reachable from the account-deletion flow's backend, but the row
//     is not on this screen.
//   * Language and Appearance open selectors instead of expanding into
//     radio lists, and the row shows the current choice — otherwise
//     collapsing them would hide the setting rather than tidy it.
//   * Deleting the account sits in its own card, away from settings a
//     student changes casually.
//   * Quick actions collapse to four with an expander, so the briefing below
//     them stays above the fold.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  group('Profile', () {
    late String source;

    setUpAll(
      () => source = _read(
        'lib/features/profile/presentation/profile_screen.dart',
      ),
    );

    test('data export is not on the screen', () {
      expect(source, isNot(contains('Export my data')));
      expect(source, isNot(contains('exportAccount')));
    });

    test('language and appearance open selectors, not inline radio lists', () {
      // The old screen rendered RadioListTile groups inline, which is what
      // made a settings page the tallest screen in the app.
      expect(source, isNot(contains('RadioListTile')));
      expect(source, isNot(contains('RadioGroup')));
      expect(source, contains('_pickLanguage'));
      expect(source, contains('_pickAppearance'));
    });

    test('each settings row shows its current value', () {
      // Collapsing a setting is only honest if the row still says what it is
      // set to. Both selectors are driven from the same notifiers the app
      // uses, so the row cannot go stale.
      expect(source, contains('ValueListenableBuilder<GochanoLocale>'));
      expect(source, contains('ValueListenableBuilder<ThemeMode>'));
      expect(source, contains('locale.nativeName'));
      expect(source, contains('_appearanceLabel(mode)'));
    });

    test('deleting the account stands apart from ordinary settings', () {
      expect(source, contains('class _DangerCard'));
      final settings = source.substring(
        source.indexOf('class _SettingsCard'),
        source.indexOf('class _DangerCard'),
      );
      expect(
        settings,
        isNot(contains('_deleteAccount')),
        reason: 'account deletion must not sit among everyday settings',
      );
    });

    test('sign out is still separate and still confirmed', () {
      expect(source, contains('_signOut'));
      expect(source, contains('showConfirmationSheet'));
    });

    test('usage access stays tappable in both permission states', () {
      final row = source.substring(
        source.indexOf("'Usage Access'"),
        source.indexOf('String _appearanceLabel'),
      );
      expect(row, contains('_usageAccessGranted'));
      expect(row, contains('UsageStatsService.openSettings()'));
      expect(row, contains('_checkUsageAccess()'));
      expect(row, isNot(contains('IgnorePointer')));
      expect(row, isNot(contains('AbsorbPointer')));
    });

    test('settings row uses GestureDetector for reliable hit-test', () {
      // _SettingsRow must use a single GestureDetector with
      // HitTestBehavior.opaque wrapping the entire row, not ListTile.onTap,
      // to avoid gesture-arena conflicts inside CardGroup's ClipRRect.
      expect(source, contains('class _SettingsRow'));
      expect(source, contains('HitTestBehavior.opaque'));
      expect(source, contains('GestureDetector'));
    });

    test('profile editing writes only the displayed fields', () {
      // Never `role`: the security rule refuses a write that changes it, and
      // this screen has no business touching it regardless.
      final service = _read('lib/services/firestore_service.dart');
      final method = service.substring(
        service.indexOf('static Future<void> updateProfile('),
        service.indexOf('static Future<Map<String, dynamic>> profile()'),
      );

      expect(method, contains("'displayName'"));
      expect(method, contains("'university'"));
      expect(method, contains("'department'"));
      expect(method, isNot(contains("'role'")));
      expect(method, isNot(contains("'email'")));
    });

    test('user values are read from the profile, never hardcoded', () {
      expect(source, contains('FirestoreService.profileStream()'));
      expect(source, contains("data['displayName']"));
      expect(source, contains("data['email']"));
      expect(source, contains('ApiService.getStudyStats()'));
    });
  });

  group('Home quick actions', () {
    late String source;

    setUpAll(
      () => source = _read('lib/features/home/presentation/home_screen.dart'),
    );

    test('collapses to three with an expander', () {
      expect(source, contains('_collapsedCount = 3'));
      expect(source, contains('See more'));
      expect(source, contains('See less'));
      expect(source, contains('আরো দেখুন'));
      expect(source, contains('কম দেখুন'));
    });

    test('every existing destination is still reachable', () {
      // A redesign that quietly drops a shortcut is a regression, not a
      // tidy-up.
      for (final destination in const [
        'AiAssistantScreen',
        'showAddExpenseSheet',
        'showAddTaskSheet',
        'PrescriptionScanScreen',
        'CommuteScreen',
      ]) {
        expect(
          source,
          contains(destination),
          reason: '$destination must stay one tap from Home',
        );
      }
    });
  });

  group('Tasks', () {
    test('the empty state no longer duplicates the floating add button', () {
      final source = _read('lib/features/tasks/presentation/tasks_view.dart');
      final emptyState = source.substring(
        source.indexOf('if (effectiveDocs.isEmpty)'),
        source.indexOf('return ListView.builder('),
      );

      expect(emptyState, isNot(contains('actionLabel')));
      expect(emptyState, isNot(contains('onAction')));
      // The floating button itself must still be there.
      expect(source, contains('showAddTaskSheet(context)'));
    });
  });

  group('Study Workspace', () {
    test('body has Quick Access grid and Recent Materials', () {
      final source = _read(
        'lib/features/study/presentation/workspace/workspace_view.dart',
      );
      // Quick Access navigation grid lives in the body.
      expect(source, contains('_QuickAccess'));
      expect(source, contains('_QuickAccessCell'));
      expect(source, contains('SliverGridDelegateWithFixedCrossAxisCount'));
      expect(source, contains('crossAxisCount: 3'));
      expect(source, contains('AiAssistantScreen'));
      expect(source, contains('NotesScreen'));
      expect(source, contains('SemesterListScreen'));
      expect(source, contains('SharedBoxScreen'));
      // Recent Materials stays in the body.
      expect(source, contains('_RecentMaterials()'));
    });

    test('collapses to three with See more / See less toggle', () {
      final source = _read(
        'lib/features/study/presentation/workspace/workspace_view.dart',
      );
      expect(source, contains('_collapsedCount = 3'));
      expect(source, contains('See more'));
      expect(source, contains('See less'));
      expect(source, contains('আরো দেখুন'));
      expect(source, contains('কম দেখুন'));
      expect(source, contains('_expanded = !_expanded'));
    });

    test('uses 3-column grid with fixed mainAxisExtent', () {
      final source = _read(
        'lib/features/study/presentation/workspace/workspace_view.dart',
      );
      expect(source, contains('GridView.builder'));
      expect(source, contains('crossAxisCount: 3'));
      final match =
          RegExp(r'mainAxisExtent:\s*(\d+)').firstMatch(source);
      expect(match, isNotNull,
          reason: 'Quick Access grid must declare a finite mainAxisExtent');
      final value = int.parse(match!.group(1)!);
      expect(value, greaterThanOrEqualTo(80));
      expect(value, lessThanOrEqualTo(96),
          reason: 'mainAxisExtent should be between 80-96px for overflow-safe tiles');
    });

    test('every existing destination is still reachable', () {
      final source = _read(
        'lib/features/study/presentation/workspace/workspace_view.dart',
      );
      for (final destination in const [
        'AiAssistantScreen',
        'NotesScreen',
        'MaterialsScreen',
        'SemesterListScreen',
        'SharedBoxScreen',
      ]) {
        expect(
          source,
          contains(destination),
          reason: '$destination must stay one tap from Study Workspace',
        );
      }
    });

    test('is a StatefulWidget for expand/collapse state', () {
      final source = _read(
        'lib/features/study/presentation/workspace/workspace_view.dart',
      );
      expect(source, contains('StatefulWidget'));
      expect(source, contains('State<_QuickAccess>'));
    });

    test('has no childAspectRatio (overflow-safe design)', () {
      final source = _read(
        'lib/features/study/presentation/workspace/workspace_view.dart',
      );
      // The old design used childAspectRatio: 2.8 which caused overflow.
      // The new design uses mainAxisExtent instead.
      expect(source, isNot(contains('childAspectRatio')),
          reason: 'Must not use childAspectRatio which caused the overflow');
    });
  });

  group('Home bento layout', () {
    late String source;

    setUpAll(
      () => source = _read('lib/features/home/presentation/home_screen.dart'),
    );

    test('has all required bento sections', () {
      expect(source, contains('_SmartSummaryCard'));
      expect(source, contains('_TodaysTasksCard'));
      expect(source, contains('_UpcomingTasksCard'));
      expect(source, contains('_StudyProgressCard'));
      expect(source, contains('_LifeSnapshotCard'));
      expect(source, contains('_RecentMaterialsCard'));
    });

    test('uses accent-rail cards with colored left border', () {
      expect(source, contains('_AccentRailCard'));
      expect(source, contains('SizedBox(width: 3'));
    });

    test('uses bento row for side-by-side layout', () {
      expect(source, contains('_BentoRow'));
    });

    test('quick actions use Material Design icons, not illustrations', () {
      expect(source, contains('Icons.auto_awesome_rounded'));
      expect(source, contains('Icons.receipt_long_rounded'));
      expect(source, contains('Icons.task_alt_rounded'));
      expect(source, contains('Icons.document_scanner_rounded'));
      expect(source, contains('Icons.directions_bus_rounded'));
    });

    test('Life Snapshot shows remaining and spent', () {
      expect(source, contains('Life Snapshot'));
      expect(source, contains('Spent'));
      expect(source, contains('Remaining'));
    });
  });
}
