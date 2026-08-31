// Gochano spacing, radius, border and elevation tokens (spec §15).
//
// The scale is fixed. If a layout "needs" 13px, the layout is wrong, not the
// scale. Keeping every gap on this ladder is what makes unrelated screens
// read as one product.

import 'package:flutter/material.dart';

/// The Gochano spacing ladder: 4 / 8 / 12 / 16 / 20 / 24 / 32 / 40.
abstract final class GochanoSpacing {
  /// 4 — icon-to-label, inside a chip.
  static const double xxs = 4;

  /// 8 — between tightly related lines of text.
  static const double xs = 8;

  /// 12 — between rows in a list, between chips.
  static const double sm = 12;

  /// 16 — the default. Card padding, screen horizontal padding.
  static const double md = 16;

  /// 20 — generous card padding for hero surfaces.
  static const double lg = 20;

  /// 24 — between a section heading and the section above it.
  static const double xl = 24;

  /// 32 — between major sections on a scrolling page.
  static const double xxl = 32;

  /// 40 — top/bottom breathing room around an empty state.
  static const double xxxl = 40;

  /// Standard horizontal page inset.
  static const EdgeInsets page = EdgeInsets.symmetric(horizontal: md);

  /// Scroll-view padding that clears the bottom navigation bar so the last
  /// item is never trapped underneath it (spec §23).
  static const EdgeInsets scrollBody =
      EdgeInsets.fromLTRB(md, xs, md, xxxl + xxl);

  /// Default padding inside an [AppCard].
  static const EdgeInsets card = EdgeInsets.all(md);
}

/// Corner radii. Four steps, no ad-hoc values (spec §15).
abstract final class GochanoRadius {
  /// 8 — chips, badges, small inline surfaces.
  static const double sm = 8;

  /// 12 — inputs, buttons, list tiles.
  static const double md = 12;

  /// 16 — cards, the default surface radius.
  static const double lg = 16;

  /// 24 — bottom sheets and full-width hero surfaces.
  static const double xl = 24;

  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius xlAll = BorderRadius.all(Radius.circular(xl));

  /// Sheet radius: rounded on top only.
  static const BorderRadius sheet = BorderRadius.vertical(
    top: Radius.circular(xl),
  );
}

/// Border widths. Gochano separates surfaces with a hairline and background
/// contrast rather than with shadows (spec §15).
abstract final class GochanoBorders {
  static const double hairline = 1;
  static const double focus = 1.6;
}

/// Shadows.
///
/// Deliberately minimal: exactly one very soft shadow, used only where a
/// surface genuinely floats above content that scrolls under it (bottom
/// sheets, menus). Cards use a border, not a shadow.
abstract final class GochanoShadows {
  /// The single shadow colour in the app. Everything that needs a shadow
  /// tint references this rather than repeating the literal, which is what
  /// the `theme_parity_test` static guard enforces.
  static const Color color = Color(0x14000000);

  static const List<BoxShadow> none = <BoxShadow>[];

  /// For surfaces that overlay scrolling content.
  static const List<BoxShadow> overlay = <BoxShadow>[
    BoxShadow(color: color, blurRadius: 16, offset: Offset(0, 4)),
  ];
}

/// Minimum interactive sizes (spec §24).
abstract final class GochanoSizes {
  /// Android's minimum comfortable touch target.
  static const double minTouchTarget = 48;

  /// Height of a primary/secondary button.
  static const double buttonHeight = 48;

  /// Height of a text field.
  static const double fieldHeight = 52;

  /// Standard leading icon inside a list tile or card.
  static const double iconSm = 18;
  static const double iconMd = 22;
  static const double iconLg = 28;

  /// Static illustration sizes.
  static const double illustrationTile = 28;
  static const double illustrationCard = 40;
  static const double illustrationEmpty = 96;
}
