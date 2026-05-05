import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme/app_theme.dart';
import 'services/auth_service.dart';
import 'services/locale_service.dart';
import 'screens/auth/login_screen.dart';
import 'screens/customer/home_screen.dart';
import 'screens/owner/owner_dashboard_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Future.wait([
    AuthService.instance.loadFromStorage(),
    LocaleService.instance.loadFromStorage(),
  ]);
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
  @override
  void initState() {
    super.initState();
    // Rebuild the whole widget tree whenever the language changes.
    // Flutter preserves the Navigator state through this rebuild because
    // MaterialApp's internal navigator key remains stable.
    LocaleService.instance.addListener(_onLocaleChanged);
  }

  @override
  void dispose() {
    LocaleService.instance.removeListener(_onLocaleChanged);
    super.dispose();
  }

  void _onLocaleChanged() => setState(() {});

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
      home: home,
    );
  }
}
