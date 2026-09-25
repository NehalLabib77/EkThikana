import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gochano/core/design_system/gochano_theme.dart';
import 'package:gochano/core/localization/gochano_language.dart';
import 'package:gochano/core/settings/gochano_app_mode.dart';
import 'package:gochano/features/profile/presentation/app_mode_selector_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GochanoAppModePreferences.current.value = GochanoAppMode.study;
    GochanoLanguage.current.value = GochanoLocale.english;
  });

  tearDown(() {
    GochanoAppModePreferences.current.value = GochanoAppMode.study;
    GochanoLanguage.current.value = GochanoLocale.english;
  });

  group('ProfileScreen App Mode Integration Source Guards', () {
    final profileSource = File(
      'lib/features/profile/presentation/profile_screen.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    test(
      'ProfileScreen integrates App mode setting row and reactive builder',
      () {
        expect(
          profileSource,
          contains("GochanoLanguage.text('App mode', 'অ্যাপ মোড')"),
        );
        expect(
          profileSource,
          contains('ValueListenableBuilder<GochanoAppMode>'),
        );
        expect(profileSource, contains('showAppModeSelectorSheet(context)'));
        expect(profileSource, contains("'Study Mode'"));
        expect(profileSource, contains("'স্টাডি মোড'"));
        expect(profileSource, contains("'Utility Mode'"));
        expect(profileSource, contains("'ইউটিলিটি মোড'"));
      },
    );
  });

  Widget buildTestHost({VoidCallback? onOpen}) {
    return MaterialApp(
      theme: GochanoTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) {
            return Center(
              child: ElevatedButton(
                key: const ValueKey('open_sheet_button'),
                onPressed: () {
                  showAppModeSelectorSheet(context);
                  onOpen?.call();
                },
                child: const Text('Open Sheet'),
              ),
            );
          },
        ),
      ),
    );
  }

  group('AppModeSelectorSheet Widget Tests', () {
    testWidgets('selector opens and displays title and both mode choices', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestHost());

      await tester.tap(find.byKey(const ValueKey('open_sheet_button')));
      await tester.pumpAndSettle();

      expect(find.text('App Mode'), findsOneWidget);
      expect(
        find.text('Choose how Gochano is organized for you.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('app_mode_study_card')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('app_mode_utility_card')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('save_app_mode_button')),
        findsOneWidget,
      );
    });

    testWidgets('initial staged selection matches current preference (Study)', (
      tester,
    ) async {
      GochanoAppModePreferences.current.value = GochanoAppMode.study;
      await tester.pumpWidget(buildTestHost());

      await tester.tap(find.byKey(const ValueKey('open_sheet_button')));
      await tester.pumpAndSettle();

      final studyCard = tester.widget<ModeCard>(
        find.byKey(const ValueKey('app_mode_study_card')),
      );
      expect(studyCard.isSelected, isTrue);

      final utilityCard = tester.widget<ModeCard>(
        find.byKey(const ValueKey('app_mode_utility_card')),
      );
      expect(utilityCard.isSelected, isFalse);
    });

    testWidgets(
      'tapping Utility stages the selection without immediate persistence',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          GochanoAppModePreferences.prefsKey: 'study',
        });
        GochanoAppModePreferences.current.value = GochanoAppMode.study;

        await tester.pumpWidget(buildTestHost());
        await tester.tap(find.byKey(const ValueKey('open_sheet_button')));
        await tester.pumpAndSettle();

        // Tap Utility card
        await tester.tap(find.byKey(const ValueKey('app_mode_utility_card')));
        await tester.pumpAndSettle();

        // Only one mode is selected in staged UI
        final studyCard = tester.widget<ModeCard>(
          find.byKey(const ValueKey('app_mode_study_card')),
        );
        expect(studyCard.isSelected, isFalse);

        final utilityCard = tester.widget<ModeCard>(
          find.byKey(const ValueKey('app_mode_utility_card')),
        );
        expect(utilityCard.isSelected, isTrue);

        // BUT underlying preference is NOT changed yet
        expect(
          GochanoAppModePreferences.current.value,
          equals(GochanoAppMode.study),
        );
        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getString(GochanoAppModePreferences.prefsKey),
          equals('study'),
        );
      },
    );

    testWidgets(
      'tapping Save Mode persists the staged selection and closes the sheet',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          GochanoAppModePreferences.prefsKey: 'study',
        });
        GochanoAppModePreferences.current.value = GochanoAppMode.study;

        await tester.pumpWidget(buildTestHost());
        await tester.tap(find.byKey(const ValueKey('open_sheet_button')));
        await tester.pumpAndSettle();

        // Select Utility
        await tester.tap(find.byKey(const ValueKey('app_mode_utility_card')));
        await tester.pumpAndSettle();

        // Tap Save Mode
        await tester.tap(find.byKey(const ValueKey('save_app_mode_button')));
        await tester.pumpAndSettle();

        // Sheet is closed
        expect(find.byType(AppModeSelectorSheet), findsNothing);

        // Preference is updated & persisted
        expect(
          GochanoAppModePreferences.current.value,
          equals(GochanoAppMode.utility),
        );
        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getString(GochanoAppModePreferences.prefsKey),
          equals('utility'),
        );
      },
    );

    testWidgets('dismissing without Save retains original preference', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        GochanoAppModePreferences.prefsKey: 'study',
      });
      GochanoAppModePreferences.current.value = GochanoAppMode.study;

      await tester.pumpWidget(buildTestHost());
      await tester.tap(find.byKey(const ValueKey('open_sheet_button')));
      await tester.pumpAndSettle();

      // Select Utility
      await tester.tap(find.byKey(const ValueKey('app_mode_utility_card')));
      await tester.pumpAndSettle();

      // Dismiss sheet by tapping outside
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      // Sheet is closed
      expect(find.byType(AppModeSelectorSheet), findsNothing);

      // Preference is still Study
      expect(
        GochanoAppModePreferences.current.value,
        equals(GochanoAppMode.study),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(GochanoAppModePreferences.prefsKey),
        equals('study'),
      );
    });

    testWidgets('renders properly in Bangla without overflow', (tester) async {
      GochanoLanguage.current.value = GochanoLocale.bangla;

      await tester.pumpWidget(buildTestHost());
      await tester.tap(find.byKey(const ValueKey('open_sheet_button')));
      await tester.pumpAndSettle();

      expect(find.text('অ্যাপ মোড'), findsOneWidget);
      expect(find.text('আপনার পছন্দ অনুযায়ী গোছানো সাজান।'), findsOneWidget);
      expect(find.text('স্টাডি মোড'), findsOneWidget);
      expect(find.text('ইউটিলিটি মোড'), findsOneWidget);
      expect(find.text('মোড সংরক্ষণ করুন'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });
  });
}
