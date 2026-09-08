class AppConfig {
  static const appName = 'Gochano';
  static const tagline = 'Everything in One Place';

  // Deliberately has no localhost default. A physical Android phone cannot
  // reach your PC through 127.0.0.1 unless adb reverse is active. Always pass
  // the local PC URL or the Render HTTPS URL with --dart-define.
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  static const bangladeshTimeZone = 'Asia/Dhaka';

  /// True when the API base URL points at a loopback / emulator-only address
  /// (localhost / 127.0.0.1 / 0.0.0.0 / ::1 / 10.0.2.2). On a physical Android
  /// device these URLs resolve to the device itself (or the emulator host
  /// alias) and will silently fail every request.
  static bool get isLoopback {
    final raw = apiBaseUrl.trim().toLowerCase();
    if (raw.isEmpty) return false;
    final hosts = [
      'localhost',
      '127.0.0.1',
      '0.0.0.0',
      '::1',
      '[::1]',
      // Android emulator alias for the host loopback. Only meaningful in an
      // emulator on the build machine; never valid for a physical device or
      // a release build.
      '10.0.2.2',
    ];
    for (final h in hosts) {
      if (raw.startsWith('$h:') || raw.startsWith('$h/') || raw == h) {
        return true;
      }
    }
    return false;
  }

  /// Throws StateError when the build is a release flavor and the API base
  /// URL resolves to a loopback host. Should be called before runApp().
  static void validateRelease({bool? isRelease}) {
    final release = isRelease ?? bool.fromEnvironment('dart.vm.product');
    if (release && apiBaseUrl.isEmpty) {
      throw StateError(
        'API_BASE_URL is not set. Build with --dart-define=API_BASE_URL=https://...',
      );
    }
    if (release && isLoopback) {
      throw StateError(
        'API_BASE_URL points at a loopback host ($apiBaseUrl). '
        'Physical devices cannot reach the developer machine. '
        'Use the Render HTTPS URL instead.',
      );
    }
  }
}
