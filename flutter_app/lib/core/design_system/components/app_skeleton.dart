import 'package:flutter/material.dart';

import '../gochano_colors.dart';

/// Clean static skeleton loader for dashboard sections during async load.
///
/// Adheres strictly to spec §11 (no decorative motion or continuous ticker loops).
class AppSkeleton extends StatelessWidget {
  const AppSkeleton({
    super.key,
    this.width,
    this.height = 80,
    this.borderRadius = 16,
  });

  final double? width;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: colors.surfaceVariant,
        borderRadius: BorderRadius.all(Radius.circular(borderRadius)),
        border: Border.all(
          color: colors.border,
          width: 1,
        ),
      ),
    );
  }
}
