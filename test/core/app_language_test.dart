import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:pet/core/l10n/app_language.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  tearDown(() {
    AppLanguage.current.value = const Locale('en');
  });

  test('language choice applies and persists across reload', () async {
    SharedPreferences.setMockInitialValues({});

    await AppLanguage.set('hi');
    expect(AppLanguage.current.value, const Locale('hi'));

    AppLanguage.current.value = const Locale('en');
    await AppLanguage.load();
    expect(AppLanguage.current.value, const Locale('hi'));

    await AppLanguage.set('en');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kAppLanguagePrefKey), 'en');
  });
}
