import 'package:flutter/material.dart';

/// Centralized modern gradient tokens for Gochano.
class AppGradients {
  AppGradients._();

  // --- Semantic category & badge color tokens ---
  static const Color amberAccent = Color(0xFFD97706);
  static const Color amberSoft = Color(0xFFFEF3C7);
  static const Color amberDark = Color(0xFF92400E);
  static const Color amberOrange = Color(0xFFF59E0B);
  static const Color amberBorder = Color(0xFFFDE68A);
  static const Color orangeAccent = Color(0xFFF97316);
  static const Color orangeSoft = Color(0xFFFFEDD5);
  static const Color orangeDark = Color(0xFFB45309);
  static const Color violetAccent = Color(0xFF7C3AED);
  static const Color violetPrimary = Color(0xFF7048F5);
  static const Color violetSoft = Color(0xFFEDE9FE);
  static const Color violetLight = Color(0xFF8B5CF6);
  static const Color skyAccent = Color(0xFF0284C7);
  static const Color skyDark = Color(0xFF0C4A6E);
  static const Color indigoAccent = Color(0xFF6366F1);
  static const Color roseAccent = Color(0xFFF43F5E);
  static const Color emeraldDark = Color(0xFF059669);
  static const Color emeraldAccent = Color(0xFF10B981);
  static const Color emeraldSoft = Color(0xFFECFDF5);
  static const Color emeraldBorder = Color(0xFFA7F3D0);
  static const Color mintAccent = Color(0xFF34D399);
  static const Color slateBorder = Color(0xFFE2E8F0);
  static const Color slateText = Color(0xFF475569);

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

