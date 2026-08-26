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
}
