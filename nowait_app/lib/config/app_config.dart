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

  /// Public policy pages served by the backend: privacy, terms, refund-policy, contact, delete-account.
  static String legalUrl(String page) => '$baseUrl/legal/$page';

  /// Why this build must not be shipped, or null when it is fine. A release build needs a real HTTPS
  /// backend and the Supabase sign-in settings; without this check a forgotten --dart-define ships an
  /// app that quietly talks to localhost. The parameters exist only for tests.
  static String? releaseConfigProblem({String? base, String? sbUrl, String? sbKey}) {
    final b = base ?? baseUrl;
    final u = sbUrl ?? supabaseUrl;
    final k = sbKey ?? supabaseAnonKey;
    if (!b.startsWith('https://')) return 'BASE_URL must be the https:// address of the production server (got "$b").';
    if (b.contains('localhost') || b.contains('10.0.2.2') || b.contains('192.168.')) {
      return 'BASE_URL points at a development machine ("$b").';
    }
    if (!u.startsWith('https://') || k.isEmpty) return 'SUPABASE_URL and SUPABASE_ANON_KEY must be set for Google sign-in.';
    return null;
  }
}
