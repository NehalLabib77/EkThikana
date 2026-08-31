// Gochano Clean Minimalist colour system.
//
// One brand identity, calm neutral surfaces, restrained accents.
//
// Every colour a screen needs is a *semantic role* on [GochanoColors], which
// is registered as a [ThemeExtension] on both the light and dark ThemeData.
// Screens read `context.colors.textSecondary` rather than a hex literal, so
// dark mode is correct by construction instead of by per-screen patching.
//
// Deliberately absent:
//   * gradients as a design device (spec §9 / §15 — clarity over decoration);
//   * per-feature saturated card backgrounds (spec §16);
//   * colour as the sole carrier of status meaning (spec §24 — every status
//     token is paired with an icon/label at the call site).

import 'package:flutter/material.dart';

/// Semantic colour roles for the Gochano design system.
///
/// Resolve through `context.colors` (see the extension at the bottom of this
/// file) instead of instantiating directly.
@immutable
class GochanoColors extends ThemeExtension<GochanoColors> {
  const GochanoColors({
    required this.brand,
    required this.brandHover,
    required this.onBrand,
    required this.brandSoft,
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.surfaceElevated,
    required this.border,
    required this.borderStrong,
    required this.divider,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.disabled,
    required this.success,
    required this.successSoft,
    required this.warning,
    required this.warningSoft,
    required this.error,
    required this.errorSoft,
    required this.info,
    required this.infoSoft,
    required this.study,
    required this.ai,
    required this.expense,
    required this.medicine,
    required this.commute,
    required this.community,
    required this.illustrationInk,
    required this.illustrationFill,
    required this.illustrationPaper,
  });

  // --- Brand -------------------------------------------------------------
  /// Primary brand colour. Used for primary actions and the active state of
  /// navigation. Never used as a large filled background.
  final Color brand;

  /// Pressed/hovered variant of [brand].
  final Color brandHover;

  /// Text/icon colour that sits on top of [brand].
  final Color onBrand;

  /// Very low-chroma brand wash for selected chips and nav indicators.
  final Color brandSoft;

  // --- Neutral surfaces --------------------------------------------------
  /// App scaffold background. Slightly off-white / near-black so pure-white
  /// cards read as raised without needing a shadow (spec §15, §17).
  final Color background;

  /// Default card / sheet surface.
  final Color surface;

  /// Recessed surface: input fills, table stripes, inactive segments.
  final Color surfaceVariant;

  /// Surface for content that sits *above* a card (dialogs, menus).
  final Color surfaceElevated;

  /// Hairline used on cards and inputs.
  final Color border;

  /// Higher-contrast border for focused/selected outlines.
  final Color borderStrong;

  /// List separators.
  final Color divider;

  // --- Text --------------------------------------------------------------
  final Color textPrimary;
  final Color textSecondary;

  /// Lowest-emphasis text: timestamps, helper captions, units.
  final Color textTertiary;

  final Color disabled;

  // --- Status ------------------------------------------------------------
  // Each status has a bold role (icon/text) and a soft role (badge fill).
  final Color success;
  final Color successSoft;
  final Color warning;
  final Color warningSoft;
  final Color error;
  final Color errorSoft;
  final Color info;
  final Color infoSoft;

  // --- Feature accents (spec §16) ---------------------------------------
  // Restrained: used for a small icon, a 2px rule, or a chip — never as a
  // full-bleed card background.
  final Color study;
  final Color ai;
  final Color expense;
  final Color medicine;
  final Color commute;
  final Color community;

  // --- Static illustration palette --------------------------------------
  /// Primary stroke/fill of a static illustration.
  final Color illustrationInk;

  /// Secondary tinted fill inside an illustration.
  final Color illustrationFill;

  /// The "paper" colour inside illustrations. In light mode this is white;
  /// in dark mode it becomes a dark surface so illustrations do not punch
  /// white holes through a dark screen (spec §18).
  final Color illustrationPaper;

