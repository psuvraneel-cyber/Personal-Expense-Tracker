import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:pet/core/utils/app_logger.dart';
import 'package:pet/firebase_options.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// SharedPreferences key for the "Share crash reports" setting.
const String kCrashReportsPrefKey = 'crashReportsEnabled';

/// Initialisation shared by the UI isolate and every background isolate
/// (WorkManager tasks, notification-action handler). Each isolate has its own
/// memory, so these must run in each one.
class AppBootstrap {
  AppBootstrap._();

  static bool _timeZonesReady = false;

  /// Loads the time-zone database and sets `tz.local` to the device's real
  /// zone (the package defaults to UTC), so scheduled reminders fire at the
  /// intended local time.
  static Future<void> initTimeZones() async {
    if (_timeZonesReady) return;
    tz.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (e) {
      // Fall back to India Standard Time — the app's primary market.
      try {
        tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
      } catch (_) {}
      AppLogger.debug('[Bootstrap] Local time zone lookup failed: $e');
    }
    _timeZonesReady = true;
  }

  /// Activates Firebase App Check so Firestore and the AI Worker can verify
  /// requests come from the genuine app (Play Integrity). Debug builds use
  /// the debug provider — register the debug token printed in logcat in the
  /// Firebase console to test against enforced back ends.
  static Future<void> activateAppCheck() async {
    try {
      await FirebaseAppCheck.instance.activate(
        providerAndroid: kDebugMode
            ? const AndroidDebugProvider()
            : const AndroidPlayIntegrityProvider(),
      );
    } catch (e) {
      AppLogger.debug('[Bootstrap] App Check activation failed: $e');
    }
  }

  /// Current App Check token, or null if unavailable.
  static Future<String?> appCheckToken() async {
    try {
      return await FirebaseAppCheck.instance.getToken();
    } catch (_) {
      return null;
    }
  }

  /// Initialises Firebase once per isolate. Returns `false` if it fails.
  static Future<bool> initFirebase() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      return true;
    } catch (e) {
      AppLogger.debug('[Bootstrap] Firebase init failed: $e');
      return false;
    }
  }
}
