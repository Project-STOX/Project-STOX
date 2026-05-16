import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';

class ApiConfig {
  static String _currentBaseUrl = 'http://localhost:8000/api/v1';

  static String get baseUrl => _currentBaseUrl;

  /// Initializes the base URL based on the current platform and device type.
  /// This should be called in main() before runApp().
  static Future<void> initialize() async {
    // 1. Priority: Explicit environment variable for the full URL
    const fromEnv = String.fromEnvironment('API_BASE_URL');
    if (fromEnv.isNotEmpty) {
      _currentBaseUrl = fromEnv;
      return;
    }

    // 2. Web Platforms
    if (kIsWeb) {
      final host = Uri.base.host;
      if (host.isNotEmpty && host != 'localhost' && host != '127.0.0.1') {
        _currentBaseUrl = 'http://$host:8000/api/v1';
      } else {
        _currentBaseUrl = 'http://127.0.0.1:8000/api/v1';
      }
      return;
    }

    // 3. Native Platforms (Android, iOS, Windows, macOS, Linux)
    try {
      if (Platform.isAndroid) {
        final deviceInfo = DeviceInfoPlugin();
        final androidInfo = await deviceInfo.androidInfo;
        
        // Use 10.0.2.2 for Android Emulator, and localhost for Physical Devices (with adb reverse).
        // This allows BOTH to work automatically without manual configuration.
        if (androidInfo.isPhysicalDevice) {
          _currentBaseUrl = 'http://localhost:8000/api/v1';
        } else {
          _currentBaseUrl = 'http://10.0.2.2:8000/api/v1';
        }
      } else {
        // iOS Simulators and Desktop platforms (Windows/macOS/Linux) correctly use 'localhost'
        _currentBaseUrl = 'http://localhost:8000/api/v1';
      }
    } catch (_) {
      // Fallback if platform detection fails
      _currentBaseUrl = 'http://localhost:8000/api/v1';
    }
  }
}
