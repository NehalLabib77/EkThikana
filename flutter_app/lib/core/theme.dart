import 'package:flutter/material.dart';

/// Standardized drop-shadows. Both modes use the same low-opacity
/// black so that the visual depth matches between light & dark themes;
/// dark mode would otherwise lose the lift because dark surfaces blend
/// into a dark background.
class EkShadows {
  /// Standard elevation shadow for floating brand marks (login logo,
  /// splash logo, large icon badges). blur 12, y-offset 4.
  static const List<BoxShadow> elevated = [
    BoxShadow(
      color: Color(0x14000000),
      blurRadius: 12,
      offset: Offset(0, 4),
    ),
  ];

  /// Stronger lift for hero surfaces (login logo 88x88 plate). blur 18,
  /// y-offset 6.
  static const List<BoxShadow> hero = [
    BoxShadow(
      color: Color(0x14000000),
      blurRadius: 18,
      offset: Offset(0, 6),
    ),
  ];
}

class EkColors {
  static const purple = Color(0xFF5B3DF5);
  static const purpleDark = Color(0xFF4527D8);
  static const lavender = Color(0xFFF2EEFF);
  static const background = Color(0xFFF9FAFE);
  static const card = Colors.white;
  static const text = Color(0xFF141522);
  static const muted = Color(0xFF6F7380);
  static const line = Color(0xFFE9EAF2);
  static const teal = Color(0xFF16B8AD);
  static const green = Color(0xFF35B96F);
  static const orange = Color(0xFFFFA52D);
  static const red = Color(0xFFFF5A5F);
  static const blue = Color(0xFF3D7BFF);

  // Dark palette tokens (scaffolding; full per-screen migration is P2).
  static const bgDark = Color(0xFF0F172A);
  static const cardDark = Color(0xFF1E293B);
  static const lineDark = Color(0xFF334155);
  static const textDark = Color(0xFFE5E7EB);
  static const mutedDark = Color(0xFF94A3B8);
}

class EkTheme {
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: EkColors.purple,
      brightness: Brightness.light,
    ).copyWith(
      primary: EkColors.purple,
      secondary: EkColors.teal,
      surface: EkColors.card,
      onSurface: EkColors.text,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: EkColors.background,
      fontFamily: 'Roboto',
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        },
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: EkColors.background,
        foregroundColor: EkColors.text,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: EkColors.text,
          fontSize: 21,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: EkColors.line),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: EkColors.lavender,
        elevation: 0,
        height: 70,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? EkColors.purple
                : EkColors.muted,
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? EkColors.purple
                : EkColors.muted,
          ),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: EkColors.purple,
        foregroundColor: Colors.white,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: EkColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: EkColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: EkColors.purple, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: EkColors.purple,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white,
        selectedColor: EkColors.purple,
        labelStyle: const TextStyle(color: EkColors.text),
        side: const BorderSide(color: EkColors.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      dividerTheme: const DividerThemeData(color: EkColors.line, thickness: 1),
    );
  }

  /// Dark theme scaffolding. Material3 will flip the components that read from
  /// [ColorScheme]; screens that hardcode `EkColors.card`, `EkColors.text` or
  /// `EkColors.background` directly will need a follow-up pass to migrate to
  /// `Theme.of(context).colorScheme.*` / [EkColors.bgDark] before this is a
  /// full dark mode. See `FINAL_AUDIT_REPORT.md` D4/P2.
  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: EkColors.purple,
      brightness: Brightness.dark,
    ).copyWith(
      primary: EkColors.purple,
      secondary: EkColors.teal,
      surface: EkColors.cardDark,
      onSurface: EkColors.textDark,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: EkColors.bgDark,
      fontFamily: 'Roboto',
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        },
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: EkColors.bgDark,
        foregroundColor: EkColors.textDark,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: EkColors.textDark,
          fontSize: 21,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: EkColors.cardDark,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: EkColors.lineDark),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: EkColors.cardDark,
        indicatorColor: EkColors.purple.withValues(alpha: .25),
        elevation: 0,
        height: 70,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? EkColors.lavender
                : EkColors.mutedDark,
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? EkColors.lavender
                : EkColors.mutedDark,
          ),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: EkColors.purple,
        foregroundColor: Colors.white,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: EkColors.cardDark,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: EkColors.lineDark),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: EkColors.lineDark),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: EkColors.purple, width: 1.4),
        ),
        labelStyle: const TextStyle(color: EkColors.mutedDark),
        hintStyle: const TextStyle(color: EkColors.mutedDark),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: EkColors.purple,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: EkColors.cardDark,
        selectedColor: EkColors.purple,
        labelStyle: const TextStyle(color: EkColors.textDark),
        side: const BorderSide(color: EkColors.lineDark),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      dividerTheme: const DividerThemeData(color: EkColors.lineDark, thickness: 1),
    );
  }
}
