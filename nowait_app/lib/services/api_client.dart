import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../config/app_config.dart';
import 'auth_service.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);
  @override
  String toString() => message;
}

class ApiClient {
  static final ApiClient instance = ApiClient._();
  ApiClient._();

  bool _isRefreshing = false;

  Map<String, String> get _headers {
    final token = AuthService.instance.accessToken;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final uri = Uri.parse('${AppConfig.baseUrl}$path');
    if (query == null) return uri;
    final filtered = Map<String, String>.from(
      query.map((k, v) => MapEntry(k, v.toString())),
    )..removeWhere((_, v) => v == 'null');
    return uri.replace(queryParameters: filtered.isEmpty ? null : filtered);
  }

  static const _timeout = Duration(seconds: 30);

  /// Attempts a token refresh via direct HTTP (no ApiClient recursion).
  /// Returns true if tokens were updated, false if refresh failed (clears session).
  Future<bool> _tryRefresh() async {
    if (_isRefreshing) return false;
    final refreshTok = AuthService.instance.refreshToken;
    if (refreshTok == null) {
      await AuthService.instance.logout();
      return false;
    }
    _isRefreshing = true;
    try {
      final res = await http.post(
        _uri('/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': refreshTok}),
      ).timeout(_timeout);
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        AuthService.instance.accessToken = data['access_token'] as String?;
        if (data['refresh_token'] != null) {
          AuthService.instance.refreshToken = data['refresh_token'] as String?;
        }
        return true;
      }
    } catch (_) {}
    await AuthService.instance.logout();
    return false;
  }

  /// Executes [makeRequest], retries once after token refresh on 401.
  Future<dynamic> _executeWithRetry(Future<http.Response> Function() makeRequest) async {
    var res = await makeRequest().timeout(_timeout);
    if (res.statusCode == 401) {
      final refreshed = await _tryRefresh();
      _isRefreshing = false;
      if (refreshed) {
        res = await makeRequest().timeout(_timeout);
      }
    }
    return _handle(res);
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    return _executeWithRetry(() => http.get(_uri(path, query), headers: _headers));
  }

  Future<dynamic> post(String path, {Map<String, dynamic>? body, Map<String, dynamic>? query}) async {
    return _executeWithRetry(() => http.post(
      _uri(path, query),
      headers: _headers,
      body: jsonEncode(body ?? {}),
    ));
  }

  Future<dynamic> put(String path, {Map<String, dynamic>? body}) async {
    return _executeWithRetry(() => http.put(
      _uri(path),
      headers: _headers,
      body: jsonEncode(body ?? {}),
    ));
  }

  Future<dynamic> patch(String path, {Map<String, dynamic>? body}) async {
    return _executeWithRetry(() => http.patch(
      _uri(path),
      headers: _headers,
      body: jsonEncode(body ?? {}),
    ));
  }

  Future<dynamic> delete(String path, {Map<String, dynamic>? body}) async {
    if (body != null) {
      return _executeWithRetry(() => http.delete(
        _uri(path),
        headers: _headers,
        body: jsonEncode(body),
      ));
    }
    return _executeWithRetry(() => http.delete(_uri(path), headers: _headers));
  }

  Future<dynamic> multipartPost(
    String path, {
    required List<int> fileBytes,
    required String filename,
    required String mimeType,
    String fieldName = 'file',
  }) async {
    final token = AuthService.instance.accessToken;
    final request = http.MultipartRequest('POST', _uri(path));
    if (token != null) request.headers['Authorization'] = 'Bearer $token';

    final parts = mimeType.split('/');
    request.files.add(http.MultipartFile.fromBytes(
      fieldName,
      fileBytes,
      filename: filename,
      contentType: MediaType(parts[0], parts.length > 1 ? parts[1] : 'octet-stream'),
    ));

    final streamed = await request.send().timeout(_timeout);
    final res = await http.Response.fromStream(streamed);
    return _handle(res);
  }

  dynamic _handle(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (res.body.isEmpty) return null;
      return jsonDecode(utf8.decode(res.bodyBytes));
    }
    String message = 'Request failed';
    try {
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      message = body['detail'] ?? message;
    } catch (_) {}
    throw ApiException(res.statusCode, message);
  }
}
