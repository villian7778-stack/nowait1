class AppConfig {
  // Android emulator: 10.0.2.2:8000
  // Web / real device: use your machine's local IP, e.g. http://192.168.1.x:8000
  static const String baseUrl = String.fromEnvironment(
    'BASE_URL',
    defaultValue: 'http://localhost:8000',
  );

  // Used only for Google sign-in and password-recovery deep links via the
  // Supabase Flutter SDK. Email/password login/register still go through the
  // FastAPI backend above — this is never used for those.
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  // Must match the intent-filter scheme/host registered in AndroidManifest.xml
  // and the Redirect URL allow-listed in the Supabase dashboard.
  static const String authCallbackUrl = 'io.nowait.app://auth-callback';
}
