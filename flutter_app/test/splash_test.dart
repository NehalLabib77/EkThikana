// The launch screen's contract.
//
// Two things matter and neither is visual: the logo is on screen, and
// `onReady` fires exactly once so the app hands off to `AuthGate`. The third
// assertion pins the *absence* of the fade the previous splash had — a
// decorative entrance that spec §11 rules out.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gochano/core/design_system/gochano_theme.dart';
import 'package:gochano/features/shell/presentation/splash_screen.dart';

void main() {
  testWidgets('renders the logo on the Gochano background', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: GochanoTheme.light(),
        home: const GochanoSplashScreen(),
      ),
    );
    await tester.pump();

    final image = tester.widget<Image>(find.byType(Image));
    // `cacheWidth` wraps the provider in a ResizeImage, so unwrap before
    // asserting. The intent is "the splash shows the brand asset", which the
    // decode hint does not change.
    final provider = image.image;
    final asset = provider is ResizeImage ? provider.imageProvider : provider;
    expect((asset as AssetImage).assetName, 'assets/branding/Gochano.png');
    expect(image.semanticLabel, isNotNull);

    // And the decode hint itself is load-bearing: the master artwork is 1254
    // square but drawn at most 240 logical px, so decoding it at full size
    // costs about 6 MB of RAM for nothing.
    expect(provider, isA<ResizeImage>());
  });

  testWidgets('fires onReady exactly once', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: GochanoTheme.light(),
        home: GochanoSplashScreen(onReady: () => calls++),
      ),
    );

    // `pumpWidget` already drains the post-frame queue, so the hand-off has
    // happened by the time the first frame is on screen — which is the point:
    // the splash must not hold the app back.
    expect(calls, 1);

    // The 1.5s hard-timeout fallback must not fire a second time.
    await tester.pump(const Duration(seconds: 3));
    expect(calls, 1);
  });

  testWidgets('fires onReady even if the first post-frame is missed',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: GochanoTheme.light(),
        home: GochanoSplashScreen(onReady: () => calls++),
      ),
    );
    await tester.pump(const Duration(seconds: 3));
    expect(calls, 1, reason: 'the 1.5s ceiling guarantees a hand-off');
  });

  testWidgets('the splash itself does not animate (spec §11)',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: GochanoTheme.light(),
        home: const GochanoSplashScreen(),
      ),
    );
    await tester.pump();

    // Scoped to the splash subtree: MaterialApp wraps *any* home in its own
    // route transition, so asserting on the whole tree would be testing
    // Flutter, not Gochano.
    //
    // The previous splash wrapped the logo in a TweenAnimationBuilder that
    // faded opacity 0 -> 1 over 360ms. Nothing inside this screen animates.
    final splash = find.byType(GochanoSplashScreen);
    expect(
      find.descendant(
        of: splash,
        matching: find.byType(TweenAnimationBuilder<double>),
      ),
      findsNothing,
    );
    expect(
      find.descendant(of: splash, matching: find.byType(AnimatedOpacity)),
      findsNothing,
    );
    expect(
      find.descendant(of: splash, matching: find.byType(AnimatedContainer)),
      findsNothing,
    );
  });
}
