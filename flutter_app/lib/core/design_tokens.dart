// Gochano design tokens — single source of truth for visual style.
//
// These tokens describe the visual contract of the Gochano brand on top of
// the existing Material 3 theme (see `theme.dart`). They are deliberately
// additive: every existing screen compiles unchanged, but new screens and
// future migrations should resolve colors / radii / spacing through the
// helpers below instead of hardcoded hex literals.
//
// Layering:
//   theme.dart          -> ThemeData + EkColors (raw + dark palette)
//   design_tokens.dart  -> semantic surfaces, module accents, motion, scale
//   gochano_primitives  -> composed widgets (GradientStatCard, EmptyState…)
//   empty_illustrations -> CustomPainter illustrations per module
//   gochano_app_bar     -> unified AppBar shape
//
// All gradients are 2-stop, hand-picked for legibility on both light and
// dark themes; they are routed through `LinearGradient` so a single widget
// paints correctly under `ThemeMode.system` without per-screen branching.

import 'package:flutter/material.dart';

import 'theme.dart';

/// Module accent gradients.
///
/// Each accent has a paired soft surface so a screen can use the gradient
/// for hero cards and the soft surface for secondary tiles — keeping the
/// module on-brand without repeating the same bold background everywhere.
class EkGradients {
  const EkGradients._();

  static const study = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF6B46FF), Color(0xFF8457E9)],
  );

  static const medicine = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF147E6D), Color(0xFF158472)],
  );

  static const expense = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFB26015), Color(0xFF996C36)],
  );

  static const commute = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1B72CC), Color(0xFF3B7AB4)],
  );

  static const bazar = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFC9327C), Color(0xFFC14885)],
  );

  static const tasks = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF5B3DF5), Color(0xFF6F5DE5)],
  );

  static const ai = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0E8332), Color(0xFF16803D)],
  );

  static const greeting = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF4F2DE8), Color(0xFF7A55FF), Color(0xFF14B8A6)],
    stops: [0.0, 0.55, 1.0],
  );

  /// Returns the gradient matching a logical module id. Centralizing this
  /// here means per-screen code never has to import a gradient by hand.
  static LinearGradient module(String module) {
    switch (module) {
      case 'study':
        return study;
      case 'medicine':
        return medicine;
      case 'expense':
        return expense;
      case 'commute':
        return commute;
      case 'bazar':
        return bazar;
      case 'tasks':
        return tasks;
      case 'ai':
        return ai;
      default:
        return study;
    }
  }

  /// A muted, light-weight gradient used for *dark* hero cards. Dark
  /// surfaces need desaturated gradients to keep text legible; the same
  /// gradients used on a light scaffold will burn through on dark mode.
  static LinearGradient moduleDark(String module) {
    switch (module) {
      case 'study':
        return const LinearGradient(
          colors: [Color(0xFF2A1F66), Color(0xFF3F2EAA)],
        );
      case 'medicine':
        return const LinearGradient(
          colors: [Color(0xFF0D6B63), Color(0xFF138C82)],
        );
      case 'expense':
        return const LinearGradient(
          colors: [Color(0xFF8A4A0E), Color(0xFFB8641D)],
        );
      case 'commute':
        return const LinearGradient(
          colors: [Color(0xFF103E80), Color(0xFF1F60B5)],
        );
      case 'bazar':
        return const LinearGradient(
          colors: [Color(0xFF7C1F4E), Color(0xFFA8326B)],
        );
      case 'tasks':
        return const LinearGradient(
          colors: [Color(0xFF2C1D8C), Color(0xFF4535B5)],
        );
      case 'ai':
        return const LinearGradient(
          colors: [Color(0xFF0D5C1E), Color(0xFF158438)],
        );
      default:
        return const LinearGradient(
          colors: [Color(0xFF2A1F66), Color(0xFF3F2EAA)],
        );
    }
  }
}

/// Soft, low-contrast surfaces used as backgrounds for secondary tiles
/// inside a module. These mirror the gradient's hue but stay low enough
/// in contrast to sit alongside a gradient hero card without competing.
class EkSoft {
  const EkSoft._();

  static const studyLight = Color(0xFFF2EEFF);
  static const medicineLight = Color(0xFFE6F8F5);
  static const expenseLight = Color(0xFFFFF1DC);
  static const commuteLight = Color(0xFFE8F2FF);
  static const bazarLight = Color(0xFFFCE6F1);
  static const tasksLight = Color(0xFFF0EDFF);
  static const aiLight = Color(0xFFE6F7EA);

