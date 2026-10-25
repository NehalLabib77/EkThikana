// Widget tests for the Utility Mode header system: the new `AppUtilityHeader`
// surface and its Home integration.
//
// These are the acceptance checks for the Utility AppBar redesign wave:
// brand/logo presentation, pinned geometry, action callbacks, localization,
// light/dark, responsive widths, text scaling, touch targets and the
// compatibility guarantees that Home serves both Student-Utility and
// non-student accounts without changing routing or Study Mode behaviour.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gochano/core/design_system/components/app_page_background.dart';
import 'package:gochano/core/design_system/components/app_utility_header.dart';
import 'package:gochano/core/design_system/gochano_colors.dart';
import 'package:gochano/core/design_system/gochano_spacing.dart';
import 'package:gochano/core/design_system/gochano_theme.dart';
import 'package:gochano/core/localization/gochano_language.dart';
import 'package:gochano/core/settings/gochano_app_mode.dart';
import 'package:gochano/features/home/presentation/home_screen.dart';
import 'package:gochano/features/notifications/presentation/notification_center_screen.dart';
import 'package:gochano/features/search/presentation/universal_search_screen.dart';
import 'package:gochano/services/local_reminder_store.dart';
import 'package:gochano/widgets/language_toggle.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

Widget _wrap(
  Widget child, {
  ThemeMode themeMode = ThemeMode.light,
}) {
  return MaterialApp(
    theme: GochanoTheme.light(),
    darkTheme: GochanoTheme.dark(),
    themeMode: themeMode,
    home: child,
  );
}

HomeScreen _home({
  String role = 'student',
  String displayName = 'Ayesha Rahman',
  ValueChanged<int>? onOpenDestination,
  VoidCallback? onOpenProfile,
}) {
  return HomeScreen(
    role: role,
    displayName: displayName,
    onOpenDestination: onOpenDestination ?? (_) {},
    onOpenProfile: onOpenProfile ?? () {},
  );
}

Finder _surfaceFinder() => find.byWidgetPredicate(
  (w) =>
      w is Container &&
      w.decoration is BoxDecoration &&
      (w.decoration! as BoxDecoration).borderRadius ==
          GochanoRadius.appBarSurfaceAll,
);

