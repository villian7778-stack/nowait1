import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'queue_service.dart';

/// Owner side: a bell when a new customer joins the queue online. Sound only - no notification.
///
/// While the owner app is open and in the foreground it checks the shop's queue every
/// [interval]; when entries appear that weren't there before (and aren't walk-ins the owner added
/// themselves), the bell rings once. The first check only records who is already waiting, so
/// opening the app doesn't ring. Muting (owner Profile tab) is remembered on this phone.
class NewCustomerBell with WidgetsBindingObserver {
  static final NewCustomerBell instance = NewCustomerBell._();
  NewCustomerBell._();

  static const interval = Duration(seconds: 8);
  static const _prefKey = 'owner_new_customer_sound';
  static const _sound = 'sounds/new_customer.wav';

  /// true = bell on (the default). The Profile switch listens to this.
  final ValueNotifier<bool> enabled = ValueNotifier(true);

  String? _shopId;
  Timer? _timer;
  Set<String>? _seen; // ids already in the queue; null = not checked yet
  bool _foreground = true;
  bool _observing = false;
  bool _checking = false;
  AudioPlayer? _player;

  /// Overridable in tests: plays the bell.
  @visibleForTesting
  Future<void> Function() ring = _playBell;

  /// Load the saved on/off choice (once at start-up).
  Future<void> loadPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      enabled.value = prefs.getBool(_prefKey) ?? true;
    } catch (_) {}
  }

  Future<void> setEnabled(bool on) async {
    enabled.value = on;
    _seen = null; // don't ring for customers who joined while it was off
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, on);
    } catch (_) {}
    _restart();
  }

  /// Start listening for this owner's shop (owner dashboard, once the shop is known).
  /// [checkNow]: tests drive [check] themselves.
  void start(String shopId, {@visibleForTesting bool checkNow = true}) {
    if (_shopId != shopId) _seen = null;
    _shopId = shopId;
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    _restart(checkNow: checkNow);
  }

  /// Owner dashboard closed / logout.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _shopId = null;
    _seen = null;
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) _seen = null; // after coming back: re-check who's there, ring only for new
    _restart();
  }

  void _restart({bool checkNow = true}) {
    _timer?.cancel();
    _timer = null;
    if (_shopId == null || !enabled.value || !_foreground) return;
    _timer = Timer.periodic(interval, (_) => check());
    if (checkNow) check();
  }

  /// One check of the queue. Public for tests.
  @visibleForTesting
  Future<void> check() async {
    final shopId = _shopId;
    if (shopId == null || !enabled.value || _checking) return;
    _checking = true;
    try {
      final res = await QueueService.instance.getShopQueue(shopId);
      final queue = (res['queue'] as List? ?? const [])
          .whereType<Map>()
          .where((e) => e['is_walk_in'] != true) // the owner added those: no bell
          .map((e) => e['id']?.toString())
          .whereType<String>()
          .toSet();
      final seen = _seen;
      if (seen != null && queue.difference(seen).isNotEmpty && enabled.value && _shopId == shopId) {
        await ring();
      }
      _seen = queue;
    } catch (_) {
      // offline / server asleep: try again next time
    } finally {
      _checking = false;
    }
  }

  static Future<void> _playBell() async {
    try {
      final player = instance._player ??= AudioPlayer();
      await player.stop();
      await player.play(AssetSource(_sound));
    } catch (e) {
      debugPrint('Could not play the new-customer bell: $e');
    }
  }

  @visibleForTesting
  void debugReset() {
    stop();
    enabled.value = true;
    ring = _playBell;
  }
}
