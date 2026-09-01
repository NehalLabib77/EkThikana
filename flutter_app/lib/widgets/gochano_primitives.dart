// Gochano UI primitives.
//
// Composable widgets used across screens. Each one is built on top of
// `lib/core/design_tokens.dart` so consumers never hardcode colors /
// spacing / radii. Adopting a primitive is purely additive — existing
// screens keep working unchanged.
//
// Available:
//   - GradientStatCard          Module-aware hero / stat card with gradient.
//   - SoftTile                  Lower-emphasis alternative to a card.
//   - EmptyState                Empty-state pattern with illustration + CTA.
//   - GochanoChip               Pill chip with tone variants.
//   - ScaleTap                  InkWell replacement that gives a press scale.
//   - AnimatedFadeIn            One-shot fade + translate for first paint.
//   - StaggeredList             Wraps a children list and reveals items in
//                               sequence, never const-stripped away.

import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import 'empty_illustrations.dart';

/// Hero / stat card with a module gradient. Use for "Today in Study"
/// style dashboards, monthly spending, today's dose taken, etc.
///
/// Renders white text on top of the gradient because the gradients are
/// tuned to ≥4.5:1 contrast against pure white. For dark mode the
/// gradient is automatically replaced with its `moduleDark` variant
/// (which keeps the same brand hue but lowers chroma so the bright
/// text still reads cleanly).
class GradientStatCard extends StatelessWidget {
  const GradientStatCard({
    super.key,
    required this.module,
    required this.title,
    required this.value,
    this.delta,
    this.icon,
    this.subtitle,
    this.onTap,
    this.compact = false,
    this.semanticsLabel,
    this.semanticsHint,
  });

  /// Logical module id passed to [EkGradients.module]. Unknown ids fall
  /// back to the study gradient.
  final String module;

  /// Primary value string, e.g. "৳3,450" or "7 doses".
  final String value;

  /// Headline shown above the value, e.g. "Today's expense".
  final String title;

  /// Optional secondary line under the value.
  final String? subtitle;

  /// Optional small "+/-" delta line.
  final String? delta;

  /// Optional leading icon.
  final IconData? icon;

  /// Tap handler — adds a press-down scale gesture when set.
  final VoidCallback? onTap;

  /// Compact variant drops vertical padding for use in 2x2 tile grids.
  final bool compact;

  /// Optional semantic label for the tappable card. Defaults to
  /// ``"$title, $value"`` when [onTap] is non-null so screen readers
  /// announce something meaningful.
  final String? semanticsLabel;

  /// Optional hint spoken after the label, e.g. "opens expense details".
  final String? semanticsHint;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final gradient =
        dark ? EkGradients.moduleDark(module) : EkGradients.module(module);

    final card = RepaintBoundary(
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(EkRadius.xl),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(EkRadius.xl),
          child: Semantics(
            button: onTap != null,
            label: onTap == null
                ? null
                : (semanticsLabel ?? '$title, $value'),
            hint: onTap == null ? null : semanticsHint,
            excludeSemantics: onTap != null && semanticsLabel != null,
            child: Ink(
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(EkRadius.xl),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: EkSpace.lg,
                vertical: compact ? EkSpace.lg : EkSpace.xl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      if (icon != null) ...[
                        Icon(icon, color: Colors.white, size: EkIcon.md),
                        const SizedBox(width: EkSpace.sm),
                      ],
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (onTap != null)
                        const Icon(
                          Icons.chevron_right,
                          color: Colors.white70,
                          size: 18,
                        ),
                    ],
                  ),
                  SizedBox(height: compact ? EkSpace.md : EkSpace.lg),
                  Text(
                    value,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: compact ? 22 : 28,
                      fontWeight: FontWeight.w900,
                      height: 1.05,
                    ),
                  ),
                  if (subtitle != null || delta != null) ...[
                    const SizedBox(height: EkSpace.xs),
                    Row(
                      children: [
                        if (subtitle != null)
                          Expanded(
                            child: Text(
                              subtitle!,
                              // Pure white is required to keep the
                              // body-text contrast ratio above WCAG AA
                              // (4.5:1) on the lighter end of every
                              // module gradient. The visual hierarchy
                              // between title (700) and subtitle (500)
                              // still comes from weight + size, not
                              // from fading the colour.
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        if (delta != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: EkSpace.sm,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .20),
                              borderRadius: BorderRadius.circular(
                                EkRadius.pill,
                              ),
                            ),
                            child: Text(
                              delta!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          ),
        ),
      ),
    );

    return card;
  }
}

/// Lower-emphasis flat surface card. Use for tiles that should sit
/// alongside a GradientStatCard without competing for attention.
class SoftTile extends StatelessWidget {
  const SoftTile({
    super.key,
    required this.module,
    required this.child,
    this.padding = const EdgeInsets.all(EkSpace.lg),
    this.onTap,
    this.radius,
    this.semanticsLabel,
    this.semanticsHint,
  });

  final String module;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double? radius;
  final String? semanticsLabel;
  final String? semanticsHint;

