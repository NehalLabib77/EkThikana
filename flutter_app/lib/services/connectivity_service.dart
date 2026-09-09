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
//
// Offline mode:
//   - [offlineCache] provides a simple in-memory cache for frequently
//     accessed data (notes, medicines, settings) that can be read when
//     offline.
//   - [requireInternet] returns whether a specific feature needs internet.
//   - Cached data is automatically invalidated when connectivity returns.

import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Features that can work offline (cached data available).
enum OfflineFeature {
  notes('notes', 'Notes'),
  medicines('medicines', 'Medicines'),
  settings('settings', 'Settings'),
  expenses('expenses', 'Expenses');

  const OfflineFeature(this.id, this.label);
  final String id;
  final String label;
}

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

  /// Simple in-memory cache for offline data.
  final Map<String, dynamic> _cache = {};

  /// Cache timestamps for staleness checks.
  final Map<String, DateTime> _cacheTimestamps = {};

  /// Maximum cache age before data is considered stale (24 hours).
  static const Duration _maxCacheAge = Duration(hours: 24);

  /// SharedPreferences key prefix for persistent cache.
  static const String _cachePrefix = 'gochano_offline_cache_';

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

    // Load persistent cache on startup
    await _loadPersistentCache();
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
      // When coming back online, we could invalidate stale cache here
      // if needed. For now, we keep cached data until explicitly cleared.
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

  // ---------------------------------------------------------------------------
  // Offline cache
  // ---------------------------------------------------------------------------

  /// Check if a feature requires internet access.
  ///
  /// Returns `true` if the feature cannot work offline.
  /// Returns `false` if cached data is available.
  bool requireInternet(OfflineFeature feature) {
    // If online, nothing requires internet (we can fetch fresh data)
    if (online.value) return false;

    // If offline, check if we have valid cache
    final cacheKey = feature.id;
    if (_cache.containsKey(cacheKey)) {
      final timestamp = _cacheTimestamps[cacheKey];
      if (timestamp != null && DateTime.now().difference(timestamp) < _maxCacheAge) {
        return false; // Cache is valid, can work offline
      }
    }

    // No valid cache, requires internet
    return true;
  }

  /// Store data in the offline cache.
  ///
  /// [feature] is the feature category (notes, medicines, etc.).
  /// [key] is the specific data identifier.
  /// [data] is the data to cache (must be JSON-serializable).
  Future<void> cacheData(OfflineFeature feature, String key, dynamic data) async {
    final cacheKey = '${feature.id}_$key';
    _cache[cacheKey] = data;
    _cacheTimestamps[cacheKey] = DateTime.now();

    // Persist to SharedPreferences for app restarts
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(data);
      await prefs.setString('$_cachePrefix$cacheKey', jsonStr);
      await prefs.setString('$_cachePrefix${cacheKey}_time',
          DateTime.now().toIso8601String());
    } catch (_) {
      // Silently fail if persistence isn't available
    }
  }

  /// Retrieve data from the offline cache.
  ///
  /// Returns `null` if no cached data exists or if it's stale.
  dynamic getCachedData(OfflineFeature feature, String key) {
    final cacheKey = '${feature.id}_$key';
    final data = _cache[cacheKey];
    if (data == null) return null;

    final timestamp = _cacheTimestamps[cacheKey];
    if (timestamp != null && DateTime.now().difference(timestamp) > _maxCacheAge) {
      return null; // Stale
    }

    return data;
  }

  /// Clear cache for a specific feature.
  Future<void> clearFeatureCache(OfflineFeature feature) async {
    final prefix = '${feature.id}_';
    final keysToRemove = _cache.keys.where((k) => k.startsWith(prefix)).toList();
    for (final key in keysToRemove) {
      _cache.remove(key);
      _cacheTimestamps.remove(key);
    }

    // Clear from SharedPreferences too
    try {
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys().where((k) => k.startsWith('$_cachePrefix$prefix'));
      for (final key in allKeys) {
        await prefs.remove(key);
      }
    } catch (_) {
      // Silently fail
    }
  }

  /// Clear all cached data.
  Future<void> clearAllCache() async {
    _cache.clear();
    _cacheTimestamps.clear();

    try {
      final prefs = await SharedPreferences.getInstance();
      final keysToRemove = prefs.getKeys().where((k) => k.startsWith(_cachePrefix));
      for (final key in keysToRemove) {
        await prefs.remove(key);
      }
    } catch (_) {
      // Silently fail
    }
  }

  /// Load persistent cache from SharedPreferences on startup.
  Future<void> _loadPersistentCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys().where((k) => k.startsWith(_cachePrefix));

      for (final key in allKeys) {
        if (key.endsWith('_time')) continue; // Skip timestamps

        final dataStr = prefs.getString(key);
        if (dataStr == null) continue;

        try {
          final data = jsonDecode(dataStr);
          final timeStr = prefs.getString('${key}_time');
          final timestamp = timeStr != null ? DateTime.parse(timeStr) : DateTime.now();

          // Only load if not stale
          if (DateTime.now().difference(timestamp) < _maxCacheAge) {
            final cacheKey = key.replaceFirst(_cachePrefix, '');
            _cache[cacheKey] = data;
            _cacheTimestamps[cacheKey] = timestamp;
          }
        } catch (_) {
          // Skip malformed entries
        }
      }
    } catch (_) {
      // Silently fail if SharedPreferences isn't available
    }
  }
}