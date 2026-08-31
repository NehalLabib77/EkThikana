// Gochano ThemeData — Material 3 foundation, Gochano surface (spec §13).
//
// Material 3 supplies the interaction model: ripples, focus traversal, field
// semantics, dialog/sheet anatomy, Talk-back plumbing. Gochano supplies the
// *look*: flat surfaces, hairline borders, one type scale, restrained accent.
//
// Everything a component needs is configured here once, so screens do not
// re-style buttons, fields, chips or sheets locally. That is what keeps
// unrelated screens looking like one product (spec §108: consistency over
// screen-by-screen experimentation).
//
// Note on motion: `pageTransitionsTheme` is left at the platform default.
// Gochano adds no custom transitions and no decorative motion (spec §11);
// the unavoidable framework page transition is the only movement in the app.

import 'package:flutter/material.dart';

import 'gochano_colors.dart';
import 'gochano_spacing.dart';
import 'gochano_typography.dart';

abstract final class GochanoTheme {
  static ThemeData light() => _build(GochanoColors.light, Brightness.light);

  static ThemeData dark() => _build(GochanoColors.dark, Brightness.dark);

  static ThemeData _build(GochanoColors c, Brightness brightness) {
    final type = GochanoTypography(c);
    final isDark = brightness == Brightness.dark;

    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.brand,
      onPrimary: c.onBrand,
      primaryContainer: c.brandSoft,
      onPrimaryContainer: isDark ? c.textPrimary : c.brandHover,
      secondary: c.study,
      onSecondary: c.onBrand,
      secondaryContainer: c.surfaceVariant,
      onSecondaryContainer: c.textPrimary,
      tertiary: c.ai,
      onTertiary: c.onBrand,
      error: c.error,
      onError: isDark ? const Color(0xFF11131F) : Colors.white,
      errorContainer: c.errorSoft,
      onErrorContainer: c.error,
      surface: c.surface,
      onSurface: c.textPrimary,
      surfaceContainerLowest: c.background,
      surfaceContainerLow: c.background,
      surfaceContainer: c.surface,
      surfaceContainerHigh: c.surfaceVariant,
      surfaceContainerHighest: c.surfaceElevated,
      onSurfaceVariant: c.textSecondary,
      outline: c.border,
      outlineVariant: c.divider,
      shadow: GochanoShadows.color,
      scrim: const Color(0x99000000),
      inverseSurface: c.textPrimary,
      onInverseSurface: c.surface,
      inversePrimary: c.brandSoft,
    );

    OutlineInputBorder fieldBorder(Color color, double width) =>
        OutlineInputBorder(
          borderRadius: GochanoRadius.mdAll,
          borderSide: BorderSide(color: color, width: width),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.background,
      canvasColor: c.background,
      fontFamily: GochanoTypography.fontFamily,
      textTheme: type.materialTextTheme,
      extensions: <ThemeExtension<dynamic>>[c],

      // Flat by default: no surface tint bleeding brand colour into every
      // elevated widget, which is what makes stock M3 look purple-washed.
      applyElevationOverlayColor: false,

      splashFactory: InkRipple.splashFactory,

      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: c.background,
        foregroundColor: c.textPrimary,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: type.pageTitle,
        iconTheme: IconThemeData(color: c.textPrimary, size: GochanoSizes.iconMd),
        actionsIconTheme:
            IconThemeData(color: c.textSecondary, size: GochanoSizes.iconMd),
      ),

