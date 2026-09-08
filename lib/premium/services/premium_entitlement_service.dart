import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pet/config/app_env.dart';
import 'package:pet/core/utils/app_logger.dart';

class PremiumEntitlementService {
  PremiumEntitlementService._();

  static const String _kExperimentalEnabled = 'pet_experimental_enabled';
  static const String _kCachedPremium = 'pet_cached_premium';
  static const String _kCachedPremiumUid = 'pet_cached_premium_uid';
  static const String _entitlementId = 'P.E.T Premium';

  // ---------------------------------------------------------------------------
  // Developer Premium Access — DEBUG BUILDS ONLY
  //
  // This in-memory flag allows the developer to access all premium features
  // without a real RevenueCat subscription during development.
  //
  // SECURITY INVARIANT:
  //   Developer premium access is strictly debug-only.
  //   It must never be enabled or honored in release builds.
  //   Release builds must rely exclusively on real RevenueCat entitlements.
  //
  // Protection layers:
  //   1. `kDebugMode` / `kReleaseMode` are compile-time constants —
  //      Dart's tree-shaker removes the debug branch entirely in release.
  //   2. The flag is in-memory only (not stored in SharedPreferences, SQLite,
  //      or any persistent storage) — it cannot be manipulated on a release
  //      device and does not survive app restarts.
  //   3. No developer UID, Dart define, or environment variable is involved.
  // ---------------------------------------------------------------------------

  /// In-memory developer premium override flag.
  /// Defaults to `true` in debug builds so the developer can immediately
  /// access premium features without a subscription.
  static bool _debugPremiumOverride = true;

  /// Whether developer premium access is currently enabled.
  ///
  /// Always returns `false` in release and profile builds.
  /// In debug builds, returns the current value of the in-memory toggle.
  ///
  /// The [isDebugOverride] and [isReleaseOverride] parameters exist solely
  /// for unit testing and must NOT be used in production code.
  static bool isDeveloperPremiumAccessEnabled({
    @visibleForTesting bool? isDebugOverride,
    @visibleForTesting bool? isReleaseOverride,
  }) {
    final release = isReleaseOverride ?? kReleaseMode;
    final debug = isDebugOverride ?? kDebugMode;

    // Compile-time constant check — entire branch tree-shaken in release
    if (release || !debug) return false;

    return _debugPremiumOverride;
  }

  /// Toggle developer premium access (debug builds only).
  ///
  /// No-op in release and profile builds.
  static void setDeveloperPremiumAccess(
    bool enabled, {
    @visibleForTesting bool? isDebugOverride,
    @visibleForTesting bool? isReleaseOverride,
  }) {
    final release = isReleaseOverride ?? kReleaseMode;
    final debug = isDebugOverride ?? kDebugMode;

    if (release || !debug) return;

    _debugPremiumOverride = enabled;
    AppLogger.info(
      'Developer Premium Access ${enabled ? "ENABLED" : "DISABLED"}',
      label: 'PremiumEntitlementService',
    );
  }

  /// Reset the developer override to its default state.
  /// Used internally for test isolation.
  @visibleForTesting
  static void resetDeveloperOverrideForTesting() {
    _debugPremiumOverride = true;
  }

  /// Safe diagnostic string identifying the key type without leaking the key.
  static String getKeyDiagnostic(String apiKey) {
    if (apiKey.isEmpty || apiKey == 'REPLACE_ME') {
      return 'Unconfigured';
    }
    if (apiKey.startsWith('test_')) {
      return 'Test Store';
    }
    if (apiKey.startsWith('goog_')) {
      return 'Android production';
    }
    if (apiKey.startsWith('appl_')) {
      return 'iOS production';
    }
    if (apiKey.startsWith('sk_') || apiKey.startsWith('rc_')) {
      return 'Secret Key (UNSAFE)';
    }
    return 'Custom / Other';
  }

