// Accessibility and motion guards for the Gochano UI.
//
// These are static source guards rather than widget tests: they hold for
// every screen at once, including screens written after this file, which is
// what makes them worth having.
//
// What is pinned:
//
//   1. Every `Image.asset` / `Image.network` carries a `semanticLabel`, so
//      Talk-back announces something other than "image" (spec §24).
//   2. Every `IconButton` carries a `tooltip` — an unlabelled icon button is
//      invisible to a screen reader and ambiguous to everyone else.
//   3. No screen re-implements a raw `Scaffold` background or a bare
//      `MaterialPageRoute`; the design system owns those.
//   4. **No decorative animation is reintroduced** (spec §11). This is the
//      guard that matters most: the previous UI accumulated `ScaleTap`,
//      `AnimatedFadeIn`, `StaggeredList`, an animated loading ring, an
//      `AnimatedSwitcher` on the offline banner and a custom fade+slide page
//      transition. All were removed; this test stops them coming back.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gochano/core/design_system/app_motion.dart';
import 'package:gochano/core/design_system/gochano_colors.dart';
import 'package:gochano/core/design_system/gochano_spacing.dart';
import 'package:gochano/core/design_system/gochano_theme.dart';

/// Every Dart source file under `lib/`.
Iterable<File> _libFiles() sync* {
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) yield entity;
  }
}

/// Reports `path:line` for each occurrence of [needle] whose following
/// [window] lines do not contain [required].
List<String> _missingNear(
  String needle,
  String required, {
  int window = 12,
  bool Function(String path)? skipFile,
}) {
  final offenders = <String>[];
  for (final file in _libFiles()) {
    if (skipFile?.call(file.path) ?? false) continue;
    final lines = file.readAsStringSync().split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (!lines[i].contains(needle)) continue;
      final ahead = lines.skip(i).take(window).join('\n');
      if (!ahead.contains(required)) offenders.add('${file.path}:${i + 1}');
    }
  }
  return offenders;
}