      cardTheme: CardThemeData(
        elevation: 0,
        color: c.surface,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: GochanoRadius.lgAll,
          side: BorderSide(color: c.border, width: GochanoBorders.hairline),
        ),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.surface,
        indicatorColor: c.brandSoft,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 68,
        indicatorShape: const RoundedRectangleBorder(
          borderRadius: GochanoRadius.smAll,
        ),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => type.caption.copyWith(
            fontSize: 11.5,
            color: states.contains(WidgetState.selected)
                ? c.brand
                : c.textSecondary,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: GochanoSizes.iconMd,
            color:
                states.contains(WidgetState.selected) ? c.brand : c.textSecondary,
          ),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: GochanoSpacing.md,
          vertical: 14,
        ),
        border: fieldBorder(c.border, GochanoBorders.hairline),
        enabledBorder: fieldBorder(c.border, GochanoBorders.hairline),
        focusedBorder: fieldBorder(c.brand, GochanoBorders.focus),
        errorBorder: fieldBorder(c.error, GochanoBorders.hairline),
        focusedErrorBorder: fieldBorder(c.error, GochanoBorders.focus),
        disabledBorder: fieldBorder(c.divider, GochanoBorders.hairline),
        labelStyle: type.label,
        floatingLabelStyle: type.label.copyWith(color: c.brand),
        hintStyle: type.body.copyWith(color: c.textTertiary),
        helperStyle: type.caption,
        errorStyle: type.caption.copyWith(color: c.error),
        prefixIconColor: c.textSecondary,
        suffixIconColor: c.textSecondary,
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.brand,
          foregroundColor: c.onBrand,
          disabledBackgroundColor: c.surfaceVariant,
          disabledForegroundColor: c.disabled,
          minimumSize: const Size(0, GochanoSizes.buttonHeight),
          padding: const EdgeInsets.symmetric(horizontal: GochanoSpacing.lg),
          textStyle: type.button,
          elevation: 0,
          shape: const RoundedRectangleBorder(borderRadius: GochanoRadius.mdAll),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.textPrimary,
          disabledForegroundColor: c.disabled,
          minimumSize: const Size(0, GochanoSizes.buttonHeight),
          padding: const EdgeInsets.symmetric(horizontal: GochanoSpacing.lg),
          textStyle: type.button,
          side: BorderSide(color: c.borderStrong, width: GochanoBorders.hairline),
          shape: const RoundedRectangleBorder(borderRadius: GochanoRadius.mdAll),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.brand,
          disabledForegroundColor: c.disabled,
          minimumSize: const Size(0, GochanoSizes.minTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: GochanoSpacing.sm),
          textStyle: type.button,
          shape: const RoundedRectangleBorder(borderRadius: GochanoRadius.smAll),
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: c.textSecondary,
          minimumSize: const Size(
            GochanoSizes.minTouchTarget,
            GochanoSizes.minTouchTarget,
          ),
        ),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.brand,
        foregroundColor: c.onBrand,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: GochanoRadius.lgAll),
        extendedTextStyle: type.button,
      ),

      chipTheme: ChipThemeData(
        backgroundColor: c.surface,
        selectedColor: c.brandSoft,
        disabledColor: c.surfaceVariant,
        checkmarkColor: c.brand,
        labelStyle: type.label.copyWith(color: c.textPrimary),
        secondaryLabelStyle: type.label.copyWith(color: c.brand),
        side: BorderSide(color: c.border, width: GochanoBorders.hairline),
        padding: const EdgeInsets.symmetric(
          horizontal: GochanoSpacing.sm,
          vertical: GochanoSpacing.xs,
        ),
        shape: const RoundedRectangleBorder(borderRadius: GochanoRadius.smAll),
        showCheckmark: true,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: c.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: GochanoRadius.xlAll,
          side: BorderSide(color: c.border, width: GochanoBorders.hairline),
        ),
        titleTextStyle: type.sectionHeading,
        contentTextStyle: type.body.copyWith(color: c.textSecondary),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        showDragHandle: true,
        dragHandleColor: c.borderStrong,
        shape: const RoundedRectangleBorder(borderRadius: GochanoRadius.sheet),
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: c.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        textStyle: type.body,
        shape: RoundedRectangleBorder(
          borderRadius: GochanoRadius.mdAll,
          side: BorderSide(color: c.border, width: GochanoBorders.hairline),
        ),
      ),

      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(c.surfaceElevated),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(0),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: GochanoRadius.mdAll,
              side: BorderSide(color: c.border, width: GochanoBorders.hairline),
            ),
          ),
        ),
      ),

      listTileTheme: ListTileThemeData(
        iconColor: c.textSecondary,
        textColor: c.textPrimary,
        titleTextStyle: type.cardHeading,
        subtitleTextStyle: type.bodySecondary,
        minVerticalPadding: GochanoSpacing.sm,
        shape: const RoundedRectangleBorder(borderRadius: GochanoRadius.mdAll),
      ),

      tabBarTheme: TabBarThemeData(
        labelColor: c.brand,
        unselectedLabelColor: c.textSecondary,
        labelStyle: type.button,
        unselectedLabelStyle: type.button.copyWith(fontWeight: FontWeight.w500),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: c.divider,
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: c.brand, width: 2.5),
        ),
        overlayColor: WidgetStatePropertyAll(c.brand.withValues(alpha: 0.06)),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? c.surfaceElevated : c.textPrimary,
        contentTextStyle: type.body.copyWith(
          color: isDark ? c.textPrimary : c.surface,
        ),
        actionTextColor: isDark ? c.brand : c.brandSoft,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: GochanoRadius.mdAll),
      ),

      dividerTheme: DividerThemeData(
        color: c.divider,
        thickness: GochanoBorders.hairline,
        space: GochanoBorders.hairline,
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.onBrand : c.surface,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.brand : c.surfaceVariant,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.brand : c.borderStrong,
        ),
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.brand : Colors.transparent,
        ),
        checkColor: WidgetStatePropertyAll(c.onBrand),
        side: BorderSide(color: c.borderStrong, width: 1.6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),

      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.brand : c.borderStrong,
        ),
      ),

      // Determinate where possible (spec §12): a percentage tells the student
      // something; a spinning ring does not.
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.brand,
        linearTrackColor: c.surfaceVariant,
        circularTrackColor: c.surfaceVariant,
        linearMinHeight: 6,
      ),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? c.surfaceElevated : c.textPrimary,
          borderRadius: GochanoRadius.smAll,
        ),
        textStyle: type.caption.copyWith(
          color: isDark ? c.textPrimary : c.surface,
        ),
      ),

      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? c.brandSoft : c.surface,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? c.brand : c.textSecondary,
          ),
          side: WidgetStatePropertyAll(
            BorderSide(color: c.border, width: GochanoBorders.hairline),
          ),
          textStyle: WidgetStatePropertyAll(type.button),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: GochanoRadius.mdAll),
          ),
        ),
      ),
    );
  }
}