  /// Resolves the appropriate RevenueCat public SDK key based on build mode
  /// and validates security invariants.
  ///
  /// Invariants:
  /// - Debug builds select `REVENUECAT_TEST_STORE_API_KEY` (or fallback).
  /// - Release builds select `REVENUECAT_ANDROID_API_KEY`.
  /// - Test Store keys (`test_*`) are STRICTLY FORBIDDEN in release builds and throw [StateError].
  /// - Secret API keys (`sk_*` / `rc_*`) are STRICTLY FORBIDDEN in client apps and throw [StateError].
  /// - Release builds without a configured production key throw [StateError].
  ///
  /// The [isDebugOverride], [isReleaseOverride], [testStoreKeyOverride], and
  /// [androidKeyOverride] parameters exist solely for unit testing.
  static String resolveApiKey({
    @visibleForTesting bool? isDebugOverride,
    @visibleForTesting bool? isReleaseOverride,
    @visibleForTesting String? testStoreKeyOverride,
    @visibleForTesting String? androidKeyOverride,
  }) {
    final release = isReleaseOverride ?? kReleaseMode;
    final debug = isDebugOverride ?? kDebugMode;

    final testKey = (testStoreKeyOverride ?? AppEnv.revenueCatTestStoreApiKey).trim();
    final androidKey = (androidKeyOverride ?? AppEnv.revenueCatAndroidApiKey).trim();

    // Critical invariant: Secret API keys must NEVER exist in client apps
    if (testKey.startsWith('sk_') ||
        testKey.startsWith('rc_') ||
        androidKey.startsWith('sk_') ||
        androidKey.startsWith('rc_')) {
      throw StateError(
        'CRITICAL SECURITY ERROR: RevenueCat Secret API key detected in client app. '
        'Mobile apps must only use public SDK keys (test_* or goog_*). Never embed secret keys.',
      );
    }

    if (release || !debug) {
      // ── RELEASE BUILD VALIDATION ──────────────────────────────────────────
      if (androidKey.isEmpty || androidKey == 'REPLACE_ME') {
        throw StateError(
          'Release build configuration error: Missing or unconfigured REVENUECAT_ANDROID_API_KEY. '
          'A valid Google Play production public SDK key (goog_*) is required for release builds.',
        );
      }

      if (androidKey.startsWith('test_')) {
        throw StateError(
          'RELEASE BUILD SECURITY ERROR: RevenueCat Test Store key cannot be used in release builds. '
          'Configure REVENUECAT_ANDROID_API_KEY with a valid Google Play production key (goog_*).',
        );
      }

      return androidKey;
    } else {
      // ── DEBUG / DEVELOPMENT BUILD RESOLUTION ──────────────────────────────
      if (testKey.isNotEmpty && testKey != 'REPLACE_ME') {
        if (testKey.startsWith('goog_')) {
          AppLogger.warn(
            'RevenueCat key type: Android production key provided in REVENUECAT_TEST_STORE_API_KEY. '
            'Test Store key (test_*) is recommended for sandbox testing.',
            label: 'PremiumEntitlementService',
          );
        }
        return testKey;
      }

      // Fallback in debug if test store key was not specified but android key was
      if (androidKey.isNotEmpty && androidKey != 'REPLACE_ME') {
        AppLogger.warn(
          'REVENUECAT_TEST_STORE_API_KEY is unset; falling back to REVENUECAT_ANDROID_API_KEY in debug mode.',
          label: 'PremiumEntitlementService',
        );
        return androidKey;
      }

      AppLogger.warn(
        'RevenueCat API key is unconfigured (empty or placeholder). In-app purchases will not work.',
        label: 'PremiumEntitlementService',
      );
      return '';
    }
  }

  static Future<void> init() async {
    // Only enable debug logging in debug builds — never leak purchase info
    // in production device logs.
    await Purchases.setLogLevel(kDebugMode ? LogLevel.debug : LogLevel.warn);

    final apiKey = resolveApiKey();
    final keyType = getKeyDiagnostic(apiKey);

    AppLogger.info(
      'RevenueCat key type: $keyType',
      label: 'PremiumEntitlementService',
    );

    if (apiKey.isEmpty) {
      return;
    }

    PurchasesConfiguration? configuration;
    if (Platform.isAndroid) {
      configuration = PurchasesConfiguration(apiKey);
    }
    // Add iOS configuration here if deploying to iOS later
    // else if (Platform.isIOS) {
    //   configuration = PurchasesConfiguration(_appleApiKey);
    // }

    if (configuration != null) {
      await Purchases.configure(configuration);
    }
  }

  /// Identify the RevenueCat user so entitlements are scoped per Firebase UID.
  /// Must be called after sign-in.
  static Future<void> logIn(String uid) async {
    try {
      await Purchases.logIn(uid);
    } catch (e) {
      AppLogger.error('logIn failed', error: e, label: 'PremiumEntitlementService');
    }
  }

  /// Reset the RevenueCat user to anonymous. Must be called on sign-out.
  static Future<void> logOut() async {
    try {
      await Purchases.logOut();
    } catch (e) {
      AppLogger.error('logOut failed', error: e, label: 'PremiumEntitlementService');
    }
    // Clear cached entitlement so the next user starts fresh
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kCachedPremium);
    await prefs.remove(_kCachedPremiumUid);
  }

  /// Check premium status with offline-resilient caching.
  ///
  /// Decision flow:
  ///   1. If developer premium access is enabled (debug only) → return true.
  ///   2. Otherwise → check real RevenueCat entitlement.
  ///   3. On SDK error → fall back to cached value for offline resilience.
  ///
  /// The [isDebugMode] and [isReleaseMode] parameters exist solely for unit
  /// testing the developer override branch and must NOT be used in app code.
  static Future<bool> isPremiumEnabled({
    String? uid,
    @visibleForTesting bool? isDebugMode,
    @visibleForTesting bool? isReleaseMode,
  }) async {
    // Developer premium access — centralized debug-only bypass
    if (isDeveloperPremiumAccessEnabled(
      isDebugOverride: isDebugMode,
      isReleaseOverride: isReleaseMode,
    )) {
      return true;
    }

    try {
      final customerInfo = await Purchases.getCustomerInfo();
      final isActive =
          customerInfo.entitlements.all[_entitlementId]?.isActive == true;

      // Cache the result for offline resilience
      if (uid != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_kCachedPremium, isActive);
        await prefs.setString(_kCachedPremiumUid, uid);
      }

      return isActive;
    } catch (e) {
      AppLogger.error('Error checking premium', error: e, label: 'PremiumEntitlementService');

      // Fall back to cached value instead of returning false
      if (uid != null) {
        final prefs = await SharedPreferences.getInstance();
        final cachedUid = prefs.getString(_kCachedPremiumUid);
        if (cachedUid == uid) {
          final cached = prefs.getBool(_kCachedPremium);
          if (cached != null) {
            AppLogger.info(
              'Using cached premium=$cached',
              label: 'PremiumEntitlementService',
            );
            return cached;
          }
        }
      }
      return false;
    }
  }

  // Experimental flag can stay in SharedPreferences
  static Future<bool> isExperimentalEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kExperimentalEnabled) ?? false;
  }

  static Future<void> setExperimentalEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kExperimentalEnabled, enabled);
  }
}
