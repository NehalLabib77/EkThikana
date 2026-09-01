// BentoIcon — small rounded square holding an icon, tinted with a
// module's accent color. Reused across bento cards to keep the
// "colorful feature blocks" feel without hardcoding hex per screen.

import 'package:flutter/material.dart';

import 'bento_colors.dart';

class BentoIcon extends StatelessWidget {
  const BentoIcon({
    super.key,
    required this.icon,
    this.moduleId,
    this.size = 38,
    this.iconSize = 20,
    this.background,
  });

  final IconData icon;
  final String? moduleId;
  final double size;
  final double iconSize;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final accent = moduleId == null
        ? BentoColors.studyAccent
        : BentoColors.module(context, moduleId!).accent;
    final bg = background ?? accent;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: Colors.white, size: iconSize),
    );
  }
}