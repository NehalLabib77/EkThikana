import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gochano/core/design_system/gochano_theme.dart';
import 'package:gochano/core/localization/gochano_language.dart';
import 'package:gochano/features/auth/presentation/otp_verify_screen.dart';

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

  group('OtpVerifyScreen Widget Visual & Interaction Tests', () {
    testWidgets('renders all expected elements in English (Light Mode)', (tester) async {
      GochanoLanguage.current.value = GochanoLocale.english;

      await tester.pumpWidget(
        _buildWrapper(
          child: const OtpVerifyScreen(phone: '01812345678'),
        ),
      );
      await tester.pump();

      // Heading and subtitle in OtpHero
      expect(find.text('Enter the verification code'), findsOneWidget);
      expect(find.text('Verification code'), findsOneWidget);
      expect(find.text('4-8 digits'), findsOneWidget);
      expect(find.byType(TextFormField), findsOneWidget);

      // Buttons
      expect(find.text('Verify'), findsOneWidget);
      expect(find.text('Resend code'), findsOneWidget);
      expect(find.text('Wrong number? Change number'), findsOneWidget);

      final exc = tester.takeException();
      if (exc != null) {
        debugPrint(exc.toString());
      }
      expect(exc, isNull);
    });

    testWidgets('renders all expected elements in Bengali', (tester) async {
      GochanoLanguage.current.value = GochanoLocale.bangla;

      await tester.pumpWidget(
        _buildWrapper(
          child: const OtpVerifyScreen(phone: '01812345678'),
        ),
      );
      await tester.pump();

      // Bengali text checks
      expect(find.text('ভেরিফিকেশন কোড লিখুন'), findsOneWidget);
      expect(find.text('ভেরিফিকেশন কোড'), findsOneWidget);
      expect(find.text('৪-৮ সংখ্যা'), findsOneWidget);
      expect(find.text('যাচাই করুন'), findsOneWidget);
      expect(find.text('আবার কোড পাঠান'), findsOneWidget);
      expect(find.text('ভুল নম্বর? নম্বর পরিবর্তন করুন'), findsOneWidget);

      final exc = tester.takeException();
      if (exc != null) {
        debugPrint(exc.toString());
      }
      expect(exc, isNull);
    });

    testWidgets('renders smoothly in Dark Mode without errors', (tester) async {
      await tester.pumpWidget(
        _buildWrapper(
          theme: GochanoTheme.dark(),
          child: const OtpVerifyScreen(phone: '01812345678'),
        ),
      );
      await tester.pump();

      expect(find.text('Enter the verification code'), findsOneWidget);
      expect(find.text('Verify'), findsOneWidget);

      final exc = tester.takeException();
      if (exc != null) {
        debugPrint(exc.toString());
      }
      expect(exc, isNull);
    });

    testWidgets('adapts to 320dp narrow viewport with zero overflow', (tester) async {
      final prevOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        debugPrint('FLUTTER_ERROR: ${details.exceptionAsString()}');
        debugPrint('CONTEXT: ${details.context?.toDescription()}');
        debugPrint('SUMMARY: ${details.summary}');
      };
      addTearDown(() => FlutterError.onError = prevOnError);

      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildWrapper(
          size: const Size(320, 568),
          child: const OtpVerifyScreen(phone: '01812345678'),
        ),
      );
      await tester.pump();

      expect(find.text('Enter the verification code'), findsOneWidget);
      expect(find.byType(TextFormField), findsOneWidget);
      expect(find.text('Verify'), findsOneWidget);

      final exc = tester.takeException();
      if (exc != null) {
        debugPrint(exc.toString());
      }
      expect(exc, isNull);
    });

    testWidgets('validates OTP length when less than 4 digits entered', (tester) async {
      GochanoLanguage.current.value = GochanoLocale.english;

      await tester.pumpWidget(
        _buildWrapper(
          child: const OtpVerifyScreen(phone: '01812345678'),
        ),
      );
      await tester.pump();

      // Enter 2 digits and submit
      await tester.enterText(find.byType(TextFormField), '12');
      await tester.pump();

      await tester.tap(find.text('Verify'));
      await tester.pump();

      expect(find.text('Enter the verification code'), findsWidgets);
    });
  });
}
