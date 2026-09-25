// Tests for GochanoShell dynamic navigation adapter (Phase C).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gochano/core/design_system/gochano_theme.dart';
import 'package:gochano/core/localization/gochano_language.dart';
import 'package:gochano/core/settings/gochano_app_mode.dart';
import 'package:gochano/features/shell/presentation/gochano_shell.dart';

Widget _buildTestShell({
  String role = 'student',
  String displayName = 'Test User',
}) {
  return MaterialApp(
    theme: GochanoTheme.light(),
    home: GochanoShell(
      role: role,
      displayName: displayName,
      pagesBuilder: (context, mode) {
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

  group('GochanoShell Dynamic Navigation Adapter (Phase C)', () {
    testWidgets('renders Study Mode 5 destinations by default',
        (tester) async {
      await tester.pumpWidget(_buildTestShell());
      await tester.pumpAndSettle();

      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.destinations.length, 5);

      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Workspace'), findsOneWidget);
      expect(find.text('Plan'), findsOneWidget);
      expect(find.text('Community'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);

      expect(find.text('Commute'), findsNothing);
      expect(find.text('Money'), findsNothing);
    });

    testWidgets('renders Utility Mode 4 destinations when active',
        (tester) async {
      await GochanoAppModePreferences.select(GochanoAppMode.utility);

      await tester.pumpWidget(_buildTestShell());
      await tester.pumpAndSettle();

      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.destinations.length, 4);

      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Commute'), findsOneWidget);
      expect(find.text('Money'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);

      expect(find.text('Workspace'), findsNothing);
      expect(find.text('Plan'), findsNothing);
      expect(find.text('Community'), findsNothing);
    });

    testWidgets(
        'switching Study -> Utility resets selection to index 0 and avoids RangeError',
        (tester) async {
      await tester.pumpWidget(_buildTestShell());
      await tester.pumpAndSettle();

      // Tap Profile (index 4 in Study Mode)
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();

      var navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.selectedIndex, 4);
      expect(find.text('Page: Profile'), findsOneWidget);

      // Now switch mode to utility (which has only 4 destinations: 0..3)
      await GochanoAppModePreferences.select(GochanoAppMode.utility);
      await tester.pumpAndSettle();

      navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      // Must safely reset to 0 (Today)
      expect(navBar.selectedIndex, 0);
      expect(find.text('Page: Today'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('switching Utility -> Study resets selection to index 0',
        (tester) async {
      await GochanoAppModePreferences.select(GochanoAppMode.utility);
      await tester.pumpWidget(_buildTestShell());
      await tester.pumpAndSettle();

      // Tap Money (index 2)
      await tester.tap(find.text('Money'));
      await tester.pumpAndSettle();

      var navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.selectedIndex, 2);
      expect(find.text('Page: Money'), findsOneWidget);

      // Switch back to Study Mode
      await GochanoAppModePreferences.select(GochanoAppMode.study);
      await tester.pumpAndSettle();

      navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.selectedIndex, 0);
      expect(find.text('Page: Today'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('repeated mode switching is stable without leaked errors',
        (tester) async {
      await tester.pumpWidget(_buildTestShell());
      await tester.pumpAndSettle();

      for (int i = 0; i < 5; i++) {
        await GochanoAppModePreferences.select(GochanoAppMode.utility);
        await tester.pumpAndSettle();
        var navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
        expect(navBar.destinations.length, 4);

        await GochanoAppModePreferences.select(GochanoAppMode.study);
        await tester.pumpAndSettle();
        navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
        expect(navBar.destinations.length, 5);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('Profile is the final destination in both modes',
        (tester) async {
      await tester.pumpWidget(_buildTestShell());
      await tester.pumpAndSettle();

      var navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      var lastDest = navBar.destinations.last as NavigationDestination;
      expect(lastDest.label, 'Profile');

      await GochanoAppModePreferences.select(GochanoAppMode.utility);
      await tester.pumpAndSettle();

      navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      lastDest = navBar.destinations.last as NavigationDestination;
      expect(lastDest.label, 'Profile');
    });

    testWidgets(
        'Bangla labels render correctly without overflow on narrow width (320dp)',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      GochanoLanguage.current.value = GochanoLocale.bangla;

      await tester.pumpWidget(_buildTestShell());
      await tester.pumpAndSettle();

      expect(find.text('আজ'), findsOneWidget);
      expect(find.text('ওয়ার্কস্পেস'), findsOneWidget);
      expect(find.text('পরিকল্পনা'), findsOneWidget);
      expect(find.text('কমিউনিটি'), findsOneWidget);
      expect(find.text('প্রোফাইল'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await GochanoAppModePreferences.select(GochanoAppMode.utility);
      await tester.pumpAndSettle();

      expect(find.text('আজ'), findsOneWidget);
      expect(find.text('যাতায়াত'), findsOneWidget);
      expect(find.text('টাকা'), findsOneWidget);
      expect(find.text('প্রোফাইল'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'One-time discovery banner shows when undiscovered, and can be dismissed/marked',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        GochanoAppModePreferences.prefsKey: 'study',
        GochanoAppModePreferences.discoveryKey: false,
      });
      await GochanoAppModePreferences.restore();

      await tester.pumpWidget(_buildTestShell());
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(
        find.text(
            'Switch between Study and Utility Mode anytime in Profile Settings.'),
        findsOneWidget,
      );

      final isDiscovered = await GochanoAppModePreferences.isDiscovered();
      expect(isDiscovered, isTrue);
    });
  });
}
