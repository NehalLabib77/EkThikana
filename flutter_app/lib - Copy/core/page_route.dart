import 'package:flutter/material.dart';

/// The route every cross-screen navigation in Gochano uses.
///
/// This used to be a `PageRouteBuilder` with a bespoke fade + 24dp rise and
/// its own duration and curve tokens — a small motion-design system of its
/// own. Spec §11 rules that out explicitly: no custom page transitions, no
/// decorative fade or slide entrances, and "do not create a motion-design
/// system". What is left is the platform's own transition, which §11 permits
/// as "standard Android/Flutter framework behavior that is unavoidable for
/// core interaction".
///
/// The wrapper is kept rather than replaced with bare `MaterialPageRoute` at
/// ~45 call sites, for two reasons:
///   * `GochanoRoute.to(builder: …)` already reads at every call site, so
///     nothing has to change to get the corrected behaviour;
///   * it stays the one place a future transition decision would be made,
///     instead of that decision being spread across the app again.
class GochanoPageRoute<T> extends MaterialPageRoute<T> {
  GochanoPageRoute({
    required super.builder,
    super.settings,
    super.fullscreenDialog,
  });
}

/// Convenience accessor so call sites read like
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
