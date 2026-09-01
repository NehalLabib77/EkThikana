// The launch screen shown while Firebase and the saved preferences load.
//
// It is deliberately motionless. The previous version faded the logo in over
// 360 ms from a shared motion token — a decorative fade entrance, which spec
// §11 rules out. A splash that appears instantly and is replaced the moment
// the app is ready is also simply faster to look at.
//
// Timing contract, unchanged:
//   * [onReady] fires on the first post-frame, so the host can swap to its
//     real first route as soon as this is on screen;
//   * a hard 1.5s ceiling fires it anyway if the host's readiness work never
//     resolves, so a hung callback cannot freeze the launch.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/design_system/gochano_colors.dart';

const String _kLogoAsset = 'assets/branding/Gochano.png';

/// Upper bound on how long to wait for [GochanoSplashScreen.onReady].
const Duration _kHardTimeout = Duration(milliseconds: 1500);

class GochanoSplashScreen extends StatefulWidget {
  const GochanoSplashScreen({super.key, this.onReady});

  /// Readiness callback. Fired once, on the first post-frame after mount or
  /// after [_kHardTimeout] — whichever comes first.
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

    WidgetsBinding.instance.addPostFrameCallback((_) => _fireOnReady());
    _timeoutTimer = Timer(_kHardTimeout, _fireOnReady);
  }

  void _fireOnReady() {
    if (_fired) return;
    final callback = widget.onReady;
    _fired = true;
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    if (callback == null) return;

    // Any error inside the host's readiness work must not break the splash;
    // the host owns its own error surface (`_SetupRequiredApp` in main.dart).
    try {
      final result = callback();
      if (result is Future<void>) result.catchError((_) {});
    } catch (_) {
      // Swallow — the splash has no UI to show an error on.
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
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: constraints.maxWidth.clamp(0.0, 240.0),
                maxHeight: constraints.maxHeight.clamp(0.0, 240.0),
              ),
              child: FittedBox(
                fit: BoxFit.contain,
                child: Image.asset(
                  _kLogoAsset,
                  width: 180,
                  height: 180,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  // Capped at 240 logical px by the ConstrainedBox above.
                  cacheWidth: 1024,
                  semanticLabel: 'Gochano logo',
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
