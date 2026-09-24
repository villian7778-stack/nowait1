import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'config/app_config.dart';
import 'theme/app_theme.dart';
import 'services/auth_service.dart';
import 'services/locale_service.dart';
import 'services/queue_monitor_service.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/create_account_screen.dart';
import 'screens/auth/reset_password_screen.dart';
import 'screens/customer/home_screen.dart';
import 'screens/owner/owner_dashboard_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Future.wait([
    AuthService.instance.loadFromStorage(),
    LocaleService.instance.loadFromStorage(),
  ]);
  // Only used for Google sign-in + password-recovery deep links — email/password
  // login/register go through the FastAPI backend regardless of this.
  if (AppConfig.supabaseUrl.isNotEmpty && AppConfig.supabaseAnonKey.isNotEmpty) {
    await sb.Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
    );
  }
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));
  runApp(const NoWaitApp());
}

class NoWaitApp extends StatefulWidget {
  const NoWaitApp({super.key});

  @override
  State<NoWaitApp> createState() => _NoWaitAppState();
}

class _NoWaitAppState extends State<NoWaitApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<sb.AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    LocaleService.instance.addListener(_onLocaleChanged);
    // Give the monitor the global key so it can show sheets from anywhere.
    QueueMonitorService.instance.navigatorKey = _navigatorKey;

    if (AppConfig.supabaseUrl.isNotEmpty && AppConfig.supabaseAnonKey.isNotEmpty) {
      _authSub = sb.Supabase.instance.client.auth.onAuthStateChange.listen(_onSupabaseAuthEvent);
    }
  }

  @override
  void dispose() {
    LocaleService.instance.removeListener(_onLocaleChanged);
    QueueMonitorService.instance.stop();
    _authSub?.cancel();
    super.dispose();
  }

  void _onLocaleChanged() => setState(() {});

  /// Handles the two deep-link-driven Supabase auth events: a completed
  /// Google OAuth sign-in, and an opened password-recovery link.
  void _onSupabaseAuthEvent(sb.AuthState state) async {
    final event = state.event;
    final session = state.session;

    if (event == sb.AuthChangeEvent.passwordRecovery) {
      _navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => const ResetPasswordScreen()),
      );
      return;
    }

    if (event == sb.AuthChangeEvent.signedIn && session != null) {
      // Email/password login never touches the Supabase client directly, so a
      // signedIn event here always means the Google OAuth deep link just landed.
      if (AuthService.instance.accessToken == session.accessToken) return;
      final profileComplete = await AuthService.instance.adoptSupabaseSession(session);
      setState(() {}); // reflect the new session in `home` below
      final nav = _navigatorKey.currentState;
      if (nav == null) return;
      if (!profileComplete) {
        nav.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const CreateAccountScreen(isCompletingProfile: true)),
          (r) => false,
        );
      } else {
        final isOwner = AuthService.instance.isOwner;
        nav.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => isOwner ? const OwnerDashboardScreen() : const HomeScreen()),
          (r) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget home;
    if (AuthService.instance.isLoggedIn) {
      home = AuthService.instance.isOwner
          ? const OwnerDashboardScreen()
          : const HomeScreen();
    } else {
      home = const LoginScreen();
    }
    return MaterialApp(
      title: 'NOWAIT',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      navigatorKey: _navigatorKey,
      home: home,
    );
  }
}
