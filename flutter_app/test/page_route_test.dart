// GochanoPageRoute.
//
// The route used to be a `PageRouteBuilder` with a bespoke 240ms fade + 24dp
// rise and its own curve tokens — a motion-design system in miniature, which
// spec §11 rules out. It is now the platform's `MaterialPageRoute`.
//
// These tests pin the two things that matter: pushes still work at every call
// site, and the transition is the framework's rather than one of ours.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gochano/core/page_route.dart';

void main() {
  group('GochanoPageRoute', () {
    testWidgets('renders the destination screen', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('home'))),
      );

      tester.state<NavigatorState>(find.byType(Navigator)).push(
            GochanoRoute.to<void>(
              builder: (_) => const Scaffold(body: Text('destination')),
            ),
          );
      await tester.pumpAndSettle();

      expect(find.text('destination'), findsOneWidget);
    });

    testWidgets('uses the platform transition, not a custom duration',
        (tester) async {
      // The old route hardcoded 240ms in both directions. Inheriting from
      // MaterialPageRoute means the duration is whatever the platform's
      // page-transition theme says — which is the point.
      //
      // `transitionDuration` resolves against the route's own context, so it
      // can only be read once the route is installed in a Navigator.
      final route = GochanoPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('d')),
      );
      expect(route, isA<MaterialPageRoute<void>>());

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('home'))),
      );
      tester.state<NavigatorState>(find.byType(Navigator)).push(route);
      await tester.pumpAndSettle();
      expect(find.text('d'), findsOneWidget);
      expect(route.transitionDuration,
          isNot(const Duration(milliseconds: 240)));
    });

    testWidgets('fullscreenDialog is honoured', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('home'))),
      );
      final route = GochanoRoute.to<void>(
        builder: (_) => const Scaffold(body: Text('modal')),
        fullscreenDialog: true,
      );
      expect(route.fullscreenDialog, isTrue);

      tester.state<NavigatorState>(find.byType(Navigator)).push(route);
      await tester.pumpAndSettle();
      expect(find.text('modal'), findsOneWidget);
    });

    testWidgets('pop returns to the previous screen', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('home'))),
      );
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(
        GochanoRoute.to<void>(
          builder: (_) => const Scaffold(body: Text('destination')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('destination'), findsOneWidget);

      navigator.pop();
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
      expect(find.text('destination'), findsNothing);
    });
  });
}
