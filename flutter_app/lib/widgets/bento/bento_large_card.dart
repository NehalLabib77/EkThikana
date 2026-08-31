// BentoLargeCard — wide, hero-sized bento block.
//
// Layout:
//   ┌───────────────────────────────┐
//   │ [icon-pill]      [optional ⟶] │
//   │                                │
//   │ Title                          │
//   │ Subtitle / description         │
//   │                                │
//   │ [value / cta]                  │
//   └───────────────────────────────┘
//
// Used for: greeting, study-progress hero, AI card, BazarBuddy block,
// medicine "next dose" panel, etc.

import 'package:flutter/material.dart';

import 'bento_card.dart';
import 'bento_colors.dart';
import 'bento_icon.dart';

class BentoLargeCard extends StatelessWidget {
  const BentoLargeCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.moduleId,
    this.icon,
    this.background,
    this.trailing,
    this.footer,
    this.onTap,
    this.delay = Duration.zero,
    this.height,
  });

  final String title;
  final String subtitle;
  final String? moduleId;
  final IconData? icon;
  final Color? background;
  final Widget? trailing;
  final Widget? footer;
  final VoidCallback? onTap;
  final Duration delay;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final c = moduleId == null
        ? null
        : BentoColors.module(context, moduleId!);

    final bg = background ?? c?.tint ?? BentoColors.scaffold(context);

    return BentoCard(
      padding: const EdgeInsets.all(22),
      radius: 28,
      background: bg,
      onTap: onTap,
      delay: delay,
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              ?icon == null ? null : BentoIcon(icon: icon!, moduleId: moduleId),
              const Spacer(),
              ?trailing,
            ],
          ),
          const SizedBox(height: 18),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: BentoColors.onTint(context),
              fontSize: 19,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: BentoColors.onTintMuted(context),
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
          if (footer != null) ...[
            const SizedBox(height: 18),
            footer!,
          ],
        ],
      ),
    );
  }
}