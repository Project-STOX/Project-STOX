import 'dart:io';
import 'package:flutter/foundation.dart';

class ApiConfig {
  static String get baseUrl => _getLocalUrl();

  static String _getLocalUrl() {
    const fromEnv = String.fromEnvironment('API_BASE_URL');
    if (fromEnv.isNotEmpty) return fromEnv;

    if (kIsWeb) {
      // Use the same host as the page (allows LAN testing with friend's PC)
      final host = Uri.base.host;
      if (host.isNotEmpty) {
        return 'http://$host:8000/api/v1';
      }
      return 'http://localhost:8000/api/v1';
    }

    try {
      if (Platform.isAndroid) return 'http://10.0.2.2:8000/api/v1';
      if (Platform.isIOS) return 'http://localhost:8000/api/v1';
    } catch (_) {}

    return 'http://localhost:8000/api/v1';
  }
}
