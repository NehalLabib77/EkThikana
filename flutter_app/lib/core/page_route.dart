import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// Branded page route used by every cross-screen navigation.
///
/// Why this exists:
///   - Default `MaterialPageRoute` on Android uses a left/right slide that
///     feels generic and ignores our seed color. We want the entire app to
///     feel like one product.
///   - Every screen in the app currently calls `MaterialPageRoute(builder:
///     (_) => …)` (~45 call-sites). Centralising the transition here means
///     every push animates the same way and theme tokens stay authoritative.
///
/// Behaviour:
///   - Forward push: new screen fades + slides up ~24 dp.
///   - Reverse (pop): mirrored.
///   - Duration / curve: [EkMotion.medium] / [EkMotion.enter] / [EkMotion.exit].
///   - `fullscreenDialog: true` flips the slide axis to vertical (slides up
///     from the bottom) so "open as modal" intent still reads visually
///     distinct (e.g. `MedicineFormScreen` push-from-list).
class GochanoPageRoute<T> extends PageRouteBuilder<T> {
  GochanoPageRoute({
    required WidgetBuilder builder,
    super.settings,
    super.fullscreenDialog,
  }) : super(
          transitionDuration: EkMotion.medium,
          reverseTransitionDuration: EkMotion.medium,
          opaque: true,
          pageBuilder: (ctx, anim, secondaryAnim) => builder(ctx),
          transitionsBuilder: (ctx, anim, secondaryAnim, child) {
            final curved = CurvedAnimation(
              parent: anim,
              curve: EkMotion.enter,
              reverseCurve: EkMotion.exit,
            );

            // For modal-style routes we slide up from the bottom; for the
            // default forward push we slide up by a small offset so the new
            // screen feels like it is *rising into* the foreground rather
            // than sliding sideways.
            final beginOffset = fullscreenDialog
                ? const Offset(0, 1)
                : const Offset(0, 0.06);

            final slide = Tween<Offset>(
              begin: beginOffset,
              end: Offset.zero,
            ).animate(curved);

            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: slide,
                child: child,
              ),
            );
          },
        );
}

/// Convenience accessor for `GochanoPageRoute` so call-sites read like
/// `GochanoRoute.to(builder: (_) => const AiAssistantScreen())`.
class GochanoRoute {
  const GochanoRoute._();

  static GochanoPageRoute<T> to<T>({
    required WidgetBuilder builder,
    RouteSettings? settings,
    bool fullscreenDialog = false,
  }) {
    return GochanoPageRoute<T>(
      builder: builder,
      settings: settings,
      fullscreenDialog: fullscreenDialog,
    );
  }
}
