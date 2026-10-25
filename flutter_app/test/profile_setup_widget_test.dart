import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gochano/core/design_system/gochano_theme.dart';
import 'package:gochano/core/localization/gochano_language.dart';
import 'package:gochano/features/auth/presentation/profile_setup_screen.dart';

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
  setUp(() {
    GochanoLanguage.current.value = GochanoLocale.english;
  });

  group('ProfileSetupScreen Widget Visual & Interaction Tests', () {
    testWidgets('renders all expected elements in English (Light Mode)', (tester) async {
      GochanoLanguage.current.value = GochanoLocale.english;

      await tester.pumpWidget(
        _buildWrapper(
          child: const ProfileSetupScreen(phone: '01812345678'),
        ),
      );
      await tester.pump();

      // Heading and subtitle
      expect(find.text('Complete your profile'), findsOneWidget);
      expect(find.text('Just one quick step to get started.'), findsOneWidget);

      // Form cards
      expect(find.text('Full name'), findsOneWidget);
      expect(find.byType(TextFormField), findsOneWidget);
      expect(find.text('Account type'), findsOneWidget);
      expect(find.text('Student'), findsOneWidget);

      // Action button
      expect(find.text('Continue'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });

    testWidgets('renders all expected elements in Bengali', (tester) async {
      GochanoLanguage.current.value = GochanoLocale.bangla;

      await tester.pumpWidget(
        _buildWrapper(
          child: const ProfileSetupScreen(phone: '01812345678'),
        ),
      );
      await tester.pump();

      // Heading and subtitle in Bengali
      expect(find.text('আপনার প্রোফাইল সম্পূর্ণ করুন'), findsOneWidget);
      expect(find.text('শুরু করতে শুধু একটি ছোট ধাপ।'), findsOneWidget);

      // Form cards in Bengali
      expect(find.text('পূর্ণ নাম'), findsOneWidget);
      expect(find.text('অ্যাকাউন্টের ধরন'), findsOneWidget);
      expect(find.text('শিক্ষার্থী'), findsOneWidget);

      // Action button in Bengali
      expect(find.text('চালিয়ে যান'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });

    testWidgets('renders smoothly in Dark Mode without errors', (tester) async {
      await tester.pumpWidget(
        _buildWrapper(
          theme: GochanoTheme.dark(),
          child: const ProfileSetupScreen(phone: '01812345678'),
        ),
      );
      await tester.pump();

      expect(find.text('Complete your profile'), findsOneWidget);
      expect(find.text('Student'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });

    testWidgets('adapts to 320dp narrow viewport with zero overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildWrapper(
          size: const Size(320, 568),
          child: const ProfileSetupScreen(phone: '01812345678'),
        ),
      );
      await tester.pump();

      expect(find.text('Complete your profile'), findsOneWidget);
      expect(find.byType(TextFormField), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });

    testWidgets('empty submission triggers form validation error in English', (tester) async {
      GochanoLanguage.current.value = GochanoLocale.english;

      await tester.pumpWidget(
        _buildWrapper(
          child: const ProfileSetupScreen(phone: '01812345678'),
        ),
      );
      await tester.pump();

      // Tap Continue without typing name
      await tester.tap(find.text('Continue'));
      await tester.pump();

      expect(find.text('Please enter your name'), findsOneWidget);
    });

    testWidgets('empty submission triggers form validation error in Bengali', (tester) async {
      GochanoLanguage.current.value = GochanoLocale.bangla;

      await tester.pumpWidget(
        _buildWrapper(
          child: const ProfileSetupScreen(phone: '01812345678'),
        ),
      );
      await tester.pump();

      // Tap Continue without typing name
      await tester.tap(find.text('চালিয়ে যান'));
      await tester.pump();

      expect(find.text('আপনার নাম লিখুন'), findsOneWidget);
    });

    testWidgets('entering name updates controller and clears validation error on submission', (tester) async {
      GochanoLanguage.current.value = GochanoLocale.english;

      await tester.pumpWidget(
        _buildWrapper(
          child: const ProfileSetupScreen(phone: '01812345678'),
        ),
      );
      await tester.pump();

      // Enter name
      await tester.enterText(find.byType(TextFormField), 'Tanvir Ahmed');
      await tester.pump();

      expect(find.text('Tanvir Ahmed'), findsOneWidget);

      // Validation error should not appear
      expect(find.text('Please enter your name'), findsNothing);
    });
  });
}