  /// Resolves a feature accent from a logical module id.
  ///
  /// Unknown ids fall back to [brand] so a new module never renders a
  /// missing/black accent.
  Color accentFor(String module) {
    switch (module) {
      case 'study':
        return study;
      case 'ai':
        return ai;
      case 'expense':
      case 'bazar':
      case 'grocery':
        return expense;
      case 'medicine':
        return medicine;
      case 'commute':
        return commute;
      case 'community':
      case 'groups':
        return community;
      default:
        return brand;
    }
  }

  /// Light theme roles.
  static const GochanoColors light = GochanoColors(
    brand: Color(0xFF4F46E5),
    brandHover: Color(0xFF4338CA),
    onBrand: Color(0xFFFFFFFF),
    brandSoft: Color(0xFFEEF0FF),
    background: Color(0xFFF7F8FA),
    surface: Color(0xFFFFFFFF),
    surfaceVariant: Color(0xFFF1F3F7),
    surfaceElevated: Color(0xFFFFFFFF),
    border: Color(0xFFE4E7EE),
    borderStrong: Color(0xFFC9CEDA),
    divider: Color(0xFFEDEFF4),
    textPrimary: Color(0xFF14161C),
    textSecondary: Color(0xFF565D6D),
    textTertiary: Color(0xFF828A9A),
    disabled: Color(0xFFACB2BF),
    success: Color(0xFF177245),
    successSoft: Color(0xFFE6F5EC),
    warning: Color(0xFF8A5300),
    warningSoft: Color(0xFFFDF1DC),
    error: Color(0xFFB3261E),
    errorSoft: Color(0xFFFCE9E7),
    info: Color(0xFF1B5FA8),
    infoSoft: Color(0xFFE7F0FB),
    study: Color(0xFF3556C8),
    ai: Color(0xFF6D4AC4),
    expense: Color(0xFF1B7A4B),
    medicine: Color(0xFF0F7C74),
    commute: Color(0xFF11688F),
    community: Color(0xFF9A5B22),
    illustrationInk: Color(0xFF3E4657),
    illustrationFill: Color(0xFFDDE2EC),
    illustrationPaper: Color(0xFFFFFFFF),
  );

  /// Dark theme roles.
  ///
  /// Not a mechanical inversion (spec §18): the background is a dark neutral,
  /// surfaces step *up* in lightness, borders stay low-contrast, and every
  /// accent is desaturated so it does not glow against the dark ground.
  static const GochanoColors dark = GochanoColors(
    brand: Color(0xFF9DA5F5),
    brandHover: Color(0xFFB3B9F8),
    onBrand: Color(0xFF11131F),
    brandSoft: Color(0xFF272B45),
    background: Color(0xFF101218),
    surface: Color(0xFF181B23),
    surfaceVariant: Color(0xFF20242E),
    surfaceElevated: Color(0xFF222630),
    border: Color(0xFF2C313D),
    borderStrong: Color(0xFF434A5A),
    divider: Color(0xFF262A34),
    textPrimary: Color(0xFFE9EBF0),
    textSecondary: Color(0xFFA9B0BE),
    textTertiary: Color(0xFF7C8494),
    disabled: Color(0xFF5A6172),
    success: Color(0xFF6FD79B),
    successSoft: Color(0xFF16301F),
    warning: Color(0xFFEFC078),
    warningSoft: Color(0xFF33260F),
    error: Color(0xFFF2A6A0),
    errorSoft: Color(0xFF3A1E1C),
    info: Color(0xFF8CBBEC),
    infoSoft: Color(0xFF152538),
    study: Color(0xFF8FA6EE),
    ai: Color(0xFFB49BE8),
    expense: Color(0xFF6FCB9B),
    medicine: Color(0xFF5FC7BD),
    commute: Color(0xFF74B9DC),
    community: Color(0xFFDCA771),
    illustrationInk: Color(0xFFB6BECD),
    illustrationFill: Color(0xFF2E3441),
    illustrationPaper: Color(0xFF181B23),
  );

