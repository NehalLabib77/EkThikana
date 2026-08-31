// BentoStatCard — single-line metric block with a module accent.
//
// Layout:
//   ┌────────────────────┐
//   │ [icon]             │
//   │                    │
//   │ 42                 │
//   │ Tasks              │
//   └────────────────────┘
//
// Used in bento dashboard rows where the headline value needs to
// stay prominent (tasks count, monthly spend, medicine count, etc.).

import 'package:flutter/material.dart';

import 'bento_card.dart';
import 'bento_colors.dart';

class BentoStatCard extends StatelessWidget {
  const BentoStatCard({
    super.key,
    required this.label,
    required this.value,
    this.moduleId,
    this.icon,
    this.background,
    this.onTap,
    this.height,
    this.padding = const EdgeInsets.all(20),
  });

  final String label;
  final String value;
  final String? moduleId;
  final IconData? icon;
  final Color? background;
  final VoidCallback? onTap;
  final double? height;
  final EdgeInsetsGeometry padding;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
          const Spacer(),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: BentoColors.onTint(context),
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: BentoColors.onTintMuted(context),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}