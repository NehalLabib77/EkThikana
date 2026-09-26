// Tests for App Mode Final Hardening, Edge Cases & UX Polish (Phase F).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gochano/core/design_system/gochano_theme.dart';
import 'package:gochano/core/localization/gochano_language.dart';
import 'package:gochano/core/page_route.dart';
import 'package:gochano/core/settings/gochano_app_mode.dart';
import 'package:gochano/features/profile/presentation/app_mode_selector_sheet.dart';
import 'package:gochano/features/shell/presentation/gochano_shell.dart';
import 'package:gochano/features/shell/presentation/quick_add_sheet.dart';

Widget _buildWrapper({
  required Widget child,
  double width = 360,
  double height = 640,
  double textScaleFactor = 1.0,
}) {
  return MaterialApp(
    theme: GochanoTheme.light(),
    home: MediaQuery(
      data: MediaQueryData(
        size: Size(width, height),
        textScaler: TextScaler.linear(textScaleFactor),
      ),
      child: Scaffold(body: child),
    ),
  );
}

Widget _buildTestShell({
  String role = 'student',
  String displayName = 'Hardening Tester',
  List<Widget> Function(BuildContext context, GochanoAppMode mode)? pagesBuilder,
}) {
  return MaterialApp(
    theme: GochanoTheme.light(),
    home: GochanoShell(
      role: role,
      displayName: displayName,
      pagesBuilder: pagesBuilder ??
          (context, mode) {
            if (mode == GochanoAppMode.study) {
              return const [
                Text('Page: Today'),
                Text('Page: Workspace'),
                Text('Page: Plan'),
                Text('Page: Community'),
                Text('Page: Profile'),
              ];
            }
            return const [
              Text('Page: Today'),
              Text('Page: Commute'),
              Text('Page: Money'),
              Text('Page: Profile'),
            ];
          },
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      GochanoAppModePreferences.prefsKey: 'study',
      GochanoAppModePreferences.discoveryKey: true,
      'gochano.language': 'en',
    });
    GochanoLanguage.current.value = GochanoLocale.english;
    await GochanoAppModePreferences.restore();
  });

  tearDown(() {
    GochanoAppModePreferences.current.value = GochanoAppMode.study;
    GochanoLanguage.current.value = GochanoLocale.english;
  });

  group('Cold Start & Persistence Edge Cases', () {
    test('saved Utility mode restores correctly before first frame', () async {
      SharedPreferences.setMockInitialValues({
        GochanoAppModePreferences.prefsKey: 'utility',
      });
      await GochanoAppModePreferences.restore();
      expect(GochanoAppModePreferences.current.value, equals(GochanoAppMode.utility));
      expect(GochanoAppModePreferences.isUtility, isTrue);
      expect(GochanoAppModePreferences.isStudy, isFalse);
    });

    test('saved Study mode restores correctly before first frame', () async {
      SharedPreferences.setMockInitialValues({
        GochanoAppModePreferences.prefsKey: 'study',
      });
      await GochanoAppModePreferences.restore();
      expect(GochanoAppModePreferences.current.value, equals(GochanoAppMode.study));
      expect(GochanoAppModePreferences.isStudy, isTrue);
      expect(GochanoAppModePreferences.isUtility, isFalse);
    });

    test('invalid or corrupted preference value safely defaults to Study Mode', () async {
      SharedPreferences.setMockInitialValues({
        GochanoAppModePreferences.prefsKey: 'random_corrupted_key_12345',
      });
      await GochanoAppModePreferences.restore();
      expect(GochanoAppModePreferences.current.value, equals(GochanoAppMode.study));
      expect(GochanoAppModePreferences.isStudy, isTrue);
    });

    test('missing preference key safely defaults to Study Mode', () async {
      SharedPreferences.setMockInitialValues({});
      await GochanoAppModePreferences.restore();
      expect(GochanoAppModePreferences.current.value, equals(GochanoAppMode.study));
      expect(GochanoAppModePreferences.isStudy, isTrue);
    });

    test('mode selection operates with zero network dependencies (offline safe)', () async {
      SharedPreferences.setMockInitialValues({});
      await GochanoAppModePreferences.select(GochanoAppMode.utility);
      expect(GochanoAppModePreferences.current.value, equals(GochanoAppMode.utility));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(GochanoAppModePreferences.prefsKey), equals('utility'));
    });
  });

  group('Mode Switch Transition & Index Bounds Safety', () {
    testWidgets('switching from Study Profile (index 4) to Utility Mode safely resets to 0', (
      tester,
    ) async {
      await tester.pumpWidget(_buildTestShell());
      await tester.pumpAndSettle();

      // Tap Profile (index 4 in Study Mode)
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();

      var navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.selectedIndex, equals(4));
      expect(find.text('Page: Profile'), findsOneWidget);

      // Change mode to utility (which only has 4 items: 0..3)
      await GochanoAppModePreferences.select(GochanoAppMode.utility);
      await tester.pumpAndSettle();

      navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.selectedIndex, equals(0));
      expect(find.text('Page: Today'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('switching from Study Community (index 3) to Utility Mode safely resets to 0', (
      tester,
    ) async {
      await tester.pumpWidget(_buildTestShell());
      await tester.pumpAndSettle();

      // Tap Community (index 3 in Study Mode)
      await tester.tap(find.text('Community'));
      await tester.pumpAndSettle();

      var navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.selectedIndex, equals(3));
      expect(find.text('Page: Community'), findsOneWidget);

      // Change mode to utility
      await GochanoAppModePreferences.select(GochanoAppMode.utility);
      await tester.pumpAndSettle();

      navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.selectedIndex, equals(0));
      expect(find.text('Page: Today'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('rapid repeated mode switching is leak-free and stable', (
      tester,
    ) async {
      await tester.pumpWidget(_buildTestShell());
      await tester.pumpAndSettle();

      for (int i = 0; i < 10; i++) {
        await GochanoAppModePreferences.select(GochanoAppMode.utility);
        await tester.pumpAndSettle();
        var navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
        expect(navBar.destinations.length, equals(4));

        await GochanoAppModePreferences.select(GochanoAppMode.study);
        await tester.pumpAndSettle();
        navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
        expect(navBar.destinations.length, equals(5));
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('Profile Selector Dismiss & Save Hardening', () {
    testWidgets('dismissing selector without save preserves original mode', (
      tester,
    ) async {
      GochanoAppModePreferences.current.value = GochanoAppMode.study;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  key: const ValueKey('open_selector'),
                  onPressed: () => showAppModeSelectorSheet(context),
                  child: const Text('Open'),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open selector
      await tester.tap(find.byKey(const ValueKey('open_selector')));
      await tester.pumpAndSettle();

      // Stage utility mode
      await tester.tap(find.byKey(const ValueKey('app_mode_utility_card')));
      await tester.pumpAndSettle();

      // Dismiss without tapping save (tap barrier)
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      // Mode must remain Study
      expect(GochanoAppModePreferences.current.value, equals(GochanoAppMode.study));
    });

    testWidgets('saving mode persists and closes modal', (
      tester,
    ) async {
      GochanoAppModePreferences.current.value = GochanoAppMode.study;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  key: const ValueKey('open_selector'),
                  onPressed: () => showAppModeSelectorSheet(context),
                  child: const Text('Open'),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('open_selector')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('app_mode_utility_card')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('save_app_mode_button')));
      await tester.pumpAndSettle();

      expect(GochanoAppModePreferences.current.value, equals(GochanoAppMode.utility));
      expect(find.byType(AppModeSelectorSheet), findsNothing);
    });
  });

  group('One-Time Discovery Notice Hardening', () {
    testWidgets('discovery notice shows once with normalized wording, dismissal persists', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        GochanoAppModePreferences.prefsKey: 'study',
        GochanoAppModePreferences.discoveryKey: false,
      });
      await GochanoAppModePreferences.restore();

      await tester.pumpWidget(_buildTestShell());
      await tester.pumpAndSettle();

      // Verify exact normalized discovery copy and action label
      expect(find.byType(SnackBar), findsOneWidget);
      expect(
        find.text('Gochano now has Study and Utility modes. Change anytime from Profile Settings.'),
        findsOneWidget,
      );
      expect(find.text('Change'), findsOneWidget);

      final isDiscovered = await GochanoAppModePreferences.isDiscovered();
      expect(isDiscovered, isTrue);

      // Rebuilding the shell should not show the snackbar again
      await tester.pumpWidget(_buildTestShell());
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  group('Deep Link & Hidden Feature Navigation Continuity', () {
    testWidgets('pushing a hidden destination does NOT alter the active App Mode', (
      tester,
    ) async {
      GochanoAppModePreferences.current.value = GochanoAppMode.study;

      late BuildContext shellContext;
      await tester.pumpWidget(
        MaterialApp(
          theme: GochanoTheme.light(),
          home: Builder(
            builder: (ctx) {
              shellContext = ctx;
              return _buildTestShell();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(GochanoAppModePreferences.isStudy, isTrue);

      // Push a commute destination (hidden from Study bottom nav)
      Navigator.of(shellContext).push(
        GochanoRoute.to(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('Pushed Commute Screen')),
            body: const Text('Commute details'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Pushed Commute Screen'), findsOneWidget);
      // Mode remains Study
      expect(GochanoAppModePreferences.isStudy, isTrue);

      // Pop back
      Navigator.of(shellContext).pop();
      await tester.pumpAndSettle();

      expect(find.text('Page: Today'), findsOneWidget);
      expect(GochanoAppModePreferences.isStudy, isTrue);
    });
  });

  group('General / Non-Student Role Invariance', () {
    testWidgets('non-student role preserves 4 canonical destinations regardless of mode', (
      tester,
    ) async {
      await tester.pumpWidget(_buildTestShell(role: 'teacher'));
      await tester.pumpAndSettle();

      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.destinations.length, equals(4));

      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Life'), findsOneWidget);
      expect(find.text('Tasks'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);

      // Non-student shell does NOT render universal quick add FAB
      expect(find.byKey(const ValueKey('universal_quick_add_fab')), findsNothing);
    });
  });

  group('Accessibility, Font Scaling & Localization on 320dp', () {
    testWidgets('AppModeSelectorSheet renders cleanly on 320dp without overflow', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildWrapper(
          width: 320,
          child: const AppModeSelectorSheet(),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('app_mode_study_card')), findsOneWidget);
      expect(find.byKey(const ValueKey('app_mode_utility_card')), findsOneWidget);
      expect(find.byKey(const ValueKey('save_app_mode_button')), findsOneWidget);
    });

    testWidgets('AppModeSelectorSheet renders cleanly with 2.0x font scale without overflow', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildWrapper(
          width: 360,
          textScaleFactor: 2.0,
          child: const AppModeSelectorSheet(),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('app_mode_study_card')), findsOneWidget);
      expect(find.byKey(const ValueKey('save_app_mode_button')), findsOneWidget);
    });

    testWidgets('AppModeSelectorSheet renders in Bengali without overflow on 320dp', (
      tester,
    ) async {
      GochanoLanguage.current.value = GochanoLocale.bangla;

      await tester.pumpWidget(
        _buildWrapper(
          width: 320,
          child: const AppModeSelectorSheet(),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('স্টাডি মোড'), findsOneWidget);
      expect(find.text('ইউটিলিটি মোড'), findsOneWidget);
      expect(find.text('মোড সংরক্ষণ করুন'), findsOneWidget);
    });

    testWidgets('Study 5-item and Utility 4-item NavBars render on 320dp with 2.0x font scaling', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: GochanoTheme.light(),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 640),
              textScaler: TextScaler.linear(2.0),
            ),
            child: const GochanoShell(
              role: 'student',
              displayName: 'Scaling Tester',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await GochanoAppModePreferences.select(GochanoAppMode.utility);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