  @override
  Widget build(BuildContext context) {
    final bg = EkSoft.module(context, module);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius ?? EkRadius.lg),
      side: BorderSide(color: EkSurfaces.line(context).withValues(alpha: .35)),
    );

    return Material(
      color: bg,
      shape: shape,
      child: Semantics(
        button: onTap != null,
        label: onTap == null ? null : semanticsLabel,
        hint: onTap == null ? null : semanticsHint,
        excludeSemantics: onTap != null && semanticsLabel != null,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(radius ?? EkRadius.lg),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Standard empty-state placeholder. The illustration is themed to the
/// module so each "nothing here yet" surface looks intentional, not
/// generic.
///
/// `primaryActionLabel` + `onPrimaryAction` render a solid CTA button.
/// `secondaryActionLabel` + `onSecondaryAction` render an outlined CTA.
///
/// Localize your own strings before passing them in; the widget itself
/// stays language-agnostic.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.module,
    required this.title,
    this.message,
    this.primaryActionLabel,
    this.onPrimaryAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
    this.compact = false,
  });

  final String module;
  final String title;
  final String? message;
  final String? primaryActionLabel;
  final VoidCallback? onPrimaryAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;

  /// Drops padding for use as an inline list empty cell (e.g. tasks tab).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final accent = _accentFor(module, context);

    final illustration = SizedBox(
      width: compact ? 96 : 140,
      height: compact ? 96 : 140,
      child: CustomPaint(
        painter: EmptyIllustrationPainter(
          module: module,
          accent: accent,
          muted: EkSurfaces.muted(context),
        ),
      ),
    );

    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: EkSpace.xl,
          vertical: compact ? EkSpace.lg : EkSpace.xxl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            illustration,
            SizedBox(height: compact ? EkSpace.md : EkSpace.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: EkText.title(context).copyWith(fontSize: 18),
            ),
            if (message != null) ...[
              const SizedBox(height: EkSpace.xs),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: EkText.body(context).copyWith(
                  color: EkSurfaces.muted(context),
                ),
              ),
            ],
            if (primaryActionLabel != null && onPrimaryAction != null) ...[
              const SizedBox(height: EkSpace.lg),
              FilledButton(
                onPressed: onPrimaryAction,
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  minimumSize: const Size(0, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(EkRadius.md),
                  ),
                ),
                child: Text(primaryActionLabel!),
              ),
            ],
            if (secondaryActionLabel != null && onSecondaryAction != null) ...[
              const SizedBox(height: EkSpace.sm),
              OutlinedButton(
                onPressed: onSecondaryAction,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(EkRadius.md),
                  ),
                ),
                child: Text(secondaryActionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _accentFor(String module, BuildContext context) {
    switch (module) {
      case 'study':
        return const Color(0xFF5B3DF5);
      case 'medicine':
        return const Color(0xFF16B8AD);
      case 'expense':
        return const Color(0xFFFF8A1E);
      case 'commute':
        return const Color(0xFF1B72CC);
      case 'bazar':
        return const Color(0xFFE0388A);
      case 'tasks':
        return const Color(0xFF5B3DF5);
      case 'ai':
        return const Color(0xFF109238);
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }
}

/// Standard branded pill / chip with 4 tones. The `tone` enum chooses
/// the color pair (background + foreground) so a screen can group
/// status badges semantically instead of color-by-color.
class GochanoChip extends StatelessWidget {
  const GochanoChip({
    super.key,
    required this.label,
    this.tone = GochanoChipTone.neutral,
    this.icon,
  });

  /// Default text-only chip.
  const GochanoChip.text(String text, {Key? key, GochanoChipTone? tone})
      : this(label: text, key: key, tone: tone ?? GochanoChipTone.neutral);

  final String label;
  final GochanoChipTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final palette = _palette(tone, context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: palette.bg,
        borderRadius: BorderRadius.circular(EkRadius.pill),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: palette.fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: palette.fg,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  _ChipPalette _palette(GochanoChipTone tone, BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    switch (tone) {
      case GochanoChipTone.success:
        return _ChipPalette(
          bg: dark ? const Color(0xFF102818) : const Color(0xFFE6F7EA),
          fg: dark ? const Color(0xFF7ED8A0) : const Color(0xFF126C25),
          border: dark ? const Color(0xFF1F4A2C) : const Color(0xFFB8E0C2),
        );
      case GochanoChipTone.warning:
        return _ChipPalette(
          bg: dark ? const Color(0xFF3A2510) : const Color(0xFFFFF3DC),
          fg: dark ? const Color(0xFFF1C26B) : const Color(0xFF8A4A0E),
          border: dark ? const Color(0xFF6E4719) : const Color(0xFFF1D27A),
        );
      case GochanoChipTone.danger:
        return _ChipPalette(
          bg: dark ? const Color(0xFF3A182A) : const Color(0xFFFFECEC),
          fg: dark ? const Color(0xFFF08080) : const Color(0xFFB5302F),
          border: dark ? const Color(0xFF6E2C44) : const Color(0xFFEFC1C1),
        );
      case GochanoChipTone.info:
        return _ChipPalette(
          bg: dark ? const Color(0xFF0F2540) : const Color(0xFFE8F2FF),
          fg: dark ? const Color(0xFF7FB3E0) : const Color(0xFF103E80),
          border: dark ? const Color(0xFF1F3F66) : const Color(0xFFBFD7F2),
        );
      case GochanoChipTone.neutral:
        return _ChipPalette(
          bg: EkSurfaces.card(context),
          fg: EkSurfaces.text(context),
          border: EkSurfaces.line(context),
        );
    }
  }
}

enum GochanoChipTone { neutral, success, warning, danger, info }

class _ChipPalette {
  const _ChipPalette({required this.bg, required this.fg, required this.border});
  final Color bg;
  final Color fg;
  final Color border;
}

/// InkWell replacement that adds a subtle scale-down + opacity dip while
/// pressed. Use on tappable surfaces that should feel "alive" without
/// pulling in [Material] / splash ripples twice.
///
/// Wraps the gesture in a [Semantics] button node so screen readers
/// announce one labeled button instead of reading every child text.
class ScaleTap extends StatefulWidget {
  const ScaleTap({
    super.key,
    required this.child,
    required this.onTap,
    this.borderRadius,
    this.semanticsLabel,
    this.semanticsHint,
  });

  final Widget child;
  final VoidCallback onTap;
  final BorderRadius? borderRadius;

  /// When provided, the wrapper is promoted to a semantic button with
  /// this label — typically the visible text on the tappable surface.
  final String? semanticsLabel;

  /// Optional hint spoken by TalkBack, e.g. "opens details".
  final String? semanticsHint;

  @override
  State<ScaleTap> createState() => _ScaleTapState();
}

class _ScaleTapState extends State<ScaleTap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: EkMotion.fast,
    lowerBound: 0.0,
    upperBound: 1.0,
    value: 1.0,
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _setPressed(bool pressed) {
    if (pressed) {
      _c.animateTo(0.0, duration: EkMotion.fast, curve: Curves.easeOut);
    } else {
      _c.animateTo(1.0, duration: EkMotion.fast, curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.semanticsLabel,
      hint: widget.semanticsHint,
      excludeSemantics: widget.semanticsLabel != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onTap: widget.onTap,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.97, end: 1.0).animate(
            CurvedAnimation(parent: _c, curve: Curves.easeOut),
          ),
          child: ClipRRect(
            borderRadius: widget.borderRadius ?? BorderRadius.circular(EkRadius.lg),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// One-shot fade + tiny slide-up, intended for first-paint reveals on
/// dashboard cards. Wrapping a tree in this once avoids re-running the
/// animation on rebuilds.
class AnimatedFadeIn extends StatefulWidget {
  const AnimatedFadeIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = EkMotion.hero,
    this.offset = 16,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final double offset;

  @override
  State<AnimatedFadeIn> createState() => _AnimatedFadeInState();
}

class _AnimatedFadeInState extends State<AnimatedFadeIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration);

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (!mounted) return;
      _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = _c.value;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * widget.offset),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Walks a static list of children and reveals each with [AnimatedFadeIn]
/// using a small cascaded delay. Keeps first-paint animations from
/// looking like every card appeared at exactly the same moment.
class StaggeredList extends StatelessWidget {
  const StaggeredList({
    super.key,
    required this.children,
    this.spacing = EkSpace.lg,
    this.baseDelay = Duration.zero,
    this.step = const Duration(milliseconds: 70),
  });

  final List<Widget> children;
  final double spacing;
  final Duration baseDelay;
  final Duration step;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          AnimatedFadeIn(
            delay: baseDelay + (step * i),
            child: children[i],
          ),
          if (i != children.length - 1) SizedBox(height: spacing),
        ],
      ],
    );
  }
}