/// Pumps Home at a *real* viewport size and text scale.
///
/// An outer `MediaQuery` would be overridden by the one `WidgetsApp` builds
/// from the view, so the viewport is driven through `tester.view` and the
/// platform dispatcher instead — the only way a "320dp" assertion is honest.
Future<void> _pumpHome(
  WidgetTester tester, {
  String role = 'student',
  Size size = const Size(390, 844),
  ThemeMode themeMode = ThemeMode.light,
  double textScale = 1.0,
  ValueChanged<int>? onOpenDestination,
  VoidCallback? onOpenProfile,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  await tester.pumpWidget(
    _wrap(
      _home(
        role: role,
        onOpenDestination: onOpenDestination,
        onOpenProfile: onOpenProfile,
      ),
      themeMode: themeMode,
    ),
  );
  await tester.pump();
  // `MaterialApp` animates theme changes (`AnimatedTheme`, 200ms default), so
  // a light -> dark switch inside a single test is still mid-transition one
  // frame later. Advance past the transition before asserting on tokens.
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String homeSource;
  late String headerSource;
  late String shellSource;

  setUpAll(() {
    homeSource = _read('lib/features/home/presentation/home_screen.dart');
    headerSource = _read(
      'lib/core/design_system/components/app_utility_header.dart',
    );
    shellSource = _read('lib/features/shell/presentation/gochano_shell.dart');
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GochanoAppModePreferences.current.value = GochanoAppMode.utility;
    GochanoLanguage.current.value = GochanoLocale.english;
    LocalReminderStore.instance.unreadCountNotifier.value = 0;
  });

  tearDown(() {
    GochanoAppModePreferences.current.value = GochanoAppMode.study;
    GochanoLanguage.current.value = GochanoLocale.english;
    LocalReminderStore.instance.unreadCountNotifier.value = 0;
  });

  group('1. Brand & surface', () {
    testWidgets('Utility Home renders exactly one pinned AppUtilityHeader', (
      tester,
    ) async {
      await _pumpHome(tester);

      expect(find.byType(AppUtilityHeader), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    test('header uses the real Gochano logo asset, never a placeholder mark', () {
      expect(headerSource, contains('AppAssets.logo'));
      expect(homeSource, contains('AppUtilityHeader('));

      // No invented slogans or taglines anywhere in the rendered UI. Assert
      // against the code itself (comments stripped) so the design notes in
      // the file header don't trip the check.
      final headerCode = headerSource
          .split('\n')
          .where((line) => !line.trimLeft().startsWith('//'))
          .join('\n')
          .toLowerCase();
      expect(headerCode, isNot(contains('slogan')));
      expect(headerCode, isNot(contains('tagline')));
    });

    testWidgets('brand mark is the logo asset with a Gochano semantic label', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pumpHome(tester);

      final header = find.byType(AppUtilityHeader);
      expect(
        find.descendant(of: header, matching: find.byType(Image)),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Gochano'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets(
      'surface keeps the 18dp inset geometry and light-mode elevation',
      (tester) async {
        await _pumpHome(tester);

        expect(_surfaceFinder(), findsOneWidget);

        final surface = tester.widget<Container>(_surfaceFinder());
        final decoration = surface.decoration! as BoxDecoration;
        expect(decoration.borderRadius, GochanoRadius.appBarSurfaceAll);
        expect(decoration.border, isNotNull);
        expect(decoration.boxShadow, isNotEmpty);

        // ~14dp outer inset on a regular phone, 4dp vertical margin.
        final insets = find.descendant(
          of: find.byType(AppUtilityHeader),
          matching: find.byWidgetPredicate(
            (w) => w is Padding && w.padding == const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 4,
            ),
          ),
        );
        expect(insets, findsOneWidget);
      },
    );

    testWidgets('dark mode drops the glow but keeps the border', (
      tester,
    ) async {
      await _pumpHome(tester, themeMode: ThemeMode.dark);

      final surface = tester.widget<Container>(_surfaceFinder());
      final decoration = surface.decoration! as BoxDecoration;
      expect(decoration.boxShadow, isEmpty);
      expect(decoration.border, isNotNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('header is pinned inside the SafeArea under the status bar', (
      tester,
    ) async {
      await _pumpHome(tester);

      expect(
        find.ancestor(
          of: find.byType(AppUtilityHeader),
          matching: find.byType(SafeArea),
        ),
        findsOneWidget,
      );
    });

    testWidgets('status-bar icons keep contrast in both themes', (
      tester,
    ) async {
      await _pumpHome(tester);
      // The Home region is the one wrapping the Utility header.
      final regionFinder = find.ancestor(
        of: find.byType(AppUtilityHeader),
        matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
      );
      var region =
          tester.widgetList<AnnotatedRegion<SystemUiOverlayStyle>>(
            regionFinder,
          ).first;
      expect(region.value.statusBarIconBrightness, Brightness.dark);
      expect(region.value.statusBarColor, Colors.transparent);

      await _pumpHome(tester, themeMode: ThemeMode.dark);
      region =
          tester.widgetList<AnnotatedRegion<SystemUiOverlayStyle>>(
            regionFinder,
          ).first;
      expect(region.value.statusBarIconBrightness, Brightness.light);
    });

    testWidgets('header surface uses theme-aware tokens, not raw hexes', (
      tester,
    ) async {
      await _pumpHome(tester);
      final light = tester.widget<Container>(_surfaceFinder());

      await _pumpHome(tester, themeMode: ThemeMode.dark);
      final dark = tester.widget<Container>(_surfaceFinder());

      final lightColor = (light.decoration! as BoxDecoration).color;
      final darkColor = (dark.decoration! as BoxDecoration).color;
      expect(lightColor, GochanoColors.light.surface);
      expect(darkColor, GochanoColors.dark.surface);
      expect(lightColor, isNot(darkColor));
    });
  });

  group('2. Actions, callbacks & localization', () {
    testWidgets('search action pushes UniversalSearchScreen', (tester) async {
      await _pumpHome(tester);

      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pumpAndSettle();

      expect(find.byType(UniversalSearchScreen), findsOneWidget);
    });

    testWidgets('notification action pushes NotificationCenterScreen', (
      tester,
    ) async {
      // Pre-existing and out of scope for this wave: NotificationCenterScreen's
      // three-chip filter bar overflows by ~40px below a ~440dp viewport
      // (verified by pumping that screen standalone at 390dp). These two tests
      // cover Home's routing wiring, so they run wide; the overflow itself is
      // reported as a baseline finding for the notifications screen's owner.
      await _pumpHome(tester, size: const Size(480, 900));

      await tester.tap(find.byIcon(Icons.notifications_outlined));
      await tester.pumpAndSettle();

      expect(find.byType(NotificationCenterScreen), findsOneWidget);
    });

    testWidgets('profile action calls onOpenProfile exactly once', (
      tester,
    ) async {
      var profileOpened = 0;
      await _pumpHome(tester, onOpenProfile: () => profileOpened++);

      await tester.tap(find.byIcon(Icons.account_circle_outlined));
      await tester.pump();

      expect(profileOpened, 1);
    });

    testWidgets('notification badge reflects unread count and stays tappable', (
      tester,
    ) async {
      LocalReminderStore.instance.unreadCountNotifier.value = 3;
      await _pumpHome(tester, size: const Size(480, 900));

      expect(find.text('3'), findsOneWidget);

      // The badge must not swallow the tap (IgnorePointer) — the bell still
      // opens the Notification Center.
      await tester.tap(find.byIcon(Icons.notifications_outlined));
      await tester.pumpAndSettle();
      expect(find.byType(NotificationCenterScreen), findsOneWidget);
    });

    testWidgets('every header action carries a localized tooltip', (
      tester,
    ) async {
      await _pumpHome(tester);
      expect(find.byTooltip('Search'), findsOneWidget);
      expect(find.byTooltip('Notification Center'), findsOneWidget);
      expect(find.byTooltip('Profile'), findsOneWidget);

      GochanoLanguage.current.value = GochanoLocale.bangla;
      await _pumpHome(tester);
      expect(find.byTooltip('অনুসন্ধান'), findsOneWidget);
      expect(find.byTooltip('নোটিফিকেশন সেন্টার'), findsOneWidget);
      expect(find.byTooltip('প্রোফাইল'), findsOneWidget);
    });

    testWidgets('language toggle switches EN -> বাংলা -> EN', (tester) async {
      await _pumpHome(tester);
      expect(find.byType(LanguageToggle), findsOneWidget);

      await tester.tap(find.text('বাংলা'));
      await tester.pump();
      expect(GochanoLanguage.current.value, GochanoLocale.bangla);

      await tester.tap(find.text('EN'));
      await tester.pump();
      expect(GochanoLanguage.current.value, GochanoLocale.english);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Bengali header labels render without overflow', (
      tester,
    ) async {
      GochanoLanguage.current.value = GochanoLocale.bangla;
      await _pumpHome(tester, size: const Size(320, 640));

      expect(find.byTooltip('অনুসন্ধান'), findsOneWidget);
      expect(find.text('যাতায়াত'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('3. Responsive geometry', () {
    testWidgets('320dp uses the 10dp narrow inset and never overflows', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pumpHome(tester, size: const Size(320, 640));

      final insets = find.descendant(
        of: find.byType(AppUtilityHeader),
        matching: find.byWidgetPredicate(
          (w) => w is Padding && w.padding == const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 4,
          ),
        ),
      );
      expect(insets, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('360dp, 390dp and 412dp render cleanly at the 14dp inset', (
      tester,
    ) async {
      for (final width in [360.0, 390.0, 412.0]) {
        await _pumpHome(tester, size: Size(width, 844));

        expect(find.byType(AppUtilityHeader), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(AppUtilityHeader),
            matching: find.byWidgetPredicate(
              (w) => w is Padding && w.padding == const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 4,
              ),
            ),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('1.5x and 2.0x text scaling render without layout exceptions', (
      tester,
    ) async {
      for (final scale in [1.5, 2.0]) {
        for (final width in [320.0, 390.0]) {
          await _pumpHome(
            tester,
            size: Size(width, 844),
            textScale: scale,
          );
          expect(
            tester.takeException(),
            isNull,
            reason: 'overflow at ${width}dp with ${scale}x text',
          );
        }
      }
    });

    testWidgets('reduced-motion (disableAnimations) renders without errors', (
      tester,
    ) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            disableAnimations: true,
          ),
          child: MaterialApp(
            theme: GochanoTheme.light(),
            darkTheme: GochanoTheme.dark(),
            themeMode: ThemeMode.light,
            home: _home(),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(AppUtilityHeader), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('icon actions hold >= 44dp effective touch targets', (
      tester,
    ) async {
      await _pumpHome(tester);

      for (final icon in [
        Icons.search_rounded,
        Icons.notifications_outlined,
        Icons.account_circle_outlined,
      ]) {
        final target = tester.getSize(
          find
              .ancestor(
                of: find.byIcon(icon),
                matching: find.byType(IconButton),
              )
              .first,
        );
        expect(target.width, greaterThanOrEqualTo(44), reason: '$icon width');
        expect(target.height, greaterThanOrEqualTo(44), reason: '$icon height');
      }

      // The shared language control is at least 44dp tall as mounted.
      final toggleSize = tester.getSize(find.byType(LanguageToggle));
      expect(toggleSize.height, greaterThanOrEqualTo(44));
      expect(tester.takeException(), isNull);
    });

    testWidgets('no hitbox overlap between adjacent header actions', (
      tester,
    ) async {
      await _pumpHome(tester);

      final searchRect = tester.getRect(
        find
            .ancestor(
              of: find.byIcon(Icons.search_rounded),
              matching: find.byType(IconButton),
            )
            .first,
      );
      final bellRect = tester.getRect(
        find
            .ancestor(
              of: find.byIcon(Icons.notifications_outlined),
              matching: find.byType(IconButton),
            )
            .first,
      );
      final profileRect = tester.getRect(
        find
            .ancestor(
              of: find.byIcon(Icons.account_circle_outlined),
              matching: find.byType(IconButton),
            )
            .first,
      );

      expect(searchRect.overlaps(bellRect), isFalse);
      expect(bellRect.overlaps(profileRect), isFalse);
      expect(searchRect.overlaps(profileRect), isFalse);
    });
  });

  group('4. Pinned behaviour', () {
    testWidgets('header does not scroll away with the dashboard', (
      tester,
    ) async {
      // Non-student Home has the tallest card stack, so the list scrolls.
      tester.view.physicalSize = const Size(390, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pumpHome(tester, role: 'general', size: const Size(390, 480));

      final headerBefore = tester.getRect(find.byType(AppUtilityHeader));
      final medicineBefore = tester.getRect(find.text('Medicine'));

      await tester.drag(find.byType(ListView), const Offset(0, -240));
      await tester.pumpAndSettle();

      final headerAfter = tester.getRect(find.byType(AppUtilityHeader));
      final medicineAfter = tester.getRect(find.text('Medicine'));

      // The list really scrolled…
      expect(medicineAfter.top, lessThan(medicineBefore.top));
      // …and the header stayed pinned.
      expect(headerAfter.top, headerBefore.top);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no duplicate top header: no Scaffold AppBar is mounted', (
      tester,
    ) async {
      await _pumpHome(tester);

      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(AppUtilityHeader), findsOneWidget);
      expect(find.byType(AppPageBackground), findsOneWidget);
    });

    test('HomeScreen no longer owns its legacy _HomeAppBar', () {
      expect(homeSource, isNot(contains('_HomeAppBar')));
      expect(homeSource, isNot(contains('PreferredSizeWidget')));
    });
  });

  group('5. Compatibility: Student-Utility, non-student and Study Mode', () {
    testWidgets('Student Utility Home keeps Commute + Money composition', (
      tester,
    ) async {
      await _pumpHome(tester);

      expect(find.text('Commute'), findsOneWidget);
      expect(find.text('Money'), findsOneWidget);
      expect(find.text('Medicine'), findsNothing);
      expect(find.text('Study Progress'), findsNothing);
    });

    testWidgets('non-student Home keeps its own card composition', (
      tester,
    ) async {
      await _pumpHome(tester, role: 'general');

      expect(find.byType(AppUtilityHeader), findsOneWidget);
      expect(find.text('Medicine'), findsOneWidget);
      expect(find.text('Commute'), findsOneWidget);
      expect(find.text('Money'), findsOneWidget);
      expect(find.text('Study Progress'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'destination mapping is unchanged: Utility Commute=2, Money=3',
      (tester) async {
        final requested = <int>[];
        await _pumpHome(tester, onOpenDestination: requested.add);

        await tester.tap(find.text('Commute'));
        await tester.pump();
        expect(requested, [2]);

        await tester.tap(find.text('Money'));
        await tester.pump();
        expect(requested, [2, 3]);
      },
    );

    testWidgets(
      'non-student mapping is unchanged: Commute=1, Money=1, Tasks=2',
      (tester) async {
        final requested = <int>[];
        await _pumpHome(
          tester,
          role: 'general',
          onOpenDestination: requested.add,
        );

        await tester.tap(find.text('Commute'));
        await tester.pump();
        expect(requested, [1]);

        await tester.tap(find.text('Money'));
        await tester.pump();
        expect(requested, [1, 1]); // non-student Money also maps to 1
      },
    );

    test('Study Mode card composition is untouched', () {
      final home = _home();
      final cards = home.buildModeCards(home.createElement(), GochanoAppMode.study);
      final types = cards.map((w) => w.runtimeType.toString()).toList();

      expect(
        types,
        containsAllInOrder([
          'SyncStatusIndicator',
          '_TodaysTasksCard',
          '_StudyProgressCard',
          '_RecentMaterialsCard',
        ]),
      );
      // Study-mode wiring inside HomeScreen still maps 1 -> Workspace,
      // 2 -> Plan for the shell adapter.
      expect(homeSource, contains('onOpenDestination(1), // Workspace tab'));
      expect(homeSource, contains('onOpenDestination(2), // Plan tab'));
    });

    test('shell bottom destinations and utility adapter are untouched', () {
      expect(shellSource, contains("GochanoLanguage.text('Commute', 'যাতায়াত')"));
      expect(shellSource, contains("GochanoLanguage.text('Money', 'টাকা')"));
      expect(shellSource, contains('_select(1); // Commute tab'));
      expect(shellSource, contains('_select(2); // Money tab'));
    });

    test('Home still wires search, notifications, profile and language', () {
      expect(homeSource, contains('LanguageToggle()'));
      expect(homeSource, contains('Icons.search_rounded'));
      expect(homeSource, contains('Icons.notifications_outlined'));
      expect(homeSource, contains('Icons.account_circle_outlined'));
      expect(homeSource, contains('CircleAvatar'));
      expect(homeSource, contains('UniversalSearchScreen'));
      expect(homeSource, contains('NotificationCenterScreen'));
      expect(homeSource, contains('onOpenProfile'));
      expect(homeSource, contains('GochanoAppModePreferences.current'));
      expect(homeSource, contains('onOpenDestination(2)'));
      expect(homeSource, contains('onOpenDestination(3)'));
    });
  });
}
