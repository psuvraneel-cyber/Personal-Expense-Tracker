import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pet/premium/models/spend_pause.dart';

class SpendPauseService {
  SpendPauseService._();

  static const String _kPauseEnabled = 'pet_spend_pause_enabled';
  static const String _kPauseUntil = 'pet_spend_pause_until';
  static const String _kPauseCategoryIds = 'pet_spend_pause_category_ids';
  static const String _kLegacyPauseCategories = 'pet_spend_pause_categories';

  static Future<SpendPause> getState({SharedPreferences? prefsInstance}) async {
    final prefs = prefsInstance ?? await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_kPauseEnabled) ?? false;
    final untilRaw = prefs.getString(_kPauseUntil);
    final until = untilRaw != null ? DateTime.tryParse(untilRaw) : null;

    List<String> categoryIds = [];
    final idsRaw = prefs.getString(_kPauseCategoryIds);
    if (idsRaw != null) {
      try {
        categoryIds = List<String>.from(jsonDecode(idsRaw) as List);
      } catch (_) {}
    } else {
      // Legacy fallback
      final legacyRaw = prefs.getString(_kLegacyPauseCategories);
      if (legacyRaw != null) {
        try {
          categoryIds = List<String>.from(jsonDecode(legacyRaw) as List);
        } catch (_) {}
      }
    }

    final pause = SpendPause(
      enabled: enabled,
      until: until,
      blockedCategoryIds: categoryIds,
    );

    // Auto-expire: if the pause time has passed, clear it and return disabled.
    if (enabled && until != null && DateTime.now().isAfter(until)) {
      await setState(SpendPause(enabled: false), prefsInstance: prefs);
      return SpendPause(enabled: false);
    }

    return pause;
  }

  static Future<void> setState(
    SpendPause pause, {
    SharedPreferences? prefsInstance,
  }) async {
    final prefs = prefsInstance ?? await SharedPreferences.getInstance();
    await prefs.setBool(_kPauseEnabled, pause.enabled);

    if (pause.until != null) {
      await prefs.setString(_kPauseUntil, pause.until!.toIso8601String());
    } else {
      await prefs.remove(_kPauseUntil);
    }

    if (pause.blockedCategoryIds.isNotEmpty) {
      await prefs.setString(
        _kPauseCategoryIds,
        jsonEncode(pause.blockedCategoryIds),
      );
    } else {
      await prefs.remove(_kPauseCategoryIds);
      await prefs.remove(_kLegacyPauseCategories);
    }
  }

  /// Wipe all Focus Mode persisted state during account sign-out.
  static Future<void> clear({SharedPreferences? prefsInstance}) async {
    final prefs = prefsInstance ?? await SharedPreferences.getInstance();
    await prefs.remove(_kPauseEnabled);
    await prefs.remove(_kPauseUntil);
    await prefs.remove(_kPauseCategoryIds);
    await prefs.remove(_kLegacyPauseCategories);
  }
}
