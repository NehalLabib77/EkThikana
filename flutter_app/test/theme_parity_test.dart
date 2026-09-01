// Light/dark parity for the Gochano design system (spec §17, §18).
//
// Dark mode used to be a per-screen problem: `EkColors.card`, `EkColors.text`
// and raw hex literals were written directly into screens, so a screen was
// light-mode-correct and dark-mode-broken until someone noticed. The colour
// system is now a `ThemeExtension`, which makes parity a property of the
// tokens rather than of each screen — and these tests check the tokens.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gochano/core/design_system/gochano_colors.dart';
import 'package:gochano/core/design_system/gochano_spacing.dart';
import 'package:gochano/core/design_system/gochano_theme.dart';

/// WCAG relative contrast between two opaque colours.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('Both themes define every role', () {
    test('the extension is registered on light and dark', () {
      expect(GochanoTheme.light().extension<GochanoColors>(),
          same(GochanoColors.light));
      expect(GochanoTheme.dark().extension<GochanoColors>(),
          same(GochanoColors.dark));
    });

    test('light and dark differ on every surface and text role', () {
      const l = GochanoColors.light;
      const d = GochanoColors.dark;
      final pairs = <String, (Color, Color)>{
        'background': (l.background, d.background),
        'surface': (l.surface, d.surface),
        'surfaceVariant': (l.surfaceVariant, d.surfaceVariant),
        'surfaceElevated': (l.surfaceElevated, d.surfaceElevated),
        'border': (l.border, d.border),
        'divider': (l.divider, d.divider),
        'textPrimary': (l.textPrimary, d.textPrimary),
        'textSecondary': (l.textSecondary, d.textSecondary),
        'textTertiary': (l.textTertiary, d.textTertiary),
        'illustrationPaper': (l.illustrationPaper, d.illustrationPaper),
      };
      for (final entry in pairs.entries) {
        expect(entry.value.$1, isNot(entry.value.$2),
            reason: '${entry.key} is identical in both themes');
      }
    });
  });

  group('Contrast floors', () {
    test('primary and secondary text clear 4.5:1 on every surface', () {
      for (final c in [GochanoColors.light, GochanoColors.dark]) {
        for (final surface in [c.background, c.surface, c.surfaceVariant, c.surfaceElevated]) {
          expect(_contrast(c.textPrimary, surface), greaterThanOrEqualTo(4.5));
          expect(_contrast(c.textSecondary, surface), greaterThanOrEqualTo(4.5));
        }
      }
    });

    test('tertiary text clears the 3:1 large/secondary floor', () {
      for (final c in [GochanoColors.light, GochanoColors.dark]) {
        for (final surface in [c.background, c.surface]) {
          expect(_contrast(c.textTertiary, surface), greaterThanOrEqualTo(3.0));
        }
      }
    });

    test('text on the brand colour is readable', () {
      for (final c in [GochanoColors.light, GochanoColors.dark]) {
        expect(_contrast(c.onBrand, c.brand), greaterThanOrEqualTo(4.5));
      }
    });

    test('feature accents are readable on their own surface', () {
      for (final c in [GochanoColors.light, GochanoColors.dark]) {
        for (final accent in [
          c.study,
          c.ai,
          c.expense,
          c.medicine,
          c.commute,
          c.community,
        ]) {
          expect(_contrast(accent, c.surface), greaterThanOrEqualTo(3.0),
              reason: 'accent $accent on ${c.surface}');
        }
      }
    });
  });

  group('Surface ordering', () {
    test('dark surfaces step up from the background (spec §18)', () {
      const d = GochanoColors.dark;
      expect(d.background.computeLuminance(),
          lessThan(d.surface.computeLuminance()));
      expect(d.surface.computeLuminance(),
          lessThan(d.surfaceElevated.computeLuminance()));
    });

    test('light scaffold is tinted so white cards read as raised (spec §17)',
        () {
      const l = GochanoColors.light;
      expect(l.background.computeLuminance(),
          lessThan(l.surface.computeLuminance()));
    });
  });

  group('Static guards', () {
    test('the legacy design layer is gone', () {
      for (final path in const [
        'lib/core/theme.dart',
        'lib/core/design_tokens.dart',
        'lib/core/language.dart',
        'lib/core/ui.dart',
        'lib/widgets/gochano_primitives.dart',
        'lib/widgets/bento',
        'lib/screens',
      ]) {
        expect(
          FileSystemEntity.typeSync(path),
          FileSystemEntityType.notFound,
          reason: '$path was superseded by the Gochano design system',
        );
      }
    });

    test('the shadow colour literal lives in exactly one place', () {
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (entity.path.endsWith('gochano_spacing.dart')) continue;
        if (entity.readAsStringSync().contains('Color(0x14000000)')) {
          offenders.add(entity.path);
        }
      }
      expect(offenders, isEmpty,
          reason: 'use GochanoShadows.color instead of the literal: $offenders');
      expect(GochanoShadows.color, const Color(0x14000000));
    });

    test('app.dart drives themeMode from the saved appearance preference', () {
      // The app used to hardcode ThemeMode.system with no way to change it;
      // spec §72 requires an Appearance setting.
      final src = File('lib/app.dart').readAsStringSync();
      expect(src.contains('GochanoAppearanceScope'), isTrue);
      expect(src.contains('themeMode: themeMode'), isTrue);
    });
  });
}
