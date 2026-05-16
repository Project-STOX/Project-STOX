import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppNavigationMode { sidebar, header }

class ThemeController with ChangeNotifier {
  static const String _themeModeKey = 'theme_mode';
  static const String _primaryColorKey = 'primary_color';
  static const String _navigationModeKey = 'app_navigation_mode';

  ThemeMode _themeMode = ThemeMode.light;
  Color _primaryColor = Colors.blue;
  AppNavigationMode _navigationMode = AppNavigationMode.sidebar;
  bool _initialized = false;

  ThemeMode get themeMode => _themeMode;
  Color get primaryColor => _primaryColor;
  AppNavigationMode get navigationMode => _navigationMode;
  bool get initialized => _initialized;

  ThemeController() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Load ThemeMode
    final modeIndex = prefs.getInt(_themeModeKey);
    if (modeIndex != null) {
      _themeMode = ThemeMode.values[modeIndex];
    }

    // Load Primary Color
    final colorValue = prefs.getInt(_primaryColorKey);
    if (colorValue != null) {
      _primaryColor = Color(colorValue);
    }

    // Load Navigation Mode
    final navIndex = prefs.getInt(_navigationModeKey);
    if (navIndex != null) {
      _navigationMode = AppNavigationMode.values[navIndex];
    }

    _initialized = true;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeModeKey, mode.index);
  }

  Future<void> setPrimaryColor(Color color) async {
    _primaryColor = color;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_primaryColorKey, color.value);
  }

  Future<void> setNavigationMode(AppNavigationMode mode) async {
    _navigationMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_navigationModeKey, mode.index);
  }

  ThemeData getLightTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorSchemeSeed: _primaryColor,
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
      ),
    );
  }

  ThemeData getDarkTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorSchemeSeed: _primaryColor,
      scaffoldBackgroundColor: const Color(0xFF0F1117),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF1A1D2E),
        centerTitle: false,
        elevation: 0,
      ),
    );
  }
}
