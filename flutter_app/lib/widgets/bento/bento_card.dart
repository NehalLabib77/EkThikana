// BentoCard — soft, large-radius, low-shadow surface for the new
// bento dashboard.
//
// Goals (per bento brief):
//   - 28px radius
//   - very soft shadow
//   - 20-24px padding
//   - subtle entrance animation (opacity 0->1, scale 0.95->1, 300ms)
//   - press scale 0.98 on tap
//   - theme-aware (light & dark scaffold)
//
// Kept self-contained inside `lib/widgets/bento/`. Other screens keep
// using `EkColors` / `EkSurfaces` until they are migrated.

import 'package:flutter/material.dart';

import 'bento_colors.dart';

/// Base bento surface. Use this as the root container for any
/// custom bento block; prefer [BentoLargeCard], [BentoSmallCard],
/// [BentoStatCard], or [BentoActionCard] for the common shapes.
class BentoCard extends StatefulWidget {
  const BentoCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(22),
    this.radius = 28,
    this.background,
    this.borderColor,
    this.onTap,
    this.animateIn = true,
    this.delay = Duration.zero,
    this.height,
    this.width,
    this.gradient,
    this.semanticsLabel,
    this.semanticsHint,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? background;
  final Color? borderColor;
  final VoidCallback? onTap;

  /// When true, the card fades + scales in on first paint.
  final bool animateIn;
  final Duration delay;

  final double? height;
  final double? width;
  final Gradient? gradient;

  /// Optional screen-reader label. When the card is tappable and this
  /// is set, the whole card becomes a single semantic button so TalkBack
  /// announces "open BazarBuddy" instead of reading every child text.
  final String? semanticsLabel;

  /// Optional screen-reader hint, e.g. "opens the shopping list".
  final String? semanticsHint;

  @override
  State<BentoCard> createState() => _BentoCardState();
}

class _BentoCardState extends State<BentoCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );

  bool _down = false;

  @override
  void initState() {
    super.initState();
    if (!widget.animateIn) {
      _c.value = 1;
      return;
    }
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
    final dark = Theme.of(context).brightness == Brightness.dark;

    final bg = widget.background ?? BentoColors.scaffold(context);
    final border = widget.borderColor ??
        (dark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.04));

    final shadow = dark
        ? const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ]
        : const [
            BoxShadow(
              color: Color(0x0F111827),
              blurRadius: 18,
              offset: Offset(0, 6),
            ),
          ];

    Widget card = AnimatedScale(
      scale: _down ? 0.98 : 1.0,
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOut,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          final t = Curves.easeOutCubic.transform(_c.value);
          return Opacity(
            opacity: t,
            child: Transform.scale(
              scale: 0.95 + 0.05 * t,
              alignment: Alignment.center,
              child: child,
            ),
          );
        },
        child: Container(
          height: widget.height,
          width: widget.width,
          padding: widget.padding,
          decoration: BoxDecoration(
            color: widget.gradient == null ? bg : null,
            gradient: widget.gradient,
            borderRadius: BorderRadius.circular(widget.radius),
            border: Border.all(color: border, width: 1),
            boxShadow: shadow,
          ),
          child: widget.child,
        ),
      ),
    );

    if (widget.onTap == null) return card;
    // Promote to a semantic button so screen readers announce one
    // button ("Open BazarBuddy") instead of every child label inside.
    return Semantics(
      button: true,
      label: widget.semanticsLabel,
      hint: widget.semanticsHint,
      excludeSemantics: widget.semanticsLabel != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        onTap: widget.onTap,
        child: card,
      ),
    );
  }
}