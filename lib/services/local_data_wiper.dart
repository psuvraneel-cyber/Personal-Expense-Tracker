import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pet/core/utils/app_logger.dart';
import 'package:pet/data/database/database_helper.dart';
import 'package:pet/premium/services/notification_service.dart';
import 'package:pet/services/native_sms_reader.dart';
import 'package:pet/services/secure_storage_service.dart';
import 'package:pet/services/sms_background_service.dart';
import 'package:pet/services/sms_service.dart';

/// The single place that removes a user's data from this device.
///
/// Used by sign-out, account deletion and the post-deletion startup cleanup
/// so all three always remove exactly the same things:
///  - every SQLite table (see [DatabaseHelper.wipeAllUserData])
///  - SMS listeners and background workers
///  - scheduled / shown notifications
///  - the native encrypted notification cache
///  - cached profile values in secure storage
///  - user-specific SharedPreferences (device settings are kept)
class LocalDataWiper {
  LocalDataWiper._();

  /// Device-level preferences that are not personal data and survive a wipe.
  static const Set<String> deviceSettingKeys = {
    'themeMode',
    'hapticEnabled',
    'biometricEnabled',
    'biometricTimeout',
    'onboardingCompleted',
    'crashReportsEnabled',
  };

  static Future<void> wipe({DatabaseHelper? dbHelper}) async {
    Future<void> step(String name, Future<void> Function() action) async {
      try {
        await action();
      } catch (e) {
        AppLogger.error('Local wipe step "$name" failed',
            error: e, label: 'Wipe');
      }
    }

    await step('stop SMS listener', () async => SmsService().stopListening());
    if (!kIsWeb) {
      await step('cancel workers', cancelSmsBackgroundService);
    }
    await step(
        'cancel notifications', NotificationService.cancelAllNotifications);
    await step('clear native cache',
        () => NativeSmsReader().clearPendingNotifications());
    if (!kIsWeb) {
      await step('wipe database',
          () => (dbHelper ?? DatabaseHelper()).wipeAllUserData());
    }
    await step('clear secure profile', () async {
      await SecureStorageService.instance.delete('userName');
      await SecureStorageService.instance.delete('userEmail');
    });
    await step('clear preferences', clearUserPreferences);
  }

  /// Clears all SharedPreferences except [deviceSettingKeys].
  static Future<void> clearUserPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final keep = <String, Object>{};
    for (final key in deviceSettingKeys) {
      final value = prefs.get(key);
      if (value != null) keep[key] = value;
    }
    await prefs.clear();
    for (final entry in keep.entries) {
      final v = entry.value;
      if (v is bool) await prefs.setBool(entry.key, v);
      if (v is int) await prefs.setInt(entry.key, v);
      if (v is double) await prefs.setDouble(entry.key, v);
      if (v is String) await prefs.setString(entry.key, v);
      if (v is List<String>) await prefs.setStringList(entry.key, v);
    }
  }
}
