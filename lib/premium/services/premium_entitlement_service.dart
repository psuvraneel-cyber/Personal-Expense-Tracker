import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pet/config/app_env.dart';

class PremiumEntitlementService {
  PremiumEntitlementService._();

  static const String _kExperimentalEnabled = 'pet_experimental_enabled';
  static const String _kCachedPremium = 'pet_cached_premium';
  static const String _kCachedPremiumUid = 'pet_cached_premium_uid';
  static const String _entitlementId = 'P.E.T Premium';

  static Future<void> init() async {
    // Only enable debug logging in debug builds — never leak purchase info
    // in production device logs.
    await Purchases.setLogLevel(kDebugMode ? LogLevel.debug : LogLevel.warn);

    PurchasesConfiguration? configuration;
    final apiKey = AppEnv.revenueCatGoogleApiKey;

    if (apiKey.isEmpty) {
      debugPrint(
        '[PremiumEntitlementService] WARNING: REVENUECAT_GOOGLE_API_KEY is '
        'empty. Premium features will not work. Add it to your .env file.',
      );
      return;
    }

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
      debugPrint('[PremiumEntitlementService] logIn failed: $e');
    }
  }

  /// Reset the RevenueCat user to anonymous. Must be called on sign-out.
  static Future<void> logOut() async {
    try {
      await Purchases.logOut();
    } catch (e) {
      debugPrint('[PremiumEntitlementService] logOut failed: $e');
    }
    // Clear cached entitlement so the next user starts fresh
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kCachedPremium);
    await prefs.remove(_kCachedPremiumUid);
  }

  /// Check premium status with offline-resilient caching.
  ///
  /// On success: caches result in SharedPreferences keyed by UID.
  /// On failure (offline / SDK error): returns the cached value instead of
  /// defaulting to `false`, so premium users aren't downgraded when offline.
  static Future<bool> isPremiumEnabled({String? uid}) async {
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
      debugPrint('[PremiumEntitlementService] Error checking premium: $e');

      // Fall back to cached value instead of returning false
      if (uid != null) {
        final prefs = await SharedPreferences.getInstance();
        final cachedUid = prefs.getString(_kCachedPremiumUid);
        if (cachedUid == uid) {
          final cached = prefs.getBool(_kCachedPremium);
          if (cached != null) {
            debugPrint(
              '[PremiumEntitlementService] Using cached premium=$cached for $uid',
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
