import 'package:flutter/widgets.dart';

/// Centralized, accessible animation durations, curves, and motion tokens for Gochano.
///
/// Follows the 2026 Accessible Meaningful Motion Policy (Spec §11 revised):
/// - Finite, purposeful transitions only.
/// - Mandatory respect for reduced-motion accessibility settings.
/// - Fast response times (100–300ms) to ensure battery efficiency and responsiveness.
class AppMotion {
  AppMotion._();

  // --- Duration tokens (approved ranges) ---
  /// Tap feedback: 100–150ms (default 120ms)
  static const Duration tapFeedback = Duration(milliseconds: 120);

  /// Selection transitions: 120–180ms (default 150ms)
  static const Duration selectionTransition = Duration(milliseconds: 150);

  /// Content reveal: 160–240ms (default 200ms)
  static const Duration contentReveal = Duration(milliseconds: 200);

  /// State changes: 180–300ms (default 240ms)
  static const Duration stateChange = Duration(milliseconds: 240);

  /// Progress and result emphasis: 200–350ms (default 280ms)
  static const Duration progressEmphasis = Duration(milliseconds: 280);

  /// Study card flip transition: 260ms
  static const Duration cardFlip = Duration(milliseconds: 260);

  // --- Backward-compatibility aliases ---
  /// Micro-interactions (checkboxes, toggles): 150ms
  static const Duration micro = Duration(milliseconds: 150);

  /// Fast interactions: 150ms
  static const Duration fast = Duration(milliseconds: 150);

  /// Standard transitions (card expansion, tab cross-fades): 240ms
  static const Duration normal = Duration(milliseconds: 240);

  /// Gentle entry: 300ms
  static const Duration slow = Duration(milliseconds: 300);

  /// Page entrance duration ceiling: 300ms
  static const Duration pageEnter = Duration(milliseconds: 300);

  /// Stagger delay between list items: 40ms
  static const Duration staggerDelay = Duration(milliseconds: 40);

  // --- Curve tokens ---
  /// Natural easeOutCubic curve for mobile surfaces.
  static const Curve standard = Curves.easeOutCubic;
  static const Curve curve = Curves.easeOutCubic;

  /// Smooth ease-in-out for two-way state transitions.
  static const Curve easeInOut = Curves.easeInOutCubic;

  /// Springy entrance for small badges and dialogs.
  static const Curve spring = Curves.easeOutBack;

  /// Sharp deceleration for dismissals.
  static const Curve decelerate = Curves.decelerate;

  /// Elastic bounce for celebratory milestone achievements.
  static const Curve elastic = Curves.elasticOut;

  // --- Offset constants for subtle slide-ins ---
  static const double slideFromBelow = 0.04;
  static const double slideFromRight = 0.06;

  // --- Reduced Motion Accessibility Helpers ---

  /// Returns true if the user has requested reduced motion or accessible navigation.
  static bool isReducedMotion(BuildContext context) {
    try {
      final mq = MediaQuery.maybeOf(context);
      if (mq == null) return false;
      return mq.disableAnimations || mq.accessibleNavigation;
    } catch (_) {
      return false;
    }
  }

  /// Returns [normalDuration] if animations are enabled, or [Duration.zero]
  /// if the user requested reduced motion.
  static Duration accessibleDuration(
    BuildContext context,
    Duration normalDuration,
  ) {
    return isReducedMotion(context) ? Duration.zero : normalDuration;
  }

  /// Alias for [accessibleDuration] for clean token usage.
  static Duration duration(
    BuildContext context,
    Duration normalDuration,
  ) => accessibleDuration(context, normalDuration);

  /// Returns [normalCurve] if animations are enabled, or [Curves.linear]
  /// if reduced motion is requested.
  static Curve accessibleCurve(
    BuildContext context, [
    Curve normalCurve = Curves.easeOutCubic,
  ]) {
    return isReducedMotion(context) ? Curves.linear : normalCurve;
  }
}

/// Convenience extension on [BuildContext] for accessible motion.
extension AppMotionContext on BuildContext {
  /// Whether the user has enabled reduced motion or accessible navigation.
  bool get isReducedMotion => AppMotion.isReducedMotion(this);

  /// Resolves an animation duration, collapsing to [Duration.zero] under reduced motion.
  Duration motionDuration(Duration base) =>
      AppMotion.accessibleDuration(this, base);

  /// Resolves an animation curve, collapsing to linear under reduced motion.
  Curve motionCurve([Curve base = Curves.easeOutCubic]) =>
      AppMotion.accessibleCurve(this, base);
}
