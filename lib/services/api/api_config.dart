import 'dart:io';
import 'package:flutter/foundation.dart';

class ApiConfig {
  static String get baseUrl {
    // Check for build-time environment variable
    const fromEnv = String.fromEnvironment('API_BASE_URL');
    if (fromEnv.isNotEmpty) {
      return fromEnv;
    }

    // Default development URLs
    if (kIsWeb) {
      return 'http://localhost:8000/api/v1';
    }

    try {
      if (Platform.isAndroid) {
        // 10.0.2.2 is the special alias for the host's loopback interface in Android emulator
        return 'http://10.0.2.2:8000/api/v1';
      }
      if (Platform.isIOS) {
        // iOS simulator usually works with localhost, but can also use machine IP
        return 'http://localhost:8000/api/v1';
      }
    } catch (_) {
      // Fallback for other platforms or if Platform throws
    }

    return 'http://localhost:8000/api/v1';
  }
}
