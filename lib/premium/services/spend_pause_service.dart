import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pet/premium/models/spend_pause.dart';

class SpendPauseService {
  SpendPauseService._();

  static const String _kBasePauseEnabled = 'spend_pause_enabled';
  static const String _kBasePauseUntil = 'spend_pause_until';
  static const String _kBasePauseCategoryIds = 'spend_pause_category_ids';
  static const String _kLegacyPauseCategories = 'pet_spend_pause_categories';
  static const String _kLegacyPauseEnabled = 'pet_spend_pause_enabled';
  static const String _kLegacyPauseUntil = 'pet_spend_pause_until';

  static String _scopedKey(String baseKey, String? userId) {
    if (userId == null || userId.isEmpty || userId == 'guest_user') {
      return 'spend_pause:guest:$baseKey';
    }
    return 'spend_pause:$userId:$baseKey';
  }

  /// Retrieves the current SpendPause state for [userId].
  ///
  /// If [userId] is null or empty, no authenticated user pause is active,
  /// returning an inactive [SpendPause] to guarantee account boundary isolation.
  static Future<SpendPause> getState({
    String? userId,
    SharedPreferences? prefsInstance,
  }) async {
    final prefs = prefsInstance ?? await SharedPreferences.getInstance();
    final enabledKey = _scopedKey(_kBasePauseEnabled, userId);
    final untilKey = _scopedKey(_kBasePauseUntil, userId);
    final categoryIdsKey = _scopedKey(_kBasePauseCategoryIds, userId);

    // Read scoped keys, with one-time legacy fallback for the current user
    bool? enabled = prefs.getBool(enabledKey);
    String? untilRaw = prefs.getString(untilKey);
    String? idsRaw = prefs.getString(categoryIdsKey);

    if (enabled == null && prefs.containsKey(_kLegacyPauseEnabled)) {
      enabled = prefs.getBool(_kLegacyPauseEnabled);
      untilRaw = prefs.getString(_kLegacyPauseUntil);
      idsRaw = prefs.getString('pet_spend_pause_category_ids') ??
          prefs.getString(_kLegacyPauseCategories);
    }

    final isEnabled = enabled ?? false;
    final until = untilRaw != null ? DateTime.tryParse(untilRaw) : null;

    List<String> categoryIds = [];
    if (idsRaw != null) {
      try {
        categoryIds = List<String>.from(jsonDecode(idsRaw) as List);
      } catch (_) {}
    }

    final pause = SpendPause(
      enabled: isEnabled,
      until: until,
      blockedCategoryIds: categoryIds,
    );

    // Auto-expire: if the pause time has passed, clear it and return disabled.
    if (isEnabled && until != null && DateTime.now().isAfter(until)) {
      await setState(SpendPause(enabled: false),
          userId: userId, prefsInstance: prefs);
      return SpendPause(enabled: false);
    }

    return pause;
  }

  /// Persists the SpendPause state scoped to [userId].
  static Future<void> setState(
    SpendPause pause, {
    String? userId,
    SharedPreferences? prefsInstance,
  }) async {
    final prefs = prefsInstance ?? await SharedPreferences.getInstance();
    final enabledKey = _scopedKey(_kBasePauseEnabled, userId);
    final untilKey = _scopedKey(_kBasePauseUntil, userId);
    final categoryIdsKey = _scopedKey(_kBasePauseCategoryIds, userId);

    await prefs.setBool(enabledKey, pause.enabled);

    if (pause.until != null) {
      await prefs.setString(untilKey, pause.until!.toIso8601String());
    } else {
      await prefs.remove(untilKey);
    }

    if (pause.blockedCategoryIds.isNotEmpty) {
      await prefs.setString(
        categoryIdsKey,
        jsonEncode(pause.blockedCategoryIds),
      );
    } else {
      await prefs.remove(categoryIdsKey);
    }
  }

  /// Wipe Focus Mode persisted state for [userId] (or guest/legacy state if null).
  static Future<void> clear({
    String? userId,
    SharedPreferences? prefsInstance,
  }) async {
    final prefs = prefsInstance ?? await SharedPreferences.getInstance();
    final enabledKey = _scopedKey(_kBasePauseEnabled, userId);
    final untilKey = _scopedKey(_kBasePauseUntil, userId);
    final categoryIdsKey = _scopedKey(_kBasePauseCategoryIds, userId);

    await prefs.remove(enabledKey);
    await prefs.remove(untilKey);
    await prefs.remove(categoryIdsKey);

    // Also clean up any legacy unscoped keys
    await prefs.remove(_kLegacyPauseEnabled);
    await prefs.remove(_kLegacyPauseUntil);
    await prefs.remove('pet_spend_pause_category_ids');
    await prefs.remove(_kLegacyPauseCategories);
  }
}
