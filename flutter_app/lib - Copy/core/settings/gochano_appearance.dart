// Appearance preference — Light / Dark / Follow system (spec §72).
//
// Previously the app was hardcoded to `ThemeMode.system` with no way for a
// student to choose, even though Profile is specified to expose an Appearance
// section. The choice is persisted so it survives a cold start.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GochanoAppearance {
  GochanoAppearance._();

  static const String _prefsKey = 'gochano.themeMode';

  /// The active theme mode. Read through [GochanoAppearanceScope].
  static final ValueNotifier<ThemeMode> mode =
      ValueNotifier<ThemeMode>(ThemeMode.system);

  /// Loads the persisted choice. Non-fatal on failure — the app simply
  /// follows the system theme.
  static Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      mode.value = _decode(prefs.getString(_prefsKey));
    } catch (_) {
      // Keep the default rather than blocking startup.
    }
  }

  static Future<void> select(ThemeMode value) async {
    if (mode.value == value) return;
    mode.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, _encode(value));
    } catch (_) {
      // Best-effort persistence; the in-memory switch already applied.
    }
  }

  static String _encode(ThemeMode value) => switch (value) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };

  static ThemeMode _decode(String? value) => switch (value) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
}

/// Rebuilds [builder] whenever the appearance preference changes.
class GochanoAppearanceScope extends StatelessWidget {
  const GochanoAppearanceScope({super.key, required this.builder});

  final Widget Function(BuildContext context, ThemeMode mode) builder;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: GochanoAppearance.mode,
      builder: (context, mode, _) => builder(context, mode),
    );
  }
}
