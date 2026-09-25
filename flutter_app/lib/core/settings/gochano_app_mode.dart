// Gochano App Mode preference — Study Mode / Utility Mode (Phase A).
//
// App Mode is a client presentation preference controlling what a student or
// user sees in the bottom navigation and the Today feed.
//
// The choice is stored in local SharedPreferences and behaves as a device-level
// presentation preference, matching GochanoLanguage and GochanoAppearance.
//
// Unknown, null, or corrupted values safely default to GochanoAppMode.study.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The two mutually exclusive presentation modes in Gochano.
enum GochanoAppMode {
  study('study'),
  utility('utility');

  const GochanoAppMode(this.storageKey);

  /// Key string used when persisting to SharedPreferences.
  final String storageKey;

  /// Safely decodes a stored string into [GochanoAppMode].
  ///
  /// Null, empty, unknown, or corrupted strings safely resolve to [study].
  static GochanoAppMode fromString(String? value) {
    if (value == 'utility') return GochanoAppMode.utility;
    return GochanoAppMode.study;
  }
}

/// Device-level preference coordinator for App Mode.
class GochanoAppModePreferences {
  GochanoAppModePreferences._();

  static const String prefsKey = 'gochano.appMode';
  static const String discoveryKey = 'gochano.appMode.discovered';

  /// The active app mode. Rebuilt subtrees can listen through
  /// [ValueListenableBuilder] or [GochanoAppModeScope].
  static final ValueNotifier<GochanoAppMode> current =
      ValueNotifier<GochanoAppMode>(GochanoAppMode.study);

  /// Whether the active mode is Study Mode.
  static bool get isStudy => current.value == GochanoAppMode.study;

  /// Whether the active mode is Utility Mode.
  static bool get isUtility => current.value == GochanoAppMode.utility;

  /// Loads the persisted choice. Called during bootstrap before runApp();
  /// non-fatal on failure — the app simply defaults to [GochanoAppMode.study].
  static Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      current.value = GochanoAppMode.fromString(prefs.getString(prefsKey));
    } catch (_) {
      // Keep default GochanoAppMode.study rather than blocking startup.
    }
  }

  /// Selects and persists the new mode.
  ///
  /// Updates the in-memory [current] notifier immediately, then persists
  /// the choice to SharedPreferences asynchronously without network calls.
  static Future<void> select(GochanoAppMode mode) async {
    if (current.value == mode) return;
    current.value = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKey, mode.storageKey);
    } catch (_) {
      // Best-effort persistence; in-memory switch already applied.
    }
  }
}

/// Rebuilds [builder] whenever the app mode changes.
class GochanoAppModeScope extends StatelessWidget {
  const GochanoAppModeScope({super.key, required this.builder});

  final Widget Function(BuildContext context, GochanoAppMode mode) builder;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<GochanoAppMode>(
      valueListenable: GochanoAppModePreferences.current,
      builder: (context, mode, _) => builder(context, mode),
    );
  }
}
