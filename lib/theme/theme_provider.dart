import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.light;
  SharedPreferences? _prefs;
  bool _userChanged = false;

  ThemeMode get themeMode => _themeMode;

  bool get isDarkMode => _themeMode == ThemeMode.dark;

  ThemeProvider() {
    _loadThemePreference();
  }

  Future<void> _loadThemePreference() async {
    _prefs = await SharedPreferences.getInstance();
    final isDark = _prefs?.getBool('isDarkMode') ?? false;
    if (!_userChanged) _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    _userChanged = true;
    _themeMode =
        _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setBool('isDarkMode', _themeMode == ThemeMode.dark);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _userChanged = true;
    _themeMode = mode;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setBool('isDarkMode', mode == ThemeMode.dark);
    notifyListeners();
  }
}
