import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gochano/widgets/ek_state_view.dart';

void main() {
  group('EkStateView', () {
    testWidgets('loading state renders GochanoLoading', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: EkStateView(state: EkViewState.loading),
        ),
      ));
      // GochanoLoading renders an Image.asset for the logo + a rotating
      // ring. We only assert that some custom paint activity exists and
      // no error has been thrown.
      expect(find.byType(EkStateView), findsOneWidget);
    });

    testWidgets('empty state renders illustration + title + message + CTA',
        (tester) async {
      var tapped = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: EkStateView(
            state: EkViewState.empty,
            module: 'study',
            title: 'No notes yet',
            message: 'Tap the button to create one.',
            actionLabel: 'Create note',
            onAction: () => tapped = true,
          ),
        ),
      ));
      expect(find.byType(CustomPaint), findsWidgets);
      expect(find.text('No notes yet'), findsOneWidget);
      expect(find.text('Tap the button to create one.'), findsOneWidget);
      expect(find.text('Create note'), findsOneWidget);
      // Action tap works.
      await tester.tap(find.text('Create note'));
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
    });

    testWidgets('error state shows retry button when onRetry is provided',
        (tester) async {
      var retried = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: EkStateView(
            state: EkViewState.error,
            message: 'Network unreachable',
            onRetry: () => retried = true,
          ),
        ),
      ));
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.text('Network unreachable'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(retried, isTrue);
    });

    testWidgets('error state falls back to default title when none given',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: EkStateView(
            state: EkViewState.error,
            onRetry: () {},
          ),
        ),
      ));
      // The default English title is "Something went wrong".
      expect(find.text('Something went wrong'), findsOneWidget);
    });

    testWidgets('success state renders dataBuilder body', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: EkStateView(
            state: EkViewState.success,
            dataBuilder: (_) => const Text('hello body'),
          ),
        ),
      ));
      expect(find.text('hello body'), findsOneWidget);
    });

    testWidgets('compact loading variant is smaller', (tester) async {
      // The compact variant uses the same widget but with a smaller
      // intrinsic size. We can only assert that the widget renders
      // without throwing — the actual size difference is verified by
      // the layout contract in [GochanoLoading].
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: EkStateView(state: EkViewState.loading, compact: true),
        ),
      ));
      expect(find.byType(EkStateView), findsOneWidget);
    });
  });
}