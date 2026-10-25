// Unit & widget tests for LanguageToggle accessibility, touch targets, and reactivity.
//
// Verifies:
// 1. Each segment (EN & বাংলা) has >= 44x44dp effective tappable region.
// 2. No hitbox overlap between adjacent segments.
// 3. Compact mode (isCompact: true) preserves >= 44x44dp targets while maintaining compact visual bounds.
// 4. Normal mode (isCompact: false) preserves >= 44x44dp targets.
// 5. Tapping EN switches locale to English.
// 6. Tapping বাংলা switches locale to Bangla.
// 7. Visual selection state reflects GochanoLanguage.current updates.
// 8. Tooltips and Semantics labels are localized and accessible.
// 9. Light and dark theme rendering integrity.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gochano/core/design_system/gochano_theme.dart';
import 'package:gochano/core/localization/gochano_language.dart';
import 'package:gochano/widgets/language_toggle.dart';

Widget _wrapToggle({
  bool isCompact = false,
  ThemeMode themeMode = ThemeMode.light,
  double textScale = 1.0,
}) {
  return MaterialApp(
    theme: GochanoTheme.light(),
    darkTheme: GochanoTheme.dark(),
    themeMode: themeMode,
    home: Scaffold(
      body: Center(
        child: MediaQuery(
          data: MediaQueryData(
            textScaler: TextScaler.linear(textScale),
          ),
          child: LanguageToggle(isCompact: isCompact),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() {
    GochanoLanguage.current.value = GochanoLocale.english;
  });

  tearDown(() {
    GochanoLanguage.current.value = GochanoLocale.english;
  });

  group('LanguageToggle Hit Target Geometry & Accessibility', () {
    testWidgets(
      'each segment has minimum 44x44dp effective touch target in compact mode',
      (tester) async {
        await tester.pumpWidget(_wrapToggle(isCompact: true));
        await tester.pumpAndSettle();

        final enText = find.text('EN');
        final bnText = find.text('বাংলা');
        expect(enText, findsOneWidget);
        expect(bnText, findsOneWidget);

        final enInkWell = find.ancestor(of: enText, matching: find.byType(InkWell));
        final bnInkWell = find.ancestor(of: bnText, matching: find.byType(InkWell));
        expect(enInkWell, findsOneWidget);
        expect(bnInkWell, findsOneWidget);

        final enSize = tester.getSize(enInkWell);
        final bnSize = tester.getSize(bnInkWell);

        expect(
          enSize.width,
          greaterThanOrEqualTo(44.0),
          reason: 'EN segment hit target width should be at least 44dp',
        );
        expect(
          enSize.height,
          greaterThanOrEqualTo(44.0),
          reason: 'EN segment hit target height should be at least 44dp',
        );

        expect(
          bnSize.width,
          greaterThanOrEqualTo(44.0),
          reason: 'বাংলা segment hit target width should be at least 44dp',
        );
        expect(
          bnSize.height,
          greaterThanOrEqualTo(44.0),
          reason: 'বাংলা segment hit target height should be at least 44dp',
        );
      },
    );

    testWidgets(
      'each segment has minimum 44x44dp effective touch target in normal mode',
      (tester) async {
        await tester.pumpWidget(_wrapToggle(isCompact: false));
        await tester.pumpAndSettle();

        final enInkWell = find.ancestor(
          of: find.text('EN'),
          matching: find.byType(InkWell),
        );
        final bnInkWell = find.ancestor(
          of: find.text('বাংলা'),
          matching: find.byType(InkWell),
        );

        final enSize = tester.getSize(enInkWell);
        final bnSize = tester.getSize(bnInkWell);

        expect(enSize.width, greaterThanOrEqualTo(44.0));
        expect(enSize.height, greaterThanOrEqualTo(44.0));
        expect(bnSize.width, greaterThanOrEqualTo(44.0));
        expect(bnSize.height, greaterThanOrEqualTo(44.0));
      },
    );

    testWidgets(
      'no hitbox overlap between adjacent segments in compact mode',
      (tester) async {
        await tester.pumpWidget(_wrapToggle(isCompact: true));
        await tester.pumpAndSettle();

        final enInkWell = find.ancestor(
          of: find.text('EN'),
          matching: find.byType(InkWell),
        );
        final bnInkWell = find.ancestor(
          of: find.text('বাংলা'),
          matching: find.byType(InkWell),
        );

        final enRect = tester.getRect(enInkWell);
        final bnRect = tester.getRect(bnInkWell);

        expect(
          enRect.overlaps(bnRect),
          isFalse,
          reason: 'EN and বাংলা hit targets must not overlap each other',
        );
        expect(enRect.right, lessThanOrEqualTo(bnRect.left));
      },
    );

    testWidgets(
      'no hitbox overlap between adjacent segments in normal mode',
      (tester) async {
        await tester.pumpWidget(_wrapToggle(isCompact: false));
        await tester.pumpAndSettle();

        final enInkWell = find.ancestor(
          of: find.text('EN'),
          matching: find.byType(InkWell),
        );
        final bnInkWell = find.ancestor(
          of: find.text('বাংলা'),
          matching: find.byType(InkWell),
        );

        final enRect = tester.getRect(enInkWell);
        final bnRect = tester.getRect(bnInkWell);

        expect(enRect.overlaps(bnRect), isFalse);
        expect(enRect.right, lessThanOrEqualTo(bnRect.left));
      },
    );

    testWidgets('tooltips and semantic labels are present for both segments', (
      tester,
    ) async {
      await tester.pumpWidget(_wrapToggle(isCompact: true));
      await tester.pumpAndSettle();

      expect(find.byTooltip('English'), findsOneWidget);
      expect(find.byTooltip('বাংলা'), findsOneWidget);

      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.button == true &&
              w.properties.label == 'English' &&
              w.properties.selected == true,
        ),
        findsOneWidget,
      );

      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.button == true &&
              w.properties.label == 'বাংলা' &&
              w.properties.selected == false,
        ),
        findsOneWidget,
      );
    });
  });

  group('LanguageToggle Reactivity & Locale Switching', () {
    testWidgets('tapping বাংলা switches locale and updates selection', (
      tester,
    ) async {
      await tester.pumpWidget(_wrapToggle(isCompact: true));
      await tester.pumpAndSettle();

      expect(GochanoLanguage.current.value, equals(GochanoLocale.english));

      await tester.tap(find.text('বাংলা'));
      await tester.pumpAndSettle();

      expect(GochanoLanguage.current.value, equals(GochanoLocale.bangla));

      // Bangla segment should now be selected
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.label == 'বাংলা' &&
              w.properties.selected == true,
        ),
        findsOneWidget,
      );
    });

    testWidgets('tapping EN switches locale back to English', (tester) async {
      GochanoLanguage.current.value = GochanoLocale.bangla;

      await tester.pumpWidget(_wrapToggle(isCompact: true));
      await tester.pumpAndSettle();

      expect(GochanoLanguage.current.value, equals(GochanoLocale.bangla));

      await tester.tap(find.text('EN'));
      await tester.pumpAndSettle();

      expect(GochanoLanguage.current.value, equals(GochanoLocale.english));

      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.label == 'English' &&
              w.properties.selected == true,
        ),
        findsOneWidget,
      );
    });

    testWidgets('renders cleanly in dark theme without errors', (
      tester,
    ) async {
      await tester.pumpWidget(_wrapToggle(themeMode: ThemeMode.dark));
      await tester.pumpAndSettle();

      expect(find.byType(LanguageToggle), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders cleanly with 2.0x font scaling without errors', (
      tester,
    ) async {
      await tester.pumpWidget(_wrapToggle(textScale: 2.0));
      await tester.pumpAndSettle();

      expect(find.byType(LanguageToggle), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
