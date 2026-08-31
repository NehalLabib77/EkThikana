// P3-11 a11y audit regression tests.
//
// Pins the accessibility contract that the Flutter app exposes to
// TalkBack / VoiceOver users, plus the contrast rule for every module
// gradient so that darkening the cards below WCAG AA in a future
// refactor is caught at PR time.
//
// What this file guards:
//
//   1. Every `Image.asset(...)` and `Image.network(...)` site in
//      `lib/` has a `semanticLabel:` argument.
//   2. Every `IconButton(...)` site has either a `tooltip:` or a
//      `semanticLabel:` so screen readers announce a meaningful name
//      instead of "button".
//   3. The hero card subtitle is rendered in pure `Colors.white`,
//      not `Colors.white70`, so the AA body-text contrast (4.5:1)
//      holds on the lighter end of every module gradient.
//   4. **Both** end-stops of **every** module gradient clear the WCAG
//      AA body-text threshold of 4.5:1 against pure white. P3-11
//      darkened seven right-end and two left-end stops to achieve
//      this; the constants below mirror `lib/core/design_tokens.dart`
//      `EkGradients` and a divergence is a regression.
//   5. The `GradientStatCard` widget collapses `title + value` into
//      a single semantic button label so screen readers announce the
//      card once instead of reading each line.

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gochano/widgets/gochano_primitives.dart';

