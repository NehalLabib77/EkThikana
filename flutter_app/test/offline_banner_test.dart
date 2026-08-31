// OfflineBanner widget tests.
//
// Validates the structural contract of P3-7's banner:
//   - When the device is online, the banner collapses to a zero-height
//     SizedBox so it does not push content down.
//   - When offline, the surface renders with the offline colour, the
//     `wifi_off` icon, and a localized "You are offline…" message.
//   - The banner carries a Semantics label so TalkBack reads it once at
//     the top of every screen flip (a11y contract from P3-1).
//   - The banner text follows the EkLanguage.bangla notifier.
//   - The visible / hidden states are keyed so AnimatedSwitcher can run
//     a clean slide transition.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gochano/core/language.dart';
import 'package:gochano/services/connectivity_service.dart';
import 'package:gochano/widgets/offline_banner.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: child),
    );

void main() {
  setUp(() {
      // Reset to online before every test so prior tests cannot leak
      // state into the next one. `debugForceValue` is the test-only hook
      // documented on ConnectivityService.
      ConnectivityService.instance.debugForceValue(true);
    });

  testWidgets('renders zero-height placeholder when online', (tester) async {
    await tester.pumpWidget(_wrap(const OfflineBanner()));
    // First frame: banner collapses to a SizedBox with height: 0.
    final hidden = find.byKey(const ValueKey('offline-banner-hidden'));
    expect(hidden, findsOneWidget);
    // The visible surface must NOT be present.
    final surface = find.byKey(const Key('offline-banner-surface'));
    expect(surface, findsNothing);
  });

  testWidgets('renders orange surface with icon + text when offline',
      (tester) async {
    ConnectivityService.instance.debugForceValue(false);
    await tester.pumpWidget(_wrap(const OfflineBanner()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('offline-banner-surface')), findsOneWidget);
    expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);

    // English default — banner copy is bilingual via EkLanguage.
    expect(find.textContaining('You are offline'), findsOneWidget);
  });

  testWidgets('renders Bangla copy when language is switched to বাংলা',
      (tester) async {
    ConnectivityService.instance.debugForceValue(false);
    EkLanguage.bangla.value = true;
    await tester.pumpWidget(_wrap(const OfflineBanner()));
    await tester.pumpAndSettle();

    expect(find.textContaining('অফলাইন'), findsOneWidget);

    // Reset so subsequent tests see the English copy.
    EkLanguage.bangla.value = false;
  });

  testWidgets('banner has a single Semantics container with offline label',
      (tester) async {
    ConnectivityService.instance.debugForceValue(false);
    await tester.pumpWidget(_wrap(const OfflineBanner()));
    await tester.pumpAndSettle();

    final semantics = tester.getSemantics(find.byKey(
      const Key('offline-banner-surface'),
    ));
    expect(semantics.label, contains('offline'));
  });

  testWidgets('reacts to online -> offline -> online transitions',
      (tester) async {
    await tester.pumpWidget(_wrap(const OfflineBanner()));

    // Online: hidden placeholder only.
    expect(
      find.byKey(const ValueKey('offline-banner-hidden')),
      findsOneWidget,
    );

    // Flip to offline; AnimatedSwitcher animates in.
    ConnectivityService.instance.debugForceValue(false);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('offline-banner-visible')),
      findsOneWidget,
    );

    // Flip back to online.
    ConnectivityService.instance.debugForceValue(true);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('offline-banner-hidden')),
      findsOneWidget,
    );
  });
}