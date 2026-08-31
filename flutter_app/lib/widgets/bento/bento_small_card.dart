// BentoSmallCard — compact 1-of-2 bento tile (used inside rows).
//
// Layout:
//   ┌────────────────────────────┐
//   │ [icon-pill]      [value]   │
//   │ Title                      │
//   │ Subtitle                   │
//   └────────────────────────────┘
//
// Defaults to filling its parent's width and letting the parent row
// define the actual aspect. Used in pairs alongside
// [BentoStatCard] / [BentoActionCard].

import 'package:flutter/material.dart';

import 'bento_card.dart';
import 'bento_colors.dart';
import 'bento_icon.dart';

class BentoSmallCard extends StatelessWidget {
  const BentoSmallCard({
    super.key,
    required this.title,
    this.subtitle,
    this.moduleId,
    this.icon,
    this.background,
    this.value,
    this.onTap,
    this.height,
    this.padding = const EdgeInsets.all(20),
    this.semanticsLabel,
    this.semanticsHint,
    this.animateIn = true,
  });

  final String title;
  final String? subtitle;
  final String? moduleId;
  final IconData? icon;
  final Color? background;
  final String? value;
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

    return BentoCard(
      padding: padding,
      radius: 28,
      background: bg,
      onTap: onTap,
      height: height,
      animateIn: animateIn,
      semanticsLabel: semanticsLabel ?? title,
      semanticsHint: semanticsHint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              ?icon == null ? null : BentoIcon(icon: icon!, moduleId: moduleId),
              const Spacer(),
              ?value == null
                  ? null
                  : Text(
                      value!,
                      style: TextStyle(
                        color: BentoColors.onTint(context),
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.4,
                        height: 1.0,
                      ),
                    ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: BentoColors.onTint(context),
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
              height: 1.2,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: BentoColors.onTintMuted(context),
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
            ),
          ],
        ],
      ),
    );
  }
}