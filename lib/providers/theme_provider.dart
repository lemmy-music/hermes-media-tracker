import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kThemeModeKey = 'theme_mode';

/// Manages the persisted theme preference (light / dark / system).
///
/// Resolution order:
///   1. Saved SharedPreferences value (if any)
///   2. System platform brightness (on first launch)
class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;

  /// Whether the *resolved* appearance (given the platform brightness) is dark.
  bool effectivelyDark(Brightness platformBrightness) {
    if (_themeMode == ThemeMode.system) {
      return platformBrightness == Brightness.dark;
    }
    return _themeMode == ThemeMode.dark;
  }

  /// Load the persisted preference. Call once at startup.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    switch (prefs.getString(_kThemeModeKey)) {
      case 'dark':
        _themeMode = ThemeMode.dark;
        break;
      case 'light':
        _themeMode = ThemeMode.light;
        break;
      default:
        _themeMode = ThemeMode.system;
    }
    notifyListeners();
  }

  /// Set and persist the theme mode.
  Future<void> setDark(bool dark) async {
    _themeMode = dark ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeModeKey, dark ? 'dark' : 'light');
  }
}
