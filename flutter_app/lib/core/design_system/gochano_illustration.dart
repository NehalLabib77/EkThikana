// Gochano static illustration engine (spec §10, §19–§22, §61, §95).
//
// Design decisions behind this file
// --------------------------------
// * **Static, always.** These are vector drawings, not animations. There is
//   no controller, no ticker and no implicit animation anywhere in this
//   file, and none may be added (spec §11).
//
// * **Drawn, not shipped as assets.** Every illustration is an inline SVG
//   body in [GochanoArt]. That keeps the whole visual language in one
//   reviewable place with one stroke width and one corner language (spec
//   §95: "consistent style, consistent stroke/shape language"), adds no
//   raster weight to the APK, can never pixelate, and is project-owned so
//   there is no third-party asset licence to track.
//
// * **Theme-aware by construction.** Each drawing is written against three
//   placeholder colours which are substituted at build time from
//   [GochanoColors]:
//
//     `{ink}`   – the stroke / primary shape colour
//     `{fill}`  – a soft tint used for supporting masses
//     `{paper}` – the interior "page" colour
//
//   `{paper}` is white in light mode and a dark surface in dark mode, which
//   is what stops illustrations punching white holes through a dark screen —
//   the failure the previous `assets/illustrations/*.svg` set had, because it
//   hardcoded `#FFFFFF` (spec §18).
//
// * **Never a missing image.** [GochanoIllustration] falls back to a generic
//   drawing when an id is unknown, so a custom subject name can never render
//   a broken or empty icon (spec §20).

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'gochano_art.dart';
import 'gochano_colors.dart';
import 'gochano_spacing.dart';

/// A static, theme-aware Gochano illustration.
///
/// ```dart
/// GochanoIllustration(GochanoArt.subjectPhysics, size: 40)
/// ```
///
/// Pass [accent] to tint the ink with a feature accent (e.g. the Study blue
/// on a subject card). Leave it null for the neutral illustration palette,
/// which is what most surfaces should use — spec §16 warns against making
/// every card a different saturated colour.
class GochanoIllustration extends StatelessWidget {
  const GochanoIllustration(
    this.id, {
    super.key,
    this.size = GochanoSizes.illustrationCard,
    this.accent,
    this.semanticLabel,
  });

  /// An id from [GochanoArt]. Unknown ids render [GochanoArt.generic].
  final String id;

  /// Rendered width and height in logical pixels. Drawings are square.
  final double size;

  /// Optional ink tint. When null the neutral illustration ink is used.
  final Color? accent;

  /// Screen-reader description. Pass null for purely decorative art that
  /// sits next to a text label that already says the same thing (spec §24 —
  /// do not make Talk-back read the same word twice).
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final svg = GochanoArt.resolve(
      id,
      ink: accent ?? colors.illustrationInk,
      fill: accent == null
          ? colors.illustrationFill
          : accent!.withValues(alpha: context.isDark ? 0.26 : 0.16),
      paper: colors.illustrationPaper,
    );

    return SizedBox(
      width: size,
      height: size,
      child: ExcludeSemantics(
        excluding: semanticLabel == null,
        child: Semantics(
          label: semanticLabel,
          image: true,
          child: SvgPicture.string(
            svg,
            width: size,
            height: size,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}

/// An illustration inside a soft rounded plate.
///
/// Use on list rows and cards where the drawing needs a consistent footprint
/// regardless of how wide or tall the individual drawing is — material rows,
/// subject rows, Life module tiles.
class GochanoIllustrationTile extends StatelessWidget {
  const GochanoIllustrationTile(
    this.id, {
    super.key,
    this.accent,
    this.plateSize = 44,
    this.semanticLabel,
  });

  final String id;
  final Color? accent;
  final double plateSize;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tint = accent ?? colors.textSecondary;
    return Container(
      width: plateSize,
      height: plateSize,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: context.isDark ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(GochanoRadius.md),
      ),
      alignment: Alignment.center,
      child: GochanoIllustration(
        id,
        size: plateSize * 0.62,
        accent: tint,
        semanticLabel: semanticLabel,
      ),
    );
  }
}
