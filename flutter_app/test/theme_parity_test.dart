// P3-8 theme parity smoke test.
//
// Pins the light/dark contract that the Gochano theme exposes so a
// future regression (forgetting pageTransitionsTheme on dark, deleting
// the legacy brutalist helper, hardcoding raw Color(0x...) literals
// in screens) is caught at PR time rather than at runtime.

import "dart:io";

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

import "package:gochano/core/theme.dart";

void main() {
  group("EkTheme.light", () {
    final light = EkTheme.light();

    test("is a Material3 theme", () {
      expect(light.useMaterial3, isTrue);
    });

    test("seeds the brand purple", () {
      expect(light.colorScheme.primary, EkColors.purple);
    });

    test("exposes a pageTransitionsTheme", () {
      expect(light.pageTransitionsTheme, isNotNull);
      expect(
        light.pageTransitionsTheme.builders[TargetPlatform.android],
        isA<PredictiveBackPageTransitionsBuilder>(),
      );
    });
  });

  group("EkTheme.dark", () {
    final dark = EkTheme.dark();

    test("is a Material3 dark theme", () {
      expect(dark.useMaterial3, isTrue);
      expect(dark.brightness, Brightness.dark);
    });

    test("exposes the same pageTransitionsTheme as light", () {
      final light = EkTheme.light();
      expect(
        dark.pageTransitionsTheme.builders[TargetPlatform.android],
        equals(light.pageTransitionsTheme.builders[TargetPlatform.android]),
      );
    });

    test("maps the scaffold background to EkColors.bgDark", () {
      expect(dark.scaffoldBackgroundColor, EkColors.bgDark);
    });
  });

  group("EkShadows", () {
    test("elevated has the standard blur 12 / y 4 profile", () {
      expect(EkShadows.elevated, hasLength(1));
      expect(EkShadows.elevated.first.blurRadius, 12);
      expect(EkShadows.elevated.first.offset, const Offset(0, 4));
    });

    test("hero has the stronger blur 18 / y 6 profile", () {
      expect(EkShadows.hero, hasLength(1));
      expect(EkShadows.hero.first.blurRadius, 18);
      expect(EkShadows.hero.first.offset, const Offset(0, 6));
    });
  });

  group("Static guards", () {
    test("legacy brutalist widget has been removed", () {
      final file = File("lib/screens/home/widgets/brutalist.dart");
      expect(file.existsSync(), isFalse,
          reason: "brutalist.dart is dead since the bento migration");
    });

    test("app.dart wires ThemeMode.system", () {
      final src = File("lib/app.dart").readAsStringSync();
      expect(src.contains("ThemeMode.system"), isTrue,
          reason: "system theme mode is required for dark parity");
    });

    test("screens no longer hardcode the elevation shadow literal", () {
      final offenders = <String>[];
      final lib = Directory("lib");
      for (final entity in lib.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith(".dart")) continue;
        // Allow the token files that own the literal: the legacy
        // `core/theme.dart` and the Gochano design-system shadow token.
        if (entity.path.endsWith("theme.dart")) continue;
        if (entity.path.endsWith("gochano_spacing.dart")) continue;
        final content = entity.readAsStringSync();
        if (content.contains("Color(0x14000000)")) {
          offenders.add(entity.path);
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: "use EkShadows.elevated/hero instead of raw literal: "
            "$offenders",
      );
    });
  });
}

