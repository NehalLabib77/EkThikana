// Gochano connectivity service.
//
// Single source of truth for online/offline state across the app. The
// offline banner subscribes to [online] instead of polling
// connectivity_plus independently, which would duplicate stream
// subscriptions and risk drift between UI consumers.
//
// Architecture:
//   - `init()` subscribes to connectivity_plus's `onConnectivityChanged`
//     stream and seeds the initial value from a single
//     `checkConnectivity()` call.
//   - The current online state lives in [online], a `ValueNotifier<bool>`
//     that any widget can rebuild against via `ValueListenableBuilder`.
//   - The user-facing contract is binary: "you can reach the server" or
//     "you cannot". Connectivity transitions are intentionally collapsed
//     across wifi / cellular / vpn because the banner text only has two
//     states.
//
//   - On non-supported platforms (desktop, web) we treat the user as
//     always online. We still emit a single `true` so any UI subscribing
//     sees a stable value.
//
// Lifecycle:
//   - `init()` is called from `main.dart` after the first frame, just like
//     `NotificationService.init()`.  It is idempotent.
//
// Testing:
//   - `debugForceValue(bool)` lets widget tests push a deterministic value
//     without standing up the platform channel. Gated by
//     `@visibleForTesting`.

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

class ConnectivityService {
  ConnectivityService._();

  static final ConnectivityService instance = ConnectivityService._();

  final Connectivity _plugin = Connectivity();

  /// Whether the device currently has any usable connectivity
  /// (wifi, cellular, ethernet, or vpn). Defaults to `true` until the
  /// first platform probe resolves, so the first frame does not flash a
  /// red banner for users who *are* online.
  final ValueNotifier<bool> online = ValueNotifier<bool>(true);

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _initialized = false;

  /// Wire up the platform stream. Idempotent — safe to call from multiple
  /// callers.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final current = await _plugin.checkConnectivity();
      _emit(_hasInternet(current));
    } catch (_) {
      // If the platform channel is unavailable (test env, rare OEM bug)
      // assume online so the UI does not falsely block features.
      _emit(true);
    }

    _subscription = _plugin.onConnectivityChanged.listen(
      (results) => _emit(_hasInternet(results)),
      onError: (_) => _emit(true),
    );
  }

  /// Tear down the stream subscription. Currently only used by tests; the
  /// service is otherwise a process-wide singleton.
  @visibleForTesting
  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    _initialized = false;
  }

  /// Force a deterministic online/offline value. Test-only — production
  /// code must let the platform stream drive the flag.
  @visibleForTesting
  void debugForceValue(bool value) {
    _emit(value);
  }

  void _emit(bool value) {
    if (online.value != value) {
      online.value = value;
    }
  }

  static bool _hasInternet(List<ConnectivityResult> results) {
    if (results.isEmpty) return false;
    return results.any((r) => r != ConnectivityResult.none);
  }

  /// Test-only re-export of [_hasInternet]. The classification rule is
  /// the contract every UI consumer relies on, so it is tested directly
  /// rather than through indirect UI rebuilds.
  @visibleForTesting
  static bool debugHasInternet(List<ConnectivityResult> results) =>
      _hasInternet(results);
}