import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the active UI locale (English or Arabic) and persists the choice.
class LocaleProvider extends ChangeNotifier {
  static const _prefsKey = 'appLocale';

  Locale _locale = const Locale('en');
  SharedPreferences? _prefs;

  Locale get locale => _locale;
  bool get isArabic => _locale.languageCode == 'ar';

  LocaleProvider() {
    _load();
  }

  Future<void> _load() async {
    _prefs = await SharedPreferences.getInstance();
    final code = _prefs?.getString(_prefsKey);
    if (code != null && (code == 'ar' || code == 'en')) {
      _locale = Locale(code);
    }
    notifyListeners();
  }

  Future<void> toggle() async {
    _locale = _locale.languageCode == 'ar'
        ? const Locale('en')
        : const Locale('ar');
    await _prefs?.setString(_prefsKey, _locale.languageCode);
    notifyListeners();
  }
}
