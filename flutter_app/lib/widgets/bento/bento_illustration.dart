// BentoIllustration — loads a monochrome cartoon SVG from
// `assets/illustrations/<module>.svg` and tints it with the module's
// accent color.
//
// Why SVG (no CustomPainter upgrade)?
//   * Crisp on every density without bundling raster art.
//   * One `Color` swap drives light/dark theme + active-pill tinting.
//   * Reused by the dashboard, Study Hub, BazarBuddy, and the floating
//     bottom nav so the visual language stays consistent.
//
// Visual contract (matches the bento brief):
//   * Sized box drawn inside a soft tinted disc — the cartoon sits on
//     top so it stays legible on dark or light tints.
//   * Defaults to a 96x96 footprint; pass `size` to scale.
//
// Module ids mirror `BentoColors.module()`.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'bento_colors.dart';

class BentoIllustration extends StatelessWidget {
  const BentoIllustration({
    super.key,
    required this.module,
    this.size = 72,
    this.background,
    this.tintWithAccent = true,
  });

  final String module;
  final double size;
  final Color? background;
  final bool tintWithAccent;

  @override
  Widget build(BuildContext context) {
    final mod = BentoColors.module(context, module);
    final accent = mod.accent;
    final bg = background ??
        (Theme.of(context).brightness == Brightness.dark
            ? accent.withValues(alpha: 0.25)
            : accent.withValues(alpha: 0.10));

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      alignment: Alignment.center,
      child: SvgPicture.asset(
        'assets/illustrations/$module.svg',
        width: size * 0.66,
        height: size * 0.66,
        colorFilter: tintWithAccent
            ? ColorFilter.mode(accent, BlendMode.srcIn)
            : null,
      ),
    );
  }
}
