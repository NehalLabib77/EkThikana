import 'package:flutter/material.dart';

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
}
