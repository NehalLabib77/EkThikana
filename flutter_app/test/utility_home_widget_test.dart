// Widget tests for Utility Mode Home screen presentation refinement,
// card composition, theme adaptability, accessibility, and navigation callbacks.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gochano/core/design_system/app_design_system.dart';
import 'package:gochano/core/design_system/app_gradients.dart';
import 'package:gochano/core/design_system/components/app_page_background.dart';
import 'package:gochano/core/localization/gochano_language.dart';
import 'package:gochano/core/settings/gochano_app_mode.dart';
import 'package:gochano/features/home/presentation/home_screen.dart';
import 'package:gochano/features/notifications/presentation/notification_center_screen.dart';
import 'package:gochano/features/search/presentation/universal_search_screen.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

List<Widget> _cardsForMode(HomeScreen home, GochanoAppMode mode) {
  final element = home.createElement();
  return home.buildModeCards(element, mode);
}

Widget _wrap(
  Widget child, {
  ThemeMode themeMode = ThemeMode.light,
  Size size = const Size(390, 844),
  double textScaleFactor = 1.0,
  bool disableAnimations = false,
}) {
  return MediaQuery(
    data: MediaQueryData(
      size: size,
      textScaler: TextScaler.linear(textScaleFactor),
      disableAnimations: disableAnimations,
    ),
    child: MaterialApp(
      theme: GochanoTheme.light(),
      darkTheme: GochanoTheme.dark(),
      themeMode: themeMode,
      home: child,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String source;

  setUpAll(() {
    source = _read('lib/features/home/presentation/home_screen.dart');
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GochanoAppModePreferences.current.value = GochanoAppMode.utility;
    GochanoLanguage.current.value = GochanoLocale.english;
  });

  tearDown(() {
    GochanoAppModePreferences.current.value = GochanoAppMode.study;
    GochanoLanguage.current.value = GochanoLocale.english;
  });

  group('1. Utility Home Source Integrity & Design Tokens', () {
    test('HomeScreen body uses AppPageBackground with adaptive gradient', () {
      expect(source, contains('AppPageBackground('));
      expect(source, contains('AppGradients.todayAppBarFor('));
      expect(source, contains('height: 260'));
    });

    test('_AccentRailCard uses Material InkWell and border styling', () {
      expect(source, contains('class _AccentRailCard extends StatelessWidget'));
      expect(source, contains('InkWell('));
      expect(source, contains('Ink('));
      expect(source, contains('accent.withValues(alpha:'));
    });

    test('_CommuteCard uses colored badge container and honest labelling', () {
      expect(source, contains('class _CommuteCard extends StatelessWidget'));
      expect(source, contains('colors.commute.withValues(alpha: 0.12)'));
      expect(source, contains('Icons.directions_transit_rounded'));
    });

    test('_MoneyCard uses colored badge container and chevron indicator', () {
      expect(source, contains('class _MoneyCard extends StatefulWidget'));
      expect(source, contains('colors.expense.withValues(alpha: 0.12)'));
      expect(source, contains('Icons.account_balance_wallet_rounded'));
    });

    test('_MoneyRow uses soft pill container styling', () {
      expect(source, contains('class _MoneyRow extends StatelessWidget'));
      expect(source, contains('color.withValues(alpha: 0.06)'));
      expect(source, contains('color.withValues(alpha: 0.14)'));
    });
  });

  group('2. Utility Home Mode Cards Composition', () {
    testWidgets('Utility mode produces exactly 5 items (Sync, SizedBox, Commute, SizedBox, Money)', (
      tester,
    ) async {
      final home = HomeScreen(
        role: 'student',
        displayName: 'Test Student',
        onOpenDestination: (_) {},
        onOpenProfile: () {},
      );

      final cards = _cardsForMode(home, GochanoAppMode.utility);

      expect(cards.length, equals(5));
      final types = cards.map((w) => w.runtimeType.toString()).toList();
      expect(types[0], equals('SyncStatusIndicator'));
      expect(types[1], equals('SizedBox'));
      expect(types[2], equals('_CommuteCard'));
      expect(types[3], equals('SizedBox'));
      expect(types[4], equals('_MoneyCard'));
    });

    testWidgets('Non-student mode preserves 9 items (Sync, Tasks, Medicine, Commute, Money)', (
      tester,
    ) async {
      final home = HomeScreen(
        role: 'general',
        displayName: 'General User',
        onOpenDestination: (_) {},
        onOpenProfile: () {},
      );

      final cards = _cardsForMode(home, GochanoAppMode.utility);

      expect(cards.length, equals(9));
      final types = cards.map((w) => w.runtimeType.toString()).toList();
      expect(types, contains('_TodaysTasksCard'));
      expect(types, contains('_MedicineScheduleCard'));
      expect(types, contains('_CommuteCard'));
      expect(types, contains('_MoneyCard'));
      expect(types, isNot(contains('_StudyProgressCard')));
      expect(types, isNot(contains('_RecentMaterialsCard')));
    });
  });

  group('3. Utility Home Widget Rendering & Interaction', () {
    testWidgets('renders Commute and Money cards in Utility Mode (English)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          HomeScreen(
            role: 'student',
            displayName: 'Ayesha Rahman',
            onOpenDestination: (_) {},
            onOpenProfile: () {},
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Commute'), findsOneWidget);
      expect(find.text('Plan a trip'), findsOneWidget);
      expect(find.text('Money'), findsOneWidget);
      expect(find.byType(AppPageBackground), findsOneWidget);
    });

    testWidgets('renders Commute and Money cards in Utility Mode (Bengali)', (
      tester,
    ) async {
      GochanoLanguage.current.value = GochanoLocale.bangla;

      await tester.pumpWidget(
        _wrap(
          HomeScreen(
            role: 'student',
            displayName: 'আয়েশা রহমান',
            onOpenDestination: (_) {},
            onOpenProfile: () {},
          ),
        ),
      );
      await tester.pump();

      expect(find.text('যাতায়াত'), findsOneWidget);
      expect(find.text('একটি যাত্রা পরিকল্পনা করুন'), findsOneWidget);
      expect(find.text('টাকা'), findsOneWidget);
    });

    testWidgets('tapping Commute card calls onOpenDestination with index 2', (
      tester,
    ) async {
      int? targetDestination;
      await tester.pumpWidget(
        _wrap(
          HomeScreen(
            role: 'student',
            displayName: 'Ayesha Rahman',
            onOpenDestination: (idx) => targetDestination = idx,
            onOpenProfile: () {},
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Commute'));
      await tester.pump();

      expect(targetDestination, equals(2));
    });

    testWidgets('tapping Money card calls onOpenDestination with index 3', (
      tester,
    ) async {
      int? targetDestination;
      await tester.pumpWidget(
        _wrap(
          HomeScreen(
            role: 'student',
            displayName: 'Ayesha Rahman',
            onOpenDestination: (idx) => targetDestination = idx,
            onOpenProfile: () {},
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Money'));
      await tester.pump();

      expect(targetDestination, equals(3));
    });

    testWidgets('tapping Profile action in AppBar triggers onOpenProfile', (
      tester,
    ) async {
      var profileOpened = false;
      await tester.pumpWidget(
        _wrap(
          HomeScreen(
            role: 'student',
            displayName: 'Ayesha Rahman',
            onOpenDestination: (_) {},
            onOpenProfile: () => profileOpened = true,
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.account_circle_outlined));
      await tester.pump();

      expect(profileOpened, isTrue);
    });

    testWidgets('tapping search button pushes UniversalSearchScreen', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          HomeScreen(
            role: 'student',
            displayName: 'Ayesha Rahman',
            onOpenDestination: (_) {},
            onOpenProfile: () {},
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pumpAndSettle();

      expect(find.byType(UniversalSearchScreen), findsOneWidget);
    });

    testWidgets('tapping notification bell pushes NotificationCenterScreen', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          HomeScreen(
            role: 'student',
            displayName: 'Ayesha Rahman',
            onOpenDestination: (_) {},
            onOpenProfile: () {},
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.notifications_outlined));
      await tester.pumpAndSettle();

      expect(find.byType(NotificationCenterScreen), findsOneWidget);
    });
  });

  group('4. Theme, Responsiveness & Accessibility', () {
    testWidgets('renders cleanly in Dark Mode with dark theme background', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          HomeScreen(
            role: 'student',
            displayName: 'Ayesha Rahman',
            onOpenDestination: (_) {},
            onOpenProfile: () {},
          ),
          themeMode: ThemeMode.dark,
        ),
      );
      await tester.pump();

      expect(find.text('Commute'), findsOneWidget);
      expect(find.text('Money'), findsOneWidget);
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('renders without overflow on narrow 320dp width', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          HomeScreen(
            role: 'student',
            displayName: 'Ayesha Rahman',
            onOpenDestination: (_) {},
            onOpenProfile: () {},
          ),
          size: const Size(320, 640),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Commute'), findsOneWidget);
      expect(find.text('Money'), findsOneWidget);
    });

    testWidgets('renders cleanly on 360dp, 390dp, and 412dp widths', (
      tester,
    ) async {
      for (final width in [360.0, 390.0, 412.0]) {
        await tester.pumpWidget(
          _wrap(
            HomeScreen(
              role: 'student',
              displayName: 'Ayesha Rahman',
              onOpenDestination: (_) {},
              onOpenProfile: () {},
            ),
            size: Size(width, 800),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.text('Commute'), findsOneWidget);
        expect(find.text('Money'), findsOneWidget);
      }
    });

    testWidgets('renders with 2.0x font scaling without layout exceptions', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          HomeScreen(
            role: 'student',
            displayName: 'Ayesha Rahman',
            onOpenDestination: (_) {},
            onOpenProfile: () {},
          ),
          textScaleFactor: 2.0,
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Commute'), findsOneWidget);
      expect(find.text('Money'), findsOneWidget);
    });

    testWidgets('respects reduced-motion setting without errors', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          HomeScreen(
            role: 'student',
            displayName: 'Ayesha Rahman',
            onOpenDestination: (_) {},
            onOpenProfile: () {},
          ),
          disableAnimations: true,
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Commute'), findsOneWidget);
      expect(find.text('Money'), findsOneWidget);
    });
  });
}
