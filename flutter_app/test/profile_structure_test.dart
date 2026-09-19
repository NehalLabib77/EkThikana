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

    test('logout and unsubscribe are separate confirmed actions', () {
      expect(source, contains('_logout'));
      expect(source, contains('_unsubscribe'));
      expect(source, contains('showConfirmationSheet'));
    });

    test('Study statistics section is completely removed', () {
      expect(source, isNot(contains('_StudyStatsRow')));
      expect(
        source,
        isNot(contains("GochanoLanguage.text('Study', 'পড়াশোনা')")),
      );
      expect(source, isNot(contains('Focus today')));
      expect(source, isNot(contains('This month')));
      expect(source, isNot(contains('Streak')));
      expect(source, isNot(contains('ApiService.getStudyStats()')));
    });

    test('Usage Access is completely removed', () {
      expect(source, isNot(contains('Usage Access')));
      expect(source, isNot(contains('ব্যবহার অ্যাক্সেস')));
      expect(source, isNot(contains('_usageAccessGranted')));
      expect(source, isNot(contains('_checkUsageAccess')));
      expect(source, isNot(contains('UsageStatsService')));
    });

    test('settings row uses GestureDetector for reliable hit-test', () {
      // _SettingsRow must use a single GestureDetector with
      // HitTestBehavior.opaque wrapping the entire row, not ListTile.onTap,
      // to avoid gesture-arena conflicts inside CardGroup's ClipRRect.
      expect(source, contains('class _SettingsRow'));
      expect(source, contains('HitTestBehavior.opaque'));
      expect(source, contains('GestureDetector'));
    });

    test('AI usage row and breakdown sheet are present in Settings', () {
      expect(
        source,
        contains("GochanoLanguage.text('AI usage', 'এআই ব্যবহার')"),
      );
      expect(source, contains('_loadAiUsage'));
      expect(source, contains('_aiUsageLabel'));
      expect(source, contains('_showAiUsageSheet'));
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
      expect(source, contains("data['phone']"));
      expect(source, contains('TelecomAuthService.readUserPhone()'));
      expect(source, isNot(contains('ApiService.getStudyStats()')));
    });

    test(
      'retains Monthly Money, Language, Appearance, and Reminders in settings',
      () {
        expect(
          source,
          contains("GochanoLanguage.text('Monthly money', 'মাসিক টাকা')"),
        );
        expect(source, contains("GochanoLanguage.text('Language', 'ভাষা')"));
        expect(
          source,
          contains("GochanoLanguage.text('Appearance', 'চেহারা')"),
        );
        expect(
          source,
          contains("GochanoLanguage.text('Reminders', 'রিমাইন্ডার')"),
        );
      },
    );

    test('contains Alarms & reminders and Auto-start with BN labels', () {
      expect(source, contains("'Alarms & reminders'"));
      expect(source, contains("'অ্যালার্ম ও রিমাইন্ডার'"));
      expect(source, contains("'Auto-start'"));
      expect(source, contains("'অটো-স্টার্ট'"));
      expect(
        source,
        contains("'Allow exact reminders when the app is closed'"),
      );
      expect(
        source,
        contains("'অ্যাপ বন্ধ থাকলেও সঠিক সময়ে রিমাইন্ডার পেতে অনুমতি দিন'"),
      );
      expect(
        source,
        contains(
          "'Allow Gochano to start for reminders after swipe-away or reboot'",
        ),
      );
      expect(
        source,
        contains(
          "'সোয়াইপ-অ্যাওয়ে বা রিবুটের পর রিমাইন্ডারের জন্য Gochano চালু হতে দিন'",
        ),
      );
      expect(source, contains("GochanoLanguage.text('Enabled', 'চালু')"));
      expect(source, contains("GochanoLanguage.text('Disabled', 'বন্ধ')"));
    });

    test(
      'alarms row calls openExactAlarmSettings and auto-start row calls openAutoStartSettings',
      () {
        expect(
          source,
          contains('NotificationService.openExactAlarmSettings()'),
        );
        expect(source, contains('NotificationService.openAutoStartSettings()'));
      },
    );

    test('no USE_EXACT_ALARM permission added to AndroidManifest.xml', () {
      final manifest = _read('android/app/src/main/AndroidManifest.xml');
      expect(manifest, isNot(contains('android.permission.USE_EXACT_ALARM')));
      expect(manifest, contains('android.permission.SCHEDULE_EXACT_ALARM'));
    });

    test('no XP, levels, gems, badges, or productivity stats remain', () {
      expect(source, isNot(contains('XP')));
      expect(source, isNot(contains('gems')));
      expect(source, isNot(contains('badges')));
      expect(source, isNot(contains('level')));
      expect(source, isNot(contains('productivity')));
    });

    test('appBar supports back navigation when pushed from home', () {
      expect(source, contains('Navigator.of(context).canPop()'));
    });
  });

  group('Home Quick Access absent', () {
    late String source;

    setUpAll(
      () => source = _read('lib/features/home/presentation/home_screen.dart'),
    );

    test('does not contain _QuickActions class', () {
      expect(source, isNot(contains('class _QuickActions')));
    });

    test('does not reference AiAssistantScreen or showAddExpenseSheet', () {
      expect(source, isNot(contains('AiAssistantScreen')));
      expect(source, isNot(contains('showAddExpenseSheet')));
    });

    test('does not mount _QuickActions in build', () {
      expect(source, isNot(contains('_QuickActions(')));
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
      expect(source, contains('crossAxisCount: 4'));
      expect(source, contains('AiAssistantScreen'));
      expect(source, contains('NotesScreen'));
      expect(source, contains('SemesterListScreen'));
      expect(source, contains('SharedBoxScreen'));
      // Recent Materials stays in the body.
      expect(source, contains('_RecentMaterials()'));
    });

    test('shows primary Workspace destinations with expandable panel', () {
      final source = _read(
        'lib/features/study/presentation/workspace/workspace_view.dart',
      );
      expect(source, contains("GochanoLanguage.text('Docs'"));
      expect(source, contains('SavedMaterialsScreen'));
      expect(source, contains('_expanded'));
      expect(source, contains('AnimatedSize'));
    });

    test('uses a grid with fixed mainAxisExtent', () {
      final source = _read(
        'lib/features/study/presentation/workspace/workspace_view.dart',
      );
      expect(source, contains('GridView.builder'));
      expect(source, contains('crossAxisCount: 4'));
      final match = RegExp(r'mainAxisExtent:\s*(\d+)').firstMatch(source);
      expect(
        match,
        isNotNull,
        reason: 'Quick Access grid must declare a finite mainAxisExtent',
      );
      final value = int.parse(match!.group(1)!);
      expect(value, greaterThanOrEqualTo(80));
      expect(
        value,
        lessThanOrEqualTo(96),
        reason:
            'mainAxisExtent should be between 80-96px for overflow-safe tiles',
      );
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
      expect(
        source,
        isNot(contains('childAspectRatio')),
        reason: 'Must not use childAspectRatio which caused the overflow',
      );
    });

    test(
      'supports vertical drag down/up gestures on the expand/collapse handle',
      () {
        final source = _read(
          'lib/features/study/presentation/workspace/workspace_view.dart',
        );
        expect(source, contains('onVerticalDragEnd'));
        expect(source, contains('onVerticalDragUpdate'));
        expect(source, contains('vy > 100'));
        expect(source, contains('vy < -100'));
        expect(source, contains('details.primaryDelta! > 8'));
        expect(source, contains('details.primaryDelta! < -8'));
        expect(source, contains("'See more'"));
        expect(source, contains("'See less'"));
      },
    );

    test(
      'renders prominent 24px icons in 44px circular container with centered labels',
      () {
        final source = _read(
          'lib/features/study/presentation/workspace/workspace_view.dart',
        );
        expect(source, contains('width: 44'));
        expect(source, contains('height: 44'));
        expect(source, contains('size: 24'));
        expect(source, contains('TextAlign.center'));
      },
    );
  });

  group('Home bento layout', () {
    late String source;

    setUpAll(
      () => source = _read('lib/features/home/presentation/home_screen.dart'),
    );

    test('has the required Home cards', () {
      expect(source, contains('_TodaysTasksCard'));
      expect(source, contains('_MedicineScheduleCard'));
      expect(source, contains('_CommuteCard'));
      expect(source, contains('_MoneyCard'));
    });

    test('uses accent-rail cards with colored left border', () {
      expect(source, contains('_AccentRailCard'));
      expect(source, contains('SizedBox(width: 3'));
    });

    test('does not compose legacy dashboard sections', () {
      final buildStart = source.indexOf('Widget build(BuildContext context)');
      final buildEnd = source.indexOf('\n  }', buildStart);
      final build = source.substring(buildStart, buildEnd);
      expect(build, isNot(contains('_SmartSummaryCard')));
      expect(build, isNot(contains('_StudyProgressCard')));
      expect(build, isNot(contains('_RecentMaterialsCard')));
      expect(build, isNot(contains('_BentoRow')));
    });

    test('Home does not contain removed Quick Actions icons', () {
      // Quick Actions was removed from Home; these icons should not appear
      // in the context of a Quick Actions grid.
      expect(source, isNot(contains('Icons.auto_awesome_rounded')));
      expect(source, isNot(contains('Icons.medication_outlined')));
      expect(source, isNot(contains('Icons.directions_bus_rounded')));
    });

    test('Money card shows spent and remaining labels', () {
      expect(source, contains('Money'));
      expect(source, contains('Spent'));
      expect(source, contains('Rem'));
    });
  });
}
