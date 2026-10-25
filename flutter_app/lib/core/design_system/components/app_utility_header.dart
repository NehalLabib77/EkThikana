// The reusable floating header surface for Gochano's Utility Mode screens.
//
// Study Mode has `AppStudyHeader`; Utility Mode (Home, Commute, Money,
// Profile) needs the same *visual family* — a compact inset floating surface
// with 18dp corners — but a different information architecture (Utility keeps
// a profile action and has no contextual calendar slot). So this is a sibling
// of the Study header, not a generalization of it, and it deliberately does
// not import it.
//
// What this component owns:
//   * the surface geometry — responsive horizontal inset (14dp, 10dp below
//     340dp), 4dp outer vertical margin, `GochanoRadius.appBarSurface` 18dp
//     corners, hairline border and a gentle light-mode elevation;
//   * the Gochano brand mark — the real logo asset (`AppAssets.logo`) ringed
//     in the contextual accent colour, so brand identity reads instantly
//     without spending vertical space on a wordmark or a tagline;
//   * the layout slot that right-aligns the parent's actions.
//
// What it deliberately does NOT own:
//   * navigation, authentication or notification state. Every visible control
//     is passed in by the parent as a pre-wired widget, so the parent keeps
//     ownership of its callbacks, its badge state and its routes;
//   * the language toggle instance — pass `const LanguageToggle()` as the
//     first action, exactly as Home does.
//
// Placement contract (HomeScreen is the reference integration):
//
// ```dart
// GochanoScaffold(
//   padBody: false,
//   body: AppPageBackground(
//     gradient: ...,
//     child: Column(children: [
//       AppUtilityHeader(accent: context.colors.brand, actions: [...]),
//       Expanded(child: RefreshIndicator(child: ListView(...))),
//     ]),
//   ),
// )
// ```
//
// `GochanoScaffold` applies `SafeArea(top: appBar == null)`, so with no
// Scaffold AppBar the header is pinned directly under the status bar and
// never scrolls with the dashboard. Never mount this inside the scroll view,
// and never nest it inside another AppBar.
//
// Contextual accent rollout contract (later waves, one screen at a time):
//   Home     -> `colors.brand`    (Gochano blue / cyan foundation)
//   Commute  -> `colors.commute`  (teal / sky)
//   Money    -> `colors.expense`  (emerald / indigo)
//   Profile  -> `colors.ai`       (violet / slate)
// Each screen composes its own parent-owned actions; the component itself
// gains no new behaviour for that rollout.

import 'package:flutter/material.dart';

import '../../localization/gochano_language.dart';
import '../app_assets.dart';
import '../gochano_colors.dart';
import '../gochano_spacing.dart';

class AppUtilityHeader extends StatelessWidget {
  const AppUtilityHeader({
    super.key,
    required this.actions,
    this.accent,
    this.logoSize = 31,
    this.semanticLabel,
  });

  /// Parent-owned trailing controls, rendered in order after the brand mark.
  ///
  /// Home passes: language switch, search, notifications (with unread
  /// badge), profile. Each entry keeps its own callback and state.
  final List<Widget> actions;

  /// Contextual accent for the surface border and the logo ring.
  ///
  /// Defaults to the Gochano brand colour, so a header that is not
  /// configured for a module is still on-brand.
  final Color? accent;

  /// Diameter of the ringed brand mark including the 1.5dp accent ring.
  final double logoSize;

  /// Announced by screen readers as the header landmark.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = context.isDark;
    final accentColor = accent ?? colors.brand;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Compact footprint: 60dp including the outer margin on a regular
        // phone, tighter horizontally on narrow devices (spec target
        // ~14dp / ~10dp outer insets).
        final isNarrow = constraints.maxWidth < 340;
        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isNarrow ? 10 : 14,
            vertical: 4,
          ),
          child: Semantics(
            container: true,
            header: true,
            label: semanticLabel ?? GochanoLanguage.text('Gochano', 'গোছানো'),
            child: Container(
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: GochanoRadius.appBarSurfaceAll,
                border: Border.all(
                  color: accentColor.withValues(alpha: isDark ? 0.30 : 0.22),
                  width: GochanoBorders.hairline,
                ),
                boxShadow: isDark
                    ? GochanoShadows.none // No dark-mode glow.
                    : GochanoShadows.overlay,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: GochanoSpacing.md,
                vertical: 4,
              ),
              child: ConstrainedBox(
                // Every action inside is at least 44dp tall, so the surface
                // never collapses below the accessible control floor.
                constraints: const BoxConstraints(minHeight: 44),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _BrandMark(
                      size: isNarrow ? logoSize - 2 : logoSize,
                      accentColor: accentColor,
                    ),
                    // The action cluster is right-aligned and only scales
                    // down when it genuinely cannot fit (320dp width at 2.0x
                    // text scaling) — a RenderFlex overflow would be worse
                    // than a briefly smaller hit target.
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final action in actions) action,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The real Gochano logo asset in a circular clip, ringed with the contextual
/// accent colour so the brand mark carries the module's colour without
/// adding text, a slogan or vertical height.
class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.size, required this.accentColor});

  final double size;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      image: true,
      excludeSemantics: true,
      label: GochanoLanguage.text('Gochano', 'গোছানো'),
      child: Container(
        width: size,
        height: size,
        padding: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: accentColor, width: 1.5),
        ),
        child: ClipOval(
          child: Image.asset(
            AppAssets.logo,
            fit: BoxFit.cover,
            semanticLabel: 'Gochano Logo',
            errorBuilder: (context, error, stackTrace) => ColoredBox(
              color: context.colors.brandSoft,
              child: Icon(
                Icons.bolt_rounded,
                size: size - 12,
                color: accentColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
