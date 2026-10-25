import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api_client.dart';

/// Forced updates. The server decides which build numbers are too old (APP_MIN_BUILD_ANDROID /
/// APP_MIN_BUILD_IOS); such a build shows the "Update required" screen instead of the app until
/// the user installs the new version from the store.
///
/// Checked at start-up and whenever the app comes back to the foreground, and any API call that
/// answers 426 (every call from a too-old build does) turns it on too, so an app left open
/// can't keep being used.
class AppUpdateService extends ChangeNotifier {
  static final AppUpdateService instance = AppUpdateService._();
  AppUpdateService._();

  static const _fallbackPackage = 'com.nowait.nowait_app';

  bool _required = false;
  String? _storeUrl;
  int? _build;
  String? _packageName;

  bool get updateRequired => _required;

  /// Lets tests (which run on a desktop) behave like a phone.
  @visibleForTesting
  static String? debugPlatformOverride;

  /// 'android' / 'ios', or null where store updates don't apply (web, desktop).
  String? get platform {
    if (debugPlatformOverride != null) return debugPlatformOverride;
    if (kIsWeb) return null;
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return null;
  }

  /// Sent with every API request so the server can tell an out-of-date build.
  Map<String, String> get requestHeaders {
    final p = platform;
    final b = _build;
    if (p == null || b == null) return const {};
    return {'X-App-Platform': p, 'X-App-Build': '$b'};
  }

  /// Reads this build's number (the +N of `version:` in pubspec.yaml). Local and fast.
  Future<void> init() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _build = int.tryParse(info.buildNumber);
      _packageName = info.packageName;
    } catch (e) {
      debugPrint('Could not read the app version: $e');
    }
  }

  /// Asks the server whether this build may still be used. Offline or server asleep: nothing
  /// changes, and the 426 on the next API call still catches an out-of-date build.
  Future<void> check() async {
    final p = platform;
    final b = _build;
    if (p == null || b == null) return;
    try {
      final res = await ApiClient.instance.get('/app/version', query: {'platform': p, 'build': b});
      if (res is! Map) return;
      final url = res['store_url'];
      if (url is String && url.isNotEmpty) _storeUrl = url;
      // Can also switch off again if the minimum was lowered on the server.
      _set(res['update_required'] == true);
    } catch (_) {}
  }

  /// Called by [ApiClient] when the server answers 426.
  void markRequired(String? storeUrl) {
    if (storeUrl != null && storeUrl.isNotEmpty) _storeUrl = storeUrl;
    _set(true);
  }

  void _set(bool value) {
    if (_required == value) return;
    _required = value;
    notifyListeners();
  }

  @visibleForTesting
  void debugReset() {
    _required = false;
    _storeUrl = null;
  }

  /// Opens this app's page in the Play Store (Android) or the App Store (iPhone).
  Future<void> openStore() async {
    final pkg = _packageName ?? _fallbackPackage;
    final url = _storeUrl;
    final candidates = <Uri>[
      if (platform == 'android') Uri.parse('market://details?id=$pkg'), // the Play Store app itself
      if (url != null && url.isNotEmpty) Uri.parse(url),
      if (platform == 'android') Uri.parse('https://play.google.com/store/apps/details?id=$pkg'),
      if (platform == 'ios') Uri.parse('https://apps.apple.com/'),
    ];
    for (final uri in candidates) {
      try {
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
      } catch (_) {}
    }
  }
}
