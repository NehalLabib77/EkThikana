import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gochano/core/page_route.dart';

void main() {
  group('GochanoPageRoute', () {
    testWidgets('renders destination screen via pageBuilder', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: const Scaffold(body: Text('home')),
      ));

      final state = tester.state<NavigatorState>(find.byType(Navigator));
      state.push(GochanoRoute.to<void>(
        builder: (_) => const Scaffold(body: Text('destination')),
      ));
      await tester.pumpAndSettle();

      expect(find.text('destination'), findsOneWidget);
    });

    testWidgets('uses EkMotion.medium duration', (tester) async {
      // Sanity check: the durations are tied to EkMotion.medium (240 ms).
      // If someone later weakens this back to the Material default we want
      // this test to fail and surface the regression.
      await tester.pumpWidget(MaterialApp(
        home: const Scaffold(body: Text('home')),
      ));
      final state = tester.state<NavigatorState>(find.byType(Navigator));
      final route = GochanoPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('d')),
      );
      expect(route.transitionDuration, const Duration(milliseconds: 240));
      expect(route.reverseTransitionDuration,
          const Duration(milliseconds: 240));
      // Smoke-push it so we also exercise the build path.
      state.push(route);
      await tester.pumpAndSettle();
      expect(find.text('d'), findsOneWidget);
    });

    testWidgets('fullscreenDialog: true is accepted and route settles',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: const Scaffold(body: Text('home')),
      ));
      final state = tester.state<NavigatorState>(find.byType(Navigator));
      state.push(GochanoRoute.to<void>(
        builder: (_) => const Scaffold(body: Text('modal')),
        fullscreenDialog: true,
      ));
      await tester.pumpAndSettle();
      expect(find.text('modal'), findsOneWidget);
    });

    testWidgets('pop reverses the animation cleanly', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: const Scaffold(body: Text('home')),
      ));
      final state = tester.state<NavigatorState>(find.byType(Navigator));
      state.push(GochanoRoute.to<void>(
        builder: (_) => const Scaffold(body: Text('detail')),
      ));
      await tester.pumpAndSettle();

      state.pop();
      await tester.pumpAndSettle();
      expect(find.text('detail'), findsNothing);
      expect(find.text('home'), findsOneWidget);
    });
  });
}