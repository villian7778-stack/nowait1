import 'dart:async';
import 'dart:io' show Platform;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'api_client.dart';
import 'auth_service.dart';

/// Push notifications (Firebase Cloud Messaging): "It's your turn", "Almost your turn", "Skipped"
/// for customers, "I'm coming" for shop owners - also when the app is closed. The server decides
/// what to send (nowait_backend/app/services/push_service.py).
///
/// After login the phone's FCM token is sent to the server (asking for the notification permission
/// once, as Android 13+ requires); at logout it is removed there and on the phone, so the next
/// person on this phone doesn't get the previous user's alerts. Everything here is best-effort:
/// without Firebase / permission the app works exactly as before (alerts stay in-app).
class PushService {
  static final PushService instance = PushService._();
  PushService._();

  /// Must match the channel the server sends to and the manifest's default channel.
  static const channelId = 'nowait_alerts';

  /// Tests (and platforms without Firebase) skip all of this.
  @visibleForTesting
  static bool disabled = false;

  final _local = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  String? _registeredUserId;
  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;

  bool get _supported => !disabled && !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Once at start-up. Never throws.
  Future<void> init() async {
    if (!_supported || _ready) return;
    try {
      await Firebase.initializeApp();
      await _local.initialize(
        settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      );
      await _local
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(const AndroidNotificationChannel(
            channelId,
            'Queue alerts',
            description: 'Your turn, almost your turn, and customers on the way',
            importance: Importance.high,
          ));
      // With the app open, Android doesn't show a push by itself: show it here.
      _foregroundSub = FirebaseMessaging.onMessage.listen(_showWhileOpen);
      _ready = true;
      AuthService.instance.addListener(_onAuthChanged);
      _onAuthChanged();
    } catch (e) {
      debugPrint('Push notifications unavailable: $e');
    }
  }

  void _onAuthChanged() {
    final userId = AuthService.instance.profile?['id'] as String?;
    if (AuthService.instance.isLoggedIn && userId != null && userId != _registeredUserId) {
      _register(userId);
    }
  }

  Future<void> _register(String userId) async {
    try {
      _registeredUserId = userId;
      final messaging = FirebaseMessaging.instance;
      final perm = await messaging.requestPermission();
      if (perm.authorizationStatus == AuthorizationStatus.denied) return; // their choice: in-app only
      final token = await messaging.getToken();
      if (token != null) await _send(token);
      _tokenRefreshSub ??= messaging.onTokenRefresh.listen((t) {
        if (AuthService.instance.isLoggedIn) _send(t);
      });
    } catch (e) {
      _registeredUserId = null; // try again next time
      debugPrint('Push registration failed: $e');
    }
  }

  Future<void> _send(String token) async {
    try {
      await ApiClient.instance.post('/auth/fcm-token', body: {'fcm_token': token});
    } catch (e) {
      debugPrint('Could not save the push token: $e');
    }
  }

  /// At logout, while still logged in: stop this phone getting this user's alerts. Quick and
  /// never throws - logout must not wait on the network.
  Future<void> unregister() async {
    if (!_ready || _registeredUserId == null) return;
    _registeredUserId = null;
    try {
      await ApiClient.instance.delete('/auth/fcm-token').timeout(const Duration(seconds: 4));
    } catch (_) {}
    try {
      await FirebaseMessaging.instance.deleteToken().timeout(const Duration(seconds: 4));
    } catch (_) {}
  }

  Future<void> _showWhileOpen(RemoteMessage message) async {
    final n = message.notification;
    if (n == null) return;
    try {
      await _local.show(
        id: message.hashCode & 0x7fffffff,
        title: n.title,
        body: n.body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            'Queue alerts',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Could not show the notification: $e');
    }
  }

  @visibleForTesting
  Future<void> debugReset() async {
    await _tokenRefreshSub?.cancel();
    await _foregroundSub?.cancel();
    _tokenRefreshSub = null;
    _foregroundSub = null;
    _registeredUserId = null;
    _ready = false;
  }
}
