import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';
import 'auth_service.dart';
import 'queue_service.dart';

/// Owner side: a bell when a new customer joins the queue online.
///
/// Two ways it reaches the owner, sharing one "already rang for" list so it never rings twice:
/// - the server's "New customer joined" push (push_service.dart; app closed or open), and
/// - while the owner app is open and in the foreground, a check of the shop's queue every
///   [interval] - the fallback when push isn't available. New entries (not walk-ins the owner
///   added themselves) ring once; the first check only records who is already waiting.
/// Muting (owner Profile tab) is remembered on this phone and sent to the server, which then
/// stops the push too.
class NewCustomerBell with WidgetsBindingObserver {
  static final NewCustomerBell instance = NewCustomerBell._();
  NewCustomerBell._();

  static const interval = Duration(seconds: 8);
  static const _prefKey = 'owner_new_customer_sound';
  static const _sound = 'sounds/new_customer.mp3';

  /// true = bell on (the default). The Profile switch listens to this.
  final ValueNotifier<bool> enabled = ValueNotifier(true);

  String? _shopId;
  Timer? _timer;
  Set<String>? _seen; // ids already in the queue; null = not checked yet
  final Set<String> _pushed = {}; // ids already announced (push or bell): never ring for them again
  DateTime? _lastFed; // Manage Shop handed us its queue at this time
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
    syncToServer();
  }

  /// Tell the server whether to push "New customer joined" to this owner (on switch change and
  /// when push registers after login). Best-effort, never throws.
  Future<void> syncToServer() async {
    final auth = AuthService.instance;
    if (!auth.isLoggedIn || auth.profile?['role'] != 'owner') return;
    try {
      await ApiClient.instance
          .put('/auth/new-customer-alerts', body: {'enabled': enabled.value})
          .timeout(const Duration(seconds: 6));
    } catch (_) {}
  }

  /// A "New customer joined" push arrived while the app is open. Returns whether it should make
  /// the sound: not when muted, and not when the queue check already rang for this customer.
  /// A customer announced here doesn't ring again on the next queue check.
  bool takeFromPush(String? entryId) {
    if (!enabled.value) return false;
    final seen = _seen;
    if (entryId == null || entryId.isEmpty) return true;
    if ((seen != null && seen.contains(entryId)) || !_pushed.add(entryId)) return false;
    if (_pushed.length > 200) _pushed.remove(_pushed.first);
    return true;
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
    _pushed.clear();
    _lastFed = null;
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

  /// Manage Shop already loads this shop's queue every few seconds: it hands the answer here, so
  /// the bell doesn't ask the server for the same thing again.
  void feed(String shopId, Map<String, dynamic> res) {
    if (shopId != _shopId || !enabled.value) return;
    _lastFed = DateTime.now();
    _process(shopId, res);
  }

  /// One check of the queue. Public for tests.
  @visibleForTesting
  Future<void> check() async {
    final shopId = _shopId;
    if (shopId == null || !enabled.value || _checking) return;
    final fed = _lastFed;
    if (fed != null && DateTime.now().difference(fed) < interval) return; // Manage Shop just looked
    _checking = true;
    try {
      _process(shopId, await QueueService.instance.getShopQueue(shopId));
    } catch (_) {
      // offline / server asleep: try again next time
    } finally {
      _checking = false;
    }
  }

  void _process(String shopId, Map<String, dynamic> res) {
    final queue = (res['queue'] as List? ?? const [])
        .whereType<Map>()
        .where((e) => e['is_walk_in'] != true) // the owner added those: no bell
        .map((e) => e['id']?.toString())
        .whereType<String>()
        .toSet();
    final seen = _seen;
    final fresh = seen == null ? const <String>{} : queue.difference(seen).difference(_pushed);
    _seen = queue;
    if (fresh.isNotEmpty && enabled.value && _shopId == shopId) {
      // remembered, so an older answer arriving late can't ring for them again
      _pushed.addAll(fresh);
      while (_pushed.length > 200) {
        _pushed.remove(_pushed.first);
      }
      ring();
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
