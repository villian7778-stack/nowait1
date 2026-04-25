import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';

class AuthService {
  static final AuthService instance = AuthService._();
  AuthService._();

  String? accessToken;
  String? refreshToken;
  Map<String, dynamic>? profile;

  // Temp storage for registration flow
  String? pendingName;
  String? pendingState;
  String? pendingCity;
  String? pendingRole;
  String? pendingPhone; // kept for demo mode (no phone in JWT)

  bool get isLoggedIn => accessToken != null && profile != null;
  bool get isOwner => profile?['role'] == 'owner';
  bool get hasPendingProfile => pendingName != null;

  Future<void> loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    accessToken = prefs.getString('access_token');
    refreshToken = prefs.getString('refresh_token');
    final profileStr = prefs.getString('user_profile');
    if (profileStr != null) {
      profile = jsonDecode(profileStr);
    }
  }

  Future<void> _saveToStorage() async {
    final prefs = await SharedPreferences.getInstance();
    if (accessToken != null) await prefs.setString('access_token', accessToken!);
    if (refreshToken != null) await prefs.setString('refresh_token', refreshToken!);
    if (profile != null) await prefs.setString('user_profile', jsonEncode(profile));
  }

  Future<void> logout() async {
    accessToken = null;
    refreshToken = null;
    profile = null;
    pendingName = null;
    pendingState = null;
    pendingCity = null;
    pendingRole = null;
    pendingPhone = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  Future<void> sendOtp(String phone) async {
    final e164 = '+91$phone';
    pendingPhone = e164;
    await ApiClient.instance.post('/auth/send-otp', body: {'phone': e164});
  }

  /// Returns true if profile is already complete, false if profile_required
  Future<bool> verifyOtp(String phone, String otp) async {
    final e164 = '+91$phone';
    pendingPhone = e164;
    final res = await ApiClient.instance.post('/auth/verify-otp', body: {
      'phone': e164,
      'token': otp,
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

  Future<void> completeProfile(String name, String state, String city, String role) async {
    final res = await ApiClient.instance.post('/auth/complete-profile', body: {
      'name': name,
      'state': state,
      'city': city,
      'role': role,
      if (pendingPhone != null) 'phone': pendingPhone!,
    });
    profile = Map<String, dynamic>.from(res);
    pendingName = null;
    pendingState = null;
    pendingCity = null;
    pendingRole = null;
    pendingPhone = null;
    await _saveToStorage();
  }

  Future<void> refreshProfile() async {
    final res = await ApiClient.instance.get('/auth/me');
    profile = Map<String, dynamic>.from(res);
    await _saveToStorage();
  }
}
