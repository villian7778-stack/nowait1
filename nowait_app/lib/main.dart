import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme/app_theme.dart';
import 'services/auth_service.dart';
import 'services/locale_service.dart';
import 'services/queue_monitor_service.dart';
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
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    LocaleService.instance.addListener(_onLocaleChanged);
    // Give the monitor the global key so it can show sheets from anywhere.
    QueueMonitorService.instance.navigatorKey = _navigatorKey;
  }

  @override
  void dispose() {
    LocaleService.instance.removeListener(_onLocaleChanged);
    QueueMonitorService.instance.stop();
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
      navigatorKey: _navigatorKey,
      home: home,
    );
  }
}
