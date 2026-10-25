import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gochano/core/design_system/gochano_theme.dart';
import 'package:gochano/core/localization/gochano_language.dart';
import 'package:gochano/features/auth/presentation/auth_gate.dart';

Widget _buildWrapper({
  required Widget child,
  ThemeData? theme,
  Size size = const Size(360, 640),
  bool disableAnimations = false,
  bool accessibleNavigation = false,
}) {
  return MaterialApp(
    theme: theme ?? GochanoTheme.light(),
    home: MediaQuery(
      data: MediaQueryData(
        size: size,
        disableAnimations: disableAnimations,
        accessibleNavigation: accessibleNavigation,
      ),
      child: child,
    ),
  );
}

void main() {
  setUp(() {
    GochanoLanguage.current.value = GochanoLocale.english;
  });

  group('AuthGate Visual & Loading State Tests', () {
    testWidgets('renders all expected loading elements in English (Light Mode)',
        (tester) async {
      GochanoLanguage.current.value = GochanoLocale.english;

      await tester.pumpWidget(
        _buildWrapper(
          child: const AuthGateLoadingView(),
        ),
      );
      await tester.pump();

      expect(find.text('Gochano'), findsOneWidget);
      expect(find.text('Starting Gochano…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.bySemanticsLabel('Loading Gochano'), findsOneWidget);

      final progress =
          tester.widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          );
      expect(progress.value, isNull, reason: 'Normal motion spins continuously');
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders all expected loading elements in Bengali',
        (tester) async {
      GochanoLanguage.current.value = GochanoLocale.bangla;

      await tester.pumpWidget(
        _buildWrapper(
          child: const AuthGateLoadingView(),
        ),
      );
      await tester.pump();

      expect(find.text('Gochano'), findsOneWidget);
      expect(find.text('Gochano শুরু হচ্ছে…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.bySemanticsLabel('Gochano লোড হচ্ছে'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders cleanly in Dark Mode with dark theme palette',
        (tester) async {
      await tester.pumpWidget(
        _buildWrapper(
          theme: GochanoTheme.dark(),
          child: const AuthGateLoadingView(),
        ),
      );
      await tester.pump();

      expect(find.text('Gochano'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('adapts to 320dp narrow viewport with zero overflow',
        (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildWrapper(
          size: const Size(320, 568),
          child: const AuthGateLoadingView(),
        ),
      );
      await tester.pump();

      expect(find.text('Gochano'), findsOneWidget);
      expect(find.text('Starting Gochano…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'honors reduced motion preference by freezing progress rotation',
        (tester) async {
      await tester.pumpWidget(
        _buildWrapper(
          disableAnimations: true,
          child: const AuthGateLoadingView(),
        ),
      );
      await tester.pump();

      final progress =
          tester.widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          );
      expect(
        progress.value,
        equals(0.75),
        reason: 'Under reduced motion, progress indicator is held static',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('never exposes sensitive user tokens, UIDs or phone numbers',
        (tester) async {
      await tester.pumpWidget(
        _buildWrapper(
          child: const AuthGateLoadingView(),
        ),
      );
      await tester.pump();

      // Ensure no raw identifiers or numbers are rendered
      expect(find.textContaining('018'), findsNothing);
      expect(find.textContaining('telecom:'), findsNothing);
      expect(find.textContaining('token'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
