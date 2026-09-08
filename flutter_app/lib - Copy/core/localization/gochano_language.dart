// Gochano bilingual layer — English / Bangla (spec §73).
//
// Two defects in the previous implementation are fixed here:
//
//  1. **The choice was not persisted.** `EkLanguage.bangla` was an in-memory
//     `ValueNotifier`, so a student who selected Bangla was back in English
//     after every cold start. The selection now round-trips through
//     SharedPreferences.
//
//  2. **Screens could go stale.** Each screen had to remember to wrap itself
//     in a `ValueListenableBuilder`; any subtree that forgot kept rendering
//     the previous language, producing exactly the "mixed-language accidental
//     strings" spec §73 warns about. [GochanoLanguageScope] now rebuilds the
//     whole app from the root on change, so a subtree cannot be stale.
//
// The call-site API is deliberately unchanged — `GochanoLanguage.text(en, bn)`
// keeps the English and Bangla strings adjacent in the source, which is what
// stops a translation being silently forgotten when a screen is edited.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The languages Gochano ships.
enum GochanoLocale {
  english('en', 'English', 'EN'),
  bangla('bn', 'বাংলা', 'বাংলা');

  const GochanoLocale(this.code, this.nativeName, this.shortLabel);

  /// ISO code persisted to disk and handed to Flutter's [Locale].
  final String code;

  /// The language's own name, always shown in that language.
  final String nativeName;

  /// Compact label for the in-app toggle.
  final String shortLabel;

  Locale get locale => Locale(code);

  static GochanoLocale fromCode(String? code) =>
      code == bangla.code ? bangla : english;
}

/// App-wide language state.
class GochanoLanguage {
  GochanoLanguage._();

  static const String _prefsKey = 'gochano.language';

  /// The active language. Listen through [GochanoLanguageScope] rather than
  /// attaching your own listener in a screen.
  static final ValueNotifier<GochanoLocale> current =
      ValueNotifier<GochanoLocale>(GochanoLocale.english);

  static bool get isBangla => current.value == GochanoLocale.bangla;

  /// Picks the string for the active language.
  ///
  /// ```dart
  /// Text(GochanoLanguage.text('Subjects', 'বিষয়'))
  /// ```
  static String text(String en, String bn) => isBangla ? bn : en;

  /// Loads the persisted choice. Called once during app bootstrap; failures
  /// are non-fatal and simply leave the app in English.
  static Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      current.value = GochanoLocale.fromCode(prefs.getString(_prefsKey));
    } catch (_) {
      // Storage unavailable — keep the default rather than blocking startup.
    }
  }

  /// Switches language and persists the choice.
  static Future<void> select(GochanoLocale locale) async {
    if (current.value == locale) return;
    current.value = locale;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, locale.code);
    } catch (_) {
      // The in-memory switch already happened; persistence is best-effort.
    }
  }
}

/// Rebuilds [child] whenever the language changes.
///
/// Mounted once, above `MaterialApp`, so every route and every dialog picks
/// up a language change in the same frame.
class GochanoLanguageScope extends StatelessWidget {
  const GochanoLanguageScope({super.key, required this.builder});

  final Widget Function(BuildContext context, GochanoLocale locale) builder;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<GochanoLocale>(
      valueListenable: GochanoLanguage.current,
      builder: (context, locale, _) => builder(context, locale),
    );
  }
}

/// `context.tr('English', 'বাংলা')` — the shorthand used inside build methods.
extension GochanoLanguageX on BuildContext {
  String tr(String en, String bn) => GochanoLanguage.text(en, bn);

  bool get isBangla => GochanoLanguage.isBangla;
}