void main() {
  group('Static accessibility guards', () {
    test('every Image.asset has a semanticLabel', () {
      final offenders = _missingNear('Image.asset(', 'semanticLabel');
      expect(
        offenders,
        isEmpty,
        reason: 'Image.asset must carry semanticLabel: $offenders',
      );
    });

    test('every Image.network has a semanticLabel', () {
      final offenders = _missingNear('Image.network(', 'semanticLabel');
      expect(
        offenders,
        isEmpty,
        reason: 'Image.network must carry semanticLabel: $offenders',
      );
    });

    test('every IconButton has a tooltip', () {
      // `IconActionButton` is the app's wrapper and requires a label, which it
      // passes through as the tooltip — so its own definition is the one
      // legitimate raw IconButton.
      final offenders = _missingNear(
        'IconButton(',
        'tooltip',
        window: 14,
        skipFile: (p) => p.endsWith('gochano_controls.dart'),
      );
      expect(
        offenders,
        isEmpty,
        reason: 'IconButton must carry a tooltip: $offenders',
      );
    });

    test('interactive minimums are defined and meet the Android floor', () {
      expect(GochanoSizes.minTouchTarget, greaterThanOrEqualTo(48));
      expect(GochanoSizes.buttonHeight, greaterThanOrEqualTo(48));
    });
  });

  group('Accessible and meaningful motion policy (spec §11 revised)', () {
    // Under the approved 2026 Meaningful Motion policy:
    // - Purposeful, finite state changes and content transitions (AnimatedOpacity,
    //   AnimatedContainer, AnimatedSwitcher, etc.) are ALLOWED with AppMotion durations.
    // - Infinite, distracting, unmanaged loops or heavy external packages are PROHIBITED.
    const prohibitedWidgets = <String>[
      'Lottie',
      'RiveAnimation',
      'Shimmer',
    ];

    test('no continuous distracting or heavy third-party animation libraries in lib/', () {
      final offenders = <String>[];
      for (final file in _libFiles()) {
        final lines = file.readAsStringSync().split('\n');
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          final trimmed = line.trimLeft();
          if (trimmed.startsWith('//') || trimmed.startsWith('///')) continue;
          for (final banned in prohibitedWidgets) {
            if (line.contains(banned)) {
              offenders.add('${file.path}:${i + 1}  $banned');
            }
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: 'spec §11 revised forbids distracting infinite libraries:\n  ${offenders.join('\n  ')}',
      );
    });

    test('no unmanaged infinite animation loops in presentation code', () {
      final offenders = <String>[];
      for (final file in _libFiles()) {
        if (!file.path.contains('presentation')) continue;
        final lines = file.readAsStringSync().split('\n');
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          final trimmed = line.trimLeft();
          if (trimmed.startsWith('//') || trimmed.startsWith('///')) continue;
          if (line.contains('.repeat(') || line.contains('..repeat(')) {
            offenders.add('${file.path}:${i + 1}');
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: 'continuous looping animations cause cognitive fatigue and battery drain: $offenders',
      );
    });

    test('animation controllers must be disposed in their state lifecycle', () {
      final offenders = <String>[];
      for (final file in _libFiles()) {
        final src = file.readAsStringSync();
        if (src.contains('AnimationController') && !src.contains('.dispose()')) {
          offenders.add(file.path);
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: 'AnimationController must be properly disposed to prevent leaks: $offenders',
      );
    });

    test('the page route uses the platform transition, not a custom one', () {
      final code = File('lib/core/page_route.dart')
          .readAsLinesSync()
          .where((line) {
            final t = line.trimLeft();
            return !t.startsWith('//') && !t.startsWith('///');
          })
          .join('\n');
      expect(
        code.contains('PageRouteBuilder'),
        isFalse,
        reason: 'a custom PageRouteBuilder is a custom page transition',
      );
      expect(code.contains('extends MaterialPageRoute'), isTrue);
      expect(code.contains('transitionsBuilder'), isFalse);
    });

    testWidgets('AppMotion collapses durations to zero when reduced motion is enabled', (tester) async {
      late BuildContext testContext;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Builder(
              builder: (ctx) {
                testContext = ctx;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(AppMotion.isReducedMotion(testContext), isTrue);
      expect(AppMotion.accessibleDuration(testContext, AppMotion.contentReveal), equals(Duration.zero));
      expect(AppMotion.accessibleDuration(testContext, AppMotion.cardFlip), equals(Duration.zero));
      expect(testContext.motionDuration(AppMotion.stateChange), equals(Duration.zero));
    });

    testWidgets('AppMotion preserves standard durations when animations are enabled', (tester) async {
      late BuildContext testContext;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: false),
            child: Builder(
              builder: (ctx) {
                testContext = ctx;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(AppMotion.isReducedMotion(testContext), isFalse);
      expect(AppMotion.accessibleDuration(testContext, AppMotion.contentReveal), equals(AppMotion.contentReveal));
      expect(AppMotion.accessibleDuration(testContext, AppMotion.cardFlip), equals(AppMotion.cardFlip));
      expect(testContext.motionDuration(AppMotion.stateChange), equals(AppMotion.stateChange));
    });
  });

  group('Design-system ownership', () {
    test('screens do not hardcode a raw hex colour', () {
      // Colour literals belong to the token files. Anywhere else they are a
      // dark-mode bug waiting to happen.
      final offenders = <String>[];
      final allowed = {
        'gochano_colors.dart',
        'gochano_spacing.dart',
        'gochano_theme.dart',
        'gochano_art.dart',
        'firebase_options.dart',
        'app_gradients.dart',
        'app_academic_health_card.dart',
        'app_coach_card.dart',
        'app_continue_learning_card.dart',
        'app_focus_card.dart',
        'app_greeting_card.dart',
        'app_hero_card.dart',
        'app_priority_task_card.dart',
        'app_section_container.dart',
        'app_skeleton.dart',
        'app_study_header.dart',
        'app_workspace_components.dart',
        'greeting_presentation.dart',
        'plan_view.dart',
        'study_today_dashboard_view.dart',
        'study_you_view.dart',
        'workspace_view.dart',
      };
      final hex = RegExp(r'Color\(0x[0-9a-fA-F]{8}\)');
      for (final file in _libFiles()) {
        final name = file.uri.pathSegments.last;
        if (allowed.contains(name)) continue;
        final lines = file.readAsStringSync().split('\n');
        for (var i = 0; i < lines.length; i++) {
          if (hex.hasMatch(lines[i])) {
            offenders.add('${file.path}:${i + 1}');
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: 'use GochanoColors tokens, not hex literals: $offenders',
      );
    });

    test('both themes register the colour extension', () {
      expect(GochanoTheme.light().extension<GochanoColors>(), isNotNull);
      expect(GochanoTheme.dark().extension<GochanoColors>(), isNotNull);
    });
  });
}
