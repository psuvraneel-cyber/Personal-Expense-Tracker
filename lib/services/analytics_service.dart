import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pet/core/utils/app_logger.dart';

/// SharedPreferences key for the "Share usage analytics" setting.
const String kAnalyticsPrefKey = 'analyticsEnabled';

/// Set once the user has answered the analytics consent prompt.
const String kAnalyticsConsentAskedKey = 'analyticsConsentAsked';

/// Funnel event names. Parameters are limited to fixed labels and counts —
/// never amounts, merchants, message text or anything the user typed.
class AnalyticsEvents {
  AnalyticsEvents._();

  static const optIn = 'analytics_opt_in';
  static const smsPermissionGranted = 'sms_permission_granted';
  static const notificationAccessGranted = 'notification_access_granted';
  static const firstAutoImport = 'first_auto_import';
  static const retainedDay7 = 'retained_day_7';
  static const paywallView = 'paywall_view';
  static const trialStart = 'trial_start';
  static const subscribe = 'subscribe';
  static const purchaseRestored = 'purchase_restored';
  static const reviewPrompt = 'review_prompt';
  static const aiQuotaExhausted = 'ai_free_quota_exhausted';
}

/// Where analytics events go. Swapped for a fake in tests.
abstract class AnalyticsBackend {
  Future<void> setCollectionEnabled(bool enabled);
  Future<void> logEvent(String name, Map<String, Object>? parameters);
  Future<void> setUserProperty(String name, String? value);
  Future<void> resetData();
  Future<String?> appInstanceId();
}

class FirebaseAnalyticsBackend implements AnalyticsBackend {
  FirebaseAnalytics? get _fa =>
      Firebase.apps.isEmpty ? null : FirebaseAnalytics.instance;

  @override
  Future<void> setCollectionEnabled(bool enabled) async {
    final fa = _fa;
    if (fa == null) return;
    // Ads storage and signals stay denied: the app shows no ads and the
    // manifest removes the advertising-ID permission.
    await fa.setConsent(
      analyticsStorageConsentGranted: enabled,
      adStorageConsentGranted: false,
      adUserDataConsentGranted: false,
      adPersonalizationSignalsConsentGranted: false,
    );
    await fa.setAnalyticsCollectionEnabled(enabled);
  }

  @override
  Future<void> logEvent(String name, Map<String, Object>? parameters) async =>
      _fa?.logEvent(name: name, parameters: parameters);

  @override
  Future<void> setUserProperty(String name, String? value) async =>
      _fa?.setUserProperty(name: name, value: value);

  @override
  Future<void> resetData() async => _fa?.resetAnalyticsData();

  @override
  Future<String?> appInstanceId() async => _fa?.appInstanceId;
}

/// Opt-in product analytics. Nothing is collected until the user agrees,
/// either in the one-time prompt or under Settings → Privacy.
class AnalyticsService {
  AnalyticsService({AnalyticsBackend? backend})
      : _backend = backend ?? FirebaseAnalyticsBackend();

  static AnalyticsService instance = AnalyticsService();

  final AnalyticsBackend _backend;
  bool _enabled = false;

  bool get isEnabled => _enabled;

  @visibleForTesting
  static void resetForTesting(AnalyticsBackend backend) {
    instance = AnalyticsService(backend: backend);
  }

  /// Applies the stored choice. Collection is also disabled in the Android
  /// manifest, so nothing is sent before this runs.
  Future<void> init() async {
    if (kIsWeb) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(kAnalyticsPrefKey) ?? false;
      await _backend.setCollectionEnabled(_enabled);
      await linkRevenueCat();
    } catch (e) {
      AppLogger.debug('[Analytics] init failed: $e');
    }
  }

  /// Whether the consent prompt still needs to be shown.
  static Future<bool> shouldAskForConsent() async {
    if (kIsWeb) return false;
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(kAnalyticsConsentAskedKey) ?? false);
  }

  Future<void> setEnabled(bool enabled) async {
    // Updated before any await so the UI reflects the choice immediately.
    final wasEnabled = _enabled;
    _enabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kAnalyticsPrefKey, enabled);
    await prefs.setBool(kAnalyticsConsentAskedKey, true);
    try {
      await _backend.setCollectionEnabled(enabled);
      if (enabled && !wasEnabled) {
        await _backend.logEvent(AnalyticsEvents.optIn, null);
        await linkRevenueCat();
      }
      // Opting out also deletes the analytics data held on the device.
      if (!enabled) await _backend.resetData();
    } catch (e) {
      AppLogger.debug('[Analytics] setEnabled failed: $e');
    }
  }

  Future<void> logEvent(String name, [Map<String, Object>? parameters]) async {
    if (!_enabled) return;
    try {
      await _backend.logEvent(name, parameters);
    } catch (e) {
      AppLogger.debug('[Analytics] logEvent $name failed: $e');
    }
  }

  Future<void> setUserProperty(String name, String? value) async {
    if (!_enabled) return;
    try {
      await _backend.setUserProperty(name, value);
    } catch (e) {
      AppLogger.debug('[Analytics] setUserProperty $name failed: $e');
    }
  }

  /// Lets RevenueCat's Firebase integration attribute renewals and trial
  /// conversions (which happen server-side) to this app instance. Called
  /// again once RevenueCat is configured.
  Future<void> linkRevenueCat() async {
    if (!_enabled || kIsWeb) return;
    try {
      if (!await Purchases.isConfigured) return;
      final id = await _backend.appInstanceId();
      if (id != null && id.isNotEmpty) {
        await Purchases.setFirebaseAppInstanceId(id);
      }
    } catch (e) {
      // RevenueCat may not be configured (e.g. missing key in debug builds).
      AppLogger.debug('[Analytics] RevenueCat link skipped: $e');
    }
  }
}
