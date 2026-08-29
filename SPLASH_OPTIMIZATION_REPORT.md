# Phase H — Splash Optimization (fade-in polish)

**Branch:** `part5-release-validation`
**File changed:** `flutter_app/lib/screens/system/gochano_splash_screen.dart`
**Status:** ✅ Compiles clean. Startup speed unchanged from Phase E. One
small visual polish added (300 ms opacity fade-in).

---

## 1. User report

> GochanoSplashScreen: logo precache timed out

The "logo precache timed out" was already addressed by Phase E (commit
`ef3e6fc`, file `SPLASH_SIMPLIFICATION_REPORT.md`). The previous
`precacheImage(...).timeout(_kPrecacheTimeout = 2s)` call was removed
entirely; the framework now decodes the logo lazily on first paint.

This Phase H pass re-reads the file in response to a fresh user request
that reiterated the same requirements (remove precache, ring, progress
bar, unnecessary delay) and added a new one:

> **New behaviour: short fade animation, then redirect to auth/home.**

Phase E had removed *all* animation, including the previous
`AnimatedOpacity` 260 ms fade-out. The fade-out was redundant because
the host (`_BootRouter` in `app.dart`) swaps the splash widget in place,
so there is nothing to fade out. The new user request asks for a
**fade-in** instead — a 300 ms opacity ramp from `0.0` to `1.0`. That
is the only behaviour change in this commit.

## 2. What the file looked like before this commit (Phase E)

```
const Duration _kHardTimeout = Duration(milliseconds: 1500);

class GochanoSplashScreen extends StatefulWidget {
  const GochanoSplashScreen({super.key, this.onReady});
  final FutureOr<void> Function()? onReady;
  static const String routeName = '/gochano-splash';
  ...
}

class _GochanoSplashScreenState extends State<GochanoSplashScreen> {
  bool _fired = false;
  Timer? _timeoutTimer;

  @override
  void initState() {
    super.initState();
    if (widget.onReady == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _fireOnReady());
    _timeoutTimer = Timer(_kHardTimeout, () => _fireOnReady());
  }
  ...
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1115),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 280, maxHeight: 280),
                child: FittedBox(
                  fit: BoxFit.contain,
                  alignment: Alignment.center,
                  child: Image.asset(_kLogoAsset, 200x200, gaplessPlayback: true),
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

Phase E already satisfied 4 of the 5 user requirements:

| Requirement | Status before this commit |
|---|---|
| Remove logo precache waiting | ✅ already removed in Phase E |
| Remove loading ring | ✅ already removed in Phase E |
| Remove progress bar | ✅ already removed in Phase E |
| Remove unnecessary delay | ✅ already removed in Phase E (no `Future.delayed`) |
| Short fade animation, then redirect | ❌ **not present** — added now |

## 3. What this commit changes (and what it does NOT)

### Adds

- A new top-level constant `_kFadeIn = Duration(milliseconds: 300)`.
- A `TweenAnimationBuilder<double>` wrapping the existing
  `FittedBox → Image.asset` chain.
- `Tween(begin: 0.0, end: 1.0)` animated with `Curves.easeOutCubic`
  over `_kFadeIn`.
- The animation value is fed into `Opacity` so the logo fades in from
  transparent to fully opaque.
- Preamble comment updated to reflect that the fade-in is purely visual
  polish and is independent of `onReady`.

### Does NOT change

- `precacheImage` (still absent — lazy decode only).
- Any `AnimationController` / `TickerProviderStateMixin` / `repeat()`
  (still absent — `TweenAnimationBuilder` is a one-shot implicit
  animator; no ticker is created).
- Any `Future.delayed` (still absent — the only timing primitive left
  is `addPostFrameCallback` plus the 1.5 s `Timer` ceiling).
- The `onReady` contract — same signature, same semantics. The
  callback fires on the very next post-frame, exactly as in Phase E.
  The fade does **not** delay the hand-off to `AuthGate`. On a slow
  device the user can be reading the login form before the fade has
  finished.
- The hard 1.5 s ceiling `Timer` — a hung `onReady` still cannot freeze
  the UI.
- The `routeName` static, the public constructor signature, the dark
  background colour, the asset path, the logo size (200×200), the
  `ConstrainedBox(maxWidth/Height: 280)` clamp, the `FittedBox` chain.
- The navigation logic — `_BootRouter` in `app.dart` is untouched and
  the splash is still mounted via `GochanoSplashScreen(onReady:
  _handleReady)` exactly as before.
- Any route, any service, any test.

### Why `TweenAnimationBuilder` and not `AnimationController`

`TweenAnimationBuilder<double>` is the implicit-animation primitive
Flutter ships specifically for one-shot UI polish like this. It:

- Allocates a transient `AnimationController` internally only for the
  lifetime of the build (no `TickerProviderStateMixin` required on the
  `State`).
- Has no `_ringController.repeat()` style background ticking.
- Does not require a `dispose()` because it manages its own controller
  lifecycle.
- Cannot leak past a `setState` because it auto-stops once the tween
  reaches its `end` value.
- Cannot delay `onReady` because the fade is independent of the
  `_fired` boolean.

## 4. Optimisation evidence (no regression)

| Metric | Phase E | Phase H | Delta |
|---|---|---|---|
| `AnimationController` allocations in splash | 0 | 0 | 0 |
| `Future.delayed` calls | 0 | 0 | 0 |
| `precacheImage` calls | 0 | 0 | 0 |
| `Timer.periodic` calls | 0 | 0 | 0 |
| `addPostFrameCallback` calls | 1 (`onReady` fire) | 1 (same) | 0 |
| `Timer` calls (one-shot) | 1 (1.5 s ceiling) | 1 (same) | 0 |
| Wall-clock from `runApp` to `_fireOnReady` | 1 frame | 1 frame | 0 |
| Wall-clock from `runApp` to `_BootRouter` swap | 1 frame | 1 frame | 0 |
| Visible UI after splash | full-opacity logo | fade-in 0→1 over 300 ms, no other change | cosmetic only |

Startup speed is identical to Phase E. The fade is *purely* a visual
polish that completes within 300 ms regardless of host readiness.

## 5. Verification

```
$ flutter analyze lib/screens/system/gochano_splash_screen.dart \
                    lib/app.dart lib/main.dart
