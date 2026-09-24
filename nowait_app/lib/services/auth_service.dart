import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'api_client.dart';

/// Result of a registration attempt — either the account is immediately
/// active (session returned) or Supabase requires email confirmation first.
class RegisterResult {
  final bool emailConfirmationRequired;
  final String? message;
  RegisterResult({required this.emailConfirmationRequired, this.message});
}

class AuthService {
  static final AuthService instance = AuthService._();
  AuthService._();

  static const _secureStorage = FlutterSecureStorage();

  String? accessToken;
  String? refreshToken;
  Map<String, dynamic>? profile;

  bool get isLoggedIn => accessToken != null && profile != null;
  bool get isOwner => profile?['role'] == 'owner';

  Future<void> loadFromStorage() async {
    // Tokens live in encrypted storage (Keystore/Keychain-backed); only the
    // non-sensitive profile blob stays in plain shared_preferences.
    accessToken = await _secureStorage.read(key: 'access_token');
    refreshToken = await _secureStorage.read(key: 'refresh_token');
    final prefs = await SharedPreferences.getInstance();
    final profileStr = prefs.getString('user_profile');
    if (profileStr != null) {
      profile = jsonDecode(profileStr);
    }
  }

  /// Persists the current in-memory tokens — call after updating them outside
  /// this service (e.g. ApiClient's silent token refresh on a 401).
  Future<void> persistTokens() => _saveToStorage();

  Future<void> _saveToStorage() async {
    if (accessToken != null) await _secureStorage.write(key: 'access_token', value: accessToken!);
    if (refreshToken != null) await _secureStorage.write(key: 'refresh_token', value: refreshToken!);
    final prefs = await SharedPreferences.getInstance();
    if (profile != null) await prefs.setString('user_profile', jsonEncode(profile));
  }

  Future<void> logout() async {
    accessToken = null;
    refreshToken = null;
    profile = null;
    await _secureStorage.deleteAll();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    try {
      await sb.Supabase.instance.client.auth.signOut();
    } catch (_) {
      // Supabase may not have an active session (e.g. email/password-only users) — fine to ignore.
    }
  }

  /// Registers a new account with email + password. The mobile number is
  /// stored on the profile only — never sent an OTP, never used to log in.
  Future<RegisterResult> register({
    required String name,
    required String phone,
    required String email,
    required String password,
    required String state,
    required String city,
    required String role,
  }) async {
    final res = await ApiClient.instance.post('/auth/register', body: {
      'name': name,
      'phone': phone,
      'email': email,
      'password': password,
      'state': state,
      'city': city,
      'role': role,
    });
    final emailConfirmationRequired = res['email_confirmation_required'] as bool? ?? false;
    if (!emailConfirmationRequired) {
      accessToken = res['access_token'];
      refreshToken = res['refresh_token'];
      if (res['profile'] != null) {
        profile = Map<String, dynamic>.from(res['profile']);
      }
      await _saveToStorage();
    }
    return RegisterResult(
      emailConfirmationRequired: emailConfirmationRequired,
      message: res['message'] as String?,
    );
  }

  /// Returns true if profile is already complete, false if profile_required
  /// (should not normally happen for email/password login, since register()
  /// creates the profile in the same call — kept for forward-compatibility).
  Future<bool> login(String email, String password) async {
    final res = await ApiClient.instance.post('/auth/login', body: {
      'email': email,
      'password': password,
    });
    accessToken = res['access_token'];
    refreshToken = res['refresh_token'];
    if (res['profile'] != null) {
      profile = Map<String, dynamic>.from(res['profile']);
      await _saveToStorage();
      return true;
    }
    await _saveToStorage();
    return false;
  }

  Future<String> forgotPassword(String email) async {
    final res = await ApiClient.instance.post('/auth/forgot-password', body: {'email': email});
    return res['message'] as String? ?? 'If an account exists for this email, a reset link has been sent.';
  }

  /// Adopts a Supabase session obtained client-side (Google sign-in), then
  /// checks whether a profile already exists for this user.
  /// Returns true if the profile is complete, false if it still needs
  /// completing via [completeProfile].
  Future<bool> adoptSupabaseSession(sb.Session session) async {
    accessToken = session.accessToken;
    refreshToken = session.refreshToken;
    await _saveToStorage();
    try {
      await refreshProfile();
      return true;
    } on ApiException catch (e) {
      if (e.statusCode == 404) {
        return false;
      }
      rethrow;
    }
  }

  /// Completes the profile for a new Google sign-in (name + mobile number are
  /// user-entered; email comes from the Google account, never re-typed).
  Future<void> completeProfile({
    required String name,
    required String phone,
    required String state,
    required String city,
    required String role,
  }) async {
    final res = await ApiClient.instance.post('/auth/complete-profile', body: {
      'name': name,
      'phone': phone,
      'state': state,
      'city': city,
      'role': role,
    });
    profile = Map<String, dynamic>.from(res);
    await _saveToStorage();
  }

  /// Sets a new password using the temporary recovery session Supabase
  /// establishes automatically when the reset-password deep link is opened.
  Future<void> resetPassword(String newPassword) async {
    await sb.Supabase.instance.client.auth.updateUser(
      sb.UserAttributes(password: newPassword),
    );
  }

  Future<void> deleteAccount() async {
    await ApiClient.instance.delete('/auth/account');
    await logout();
  }

  Future<void> refreshProfile() async {
    final res = await ApiClient.instance.get('/auth/me');
    profile = Map<String, dynamic>.from(res);
    await _saveToStorage();
  }
}
