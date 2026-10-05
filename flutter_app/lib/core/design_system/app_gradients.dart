import 'package:flutter/material.dart';

/// Centralized modern gradient tokens for Gochano.
class AppGradients {
  AppGradients._();

  /// Premium Exam Rescue Gradient (spec §7):
  /// Violet (#7048F5) -> Royal Blue (#2F6BFF) -> Cyan/Soft Blue (#38BDF8)
  static const LinearGradient examRescue = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF7048F5), // Violet
      Color(0xFF2F6BFF), // Royal / Primary Blue
      Color(0xFF38BDF8), // Cyan
    ],
    stops: [0.0, 0.55, 1.0],
  );

  /// Vibrant fallback hero gradient for daily recommendations / kickoff.
  static const LinearGradient fallbackHero = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF1E3A8A), // Deep Navy / Blue
      Color(0xFF2563EB), // Primary Blue
      Color(0xFF0284C7), // Sky Cyan
    ],
    stops: [0.0, 0.6, 1.0],
  );

  /// Soft accent gradient for Ziku Coach cards.
  static const LinearGradient zikuCoach = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFF0FDF4),
      Color(0xFFEFF6FF),
    ],
  );

  /// Focus session subtle background gradient.
  static const LinearGradient focusSession = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFFAF5FF),
      Color(0xFFF3E8FF),
    ],
  );
}

/// Category soft tint definitions for priority cards (spec §8).
enum CategoryTint {
  coral,
  blue,
  mint,
  violet,
  amber;

  static CategoryTint resolve(String? category, {bool isDark = false}) {
    if (category == null || category.isEmpty) {
      return CategoryTint.blue;
    }
    final lower = category.toLowerCase();
    if (lower.contains('math') || lower.contains('exam') || lower.contains('urgent')) {
      return CategoryTint.coral;
    } else if (lower.contains('physic') || lower.contains('doc') || lower.contains('read')) {
      return CategoryTint.blue;
    } else if (lower.contains('chem') || lower.contains('rev') || lower.contains('bio')) {
      return CategoryTint.mint;
    } else if (lower.contains('focus') || lower.contains('deep') || lower.contains('session')) {
      return CategoryTint.violet;
    } else if (lower.contains('ai') || lower.contains('ziku') || lower.contains('coach')) {
      return CategoryTint.amber;
    }
    return CategoryTint.blue;
  }
}

extension CategoryTintColors on CategoryTint {
  Color get background {
    switch (this) {
      case CategoryTint.coral:
        return const Color(0xFFFFF1F2);
      case CategoryTint.blue:
        return const Color(0xFFEFF6FF);
      case CategoryTint.mint:
        return const Color(0xFFECFDF5);
      case CategoryTint.violet:
        return const Color(0xFFF5F3FF);
      case CategoryTint.amber:
        return const Color(0xFFFFFBEB);
    }
  }

  Color get border {
    switch (this) {
      case CategoryTint.coral:
        return const Color(0xFFFECDD3);
      case CategoryTint.blue:
        return const Color(0xFFBFDBFE);
      case CategoryTint.mint:
        return const Color(0xFFA7F3D0);
      case CategoryTint.violet:
        return const Color(0xFFDDD6FE);
      case CategoryTint.amber:
        return const Color(0xFFFDE68A);
    }
  }

  Color get accent {
    switch (this) {
      case CategoryTint.coral:
        return const Color(0xFFE11D48);
      case CategoryTint.blue:
        return const Color(0xFF2563EB);
      case CategoryTint.mint:
        return const Color(0xFF059669);
      case CategoryTint.violet:
        return const Color(0xFF7C3AED);
      case CategoryTint.amber:
        return const Color(0xFFD97706);
    }
  }

  Color get chipBackground {
    switch (this) {
      case CategoryTint.coral:
        return const Color(0xFFFFE4E6);
      case CategoryTint.blue:
        return const Color(0xFFDBEAFE);
      case CategoryTint.mint:
        return const Color(0xFFD1FAE5);
      case CategoryTint.violet:
        return const Color(0xFFEDE9FE);
      case CategoryTint.amber:
        return const Color(0xFFFEF3C7);
    }
  }

  Color get chipText {
    switch (this) {
      case CategoryTint.coral:
        return const Color(0xFFBE123C);
      case CategoryTint.blue:
        return const Color(0xFF1D4ED8);
      case CategoryTint.mint:
        return const Color(0xFF047857);
      case CategoryTint.violet:
        return const Color(0xFF6D28D9);
      case CategoryTint.amber:
        return const Color(0xFFB45309);
    }
  }
}
