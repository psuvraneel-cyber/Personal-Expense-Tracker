import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences key for the chosen app language ('en' or 'hi').
const String kAppLanguagePrefKey = 'appLanguage';

/// The app's display language.
///
/// Hindi is a beta: it's used only when chosen in Settings (never picked
/// automatically from the device language) because some screens are still
/// in English.
class AppLanguage {
  AppLanguage._();

  static const supportedCodes = ['en', 'hi'];

  static final ValueNotifier<Locale> current =
      ValueNotifier<Locale>(const Locale('en'));

  static Locale localeFor(String? code) =>
      code == 'hi' ? const Locale('hi') : const Locale('en');

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      current.value = localeFor(prefs.getString(kAppLanguagePrefKey));
    } catch (_) {}
  }

  static Future<void> set(String code) async {
    final locale = localeFor(code);
    // Persist before notifying MaterialApp so a locale rebuild cannot race
    // with the preference write. A preferences failure must not surface as a
    // Flutter error screen; the in-memory choice still applies for this run.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kAppLanguagePrefKey, locale.languageCode);
    } catch (_) {}
    if (current.value != locale) current.value = locale;
  }
}
