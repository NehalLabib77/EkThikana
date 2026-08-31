import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gochano/core/design_tokens.dart';
import 'package:gochano/screens/system/gochano_splash_screen.dart';

void main() {
  group('GochanoSplashScreen', () {
    testWidgets('renders logo asset on a flat brand background',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: GochanoSplashScreen(),
      ));
      // Splash uses TweenAnimationBuilder on opacity 0->1. After one pump
      // the logo should already be in the tree (even at opacity 0).
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('calls onReady on the next post-frame', (tester) async {
      var fired = false;
      await tester.pumpWidget(MaterialApp(
        home: GochanoSplashScreen(
          onReady: () => fired = true,
        ),
      ));
      await tester.pump();
      expect(fired, isTrue);
    });

    test('EkMotion.slow is 360 ms (regression sentinel)', () {
      // If EkMotion.slow ever changes, this test breaks on purpose so we
      // review the splash contract together with the change. Splash uses
      // EkMotion.slow directly.
      expect(EkMotion.slow, const Duration(milliseconds: 360));
    });
  });
}