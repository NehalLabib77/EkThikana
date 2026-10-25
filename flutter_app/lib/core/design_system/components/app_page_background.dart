import 'package:flutter/material.dart';

/// Reusable page background with a colorful gradient wash at the top,
/// fading to the neutral app background below.
///
/// Usage:
/// ```dart
/// AppPageBackground(
///   gradient: AppGradients.workspacePage,
///   child: Scaffold(...),
/// )
/// ```
class AppPageBackground extends StatelessWidget {
  const AppPageBackground({
    super.key,
    required this.gradient,
    required this.child,
    this.height = 320,
  });

  final LinearGradient gradient;
  final Widget child;

  /// How far down the gradient wash extends (pixels).
  final double height;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: height,
          child: DecoratedBox(decoration: BoxDecoration(gradient: gradient)),
        ),
        child,
      ],
    );
  }
}
