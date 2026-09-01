// Guards that Material widgets actually work in Bangla.
//
// The bug this pins shipped to a device. `MaterialApp` declared
// `supportedLocales: [en, bn]` but no `localizationsDelegates` at all, and
// the built-in `DefaultMaterialLocalizations` covers **only English**. So the
// moment a student switched to Bangla, every `AppBar`, `TextField`, dialog
// and bottom sheet threw:
//
//     No MaterialLocalizations found.
//     AppBar widgets require MaterialLocalizations to be provided by a
//     Localizations widget ancestor.
//
// English was fine, which is exactly why it survived review — the failure
// only appears in the locale the tests never exercised.
//
// These tests build the real `GochanoApp`-shaped MaterialApp configuration in
// both locales and assert that the widgets which threw can now be laid out.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gochano/core/design_system/gochano_theme.dart';
import 'package:gochano/core/localization/gochano_language.dart';

/// A MaterialApp configured exactly as `app.dart` configures the real one.
///
/// Mirrored rather than imported because `GochanoApp` boots Firebase through
/// its splash. The point of the test is the localization configuration, and a
/// static test below asserts the real app still carries it.
Widget _app({required Locale locale, required Widget home}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: GochanoTheme.light(),
    darkTheme: GochanoTheme.dark(),
    locale: locale,
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: [for (final value in GochanoLocale.values) value.locale],
    home: home,
  );
}

void main() {
  for (final locale in GochanoLocale.values) {
    final code = locale.code;

    group('Material widgets in "$code"', () {
      testWidgets('an AppBar lays out', (tester) async {
        await tester.pumpWidget(
          _app(
            locale: locale.locale,
            home: Scaffold(
              appBar: AppBar(title: const Text('Gochano')),
              body: const SizedBox.shrink(),
            ),
          ),
        );

        expect(tester.takeException(), isNull);
        expect(find.byType(AppBar), findsOneWidget);
      });

      testWidgets('a TextField lays out', (tester) async {
        await tester.pumpWidget(
          _app(
            locale: locale.locale,
            home: const Scaffold(body: TextField()),
          ),
        );

        expect(tester.takeException(), isNull);
        expect(find.byType(TextField), findsOneWidget);
      });

      testWidgets('MaterialLocalizations resolves for this locale',
          (tester) async {
        // The direct assertion. Everything above is a symptom of this.
        late BuildContext captured;
        await tester.pumpWidget(
          _app(
            locale: locale.locale,
            home: Builder(
              builder: (context) {
                captured = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        );

        expect(
          Localizations.of<MaterialLocalizations>(
            captured,
            MaterialLocalizations,
          ),
          isNotNull,
          reason: 'MaterialLocalizations must resolve in "$code"',
        );
        // A real localised string, proving the delegate loaded rather than
        // merely being registered.
        expect(MaterialLocalizations.of(captured).okButtonLabel, isNotEmpty);
      });

      testWidgets('a dialog opens', (tester) async {
        await tester.pumpWidget(
          _app(
            locale: locale.locale,
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => const AlertDialog(title: Text('Hello')),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(AlertDialog), findsOneWidget);
      });

      testWidgets('a modal bottom sheet with a TextField opens',
          (tester) async {
        // The second screenshot: the composer inside a bottom sheet.
        await tester.pumpWidget(
          _app(
            locale: locale.locale,
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    builder: (_) => const Padding(
                      padding: EdgeInsets.all(16),
                      child: TextField(),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(TextField), findsOneWidget);
      });
    });
  }

  group('The real app carries the delegates', () {
    test('app.dart registers the three Global delegates', () {
      // A static guard, so removing them from `app.dart` fails here even
      // though the widget tests above build their own MaterialApp.
      final source = File(
        'lib/app.dart',
      ).readAsStringSync().replaceAll('\r\n', '\n');

      expect(source, contains('localizationsDelegates'));
      for (final delegate in const [
        'GlobalMaterialLocalizations.delegate',
        'GlobalWidgetsLocalizations.delegate',
        'GlobalCupertinoLocalizations.delegate',
      ]) {
        expect(source, contains(delegate),
            reason: '$delegate must stay registered in app.dart');
      }
    });

    test('every supported locale is one the delegates can serve', () {
      // Adding a locale to the enum without checking this is how the
      // original bug would come back.
      for (final locale in GochanoLocale.values) {
        expect(
          GlobalMaterialLocalizations.delegate.isSupported(locale.locale),
          isTrue,
          reason: 'flutter_localizations must support "${locale.code}"',
        );
      }
    });
  });
}