/// Soft skeleton block. Use while async data is loading so the layout
/// stops jumping around once the data arrives.
class SoftSkeleton extends StatefulWidget {
  const SoftSkeleton({
    super.key,
    this.height = 16,
    this.width,
    this.radius = EkRadius.sm,
  });

  final double height;
  final double? width;
  final double radius;

  @override
  State<SoftSkeleton> createState() => _SoftSkeletonState();
}

class _SoftSkeletonState extends State<SoftSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? const Color(0xFF273244) : const Color(0xFFE9EAF2);
    final hi = isDark ? const Color(0xFF334155) : const Color(0xFFF4F5FA);

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          return Container(
            width: widget.width ?? double.infinity,
            height: widget.height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.radius),
              gradient: LinearGradient(
                colors: [base, hi, base],
                stops: [
                  (0.0 + t * 0.5).clamp(0.0, 1.0),
                  (0.5 + t * 0.0).clamp(0.0, 1.0),
                  (1.0 - t * 0.5).clamp(0.0, 1.0),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Convenience: branded divider that adapts to the active theme.
class SoftDivider extends StatelessWidget {
  const SoftDivider({super.key, this.indent = 0, this.thickness = 1});

  final double indent;
  final double thickness;

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: thickness,
      thickness: thickness,
      indent: indent,
      color: EkSurfaces.line(context).withValues(alpha: .55),
    );
  }
}