void main() {
  group('Static a11y guards', () {
    final lib = Directory('lib');

    test('every Image.asset has a semanticLabel', () {
      final offenders = <String>[];
      for (final entity in lib.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final src = entity.readAsStringSync();
        final lines = src.split('\n');
        for (var i = 0; i < lines.length; i++) {
          if (!lines[i].contains('Image.asset(')) continue;
          final window = lines.skip(i).take(12).join('\n');
          if (!window.contains('semanticLabel')) {
            offenders.add('${entity.path}:${i + 1}');
          }
        }
      }
      expect(offenders, isEmpty,
          reason: 'every Image.asset must carry semanticLabel for TalkBack: $offenders');
    });

    test('every Image.network has a semanticLabel', () {
      final offenders = <String>[];
      for (final entity in lib.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final src = entity.readAsStringSync();
        final lines = src.split('\n');
        for (var i = 0; i < lines.length; i++) {
          if (!lines[i].contains('Image.network(')) continue;
          final window = lines.skip(i).take(14).join('\n');
          if (!window.contains('semanticLabel')) {
            offenders.add('${entity.path}:${i + 1}');
          }
        }
      }
      expect(offenders, isEmpty,
          reason: 'every Image.network must carry semanticLabel: $offenders');
    });

    test('every IconButton has a tooltip or semanticLabel', () {
      final offenders = <String>[];
      for (final entity in lib.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final src = entity.readAsStringSync();
        final lines = src.split('\n');
        for (var i = 0; i < lines.length; i++) {
          if (!lines[i].contains('IconButton(')) continue;
          final window = lines.skip(i).take(12).join('\n');
          final hasTooltip = window.contains('tooltip:');
          final hasSem = window.contains('semanticLabel');
          if (!hasTooltip && !hasSem) {
            offenders.add('${entity.path}:${i + 1}');
          }
        }
      }
      expect(offenders, isEmpty,
          reason: 'every IconButton must advertise a name: $offenders');
    });

    test('hero card subtitle no longer uses Colors.white70', () {
      // The hero card subtitle dropped from Colors.white70 to
      // Colors.white for AA contrast in P3-11. If a future refactor
      // reintroduces the 70% opacity, this test fires.
      final f = File('lib/widgets/gochano_primitives.dart');
      final src = f.readAsStringSync();

      final lines = src.split('\n');
      var inSubtitleBlock = false;
      var sawWhite70 = false;
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains('subtitle != null')) {
          inSubtitleBlock = true;
          continue;
        }
        if (inSubtitleBlock) {
          if (lines[i].contains('Colors.white70')) {
            sawWhite70 = true;
            break;
          }
          if (lines[i].contains('),')) {
            inSubtitleBlock = false;
          }
        }
      }
      expect(sawWhite70, isFalse,
          reason:
              'hero card subtitle must use Colors.white (not white70) to '
              'clear WCAG AA 4.5:1 on every module gradient.');
    });
  });

  group('Module gradient contrast', () {
    // Pin the design tokens: white text on **both** end-stops of every
    // module gradient must clear the WCAG AA body-text threshold of
    // 4.5:1. The hero card renders white text at fontSize 13 (title),
    // 22/28 (value, weight 900), and 11 (subtitle), so the *strict*
    // AA body threshold (4.5:1) applies even to the subtitle.
    //
    // P3-11 darkened every right end so that no module gradient drops
    // below 4.5:1 against pure white. If a future palette tweak pulls
    // a stop back into the < 4.5:1 range, this test fires.

    double relLuminance(int hex) {
      final r = ((hex >> 16) & 0xFF) / 255.0;
      final g = ((hex >> 8) & 0xFF) / 255.0;
      final b = (hex & 0xFF) / 255.0;
      double s(double c) => c <= 0.03928
          ? c / 12.92
          : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
      return 0.2126 * s(r) + 0.7152 * s(g) + 0.0722 * s(b);
    }

    double ratio(int fg, int bg) {
      final l1 = relLuminance(fg);
      final l2 = relLuminance(bg);
      final a = l1 > l2 ? l1 : l2;
      final b = l1 > l2 ? l2 : l1;
      return (a + 0.05) / (b + 0.05);
    }

    // Module -> [left (top-left), right (bottom-right)].
    // These constants mirror lib/core/design_tokens.dart EkGradients.
    const moduleStops = <String, List<int>>{
      'study':    [0xFF6B46FF, 0xFF8457E9],
      'medicine': [0xFF147E6D, 0xFF158472],
      'expense':  [0xFFB26015, 0xFF996C36],
      'commute':  [0xFF1B72CC, 0xFF3B7AB4],
      'bazar':    [0xFFC9327C, 0xFFC14885],
      'tasks':    [0xFF5B3DF5, 0xFF6F5DE5],
      'ai':       [0xFF0E8332, 0xFF16803D],
    };

    for (final entry in moduleStops.entries) {
      final module = entry.key;
      final stops = entry.value;
      test('white on $module top-left stop clears AA body text (4.5:1)', () {
        final r = ratio(0xFFFFFFFF, stops[0]);
        expect(r, greaterThanOrEqualTo(4.5),
            reason:
                '$module gradient top-left stop (#${stops[0].toRadixString(16)}) '
                'must give >= 4.5:1 against white. Got ${r.toStringAsFixed(2)}:1');
      });
      test('white on $module bottom-right stop clears AA body text (4.5:1)', () {
        final r = ratio(0xFFFFFFFF, stops[1]);
        expect(r, greaterThanOrEqualTo(4.5),
            reason:
                '$module gradient bottom-right stop (#${stops[1].toRadixString(16)}) '
                'must give >= 4.5:1 against white. Got ${r.toStringAsFixed(2)}:1');
      });
    }
  });

  group('GradientStatCard semantics', () {
    testWidgets(
      'exposes its title and value as a semantic button label',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: GradientStatCard(
                module: 'study',
                title: 'Study',
                value: '7m',
                onTap: () {},
              ),
            ),
          ),
        );

        final handle = tester.ensureSemantics();

        // Walk the widget tree directly. The Semantics widget inside
        // the GradientStatCard exposes a `SemanticsProperties` node
        // whose `label` is "Study, 7m" and `button` is true. Walking
        // the widget tree (rather than the rendered semantics tree)
        // is more deterministic here because the InkWell also wraps
        // its own Semantics node, and we want to assert the *user*
        // label is present on *the* card-level node.
        final semNodes = find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'Study, 7m',
        );
        handle.dispose();

        expect(semNodes, findsOneWidget,
            reason:
                'GradientStatCard with onTap should expose a single '
                'Semantics node labelled "Study, 7m"');

        // And that node is promoted to a button so TalkBack
        // announces it as "Study, 7m, button" rather than reading the
        // two text children separately.
        final widget = tester.widget<Semantics>(semNodes);
        expect(widget.properties.button, isTrue,
            reason:
                'The Semantics node for a tappable GradientStatCard '
                'must set button: true so TalkBack announces it as a '
                'button rather than a label.');
      },
    );

    testWidgets(
      'non-tappable card stays as an informational label, not a button',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: GradientStatCard(
                module: 'study',
                title: 'Study',
                value: '7m',
              ),
            ),
          ),
        );

        // Without onTap, the wrapper must NOT promote to a button
        // (otherwise TalkBack would announce a button that does
        // nothing when tapped). Look for any Semantics node with
        // button: true that we own — the card itself, not the
        // children.
        final buttons = find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.label == 'Study, 7m' &&
              w.properties.button == true,
        );
        expect(buttons, findsNothing,
            reason:
                'A non-tappable GradientStatCard must not advertise '
                'itself as a button to the screen reader.');
      },
    );
  });
}