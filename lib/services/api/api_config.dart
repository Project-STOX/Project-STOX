import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class ApiConfig {
  static const String cloudUrl = 'https://project-stox.onrender.com/api/v1';
  static final ValueNotifier<bool> isUsingCloud = ValueNotifier(false);
  static final ValueNotifier<bool> isConnecting = ValueNotifier(false);

  static String _activeUrl = _getLocalUrl();

  static String get baseUrl => _activeUrl;

  static String _getLocalUrl() {
    const fromEnv = String.fromEnvironment('API_BASE_URL');
    if (fromEnv.isNotEmpty) return fromEnv;

    if (kIsWeb) return 'http://localhost:8000/api/v1';

    try {
      if (Platform.isAndroid) return 'http://10.0.2.2:8000/api/v1';
      if (Platform.isIOS) return 'http://localhost:8000/api/v1';
    } catch (_) {}

    return 'http://localhost:8000/api/v1';
  }

  /// Pings the cloud server. If it responds within [timeout], we use Cloud mode.
  /// Otherwise, we stick to Local Failover.
  static Future<void> checkHealth({Duration timeout = const Duration(seconds: 3)}) async {
    isConnecting.value = true;
    final cloudHealthUrl = cloudUrl.replaceAll('/api/v1', '/health');

    try {
      final response = await http.get(Uri.parse(cloudHealthUrl)).timeout(timeout);
      if (response.statusCode == 200) {
        _activeUrl = cloudUrl;
        isUsingCloud.value = true;
      } else {
        _activeUrl = _getLocalUrl();
        isUsingCloud.value = false;
      }
    } catch (e) {
      // Timeout or connection error -> use Local
      _activeUrl = _getLocalUrl();
      isUsingCloud.value = false;
    } finally {
      isConnecting.value = false;
    }
  }

  /// Manually switch to Cloud if it becomes available later.
  static Future<bool> trySwitchToCloud() async {
    await checkHealth(timeout: const Duration(seconds: 5));
    return isUsingCloud.value;
  }
}
