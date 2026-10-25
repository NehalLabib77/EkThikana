import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gochano/core/design_system/gochano_theme.dart';
import 'package:gochano/core/localization/gochano_language.dart';
import 'package:gochano/core/settings/gochano_app_mode.dart';
import 'package:gochano/features/shell/presentation/gochano_shell.dart';

Widget _buildWrapper({
  required Widget child,
  ThemeData? theme,
  Size size = const Size(360, 640),
}) {
  return MaterialApp(
    theme: theme ?? GochanoTheme.light(),
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: child,
    ),
  );
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    GochanoLanguage.current.value = GochanoLocale.english;
    await GochanoAppModePreferences.restore();
    await GochanoAppModePreferences.select(GochanoAppMode.study);
  });

  group('GochanoShell Visual & Navigation Integrity Tests', () {
    testWidgets('Study mode renders 5 canonical destinations in English',
        (tester) async {
      GochanoLanguage.current.value = GochanoLocale.english;
      await GochanoAppModePreferences.select(GochanoAppMode.study);

      await tester.pumpWidget(
        _buildWrapper(
          child: GochanoShell(
            role: 'student',
            displayName: 'Test Student',
            pagesBuilder: (context, mode) => const [
              Text('Page 0: Today'),
              Text('Page 1: Workspace'),
              Text('Page 2: Plan'),
              Text('Page 3: Community'),
              Text('Page 4: You'),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.destinations.length, 5);

      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Workspace'), findsOneWidget);
      expect(find.text('Plan'), findsOneWidget);
      expect(find.text('Community'), findsOneWidget);
      expect(find.text('You'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });

    testWidgets('Study mode renders 5 canonical destinations in Bengali',
        (tester) async {
      GochanoLanguage.current.value = GochanoLocale.bangla;
      await GochanoAppModePreferences.select(GochanoAppMode.study);

      await tester.pumpWidget(
        _buildWrapper(
          child: GochanoShell(
            role: 'student',
            displayName: 'Test Student',
            pagesBuilder: (context, mode) => const [
              Text('Page 0: Today'),
              Text('Page 1: Workspace'),
              Text('Page 2: Plan'),
              Text('Page 3: Community'),
              Text('Page 4: You'),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.destinations.length, 5);

      expect(find.text('আজ'), findsOneWidget);
      expect(find.text('ওয়ার্কস্পেস'), findsOneWidget);
      expect(find.text('পরিকল্পনা'), findsOneWidget);
      expect(find.text('কমিউনিটি'), findsOneWidget);
      expect(find.text('আপনি'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });

    testWidgets('Utility mode renders 4 canonical destinations in English',
        (tester) async {
      GochanoLanguage.current.value = GochanoLocale.english;
      await GochanoAppModePreferences.select(GochanoAppMode.utility);

      await tester.pumpWidget(
        _buildWrapper(
          child: GochanoShell(
            role: 'student',
            displayName: 'Test Student',
            pagesBuilder: (context, mode) => const [
              Text('Page 0: Today'),
              Text('Page 1: Commute'),
              Text('Page 2: Money'),
              Text('Page 3: Profile'),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.destinations.length, 4);

      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Commute'), findsOneWidget);
      expect(find.text('Money'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);

      // Verify Study-only items are absent
      expect(find.text('Workspace'), findsNothing);
      expect(find.text('Plan'), findsNothing);
      expect(find.text('Community'), findsNothing);
      expect(find.text('You'), findsNothing);

      expect(tester.takeException(), isNull);
    });

    testWidgets('Non-student mode renders 4 canonical destinations in English',
        (tester) async {
      GochanoLanguage.current.value = GochanoLocale.english;

      await tester.pumpWidget(
        _buildWrapper(
          child: GochanoShell(
            role: 'teacher',
            displayName: 'Test Teacher',
            pagesBuilder: (context, mode) => const [
              Text('Page 0: Home'),
              Text('Page 1: Life'),
              Text('Page 2: Tasks'),
              Text('Page 3: Profile'),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.destinations.length, 4);

      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Life'), findsOneWidget);
      expect(find.text('Tasks'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });

    testWidgets('IndexedStack preserves page state across tab switches',
        (tester) async {
      await GochanoAppModePreferences.select(GochanoAppMode.study);

      int counterToday = 0;
      int counterPlan = 0;

      await tester.pumpWidget(
        _buildWrapper(
          child: GochanoShell(
            role: 'student',
            displayName: 'Test Student',
            pagesBuilder: (context, mode) => [
              StatefulBuilder(
                builder: (context, setState) => Column(
                  children: [
                    Text('Today count: $counterToday'),
                    ElevatedButton(
                      onPressed: () => setState(() => counterToday++),
                      child: const Text('Increment Today'),
                    ),
                  ],
                ),
              ),
              const Text('Page 1: Workspace'),
              StatefulBuilder(
                builder: (context, setState) => Column(
                  children: [
                    Text('Plan count: $counterPlan'),
                    ElevatedButton(
                      onPressed: () => setState(() => counterPlan++),
                      child: const Text('Increment Plan'),
                    ),
                  ],
                ),
              ),
              const Text('Page 3: Community'),
              const Text('Page 4: You'),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Increment Today counter to 1
      await tester.tap(find.text('Increment Today'));
      await tester.pumpAndSettle();
      expect(find.text('Today count: 1'), findsOneWidget);

      // Switch to Plan tab (index 2)
      await tester.tap(find.text('Plan'));
      await tester.pumpAndSettle();

      // Increment Plan counter to 5
      for (int i = 0; i < 5; i++) {
        await tester.tap(find.text('Increment Plan'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Plan count: 5'), findsOneWidget);

      // Switch back to Today tab (index 0)
      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();

      // Verify Today state is preserved at 1
      expect(find.text('Today count: 1'), findsOneWidget);

      // Switch back to Plan tab (index 2) and verify Plan state is preserved at 5
      await tester.tap(find.text('Plan'));
      await tester.pumpAndSettle();
      expect(find.text('Plan count: 5'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });

    testWidgets('renders cleanly on 320dp narrow viewport with zero overflow',
        (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildWrapper(
          size: const Size(320, 568),
          child: GochanoShell(
            role: 'student',
            displayName: 'Test Student',
            pagesBuilder: (context, mode) => const [
              Text('Page 0: Today'),
              Text('Page 1: Workspace'),
              Text('Page 2: Plan'),
              Text('Page 3: Community'),
              Text('Page 4: You'),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Workspace'), findsOneWidget);
      expect(find.text('Plan'), findsOneWidget);
      expect(find.text('Community'), findsOneWidget);
      expect(find.text('You'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });

    testWidgets('renders cleanly in Dark Mode with dark navigation bar theme',
        (tester) async {
      await tester.pumpWidget(
        _buildWrapper(
          theme: GochanoTheme.dark(),
          child: GochanoShell(
            role: 'student',
            displayName: 'Test Student',
            pagesBuilder: (context, mode) => const [
              Text('Page 0: Today'),
              Text('Page 1: Workspace'),
              Text('Page 2: Plan'),
              Text('Page 3: Community'),
              Text('Page 4: You'),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.destinations.length, 5);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'Utility mode: tapping Commute card selects CommuteScreen and Money selects ExpenseScreen',
      (tester) async {
        await GochanoAppModePreferences.select(GochanoAppMode.utility);

        await tester.pumpWidget(
          _buildWrapper(
            child: GochanoShell(
              role: 'student',
              displayName: 'Test Student',
              pagesWithNavigationBuilder: (context, mode, onNavigate) => [
                Column(
                  children: [
                    ElevatedButton(
                      onPressed: () => onNavigate(2),
                      child: const Text('Tap Commute Card'),
                    ),
                    ElevatedButton(
                      onPressed: () => onNavigate(3),
                      child: const Text('Tap Money Card'),
                    ),
                  ],
                ),
                const Text('Active Destination: CommuteScreen'),
                const Text('Active Destination: ExpenseScreen'),
                const Text('Active Destination: ProfileScreen'),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Initially on Tab 0 (Home)
        final indexedStackInitial =
            tester.widget<IndexedStack>(find.byType(IndexedStack));
        expect(indexedStackInitial.index, equals(0));

        // Tap Commute card -> triggers onNavigate(2) -> _select(1)
        await tester.tap(find.text('Tap Commute Card'));
        await tester.pumpAndSettle();

        final indexedStackCommute =
            tester.widget<IndexedStack>(find.byType(IndexedStack));
        expect(indexedStackCommute.index, equals(1));
        expect(find.text('Active Destination: CommuteScreen'), findsOneWidget);

        // Switch back to Home (Tab 0) via navigation bar
        await tester.tap(find.text('Today'));
        await tester.pumpAndSettle();

        final indexedStackHome =
            tester.widget<IndexedStack>(find.byType(IndexedStack));
        expect(indexedStackHome.index, equals(0));

        // Tap Money card -> triggers onNavigate(3) -> _select(2)
        await tester.tap(find.text('Tap Money Card'));
        await tester.pumpAndSettle();

        final indexedStackMoney =
            tester.widget<IndexedStack>(find.byType(IndexedStack));
        expect(indexedStackMoney.index, equals(2));
        expect(find.text('Active Destination: ExpenseScreen'), findsOneWidget);
      },
    );

    testWidgets(
      'Utility mode end-to-end: tapping HomeScreen Commute card selects CommuteScreen tab',
      (tester) async {
        await GochanoAppModePreferences.select(GochanoAppMode.utility);

        await tester.pumpWidget(
          _buildWrapper(
            child: const GochanoShell(
              role: 'student',
              displayName: 'Test Student',
            ),
          ),
        );
        await tester.pump();

        // Initially on Tab 0 (HomeScreen)
        final indexedStack =
            tester.widget<IndexedStack>(find.byType(IndexedStack));
        expect(indexedStack.index, equals(0));

        // Tap Commute card on HomeScreen (Plan a trip text is unique to the card)
        await tester.tap(find.text('Plan a trip'));
        await tester.pump();

        final indexedStackAfter =
            tester.widget<IndexedStack>(find.byType(IndexedStack));
        expect(indexedStackAfter.index, equals(1));
      },
    );
  });
}
