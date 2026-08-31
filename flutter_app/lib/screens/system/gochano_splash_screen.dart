// Gochano splash screen.
//
// Simplified for startup performance: the splash now renders exactly one
// static logo on a flat surface, then fires its [onReady] callback on
// the next post-frame so the host (typically `_BootRouter` in app.dart)
// can swap in the real first route.
//
// No spinner, no progress bar, no rotating ring — just a one-shot
// opacity fade-in on the logo. The hand-off fires regardless of how
// far the fade has progressed, so a slow fade never blocks reaching
// `AuthGate`.
//
// What was removed:
//   - Asset precache (no `precacheImage` await; the framework decodes the
//     logo lazily on first paint).
//   - Rotating ring animation (no `AnimationController` / `repeat()`).
//   - Progress bar (the `_StartupProgressBar` helper is gone).
//   - Logo scale entrance animation (no `ScaleTransition`).
//   - Manual `Future.delayed` waits; the only timing primitive left is
//     `addPostFrameCallback`, which fires once per build.
//
// What remains (one-shot, free of animation controllers):
//   - A 300 ms opacity fade-in via `TweenAnimationBuilder<double>`,
//     curved with `Curves.easeOutCubic`. Independent of [onReady]:
//     the hand-off fires on the next post-frame regardless of how far
//     the fade has progressed, so a slow fade never blocks reaching
//     `AuthGate`. The fade is purely visual polish.
//
// What is preserved (the public contract):
//   - `const GochanoSplashScreen({super.key, this.onReady})` — same
//     signature used by `_BootRouter` in app.dart.
//   - `static const String routeName = '/gochano-splash';` — preserved
//     for callers that navigate by name.
//   - `onReady` callback fires when the splash is ready to hand control
//     back to the host (used by `_BootRouter` to swap in `AuthGate`).
//
// A hard upper bound is still kept in case `onReady` itself hangs: if
// the callback does not resolve within [_kHardTimeout] the splash
// fires it once on a timer so the UI cannot freeze. There is no
// minimum-visible timer — the splash hands off as fast as the host is
// ready.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/design_tokens.dart';

const String _kLogoAsset = 'assets/branding/Gochano.png';

/// Hard upper bound on how long the splash will wait for [onReady] to
/// resolve before firing it once on a timer so the UI cannot freeze.
/// Intentionally short: a hung callback should not block startup.
const Duration _kHardTimeout = Duration(milliseconds: 1500);

/// Duration of the logo fade-in.
///
/// Aliased to `EkMotion.slow` (360 ms) so the splash obeys the same
/// motion tokens as the rest of the app. Kept intentionally short so the
/// splash never feels heavy on cold start. Independent of [onReady]:
/// the hand-off happens on the next post-frame whether or not the fade
/// has finished, so a slow fade never blocks the user from reaching
/// `AuthGate`.
const Duration _kFadeIn = EkMotion.slow;

class GochanoSplashScreen extends StatefulWidget {
  const GochanoSplashScreen({super.key, this.onReady});

  /// Optional readiness callback. When provided, the splash fires it
  /// on the first post-frame after the splash mounts (so the host can
  /// swap to its real first route on the next frame), or after
  /// [_kHardTimeout] — whichever comes first.
  final FutureOr<void> Function()? onReady;

  static const String routeName = '/gochano-splash';

  @override
  State<GochanoSplashScreen> createState() => _GochanoSplashScreenState();
}

class _GochanoSplashScreenState extends State<GochanoSplashScreen> {
  bool _fired = false;
  Timer? _timeoutTimer;

  @override
  void initState() {
    super.initState();
    if (widget.onReady == null) return;

    // Fire onReady on the very next post-frame so the host can swap
    // in its real first route as soon as the splash is on screen.
    // No minimum-visible timer: the hand-off is as fast as the host.
    WidgetsBinding.instance.addPostFrameCallback((_) => _fireOnReady());

    // Hard ceiling: if onReady never resolves within [_kHardTimeout],
    // the timer fires it once anyway so the UI cannot freeze.
    _timeoutTimer = Timer(_kHardTimeout, () => _fireOnReady());
  }

  void _fireOnReady() {
    if (_fired) return;
    final cb = widget.onReady;
    if (cb == null) {
      _fired = true;
      return;
    }
    _fired = true;
    _timeoutTimer?.cancel();
    _timeoutTimer = null;

    // Best-effort: any error inside the host's readiness work must
    // not break the splash. The host owns its own error surface
    // (e.g. `_SetupRequiredApp` from main.dart).
    try {
      final result = cb();
      if (result is Future<void>) {
        result.catchError((_) {});
      }
    } catch (_) {
      // Swallow — splash has no UI to show errors on.
    }
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF0F172A)
          : const Color(0xFFF8F7F2),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth.clamp(0.0, 280.0),
                  maxHeight: constraints.maxHeight.clamp(0.0, 280.0),
                ),
                // One-shot implicit fade-in: opacity 0 -> 1 over
                // [_kFadeIn]. No AnimationController, no TickerProvider,
                // no Future.delayed. The animation is purely visual;
                // [onReady] still fires on the next post-frame so the
                // hand-off to AuthGate is not blocked by the fade.
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0.0, end: 1.0),
                  duration: _kFadeIn,
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) {
                    return Opacity(
                      opacity: value,
                      child: child,
                    );
                  },
                  child: FittedBox(
                    fit: BoxFit.contain,
                    alignment: Alignment.center,
                    child: Image.asset(
                      _kLogoAsset,
                      width: 200,
                      height: 200,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      semanticLabel: 'Gochano logo',
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
