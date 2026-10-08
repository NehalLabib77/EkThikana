import 'package:flutter/animation.dart';

/// Centralized animation durations and curves for Gochano.
class AppMotion {
  AppMotion._();

  /// Fast interactions (checkboxes, toggles, micro-feedback): 150ms
  static const Duration fast = Duration(milliseconds: 150);

  /// Standard transitions (card expansion, tab cross-fades): 250ms
  static const Duration normal = Duration(milliseconds: 250);

  /// Gentle entry and layout shifts: 350ms
  static const Duration slow = Duration(milliseconds: 350);

  /// Natural easeOutCubic curve for mobile surfaces.
  static const Curve curve = Curves.easeOutCubic;
}
