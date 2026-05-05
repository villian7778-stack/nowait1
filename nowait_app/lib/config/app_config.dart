class AppConfig {
  // Android emulator: 10.0.2.2:8000
  // Web / real device: use your machine's local IP, e.g. http://192.168.1.x:8000
  static const String baseUrl = String.fromEnvironment(
    'BASE_URL',
    defaultValue: 'http://localhost:8000',
  );
}
