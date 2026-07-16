import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages app locale (English / Traditional Chinese).
class LocaleService extends ChangeNotifier {
  static const String _prefsKey = 'app_language';
  static const String langEn = 'en';
  static const String langZh = 'zh';

  String _currentLang = langEn;

  String get currentLang => _currentLang;
  bool get isZh => _currentLang == langZh;

  LocaleService() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _currentLang = prefs.getString(_prefsKey) ?? langEn;
    notifyListeners();
  }

  Future<void> setLanguage(String lang) async {
    if (lang == _currentLang) return;
    _currentLang = lang;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, lang);
    notifyListeners();
  }

  Future<void> toggle() async {
    await setLanguage(isZh ? langEn : langZh);
  }

  Locale get locale => Locale(_currentLang);
}
