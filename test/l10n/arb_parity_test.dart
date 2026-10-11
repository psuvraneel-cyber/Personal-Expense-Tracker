import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every English string has a Hindi translation with the same placeholders.
void main() {
  Map<String, dynamic> load(String locale) =>
      jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
          as Map<String, dynamic>;

  Set<String> keys(Map<String, dynamic> arb) =>
      arb.keys.where((k) => !k.startsWith('@')).toSet();

  Set<String> placeholders(String text) =>
      RegExp(r'\{(\w+)\}').allMatches(text).map((m) => m.group(1)!).toSet();

  test('Hindi has exactly the English keys', () {
    final en = load('en'), hi = load('hi');
    expect(keys(hi), keys(en));
  });

  test('placeholders match in every translation', () {
    final en = load('en'), hi = load('hi');
    for (final key in keys(en)) {
      expect(placeholders(hi[key] as String), placeholders(en[key] as String),
          reason: key);
    }
  });

  test('no Hindi string is left in English by mistake', () {
    final en = load('en'), hi = load('hi');
    const sameOnPurpose = {'@@locale', 'languageEnglish', 'languageHindi'};
    for (final key in keys(en).difference(sameOnPurpose)) {
      expect(hi[key], isNot(en[key]), reason: key);
    }
  });
}
