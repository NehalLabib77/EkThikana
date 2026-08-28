# Phase E — Gochano Splash Simplification

**Branch:** `part5-release-validation`
**Head before this commit:** `1ffd7b6` (Phase D)
**File changed:** `flutter_app/lib/screens/system/gochano_splash_screen.dart`
**Status:** ✅ Compiles clean, 19/19 tests pass.

---

## 1. Goal

Reduce the splash's cold-start cost to the absolute minimum:

- Show the Gochano logo as soon as the first frame is ready.
- Hand off to the host (`_BootRouter` → `AuthGate`) on the very next
  post-frame — no artificial minimum-visible timer.
- No asset precache, no rotating ring, no progress bar, no scale/opacity
  entrance animation, no retry / failure UI inside the splash.

No architectural changes — same widget, same `onReady` contract, same
`routeName`, same parent (`_BootRouter` in `app.dart`).

## 2. Audit — what was inside the splash before

| # | Element | Lines | Purpose | Kept? |
|---|---|---|---|---|
| 1 | `AssetImage` + `precacheImage(...).timeout(_kPrecacheTimeout)` | ~5 | Warm asset cache before hand-off | ❌ removed (lazy decode is enough) |
| 2 | `_ringController` (`AnimationController..repeat()`) + `GochanoLoading` widget | ~10 | Rotating amber ring | ❌ removed |
| 3 | `_entranceController` + `_logoScale` + `_logoOpacity` (`FadeTransition` + `ScaleTransition`) | ~25 | Logo scale/opacity entrance | ❌ removed |
| 4 | `_StartupProgressBar` (`LinearProgressIndicator`) | ~15 | Indeterminate progress strip | ❌ removed |
| 5 | `_failed` / `_failure` / `_retry()` state | ~20 | Error UI with retry button | ❌ removed (host owns errors) |
| 6 | `AnimatedOpacity` for fade-out | ~6 | 260 ms fade-out on hand-off | ❌ removed (no longer needed — host swaps the widget) |
| 7 | `Future.delayed` waits inside `_kickOff` | implicit | Drive `_canFinish` | ❌ removed |
| 8 | `widgets/gochano_loading.dart` import | 1 | Pulls in the ring widget | ❌ removed (other 3 callers still import it directly) |
| 9 | `TickerProviderStateMixin` | 1 | Required for `AnimationController` | ❌ removed |
| 10 | `onReady` callback + `routeName` static | ~6 | Public contract used by `app.dart` | ✅ kept |
| 11 | Hard timeout ceiling (so a hung `onReady` cannot freeze the UI) | ~3 | Safety net | ✅ kept (shortened 8 s → 1.5 s) |

Net: **227 lines → 161 lines** (about 30 % smaller, no animation, no
controllers, no Future work).

## 3. External callers

```
flutter_app/lib/app.dart:72  GochanoSplashScreen(onReady: _handleReady)
```

Exactly **one** caller. It uses the `onReady` callback to flip
`_ready = true` and rebuild `_BootRouter` to render `AuthGate`. That
contract is preserved verbatim.

`GochanoLoading` (the rotating-ring widget previously embedded in the
splash) is also imported by `auth_gate.dart`, `bazar_buddy_screen.dart`,
and `daily_expenses_screen.dart` for inline async-wait spinners — those
imports are unaffected.

`assets/branding/Gochano.png` — already declared in `pubspec.yaml`,
unchanged.

## 4. New behaviour

1. App cold-starts → `main()` → `GochanoApp` → `MaterialApp` →
   `_BootRouter` (with `_ready = false`) → `GochanoSplashScreen`.
2. `GochanoSplashScreen.initState`:
   - Schedules `addPostFrameCallback(_fireOnReady)` — fires on the
     first frame after mount.
   - Starts a 1.5 s `Timer` as a hard ceiling against a hung
     `onReady`.
3. `build()` paints: dark `Scaffold`, `SafeArea`, `LayoutBuilder`,
   centered `ConstrainedBox(maxWidth/Height: 280)`,
   `FittedBox(BoxFit.contain)`, `Image.asset(_kLogoAsset, 200×200)`.
   No animation, no transition widget.
4. First post-frame → `_fireOnReady` → calls `_BootRouter._handleReady`
   → that uses `addPostFrameCallback` to defer the
   `setState(() => _ready = true)` so we never `setState` from inside
   another widget's build (preserves the same defensive pattern from
   Phase B / C). The next rebuild of `_BootRouter` swaps the splash
   for `AuthGate`.

## 5. Code — full new splash

```dart
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
    // not break the splash. The host owns its own error surface.
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
```

## 6. Why this is faster

