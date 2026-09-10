import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gochano/core/localization/gochano_language.dart';
import 'package:gochano/widgets/language_toggle.dart';

void main() {
  setUp(() {
    GochanoLanguage.current.value = GochanoLocale.english;
  });

  tearDown(() {
    GochanoLanguage.current.value = GochanoLocale.english;
  });

  group('Specific Required Labels Test (EN & BN)', () {
    test('all 14 required labels match exact specifications in EN and BN', () {
      final labelSpecs = <String, (String, String)>{
        'Home': ('Home', 'হোম'),
        'Study': ('Study', 'পড়াশোনা'),
        'Life': ('Life', 'জীবন'),
        'Community': ('Community', 'কমিউনিটি'),
        'Profile': ('Profile', 'প্রোফাইল'),
        'Workspace': ('Workspace', 'ওয়ার্কস্পেস'),
        'Plan': ('Plan', 'পরিকল্পনা'),
        'Focus': ('Focus', 'ফোকাস'),
        'Distraction': ('Distraction', 'বিচ্ছিন্নতা'),
        'Today': ('Today', 'আজ'),
        'Recent': ('Recent', 'সাম্প্রতিক'),
        'Medicine': ('Medicine', 'ওষুধ'),
        'Add task': ('Add task', 'কাজ যোগ করুন'),
        'Add expense': ('Add expense', 'খরচ যোগ করুন'),
      };

      // Test English
      GochanoLanguage.current.value = GochanoLocale.english;
      expect(GochanoLanguage.isBangla, isFalse);
      for (final entry in labelSpecs.entries) {
        final (en, bn) = entry.value;
        expect(
          GochanoLanguage.text(en, bn),
          equals(en),
          reason: 'Expected $en in English mode',
        );
      }

      // Test Bangla
      GochanoLanguage.current.value = GochanoLocale.bangla;
      expect(GochanoLanguage.isBangla, isTrue);
      for (final entry in labelSpecs.entries) {
        final (en, bn) = entry.value;
        expect(
          GochanoLanguage.text(en, bn),
          equals(bn),
          reason: 'Expected $bn in Bangla mode',
        );
      }
    });
  });

  group('LanguageToggle Reactivity Test', () {
    testWidgets(
      'LanguageToggle updates its visual selection on language change',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: const LanguageToggle())),
        );

        // Initially English
        expect(find.text('EN'), findsOneWidget);
        expect(find.text('বাংলা'), findsOneWidget);

        // Tap Bangla toggle
        await tester.tap(find.text('বাংলা'));
        await tester.pumpAndSettle();

        expect(GochanoLanguage.current.value, equals(GochanoLocale.bangla));
        expect(GochanoLanguage.isBangla, isTrue);

        // Tap EN toggle
        await tester.tap(find.text('EN'));
        await tester.pumpAndSettle();

        expect(GochanoLanguage.current.value, equals(GochanoLocale.english));
        expect(GochanoLanguage.isBangla, isFalse);
      },
    );
  });

  group('GochanoShell Destinations Reactivity Test', () {
    test(
      'GochanoShell subscribes to GochanoLanguage.current and defines localized destinations',
      () {
        final shellSource = File(
          'lib/features/shell/presentation/gochano_shell.dart',
        ).readAsStringSync();
        expect(
          shellSource,
          contains('GochanoLanguage.current.addListener(_onLanguageChange)'),
        );
        expect(
          shellSource,
          contains('GochanoLanguage.current.removeListener(_onLanguageChange)'),
        );
        expect(shellSource, contains('_buildDestinations()'));
        expect(shellSource, contains("GochanoLanguage.text('Today', 'আজ')"));
        expect(
          shellSource,
          contains("GochanoLanguage.text('Study', 'পড়াশোনা')"),
        );
        expect(
          shellSource,
          contains("GochanoLanguage.text('Money', 'টাকা')"),
        );
        expect(
          shellSource,
          contains("GochanoLanguage.text('Commute', 'যাতায়াত')"),
        );
        expect(
          shellSource,
          contains("GochanoLanguage.text('Community', 'কমিউনিটি')"),
        );
      },
    );

    testWidgets(
      'NavigationBar destinations dynamically update on language change',
      (tester) async {
        Widget buildNavBar() {
          return ListenableBuilder(
            listenable: GochanoLanguage.current,
            builder: (context, _) {
              return NavigationBar(
                selectedIndex: 0,
                destinations: [
                  NavigationDestination(
                    icon: const Icon(Icons.home),
                    label: GochanoLanguage.text('Today', 'আজ'),
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.school),
                    label: GochanoLanguage.text('Study', 'পড়াশোনা'),
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.receipt_long),
                    label: GochanoLanguage.text('Money', 'টাকা'),
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.directions_bus),
                    label: GochanoLanguage.text('Commute', 'যাতায়াত'),
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.groups),
                    label: GochanoLanguage.text('Community', 'কমিউনিটি'),
                  ),
                ],
              );
            },
          );
        }

        await tester.pumpWidget(
          MaterialApp(home: Scaffold(bottomNavigationBar: buildNavBar())),
        );

        // Verify English bottom nav labels
        expect(find.text('Today'), findsOneWidget);
        expect(find.text('Study'), findsOneWidget);
        expect(find.text('Money'), findsOneWidget);
        expect(find.text('Commute'), findsOneWidget);
        expect(find.text('Community'), findsOneWidget);

        // Switch language to Bangla
        GochanoLanguage.current.value = GochanoLocale.bangla;
        await tester.pump();

        // Verify Bangla bottom nav labels immediately update
        expect(find.text('আজ'), findsOneWidget);
        expect(find.text('পড়াশোনা'), findsOneWidget);
        expect(find.text('টাকা'), findsOneWidget);
        expect(find.text('যাতায়াত'), findsOneWidget);
        expect(find.text('কমিউনিটি'), findsOneWidget);

        // Switch back to English
        GochanoLanguage.current.value = GochanoLocale.english;
        await tester.pump();

        // Verify labels flip back to English
        expect(find.text('Today'), findsOneWidget);
        expect(find.text('Study'), findsOneWidget);
        expect(find.text('Money'), findsOneWidget);
        expect(find.text('Commute'), findsOneWidget);
        expect(find.text('Community'), findsOneWidget);
      },
    );
  });
}
