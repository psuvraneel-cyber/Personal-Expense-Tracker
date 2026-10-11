import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:pet/core/utils/app_logger.dart';

/// Server-tunable values for paywall copy and growth prompts, so prices,
/// copy and thresholds can be A/B tested (Firebase A/B Testing) without a
/// new release. Every value is validated and falls back to the bundled
/// default, so a bad console edit can't break the paywall.
class RemoteConfigService {
  RemoteConfigService._();

  static const kPaywallHeadline = 'paywall_headline';
  static const kPaywallSubtitle = 'paywall_subtitle';
  static const kPaywallDefaultPlan = 'paywall_default_plan';
  static const kReviewAutoImportThreshold = 'review_auto_import_threshold';

  static const defaults = <String, Object>{
    kPaywallHeadline: 'Unlock P.E.T Premium',
    kPaywallSubtitle: 'Unlock AI insights, tax tracking, cash-flow forecasts '
        'and Focus Mode.',
    // annual | monthly | lifetime | first (RevenueCat's own order)
    kPaywallDefaultPlan: 'annual',
    kReviewAutoImportThreshold: 10,
  };

  static const allowedPlans = {'annual', 'monthly', 'lifetime', 'first'};

  /// Raw values; overridable in tests.
  static Object? Function(String key)? _override;

  static set debugOverride(Object? Function(String key)? override) =>
      _override = override;

  static FirebaseRemoteConfig? get _rc =>
      kIsWeb || Firebase.apps.isEmpty ? null : FirebaseRemoteConfig.instance;

  /// Applies defaults and starts a fetch in the background. Values fetched
  /// now are activated on the next call to [init] (next launch), so the
  /// paywall never changes while someone is looking at it.
  static Future<void> init() async {
    final rc = _rc;
    if (rc == null) return;
    try {
      await rc.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval:
            kDebugMode ? const Duration(minutes: 5) : const Duration(hours: 12),
      ));
      await rc.setDefaults(defaults);
      await rc.activate();
      // Not awaited: startup must not wait on the network.
      rc.fetch().catchError((Object e) {
        AppLogger.debug('[RemoteConfig] fetch failed: $e');
      });
    } catch (e) {
      AppLogger.debug('[RemoteConfig] init failed: $e');
    }
  }

  static String _string(String key) {
    final fallback = defaults[key] as String;
    try {
      final raw =
          _override != null ? _override!(key) : _rc?.getValue(key).asString();
      return raw is String ? raw.trim() : fallback;
    } catch (_) {
      return fallback;
    }
  }

  static int _int(String key) {
    final fallback = defaults[key] as int;
    try {
      final raw =
          _override != null ? _override!(key) : _rc?.getValue(key).asInt();
      return raw is int ? raw : int.tryParse('$raw') ?? fallback;
    } catch (_) {
      return fallback;
    }
  }

  static String _text(String key, {required int maxLength}) {
    final value = _string(key);
    if (value.isEmpty || value.length > maxLength) {
      return defaults[key] as String;
    }
    return value;
  }

  static String get paywallHeadline => _text(kPaywallHeadline, maxLength: 40);

  static String get paywallSubtitle => _text(kPaywallSubtitle, maxLength: 140);

  static String get paywallDefaultPlan {
    final plan = _string(kPaywallDefaultPlan).toLowerCase();
    return allowedPlans.contains(plan)
        ? plan
        : defaults[kPaywallDefaultPlan] as String;
  }

  /// Auto-imported transactions before the Play review prompt (3–50).
  static int get reviewAutoImportThreshold =>
      _int(kReviewAutoImportThreshold).clamp(3, 50);
}
