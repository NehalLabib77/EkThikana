// Gochano splash screen.
//
// Simplified for startup performance: the splash now renders exactly one
// static logo on a dark background, then fires its [onReady] callback on
// the next post-frame so the host (typically `_BootRouter` in app.dart)
// can swap in the real first route.
//
// What was removed:
//   - Asset precache (no `precacheImage` await; the framework decodes the
//     logo lazily on first paint).
//   - Rotating ring animation (no `AnimationController` / `repeat()`).
//   - Progress bar (the `_StartupProgressBar` helper is gone).
//   - Logo scale / opacity entrance animation (no `FadeTransition`,
//     no `ScaleTransition`, no `TickerProviderStateMixin`).
//   - Manual `Future.delayed` waits; the only timing primitive left is
//     `addPostFrameCallback`, which fires once per build.
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

const String _kLogoAsset = 'assets/branding/Gochano.png';

/// Hard upper bound on how long the splash will wait for [onReady] to
/// resolve before firing it once on a timer so the UI cannot freeze.
/// Intentionally short: a hung callback should not block startup.
const Duration _kHardTimeout = Duration(milliseconds: 1500);

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
      backgroundColor: const Color(0xFF0F1115),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth.clamp(0.0, 280.0),
                  maxHeight: constraints.maxHeight.clamp(0.0, 280.0),
                ),
                child: FittedBox(
                  fit: BoxFit.contain,
                  alignment: Alignment.center,
                  child: Image.asset(
                    _kLogoAsset,
                    width: 200,
                    height: 200,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
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
