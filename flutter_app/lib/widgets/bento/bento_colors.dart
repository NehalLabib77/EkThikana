// Gochano Bento palette — module tints used across the bento cards.
//
// The bento design system intentionally separates the *background tint*
// (soft pastel, large surface) from the *accent color* (saturated, used
// for icons, numbers, gradients). Every module has a paired dark-mode
// tint as well so dark dashboards stay legible without burning through.
//
// The class is deliberately scoped to `lib/widgets/bento/`. Screens
// outside the bento system should keep using `EkColors` / `EkSurfaces`.

import 'package:flutter/material.dart';

import '../../core/theme.dart';

class BentoColors {
  const BentoColors._();

  // Module light tints.
  static const Color studyTint = Color(0xFFE9D5FF);
  static const Color aiTint = Color(0xFFDBEAFE);
  static const Color medicineTint = Color(0xFFDCFCE7);
  static const Color bazarTint = Color(0xFFFFEDD5);
  static const Color commuteTint = Color(0xFFCFFAFE);
  static const Color moneyTint = Color(0xFFFEF3C7);
  static const Color tasksTint = Color(0xFFE0E7FF);

  // Module accents.
  static const Color studyAccent = Color(0xFF8B5CF6);
  static const Color aiAccent = Color(0xFF2563EB);
  static const Color medicineAccent = Color(0xFF16A34A);
  static const Color bazarAccent = Color(0xFFEA580C);
  static const Color commuteAccent = Color(0xFF0891B2);
  static const Color moneyAccent = Color(0xFFD97706);
  static const Color tasksAccent = Color(0xFF6366F1);

  // Module dark tints.
  static const Color studyTintDark = Color(0xFF3B1F6B);
  static const Color aiTintDark = Color(0xFF1E3A8A);
  static const Color medicineTintDark = Color(0xFF14532D);
  static const Color bazarTintDark = Color(0xFF7C2D12);
  static const Color commuteTintDark = Color(0xFF155E75);
  static const Color moneyTintDark = Color(0xFF78350F);
  static const Color tasksTintDark = Color(0xFF312E81);

  /// Pair (tint, accent) for the named module.
  ///
  /// Falls back to study for unknown modules so a stray caller cannot
  /// crash the dashboard build.
  static ({Color tint, Color accent}) module(BuildContext context, String id) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    switch (id) {
      case 'study':
        return (
          tint: dark ? studyTintDark : studyTint,
          accent: studyAccent,
        );
      case 'ai':
        return (
          tint: dark ? aiTintDark : aiTint,
          accent: aiAccent,
        );
      case 'medicine':
        return (
          tint: dark ? medicineTintDark : medicineTint,
          accent: medicineAccent,
        );
      case 'bazar':
        return (
          tint: dark ? bazarTintDark : bazarTint,
          accent: bazarAccent,
        );
      case 'commute':
        return (
          tint: dark ? commuteTintDark : commuteTint,
          accent: commuteAccent,
        );
      case 'money':
        return (
          tint: dark ? moneyTintDark : moneyTint,
          accent: moneyAccent,
        );
      case 'tasks':
        return (
          tint: dark ? tasksTintDark : tasksTint,
          accent: tasksAccent,
        );
      default:
        return (
          tint: dark ? studyTintDark : studyTint,
          accent: studyAccent,
        );
    }
  }

  /// Soft scaffold color. Light = #FAFAF8, dark = #0F172A.
  static Color scaffold(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? EkColors.bgDark
          : const Color(0xFFFAFAF8);

  /// On-tint text color (the dark ink drawn on a pastel tint).
  static Color onTint(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFFF8FAFC)
          : EkColors.text;

  /// Subtle text color (caption / muted) drawn on a tint.
  static Color onTintMuted(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFFCBD5E1)
          : const Color(0xFF475569);
}
