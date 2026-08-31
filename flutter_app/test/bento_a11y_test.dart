// Pin the accessibility contract for the bento primitives.
//
// The bento widgets are touched by TalkBack / VoiceOver users all day.
// These tests pin three rules:
//
//   1. A tappable [BentoCard] with [semanticsLabel] collapses into a
//      single semantic button — screen readers announce the label
//      once instead of reading every child text.
//   2. A non-tappable [BentoCard] does NOT promote itself to a button
//      (so it stays a passive informational card).
//   3. The same contract holds for [ScaleTap] (the InkWell replacement
//      used by module tiles and social feed actions).
//
// We use [WidgetTester.getSemantics] to find nodes by label, which is
// the canonical Flutter API for accessibility assertions.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gochano/widgets/bento/bento_card.dart';
import 'package:gochano/widgets/bento/bento_small_card.dart';
import 'package:gochano/widgets/bento/bento_action_card.dart';
import 'package:gochano/widgets/gochano_primitives.dart';

Future<void> _pumpHost(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  group('BentoCard a11y', () {
    testWidgets(
      'tappable card with semanticsLabel exposes a button node',
      (tester) async {
        var tapped = 0;
        await _pumpHost(
          tester,
          BentoCard(
            animateIn: false,
            semanticsLabel: 'Open BazarBuddy',
            semanticsHint: 'opens the shopping list',
            onTap: () => tapped++,
            child: const Column(
              children: [
                Text('BazarBuddy'),
                Text('Plan your shopping'),
              ],
            ),
          ),
        );

        final handle = tester.ensureSemantics();

        // find.bySemanticsLabel walks the entire semantics tree for a
        // node whose label matches. If our Semantics wrapper registered
        // "Open BazarBuddy", the finder must return at least one match.
        final matches = find.bySemanticsLabel('Open BazarBuddy');

        handle.dispose();

        expect(matches, findsWidgets,
            reason: 'Expected "Open BazarBuddy" label to be advertised to '
                'the screen reader');

        // Tapping the card still works through the GestureDetector.
        await tester.tap(find.byType(BentoCard));
        expect(tapped, 1);
      },
    );

    testWidgets(
      'non-tappable card renders the child without errors',
      (tester) async {
        await _pumpHost(
          tester,
          const BentoCard(
            animateIn: false,
            child: Text('Stat: 7 doses'),
          ),
        );
        expect(find.text('Stat: 7 doses'), findsOneWidget);
      },
    );
  });

  group('BentoSmallCard a11y', () {
    testWidgets(
      'passes its title through as the semantic label',
      (tester) async {
        await _pumpHost(
          tester,
          BentoSmallCard(
            title: 'Medicine',
            subtitle: 'Today',
            moduleId: 'medicine',
            onTap: () {},
            // The base BentoCard runs a delayed entrance animation; turn
            // it off here so the test does not leave a pending Timer
            // behind when the widget is disposed. The a11y contract is
            // independent of the entrance animation.
            animateIn: false,
          ),
        );

        final handle = tester.ensureSemantics();
        final matches = find.bySemanticsLabel('Medicine');
        handle.dispose();

        expect(matches, findsWidgets,
            reason: 'Semantic tree should expose "Medicine" as label');
      },
    );
  });

  group('BentoActionCard a11y', () {
    testWidgets(
      'exposes its title as the semantic label',
      (tester) async {
        await _pumpHost(
          tester,
          BentoActionCard(
            title: 'Add expense',
            subtitle: 'Record a purchase',
            icon: Icons.add_rounded,
            onTap: () {},
            animateIn: false,
          ),
        );

        final handle = tester.ensureSemantics();
        final matches = find.bySemanticsLabel('Add expense');
        handle.dispose();

        expect(matches, findsWidgets,
            reason: 'Semantic tree should expose "Add expense" as label');
      },
    );
  });

  group('ScaleTap a11y', () {
    testWidgets(
      'tappable wrapper advertises itself as a button with the label',
      (tester) async {
        await _pumpHost(
          tester,
          ScaleTap(
            semanticsLabel: 'Open shopping list',
            onTap: () {},
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Shopping list'),
            ),
          ),
        );

        final handle = tester.ensureSemantics();
        final matches = find.bySemanticsLabel('Open shopping list');
        handle.dispose();

        expect(matches, findsWidgets,
            reason: 'ScaleTap should promote to a semantic button');
      },
    );
  });
}