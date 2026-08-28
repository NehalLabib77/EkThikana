# Phase D — Duplicate `GlobalKey<NavigatorState>` Hardening

**Branch:** `part5-release-validation`
**Head before this commit:** `b12426f` (Phase C)
**Files changed:** `flutter_app/lib/core/navigation.dart`, `flutter_app/lib/main.dart`
**Status:** ✅ Compiles clean, 19/19 tests pass.

---

## 1. User report

> Duplicate GlobalKey detected:
> LabeledGlobalKey<NavigatorState>

Triggered on the device after Phase C was deployed and the dev session
was restarted (`flutter run -d 0935625332014966 ...`).

## 2. Audit

Static read of the entire `lib/` tree (Flutter 3.38.1):

| File | Line | Symbol | Notes |
|---|---|---|---|
| `core/navigation.dart` | 6-7 | `static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();` | Single `GlobalKey` declaration in the whole `lib/`. |
| `app.dart` | 15-16 | `MaterialApp(navigatorKey: AppNavigation.navigatorKey, …)` | Only **one** root `MaterialApp` ever mounted in production. |
| `main.dart` | 49 | `_SetupRequiredApp` returns a `MaterialApp` (no `navigatorKey`) | Rendered **only** when `AppConfig.validateRelease()` fails or `Firebase.initializeApp` throws — mutually exclusive with `GochanoApp`. |
| `widgets/notification_action_host.dart` | 42, 50, 57 | reads `AppNavigation.navigatorKey.currentContext` / `.currentState` | Consumer of the live Navigator key from a single tree. |

Cross-check (`Select-String -Path "flutter_app\lib\**\*.dart" -Pattern "navigatorKey|Navigator\(|MaterialApp|GlobalKey"`):

```
core/navigation.dart:6:  static final GlobalKey<NavigatorState> navigatorKey =
core/navigation.dart:7:      GlobalKey<NavigatorState>();
widgets/notification_action_host.dart:42:      context = AppNavigation.navigatorKey.currentContext;
widgets/notification_action_host.dart:50:    final nav = AppNavigation.navigatorKey.currentState;
widgets/notification_action_host.dart:57:      context = AppNavigation.navigatorKey.currentContext;
app.dart:15:    return MaterialApp(
app.dart:16:      navigatorKey: AppNavigation.navigatorKey,
main.dart:49:    return MaterialApp(
```

**No second `GlobalKey` declaration. No nested `Navigator`.**

## 3. Root cause

A `static final GlobalKey` is allocated **once per Dart process
lifetime**. On a Flutter **hot-restart** the previous widget tree (and
the `Navigator` it mounted with the static key) is torn down lazily
while the *new* tree is rebuilt against the *same* `GlobalKey`
instance. While both trees coexist for a few frames, two `Navigator`
widgets are simultaneously associated with the same key, and Flutter
throws:

```
Duplicate GlobalKey<NavigatorState> detected in widget tree.
```

That is exactly the assertion the user hit after the dev session was
restarted mid-cycle.

`AuthGate` / `_BootRouter` / `HomeShell` are all children of the single
`MaterialApp.home:` slot, so they swap in place — they do not mount a
new `Navigator`. The bug is the **lifetime of the key**, not the
**shape of the tree**.

## 4. The fix — fresh key per cold start

`core/navigation.dart` now holds the key in a `static GlobalKey<NavigatorState>?`
backing field that is reset on every cold start. The accessor stays the
same — `AppNavigation.navigatorKey` — so all existing call sites
compile unchanged.

### 4.1 `lib/core/navigation.dart`

```dart
import 'package:flutter/material.dart';

/// Centralised accessor for the single app-wide Navigator key.
///
/// Why this is a function + reset hook instead of a `static final`:
/// a `static final GlobalKey` is allocated **once per process lifetime**.
/// On Flutter hot-restart the old widget tree (and the Navigator it
/// mounted with the static key) is torn down lazily while the new tree
/// is rebuilt against the *same* `GlobalKey` instance. While both
/// trees coexist for a few frames, two `Navigator` widgets are
/// simultaneously associated with the same key, and Flutter throws:
///
///   "Duplicate `GlobalKey<NavigatorState>` detected in widget tree."
///
/// To eliminate that race we:
///   1. Hold the key in a *per cold start* late field ([_navigatorKey]).
///   2. Expose it via [navigatorKey], which allocates the field the
///      first time it is read and returns the same instance thereafter
///      for the rest of that cold start.
///   3. Reset it from `main()` via [resetForColdStart] before the first
///      `runApp` so hot-restart cannot reuse a stale instance.
class AppNavigation {
  AppNavigation._();

  static GlobalKey<NavigatorState>? _navigatorKey;

  static GlobalKey<NavigatorState> get navigatorKey {
    return _navigatorKey ??= GlobalKey<NavigatorState>();
  }

  static void resetForColdStart() {
    _navigatorKey = null;
  }
}
```

