import 'package:flutter/material.dart';

import '../gochano_colors.dart';

/// Clean skeleton loader for dashboard sections during async load.
class AppSkeleton extends StatefulWidget {
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
  State<AppSkeleton> createState() => _AppSkeletonState();
}

class _AppSkeletonState extends State<AppSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.45, end: 0.90).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = context.isDark;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: isDark
                ? colors.surfaceVariant.withValues(alpha: _animation.value)
                : const Color(0xFFF1F5F9).withValues(alpha: _animation.value),
            borderRadius: BorderRadius.all(Radius.circular(widget.borderRadius)),
            border: Border.all(
              color: isDark ? colors.border : const Color(0xFFE2E8F0),
              width: 1,
            ),
          ),
        );
      },
    );
  }
}
