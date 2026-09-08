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
///
/// This keeps:
///   - exactly one `MaterialApp` / one root `Navigator` (no architectural
///     change),
///   - the same `navigatorKey:` call site in `app.dart`,
///   - the same `AppNavigation.navigatorKey.currentContext` /
///     `.currentState` access pattern used by
///     `NotificationActionHost`,
///   - Firebase auth routing untouched (AuthGate stays inside the same
///     MaterialApp -> Navigator).
class AppNavigation {
  AppNavigation._();

  static GlobalKey<NavigatorState>? _navigatorKey;

  /// The single Navigator key for the current cold start.
  ///
  /// Allocated lazily on first read so callers that import this file
  /// don't accidentally trigger a key allocation before `main()` has
  /// finished initialising Firebase / notifications.
  static GlobalKey<NavigatorState> get navigatorKey {
    return _navigatorKey ??= GlobalKey<NavigatorState>();
  }

  /// Drop the cached key so the next cold start gets a fresh
  /// `GlobalKey` instance.
  ///
  /// Called from `main()` *before* the first `runApp`. Without this,
  /// a hot-restart on a developer build would reuse the same static
  /// key and trip Flutter's "Duplicate GlobalKey" assertion.
  static void resetForColdStart() {
    _navigatorKey = null;
  }
}