### 4.2 `lib/main.dart`

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  pdfrxFlutterInitialize();

  // Always start each cold launch with a fresh Navigator key. Without
  // this hook, a hot-restart on a developer build would reuse the same
  // `GlobalKey<NavigatorState>` instance for both the outgoing and the
  // incoming root `Navigator`, tripping Flutter's
  // "Duplicate GlobalKey detected" assertion.
  AppNavigation.resetForColdStart();

  try {
    AppConfig.validateRelease();
  } on StateError catch (e) {
    runApp(_SetupRequiredApp(error: e));
    return;
  }

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    runApp(const GochanoApp());
    // … notification init unchanged
  } catch (e) {
    runApp(_SetupRequiredApp(error: e));
  }
}
```

## 5. Why this satisfies every requirement

| Requirement | How it is met |
|---|---|
| Keep only one `MaterialApp` / `Navigator` | The tree shape is unchanged. `app.dart` still has the only production `MaterialApp`; `main.dart` `_SetupRequiredApp` is still mutually exclusive with it. |
| Do not change routes | No route table, no `routes:`, no `onGenerateRoute:` was touched. |
| Do not change architecture | Only the **lifetime** of the `GlobalKey` changed; the public API (`AppNavigation.navigatorKey`) is identical. All call sites compile unchanged. |
| Preserve Firebase auth routing | `AuthGate` is still the child of `_BootRouter` inside `GochanoApp`'s `home:` slot, inside the single `MaterialApp.navigatorKey`. Firebase auth state still flows through `AuthService.authState()` exactly as before. |

## 6. Why this fixes the duplicate-key race

On a hot-restart:

1. `main()` runs again from the top.
2. The very first thing it does — before `runApp`, before Firebase,
   before the splash — is `AppNavigation.resetForColdStart()`, which
   drops `_navigatorKey` to `null`.
3. `GochanoApp.build()` then calls `navigatorKey: AppNavigation.navigatorKey`,
   which lazily allocates a **brand new** `GlobalKey<NavigatorState>()`.
4. The new tree mounts with the new key; the old tree (still tearing
   down) was associated with the previous key — they are now
   different instances, so no duplicate-key assertion.

On a normal cold start (no hot-restart):

1. `resetForColdStart()` is idempotent — it just sets `_navigatorKey`
   to `null`.
2. The first read of `AppNavigation.navigatorKey` allocates a fresh
   `GlobalKey<NavigatorState>()` exactly as the old static did.
3. Subsequent reads return the same instance for the rest of that
   cold start, so `NotificationActionHost.currentContext` /
   `.currentState` continue to resolve correctly.

## 7. Verification evidence

```
$ flutter analyze lib/main.dart lib/app.dart lib/core/navigation.dart
Analyzing 3 items...
No issues found! (ran in 6.3s)
```

Full-project analyze (3 unrelated, pre-existing infos in
`medicine_screen.dart` and `ai_assistant_screen.dart` — none introduced
by this commit):

```
$ flutter analyze
3 issues found.  ← all are pre-existing infos in other files
```

Test suite (Phase C baseline was 19 tests, all passing):

```
$ flutter test --no-pub
00:01 +19: All tests passed!
```

## 8. File diff summary

```
flutter_app/lib/core/navigation.dart
  - static final GlobalKey<NavigatorState> navigatorKey = ...
  + static GlobalKey<NavigatorState>? _navigatorKey;
  + static GlobalKey<NavigatorState> get navigatorKey { … lazy allocate … }
  + static void resetForColdStart() { _navigatorKey = null; }

flutter_app/lib/main.dart
  + import 'core/navigation.dart';
  + AppNavigation.resetForColdStart();   // first line of main()
```

Net: 2 lines of behaviour change in `main.dart`, one class rewritten in
`navigation.dart`. Zero call-site changes anywhere else.

## 9. Manual smoke test plan (device-side)

1. Cold-launch the app on the device.
2. Verify the splash → AuthGate → HomeShell flow renders normally.
3. Trigger a deep-link via a medicine notification ("taken" action).
   Verify `NotificationActionHost` pushes `MedicineScreen` correctly
   (proves `AppNavigation.navigatorKey.currentState` still resolves).
4. From a connected dev session, press **R** (hot-restart). Verify no
   "Duplicate GlobalKey" assertion in `flutter logs` and the app comes
   back to the splash / AuthGate cleanly.
5. From a connected dev session, press **r** (hot-reload). Verify no
   regression in any tab.
6. Kill the dev session and re-run `flutter run -d 0935625332014966
   --dart-define=API_BASE_URL=https://ekthikana-api-x473.onrender.com`.
   Verify the app boots without "Duplicate GlobalKey".

## 10. What this commit does NOT change

- The `MaterialApp` / `Navigator` tree shape.
- Any route or `onGenerateRoute` entry.
- `AuthGate`, `_BootRouter`, `HomeShell`, or any screen.
- `NotificationService` or `NotificationActionHost` — they still read
  through the same `AppNavigation.navigatorKey` accessor.
- Firebase auth, Firestore, or `AuthService`.
- All 19 unit tests in `test/` — pass unchanged.