  /// Status pill soft green gradient.
  static const LinearGradient statusPill = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFF0FDF4), // Emerald 50
      Color(0xFFDCFCE7), // Emerald 100
    ],
  );

  /// Soft accent gradient for Ziku Coach cards (cyan -> soft blue).
  static const LinearGradient zikuCoach = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFF0FDFA), // Cyan 50
      Color(0xFFE0F2FE), // Sky 100
    ],
  );

  /// Focus session subtle background gradient (violet -> lavender -> soft blue).
  static const LinearGradient focusSession = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFFAF5FF), // Purple 50
      Color(0xFFEDE9FE), // Violet 100
      Color(0xFFE0E7FF), // Indigo 100
    ],
  );

  /// Continue Learning soft indigo / purple gradient.
  static const LinearGradient continueLearning = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFF5F3FF), // Purple 50
      Color(0xFFEEF2FF), // Indigo 50
    ],
  );

  /// Academic Health soft mint / teal / green gradient.
  static const LinearGradient academicHealth = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFF0FDF4), // Green 50
      Color(0xFFECFDF5), // Emerald 50
      Color(0xFFCCFBF1), // Teal 100
    ],
  );

  /// Today's Priorities subtle grouped container gradient.
  static const LinearGradient prioritiesContainer = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFFAFAFE), // Very soft lavender white
      Color(0xFFF1F5F9), // Slate 100
    ],
  );

  /// Fixed Today App Bar gradient (light mode):
  /// Soft brand blue (#EEF4FF) -> very light indigo (#F2EEFF) -> soft cyan (#E8F9FF)
  static const LinearGradient todayAppBar = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFEEF4FF), // Soft brand blue
      Color(0xFFF2EEFF), // Very light indigo
      Color(0xFFE8F9FF), // Soft cyan
    ],
    stops: [0.0, 0.5, 1.0],
  );

  /// Fixed Today App Bar gradient (dark mode):
  /// Deep slate (#0B1120) -> deep indigo navy (#0F172A) -> deep midnight (#111827)
  static const LinearGradient todayAppBarDark = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF0B1120), // Deep slate
      Color(0xFF0F172A), // Slate 900
      Color(0xFF111827), // Gray 900
    ],
    stops: [0.0, 0.5, 1.0],
  );

  /// Helper returning the appropriate today app bar gradient based on theme mode.
  static LinearGradient todayAppBarFor({required bool isDark}) =>
      isDark ? todayAppBarDark : todayAppBar;

  /// Workspace Tool Card Semantic Gradients (spec §5, §17):
  /// Notes: soft blue / cyan
  static const LinearGradient toolNotes = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFEFF6FF), // Blue 50
      Color(0xFFDBEAFE), // Blue 100
    ],
  );

  /// Flashcards: violet / purple
  static const LinearGradient toolFlashcards = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFFAF5FF), // Purple 50
      Color(0xFFEDE9FE), // Violet 100
    ],
  );

  /// Past Papers: emerald to mint (spec §4: #059669 -> #10B981 -> #34D399)
  static const LinearGradient toolPastPapers = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFECFDF5), // Emerald 50
      Color(0xFFD1FAE5), // Emerald 100
    ],
  );

  /// Mock Tests: coral / rose
  static const LinearGradient toolMockTests = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFFFF1F2), // Rose 50
      Color(0xFFFFE4E6), // Rose 100
    ],
  );

  /// Study Materials: sky blue to cyan (spec §4: #0284C7 -> #0EA5E9 -> #38BDF8)
  static const LinearGradient toolMaterials = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFF0F9FF), // Sky 50
      Color(0xFFE0F2FE), // Sky 100
    ],
  );

  /// Question Bank: indigo / lavender
  static const LinearGradient toolQuestionBank = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFEEF2FF), // Indigo 50
      Color(0xFFE0E7FF), // Indigo 100
    ],
  );

  /// Bookmarks / Saved: warm yellow
  static const LinearGradient toolBookmarks = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFFEFCE8), // Yellow 50
      Color(0xFFFEF9C3), // Yellow 100
    ],
  );

  /// Downloads / Shared Box: teal / cyan
  static const LinearGradient toolDownloads = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFF0FDFA), // Teal 50
      Color(0xFFCCFBF1), // Teal 100
    ],
  );


  /// Time-of-day greeting gradients:
  /// Early Morning (5:00 - 8:59): warm sunrise (peach -> pale yellow -> soft blue)
  static const LinearGradient greetingEarlyMorning = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFFFEDD5), // Peach / Orange 100
      Color(0xFFFEF3C7), // Amber 100
      Color(0xFFE0F2FE), // Sky 100
    ],
    stops: [0.0, 0.5, 1.0],
  );

  /// Morning (9:00 - 11:59): soft yellow -> light sky blue
  static const LinearGradient greetingMorning = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFFEF9C3), // Yellow 100
      Color(0xFFE0F2FE), // Sky 100
    ],
    stops: [0.0, 1.0],
  );

  /// Afternoon (12:00 - 16:59): soft sky blue -> cyan -> light lavender
  static const LinearGradient greetingAfternoon = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFE0F2FE), // Sky 100
      Color(0xFFE0F7FA), // Cyan 50
      Color(0xFFEDE9FE), // Violet 100
    ],
    stops: [0.0, 0.55, 1.0],
  );

  /// Evening (17:00 - 19:59): soft orange -> rose -> violet
  static const LinearGradient greetingEvening = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFFFEDD5), // Orange 100
      Color(0xFFFFE4E6), // Rose 100
      Color(0xFFEDE9FE), // Violet 100
    ],
    stops: [0.0, 0.5, 1.0],
  );

  /// Night (20:00 - 4:59): deep navy -> indigo -> soft violet
  static const LinearGradient greetingNight = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF0F172A), // Slate 900
      Color(0xFF1E1B4B), // Indigo 950
      Color(0xFF311042), // Dark Violet
    ],
    stops: [0.0, 0.55, 1.0],
  );

  // --- Page-level background gradient washes ---

  /// Workspace page background: very subtle indigo top wash fading to neutral.
  static const LinearGradient workspacePage = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFEEF2FF), Color(0xFFF7F8FA)],
    stops: [0.0, 0.35],
  );

  /// Plan page background: soft mint/emerald top wash.
  static const LinearGradient planPage = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFECFDF5), Color(0xFFF7F8FA)],
    stops: [0.0, 0.35],
  );

  /// Community page background: soft purple/violet top wash.
  static const LinearGradient communityPage = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFAF5FF), Color(0xFFF7F8FA)],
    stops: [0.0, 0.35],
  );

  /// Community Hub gradient wash
  static const LinearGradient communityHub = communityPage;

  /// You/Profile page background: soft sky blue top wash.
  static const LinearGradient youPage = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFE0F2FE), Color(0xFFF7F8FA)],
    stops: [0.0, 0.35],
  );

  /// Notes page background: soft blue top wash.
  static const LinearGradient notesPage = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFEFF6FF), Color(0xFFF7F8FA)],
    stops: [0.0, 1.0],
  );

  /// Focus page background: soft mint top wash.
  static const LinearGradient focusPage = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFECFDF5), Color(0xFFF7F8FA)],
    stops: [0.0, 1.0],
  );

  /// Exam hero gradient: indigo -> soft blue.
  static const LinearGradient examHero = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFEEF2FF),
      Color(0xFFE0E7FF),
    ],
  );

  /// Study packs tool background: indigo -> neutral.
  static const LinearGradient toolStudyPacks = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFFEEF2FF),
      Color(0xFFF7F8FA),
    ],
  );

  // --- Feature card gradients ---

  /// Profile identity header block: blue → sky → purple.
  static const LinearGradient profileHeader = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFEFF6FF), Color(0xFFE0F2FE), Color(0xFFF5F3FF)],
    stops: [0.0, 0.5, 1.0],
  );

  /// Download / offline card: emerald → teal.
  static const LinearGradient downloadCard = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFECFDF5), Color(0xFFCCFBF1)],
  );

  /// Plan task card: calm blue.
  static const LinearGradient planTask = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFEFF6FF), Color(0xFFDBEAFE)],
  );

  /// Plan goal card: warm teal.
  static const LinearGradient planGoal = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF0FDFA), Color(0xFFCCFBF1)],
  );

  /// Community group card: soft purple.
  static const LinearGradient communityGroup = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFAF5FF), Color(0xFFF3E8FF)],
  );

  /// Achievement / milestone gradient: warm amber.
  static const LinearGradient achievement = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFFBEB), Color(0xFFFEF3C7)],
  );

  /// Login screen hero gradient: deep indigo → violet → blue.
  static const LinearGradient loginHero = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF4F46E5), Color(0xFF7C3AED), Color(0xFF2563EB)],
    stops: [0.0, 0.55, 1.0],
  );

  /// Focus active session gradient: indigo → violet.
  static const LinearGradient focusActive = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
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
  LinearGradient get gradient {
    switch (this) {
      case CategoryTint.coral:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFF1F2), Color(0xFFFFE4E6)],
        );
      case CategoryTint.blue:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEFF6FF), Color(0xFFDBEAFE)],
        );
      case CategoryTint.mint:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFECFDF5), Color(0xFFD1FAE5)],
        );
      case CategoryTint.violet:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF5F3FF), Color(0xFFEDE9FE)],
        );
      case CategoryTint.amber:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFBEB), Color(0xFFFEF3C7)],
        );
    }
  }

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