  @override
  GochanoColors copyWith({
    Color? brand,
    Color? brandHover,
    Color? onBrand,
    Color? brandSoft,
    Color? background,
    Color? surface,
    Color? surfaceVariant,
    Color? surfaceElevated,
    Color? border,
    Color? borderStrong,
    Color? divider,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? disabled,
    Color? success,
    Color? successSoft,
    Color? warning,
    Color? warningSoft,
    Color? error,
    Color? errorSoft,
    Color? info,
    Color? infoSoft,
    Color? study,
    Color? ai,
    Color? expense,
    Color? medicine,
    Color? commute,
    Color? community,
    Color? illustrationInk,
    Color? illustrationFill,
    Color? illustrationPaper,
  }) {
    return GochanoColors(
      brand: brand ?? this.brand,
      brandHover: brandHover ?? this.brandHover,
      onBrand: onBrand ?? this.onBrand,
      brandSoft: brandSoft ?? this.brandSoft,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceVariant: surfaceVariant ?? this.surfaceVariant,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      divider: divider ?? this.divider,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      disabled: disabled ?? this.disabled,
      success: success ?? this.success,
      successSoft: successSoft ?? this.successSoft,
      warning: warning ?? this.warning,
      warningSoft: warningSoft ?? this.warningSoft,
      error: error ?? this.error,
      errorSoft: errorSoft ?? this.errorSoft,
      info: info ?? this.info,
      infoSoft: infoSoft ?? this.infoSoft,
      study: study ?? this.study,
      ai: ai ?? this.ai,
      expense: expense ?? this.expense,
      medicine: medicine ?? this.medicine,
      commute: commute ?? this.commute,
      community: community ?? this.community,
      illustrationInk: illustrationInk ?? this.illustrationInk,
      illustrationFill: illustrationFill ?? this.illustrationFill,
      illustrationPaper: illustrationPaper ?? this.illustrationPaper,
    );
  }

  @override
  GochanoColors lerp(ThemeExtension<GochanoColors>? other, double t) {
    if (other is! GochanoColors) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return GochanoColors(
      brand: c(brand, other.brand),
      brandHover: c(brandHover, other.brandHover),
      onBrand: c(onBrand, other.onBrand),
      brandSoft: c(brandSoft, other.brandSoft),
      background: c(background, other.background),
      surface: c(surface, other.surface),
      surfaceVariant: c(surfaceVariant, other.surfaceVariant),
      surfaceElevated: c(surfaceElevated, other.surfaceElevated),
      border: c(border, other.border),
      borderStrong: c(borderStrong, other.borderStrong),
      divider: c(divider, other.divider),
      textPrimary: c(textPrimary, other.textPrimary),
      textSecondary: c(textSecondary, other.textSecondary),
      textTertiary: c(textTertiary, other.textTertiary),
      disabled: c(disabled, other.disabled),
      success: c(success, other.success),
      successSoft: c(successSoft, other.successSoft),
      warning: c(warning, other.warning),
      warningSoft: c(warningSoft, other.warningSoft),
      error: c(error, other.error),
      errorSoft: c(errorSoft, other.errorSoft),
      info: c(info, other.info),
      infoSoft: c(infoSoft, other.infoSoft),
      study: c(study, other.study),
      ai: c(ai, other.ai),
      expense: c(expense, other.expense),
      medicine: c(medicine, other.medicine),
      commute: c(commute, other.commute),
      community: c(community, other.community),
      illustrationInk: c(illustrationInk, other.illustrationInk),
      illustrationFill: c(illustrationFill, other.illustrationFill),
      illustrationPaper: c(illustrationPaper, other.illustrationPaper),
    );
  }
}

/// `context.colors` — the single accessor every Gochano screen uses.
extension GochanoColorsX on BuildContext {
  GochanoColors get colors {
    return Theme.of(this).extension<GochanoColors>() ??
        (Theme.of(this).brightness == Brightness.dark
            ? GochanoColors.dark
            : GochanoColors.light);
  }

  /// True when the app is rendering the dark theme.
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}