  // Dark variants tuned for the dark scaffold (EkColors.bgDark).
  static const studyDark = Color(0xFF241B4A);
  static const medicineDark = Color(0xFF0F2E2B);
  static const expenseDark = Color(0xFF3A2510);
  static const commuteDark = Color(0xFF0F2540);
  static const bazarDark = Color(0xFF3A182A);
  static const tasksDark = Color(0xFF1F1A40);
  static const aiDark = Color(0xFF102818);

  /// Module-aware soft surface that flips with the theme.
  static Color module(BuildContext context, String module) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    switch (module) {
      case 'study':
        return dark ? studyDark : studyLight;
      case 'medicine':
        return dark ? medicineDark : medicineLight;
      case 'expense':
        return dark ? expenseDark : expenseLight;
      case 'commute':
        return dark ? commuteDark : commuteLight;
      case 'bazar':
        return dark ? bazarDark : bazarLight;
      case 'tasks':
        return dark ? tasksDark : tasksLight;
      case 'ai':
        return dark ? aiDark : aiLight;
      default:
        return dark ? studyDark : studyLight;
    }
  }
}

/// Spacing scale, in logical pixels. Always use these constants instead of
/// magic numbers when laying out screens — this keeps vertical rhythm
/// consistent across the app.
class EkSpace {
  const EkSpace._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 48;
}

/// Corner radius scale.
class EkRadius {
  const EkRadius._();

  static const double xs = 8;
  static const double sm = 12;
  static const double md = 14;
  static const double lg = 18;
  static const double xl = 22;
  static const double pill = 999;
}

/// Icon size scale.
class EkIcon {
  const EkIcon._();

  static const double xs = 16;
  static const double sm = 20;
  static const double md = 24;
  static const double lg = 28;
  static const double xl = 36;
  static const double hero = 56;
}

/// Typography scale. Builds on Theme.of(context).textTheme but adds the
/// branded display / headline / title / body / caption tiers. These are
/// used by the primitives; existing screens keep their inline TextStyles.
class EkText {
  const EkText._();

  static TextStyle display(BuildContext context) {
    final base = Theme.of(context).textTheme.headlineMedium;
    return (base ?? const TextStyle()).copyWith(
      fontSize: 30,
      fontWeight: FontWeight.w900,
      letterSpacing: -0.4,
      height: 1.15,
    );
  }

  static TextStyle headline(BuildContext context) =>
      Theme.of(context).textTheme.titleLarge?.copyWith(
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ) ??
      const TextStyle(fontSize: 22, fontWeight: FontWeight.w800);

  static TextStyle title(BuildContext context) =>
      Theme.of(context).textTheme.titleMedium?.copyWith(
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ) ??
      const TextStyle(fontSize: 17, fontWeight: FontWeight.w800);

  static TextStyle body(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            height: 1.35,
          ) ??
      const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, height: 1.35);

  static TextStyle caption(BuildContext context) =>
      Theme.of(context).textTheme.bodySmall?.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: EkColors.muted,
          ) ??
      const TextStyle(fontSize: 11, fontWeight: FontWeight.w500);
}

/// Motion tokens. All animation durations and curves should come from here.
class EkMotion {
  const EkMotion._();

  static const Duration fast = Duration(milliseconds: 160);
  static const Duration medium = Duration(milliseconds: 240);
  static const Duration slow = Duration(milliseconds: 360);
  static const Duration hero = Duration(milliseconds: 600);

  static const Curve enter = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;
  static const Curve emphasize = Curves.easeOutBack;
}

/// Semantic surface helper — read `Theme.of(context).colorScheme` first,
/// fall back to `EkColors` only when a screen needs a flat, brand-tinted
/// background that the Material scheme does not model.
class EkSurfaces {
  const EkSurfaces._();

  /// Returns a card background that follows the active theme.
  static Color card(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return dark ? EkColors.cardDark : EkColors.card;
  }

  /// Outline / divider color, theme-aware.
  static Color line(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return dark ? EkColors.lineDark : EkColors.line;
  }

  /// Primary text color, theme-aware.
  static Color text(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return dark ? EkColors.textDark : EkColors.text;
  }

  /// Muted / caption text color, theme-aware.
  static Color muted(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return dark ? EkColors.mutedDark : EkColors.muted;
  }

  /// Scaffold background, theme-aware. Falls back to the M3 surface in
  /// case `EkColors.background` is migrated to `colorScheme.surface`.
  static Color scaffold(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return dark ? EkColors.bgDark : EkColors.background;
  }
}