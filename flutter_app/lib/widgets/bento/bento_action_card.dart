// BentoActionCard — CTA-style block that pairs a module tint with an
// arrow pill. Used on the dashboard for primary actions like
// "Add medicine", "Open BazarBuddy", etc.

import 'package:flutter/material.dart';

import 'bento_card.dart';
import 'bento_colors.dart';

class BentoActionCard extends StatelessWidget {
  const BentoActionCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.moduleId,
    this.background,
    this.onTap,
    this.height,
    this.padding = const EdgeInsets.all(20),
    this.semanticsLabel,
    this.semanticsHint,
    this.animateIn = true,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String? moduleId;
  final Color? background;
  final VoidCallback? onTap;
  final double? height;
  final EdgeInsetsGeometry padding;
  final String? semanticsLabel;
  final String? semanticsHint;
  final bool animateIn;

  @override
  Widget build(BuildContext context) {
    final c = moduleId == null
        ? null
        : BentoColors.module(context, moduleId!);
    final bg = background ?? c?.tint ?? BentoColors.scaffold(context);
    final accent = c?.accent ?? BentoColors.studyAccent;

    return BentoCard(
      padding: padding,
      radius: 28,
      background: bg,
      onTap: onTap,
      height: height,
      animateIn: animateIn,
      semanticsLabel: semanticsLabel ?? title,
      semanticsHint: semanticsHint,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: BentoColors.onTint(context),
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: BentoColors.onTintMuted(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.arrow_forward_rounded, size: 16, color: accent),
          ),
        ],
      ),
    );
  }
}