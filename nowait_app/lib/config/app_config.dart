import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  // Android emulator: 10.0.2.2:8000
  // Web / real device: use your machine's local IP, e.g. http://192.168.1.x:8000
  static const String baseUrl = String.fromEnvironment(
    'BASE_URL',
    defaultValue: 'http://localhost:8000',
  );

  // Read GOOGLE_MAP_KEY from .env file at runtime.
  // Falls back to --dart-define=GOOGLE_MAP_KEY=<value> for CI/CD pipelines.
  static String get googleMapsApiKey {
    return dotenv.env['GOOGLE_MAP_KEY'] ??
        const String.fromEnvironment('GOOGLE_MAP_KEY', defaultValue: '');
  }
}
