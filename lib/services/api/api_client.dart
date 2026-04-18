import 'dart:convert';

import 'package:http/http.dart' as http;

import 'token_storage.dart';

class ApiClient {
  ApiClient({
    required this.baseUrl,
    TokenStorage? tokenStorage,
    http.Client? httpClient,
  })  : _tokenStorage = tokenStorage ?? TokenStorage(),
        _http = httpClient ?? http.Client();

  final String baseUrl;
  final TokenStorage _tokenStorage;
  final http.Client _http;
  final Duration _timeout = const Duration(seconds: 25);

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final normalizedBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$normalizedBase$normalizedPath').replace(queryParameters: query);
  }

  Future<Map<String, String>> _headers({bool authorized = false}) async {
    final headers = {'Content-Type': 'application/json'};
    if (authorized) {
      final token = await _tokenStorage.getAccessToken();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }
    return headers;
  }

  Future<dynamic> post(
    String path, {
    Map<String, dynamic>? body,
    bool authorized = false,
  }) async {
    final response = await _http.post(
      _uri(path),
      headers: await _headers(authorized: authorized),
      body: jsonEncode(body ?? {}),
    ).timeout(_timeout);
    return _handleResponse(
      response,
      () => post(path, body: body, authorized: authorized),
      authorized: authorized,
    );
  }

  /// New method to handle binary responses (like ZIP files) while keeping 401 refresh logic.
  Future<dynamic> postBinary(
    String path, {
    Map<String, dynamic>? body,
    bool authorized = false,
  }) async {
    final response = await _http.post(
      _uri(path),
      headers: await _headers(authorized: authorized),
      body: jsonEncode(body ?? {}),
    ).timeout(_timeout);
    return _handleResponse(
      response,
      () => postBinary(path, body: body, authorized: authorized),
      authorized: authorized,
      isBinary: true,
    );
  }

  Future<dynamic> put(
    String path, {
    Map<String, dynamic>? body,
    bool authorized = false,
  }) async {
    final response = await _http.put(
      _uri(path),
      headers: await _headers(authorized: authorized),
      body: jsonEncode(body ?? {}),
    ).timeout(_timeout);
    return _handleResponse(
      response,
      () => put(path, body: body, authorized: authorized),
      authorized: authorized,
    );
  }

  Future<dynamic> patch(
    String path, {
    Map<String, dynamic>? body,
    bool authorized = false,
  }) async {
    final response = await _http.patch(
      _uri(path),
      headers: await _headers(authorized: authorized),
      body: jsonEncode(body ?? {}),
    ).timeout(_timeout);
    return _handleResponse(
      response,
      () => patch(path, body: body, authorized: authorized),
      authorized: authorized,
    );
  }

  Future<dynamic> delete(
    String path, {
    bool authorized = false,
  }) async {
    final response = await _http.delete(
      _uri(path),
      headers: await _headers(authorized: authorized),
    ).timeout(_timeout);
    return _handleResponse(
      response,
      () => delete(path, authorized: authorized),
      authorized: authorized,
    );
  }

  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? query,
    bool authorized = false,
  }) async {
    final response = await _http.get(
      _uri(path, query),
      headers: await _headers(authorized: authorized),
    ).timeout(_timeout);
    return _handleResponse(
      response,
      () => get(path, query: query, authorized: authorized),
      authorized: authorized,
    );
  }

  bool _isRefreshing = false;

  Future<dynamic> _handleResponse(
    http.Response response,
    Future<dynamic> Function() retry, {
    bool authorized = false,
    bool isBinary = false,
  }) async {
    if (response.statusCode == 401 && authorized && !_isRefreshing) {
      _isRefreshing = true;
      try {
        final success = await _refreshToken();
        if (success) {
          return await retry();
        }
      } finally {
        _isRefreshing = false;
      }
    }
    return _decode(response, isBinary: isBinary);
  }

  Future<bool> _refreshToken() async {
    final refreshToken = await _tokenStorage.getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) return false;

    try {
      final response = await _http.post(
        _uri('/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': refreshToken}),
      ).timeout(_timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final newAccessToken = data['access_token']?.toString();
        final newRefreshToken = data['refresh_token']?.toString();

        if (newAccessToken != null && newRefreshToken != null) {
          await _tokenStorage.saveTokens(
            accessToken: newAccessToken,
            refreshToken: newRefreshToken,
          );
          return true;
        }
      }
    } catch (_) {
      // Refresh failed
    }
    return false;
  }

  dynamic _decode(http.Response response, {bool isBinary = false}) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (isBinary) return response.bodyBytes;
      if (response.body.isEmpty) return {};
      try {
        return jsonDecode(response.body);
      } catch (_) {
        return response.body;
      }
    }
    final message = response.body.isEmpty ? 'Request failed' : response.body;
    throw Exception('HTTP ${response.statusCode}: $message');
  }
}