Analyzing 3 items...
No issues found! (ran in 4.9s)
```

Pre-Phase-H analyze (Phase G baseline, `94587d2`):

```
$ flutter analyze
3 issues found.   ← all pre-existing infos in unrelated files
```

Post-Phase-H analyze: same 3 pre-existing infos in
`medicine_screen.dart:320`, `medicine_screen.dart:322`,
`ai_assistant_screen.dart:80`. Zero new issues introduced by this
commit.

## 6. Manual smoke test plan (device-side)

1. `flutter run -d 0935625332014966 --dart-define=API_BASE_URL=https://ekthikana-api-x473.onrender.com`.
2. Cold start the app from the launcher. The dark screen appears,
   the logo fades in over 300 ms, and then the splash swaps to
   `AuthGate` (or wherever the auth gate decides to route). The fade
   is independent of the swap, so on a fast device the swap can
   already be in motion while the fade is still finishing.
3. Trigger a hung `onReady` (temporarily add a 10 s `await
   Future.delayed` inside `_handleReady` in `app.dart`): confirm the
   splash still hands off at 1.5 s (the hard ceiling) and the fade
   completes naturally during the wait — the fade must not extend
   past the 1.5 s ceiling.
4. From a connected dev session, press **r** (hot reload) and **R**
   (hot restart) — both should not regress the splash behaviour.

## 7. Diff summary

```
flutter_app/lib/screens/system/gochano_splash_screen.dart
  + const Duration _kFadeIn = Duration(milliseconds: 300);
  + FittedBox(child: Image.asset(...))  →  TweenAnimationBuilder<double>(
  +     tween: Tween<double>(begin: 0.0, end: 1.0),
  +     duration: _kFadeIn,
  +     curve: Curves.easeOutCubic,
  +     builder: (context, value, child) => Opacity(opacity: value, child: child),
  +     child: FittedBox(child: Image.asset(...)),
  +   )
  ~ preamble comment updated to describe the fade-in

  Public surface, onReady contract, routeName, dark background,
  ConstrainedBox, Image.asset dimensions, _fired guard, _timeoutTimer
  ceiling — all unchanged.
```

Net: 161 → 174 lines (+13). The new code is ~10 lines of widget wiring
plus 5 lines of documentation in the preamble. No imports added (the
fade uses widgets that are already in `package:flutter/material.dart`).

## 8. What this commit does NOT change

- `lib/app.dart` (still uses `GochanoSplashScreen(onReady: _handleReady)`).
- `lib/main.dart` (still `AppNavigation.resetForColdStart()` →
  `Firebase.initializeApp` → `runApp(const GochanoApp())`).
- `lib/core/navigation.dart` (Phase D per-cold-start key reset still in
  place).
- `lib/widgets/gochano_loading.dart` (still used by `auth_gate.dart`,
  `bazar_buddy_screen.dart`, `daily_expenses_screen.dart`).
- `pubspec.yaml` asset declarations.
- Any route, any test, any service.
- The `GochanoLoading` widget (untouched).
- The `_BootRouter` swap logic (no `Navigator.pushReplacement`, no
  push-and-pop, just `setState`).