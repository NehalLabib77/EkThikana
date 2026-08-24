class AppConfig {
  static const appName = 'EkThikana';
  static const tagline = 'One place for everything';

  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  static const bangladeshTimeZone = 'Asia/Dhaka';
}
