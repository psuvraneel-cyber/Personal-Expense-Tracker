import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pet/premium/models/notification_category.dart';

/// SharedPreferences-backed service for managing notification category preferences.
/// Integrates with Flutter UI via [ChangeNotifier] and provides static async access for background isolates.
class NotificationPreferencesService extends ChangeNotifier {
  NotificationPreferencesService._();
  static final NotificationPreferencesService instance =
      NotificationPreferencesService._();

  static const String _prefix = 'notif_pref_';
  static const String _keyReminderHour = 'notif_daily_reminder_hour';
  static const String _keyLastReminderDate = 'notif_daily_reminder_last_date';
  static const String _keyBannerDismissed = 'notif_banner_dismissed';

  final Map<NotificationCategory, bool> _preferences = {
    for (final category in NotificationCategory.values) category: true,
  };

  int _reminderHour = 20;
  int get reminderHour => _reminderHour;

  bool _isBannerDismissed = false;
  bool get isBannerDismissed => _isBannerDismissed;

  bool _isLoaded = false;
  bool get isLoaded => _isLoaded;

  /// Loads category preferences, reminder config, and banner dismissal from SharedPreferences.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    for (final category in NotificationCategory.values) {
      final value = prefs.getBool('$_prefix${category.key}');
      _preferences[category] = value ?? true;
    }
    _reminderHour = prefs.getInt(_keyReminderHour) ?? 20;
    _isBannerDismissed = prefs.getBool(_keyBannerDismissed) ?? false;
    _isLoaded = true;
    notifyListeners();
  }

  /// Sets whether the dashboard permission rationale banner was dismissed.
  Future<void> setBannerDismissed(bool dismissed) async {
    _isBannerDismissed = dismissed;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyBannerDismissed, dismissed);
  }

  /// Returns whether a category is enabled from synchronous in-memory cache.
  bool isEnabled(NotificationCategory category) {
    return _preferences[category] ?? true;
  }

  /// Returns whether a category is enabled directly from SharedPreferences.
  /// Safe for background WorkManager isolates.
  static Future<bool> isCategoryEnabled(NotificationCategory category) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_prefix${category.key}') ?? true;
  }

  /// Updates preference for a category and persists to SharedPreferences.
  Future<void> setCategoryEnabled(
    NotificationCategory category,
    bool enabled,
  ) async {
    _preferences[category] = enabled;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_prefix${category.key}', enabled);
  }

  /// Gets the configured daily reminder hour (default 20 / 8 PM).
  static Future<int> getReminderHour() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyReminderHour) ?? 20;
  }

  /// Sets the daily reminder hour (0-23) and persists to SharedPreferences.
  Future<void> setReminderHour(int hour) async {
    _reminderHour = hour;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyReminderHour, hour);
  }

  /// Gets the watermark date ('YYYY-MM-DD') when the daily reminder last fired.
  static Future<String?> getLastDailyReminderDate() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLastReminderDate);
  }

  /// Updates the watermark date ('YYYY-MM-DD') when the daily reminder fires.
  static Future<void> setLastDailyReminderDate(String dateIso) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastReminderDate, dateIso);
  }
}
