// Gochano type scale (spec §15).
//
// One scale, named by *role* rather than by size, so a screen never invents
// `fontSize: 17`. Sizes are expressed in logical pixels and scale with the
// platform text-scale factor; nothing here pins a text size against scaling.
//
// Bangla note: the app ships Bangla strings that render taller than Latin at
// the same point size. Every role therefore carries generous `height` (line
// height) so Bangla ascenders/descenders are not clipped (spec §23, §73).

import 'package:flutter/material.dart';

import 'gochano_colors.dart';

/// Named text roles for the Gochano design system.
///
/// Resolve through `context.type` and colour them with `context.colors`:
///
/// ```dart
/// Text(title, style: context.type.cardHeading)
/// ```
///
/// Every getter already applies [GochanoColors.textPrimary] or
/// [GochanoColors.textSecondary]; override with `.copyWith(color: …)` only
/// when the role genuinely differs (e.g. an error message).
@immutable
class GochanoTypography {
  const GochanoTypography(this._colors);

  final GochanoColors _colors;

  static const String fontFamily = 'HindSiliguri';

  TextStyle get _base => TextStyle(
        fontFamily: fontFamily,
        color: _colors.textPrimary,
        letterSpacing: 0,
      );

  /// Largest role. Reserved for a single number or word on an otherwise
  /// empty surface (focus timer, onboarding). Not for page titles.
  TextStyle get display => _base.copyWith(
        fontSize: 34,
        height: 1.22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      );

  /// The one H1 on a screen — usually the AppBar title or a hero header.
  TextStyle get pageTitle => _base.copyWith(
        fontSize: 24,
        height: 1.30,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      );

  /// Groups a set of cards or rows below it.
  TextStyle get sectionHeading => _base.copyWith(
        fontSize: 17,
        height: 1.35,
        fontWeight: FontWeight.w600,
      );

  /// Title inside a card / list tile.
  TextStyle get cardHeading => _base.copyWith(
        fontSize: 15,
        height: 1.40,
        fontWeight: FontWeight.w600,
      );

  /// Default reading text.
  TextStyle get body => _base.copyWith(
        fontSize: 14.5,
        height: 1.50,
        fontWeight: FontWeight.w400,
      );

  /// Supporting text under a heading or inside a card.
  TextStyle get bodySecondary => _base.copyWith(
        fontSize: 13.5,
        height: 1.50,
        fontWeight: FontWeight.w400,
        color: _colors.textSecondary,
      );

  /// Text inside buttons. Slightly tighter and heavier than [body].
  TextStyle get button => _base.copyWith(
        fontSize: 14.5,
        height: 1.20,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      );

  /// Field labels, chip text, tab labels.
  TextStyle get label => _base.copyWith(
        fontSize: 13,
        height: 1.35,
        fontWeight: FontWeight.w500,
        color: _colors.textSecondary,
      );

  /// Timestamps, file sizes, helper text, footnotes.
  TextStyle get caption => _base.copyWith(
        fontSize: 12,
        height: 1.40,
        fontWeight: FontWeight.w400,
        color: _colors.textTertiary,
      );

  /// Large figures on stat tiles (amounts, counts, durations).
  ///
  /// Uses tabular figures so a column of numbers stays aligned as values
  /// change — important for the expense ledger and the focus timer.
  TextStyle get statistic => _base.copyWith(
        fontSize: 26,
        height: 1.15,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// Smaller sibling of [statistic] for secondary metrics in a bento tile.
  TextStyle get statisticSmall => _base.copyWith(
        fontSize: 19,
        height: 1.20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// Builds a Material [TextTheme] so stock Material widgets inherit the
  /// same scale as Gochano components.
  TextTheme get materialTextTheme => TextTheme(
        displaySmall: display,
        headlineMedium: pageTitle,
        headlineSmall: pageTitle,
        titleLarge: pageTitle,
        titleMedium: sectionHeading,
        titleSmall: cardHeading,
        bodyLarge: body,
        bodyMedium: body,
        bodySmall: bodySecondary,
        labelLarge: button,
        labelMedium: label,
        labelSmall: caption,
      );
}

/// `context.type` — the type-scale accessor for every Gochano screen.
extension GochanoTypographyX on BuildContext {
  GochanoTypography get type => GochanoTypography(colors);
}
