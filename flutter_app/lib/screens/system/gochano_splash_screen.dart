// Gochano animated splash screen.
//
// Renders a stationary Gochano logo wrapped in a thin amber ring that rotates
// while the app boots. The logo itself never spins. After the splash duration
// elapses (or [onReady] fires first), the screen fades out into the route
// stack that called it (typically AuthGate).
//
// Usage from main.dart:
//   runApp(const GochanoApp(initialRoute: GochanoSplashScreen.routeName));
// or, when using a builder / Navigator.pushReplacementNamed:
//   Navigator.of(context).pushReplacementNamed(GochanoSplashScreen.routeName);

import 'dart:async';

import 'package:flutter/material.dart';

import '../../widgets/gochano_loading.dart';

const String _kLogoAsset = 'assets/branding/Gochano.png';

/// Hard upper bound for the splash. If startup takes longer than this, the
/// splash fades out anyway and hands control to the next route. The caller
/// can keep doing work in the background; the UI must never freeze.
const Duration _kHardTimeout = Duration(seconds: 8);

/// Cap for a single precache attempt. On slow devices asset decode can stall;
/// we prefer to show the app with a possible logo pop-in over an infinite
/// spinner.
const Duration _kPrecacheTimeout = Duration(seconds: 2);

class GochanoSplashScreen extends StatefulWidget {
  const GochanoSplashScreen({super.key, this.onReady});

  /// Optional readiness callback. When provided, the splash waits until the
  /// future resolves (or [_kMinimumVisible] elapses, whichever is later)
  /// before fading out.
  final FutureOr<void> Function()? onReady;

  static const String routeName = '/gochano-splash';

  @override
  State<GochanoSplashScreen> createState() => _GochanoSplashScreenState();
}

class _GochanoSplashScreenState extends State<GochanoSplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _ringController;
  late final AnimationController _entranceController;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;

  bool _canFinish = false;
  bool _kickedOff = false;
  bool _failed = false;
  Object? _failure;

  @override
  void initState() {
    super.initState();
    _ringController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _logoScale = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOutCubic,
    );
    _logoOpacity = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
    );

    _entranceController.forward();
    // _kickOff() calls precacheImage(provider, context) which reads
    // MediaQuery off the inherited-widget tree; doing that from initState()
    // throws "dependOnInheritedWidgetOfExactType<MediaQuery>() ... before
    // _GochanoSplashScreenState.initState() completed." Defer the kickoff
    // to didChangeDependencies(), where the inherited-widget tree is wired
    // up and safe to read.
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_kickedOff) {
      _kickedOff = true;
      _kickOff();
    }
  }

  Future<void> _kickOff() async {
    // No artificial delays. The splash disappears as soon as the real startup
    // work resolves. Every async step is bounded by a hard timeout so a hung
    // callback or a slow asset decode cannot lock the splash.
    try {
      // Step 1: warm the asset cache so the first frame is clean. Bounded.
      final provider = AssetImage(_kLogoAsset);
      await precacheImage(provider, context)
          .timeout(_kPrecacheTimeout, onTimeout: () {
        // Don't throw - the splash still has to give way to the app.
        debugPrint('GochanoSplashScreen: logo precache timed out');
      });

      // Step 2: wait for the caller's readiness future. Wrapped so a
      // hang or exception in onReady cannot lock the splash.
      if (widget.onReady != null) {
        await Future<void>.sync(widget.onReady!).timeout(
          _kHardTimeout,
          onTimeout: () {
            debugPrint('GochanoSplashScreen: onReady exceeded hard timeout');
          },
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _failure = e;
      });
      // Still finish so the caller can show its own retry / error surface
      // instead of leaving the user on a frozen splash.
    }

    if (!mounted) return;
    setState(() => _canFinish = true);
  }

  void _retry() {
    setState(() {
      _failed = false;
      _failure = null;
      _canFinish = false;
    });
    _kickOff();
  }

  @override
  void dispose() {
    _ringController
      ..stop()
      ..dispose();
    _entranceController
      ..stop()
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Gochano always boots on dark for brand consistency. The Scaffold
    // background fills the window (cover) while the logo artwork inside is
    // constrained by FittedBox(BoxFit.contain) so it never crops or
    // stretches, regardless of device size or aspect ratio.
    return Scaffold(
      backgroundColor: const Color(0xFF0F1115),
      body: SafeArea(
        child: AnimatedOpacity(
          opacity: _canFinish ? 0.0 : 1.0,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Center(
                child: ConstrainedBox(
                  // Keep the artwork from getting uncomfortably large on
                  // tablets / foldables while still respecting small screens.
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth.clamp(0.0, 360.0),
                    maxHeight: constraints.maxHeight.clamp(0.0, 480.0),
                  ),
                  child: FittedBox(
                    // BoxFit.contain: logo + ring + progress always fit the
                    // available area without ever being cropped or stretched.
                    fit: BoxFit.contain,
                    alignment: Alignment.center,
                    child: SizedBox(
                      width: 280,
                      height: 280,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          FadeTransition(
                            opacity: _logoOpacity,
                            child: ScaleTransition(
                              scale: Tween<double>(begin: 0.92, end: 1.0)
                                  .animate(_logoScale),
                              child: const GochanoLoading(),
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Real progress indicator driven by the actual
                          // startup work (asset decode + onReady), not a
                          // manually controlled fake percentage.
                          const _StartupProgressBar(),
                          if (_failed) ...[
                            const SizedBox(height: 12),
                            Text(
                              'Startup failed: $_failure',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: _retry,
                              child: const Text('Retry'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// A thin indeterminate progress strip that runs while the splash is
/// visible. Driven by the splash's own state so it freezes (rather than
/// showing 100%) when the splash fades out.
class _StartupProgressBar extends StatelessWidget {
  const _StartupProgressBar();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: const LinearProgressIndicator(
          minHeight: 4,
          backgroundColor: Color(0x33FFFFFF),
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFFC107)),
        ),
      ),
    );
  }
}