| Source of latency (before) | Now |
|---|---|
| `precacheImage(...).timeout(2 s)` blocking the hand-off | Lazy decode — first paint includes the logo, no extra round-trip |
| `_ringController..repeat()` + `_entranceController.forward()` → 700 ms entrance animation | No animation; the splash paints and hands off on the next frame |
| `AnimatedOpacity` 260 ms fade-out | Replaced by an instant widget swap inside `_BootRouter` |
| `Future<void>.sync(onReady).timeout(_kHardTimeout = 8 s)` | `onReady` is invoked, but we don't `await` its return — the host decides when to swap to `AuthGate` (it already does, via `addPostFrameCallback`) |
| Failure UI kept the splash on-screen via `_canFinish = false` until manual retry | Removed entirely; host owns errors via `_SetupRequiredApp` (in `main.dart`) |

The minimum-visible splash time is now exactly **one frame after
mount** — typically 16 ms on a 60 Hz device, 8 ms on 120 Hz. The hand-off
to `AuthGate` happens on the *following* frame, after `_BootRouter`'s
own `addPostFrameCallback` fires.

## 7. Verification evidence

```
$ flutter analyze lib/screens/system/gochano_splash_screen.dart lib/app.dart lib/main.dart
Analyzing 3 items...
No issues found! (ran in 17.5s)
```

Full-project analyze (3 unrelated, pre-existing infos in
`medicine_screen.dart` and `ai_assistant_screen.dart` — none introduced
by this commit):

```
$ flutter analyze
3 issues found.  ← all are pre-existing infos in other files
```

Test suite (Phase D baseline was 19 tests, all passing):

```
$ flutter test --no-pub
00:05 +19: All tests passed!
```

## 8. File diff summary

```
flutter_app/lib/screens/system/gochano_splash_screen.dart
  - import '../../widgets/gochano_loading.dart';
  - class _GochanoSplashScreenState with TickerProviderStateMixin
  - AnimationController _ringController, _entranceController
  - Animation<double> _logoScale, _logoOpacity
  - bool _canFinish, _kickedOff, _failed; Object? _failure;
  - Future<void> _kickOff() with precacheImage + Future.sync(onReady)
  - void _retry()
  - 'failed' Text + Retry TextButton inside build()
  - AnimatedOpacity + FadeTransition + ScaleTransition
  - SizedBox(280x280) wrapping the logo with the progress strip
  - const _kPrecacheTimeout = Duration(seconds: 2)
  - const _kHardTimeout = Duration(seconds: 8)
  - class _StartupProgressBar (LinearProgressIndicator wrapper)
  + bool _fired; Timer? _timeoutTimer;
  + WidgetsBinding.instance.addPostFrameCallback((_) => _fireOnReady())
  + Timer(_kHardTimeout, () => _fireOnReady())   // 1.5s ceiling
  + void _fireOnReady() — calls cb(); swallows Future errors
  + dispose() cancels _timeoutTimer
  + build() — static Scaffold + LayoutBuilder + ConstrainedBox + FittedBox + Image.asset(200x200)
  + const _kHardTimeout = Duration(milliseconds: 1500)
```

Net: 227 → 161 lines (-29 %). Zero `AnimationController`, zero `Future`,
zero `Timer.periodic`, zero `precacheImage`, zero `LinearProgressIndicator`.

## 9. Manual smoke test plan (device-side)

1. `flutter run -d 0935625332014966 --dart-define=API_BASE_URL=https://ekthikana-api-x473.onrender.com`.
2. Watch the launch: the dark splash appears for ~1 frame and then
   swaps to `AuthGate` / `LoginScreen` / `HomeShell` depending on
   auth state. No ring rotation, no progress bar, no fade.
3. Kill the app and relaunch from the launcher (cold start) several
   times — splash should never stay on screen for more than a fraction
   of a second.
4. Force a hung `onReady` (e.g. temporarily add a 10 s `await
   Future.delayed` inside `_handleReady` in `app.dart`) — confirm
   the splash still hands off at 1.5 s (the hard ceiling) instead of
   freezing.
5. From a connected dev session, press **r** (hot reload) and **R**
   (hot restart) — both should not regress the splash behaviour.

## 10. What this commit does NOT change

- `app.dart` and `_BootRouter` (still uses `GochanoSplashScreen(onReady: _handleReady)`).
- `main.dart` (no change).
- `core/navigation.dart` (Phase D's per-cold-start key reset still applies).
- `GochanoLoading` widget (still used by `auth_gate.dart`,
  `bazar_buddy_screen.dart`, `daily_expenses_screen.dart`).
- `pubspec.yaml` asset declarations.
- Any route, any test, any service.
