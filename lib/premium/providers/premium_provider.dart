import 'package:flutter/material.dart';
import 'package:pet/core/utils/app_logger.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:pet/premium/services/premium_entitlement_service.dart';

class PremiumProvider extends ChangeNotifier {
  bool _isPremium = false;
  bool _experimentalEnabled = false;
  bool _isLoading = true;

  bool get isPremium => _isPremium;
  bool get experimentalEnabled => _experimentalEnabled;
  bool get isLoading => _isLoading;

  /// Whether developer premium access is currently enabled (debug only).
  /// Always returns `false` in release builds.
  bool get isDeveloperPremiumAccessEnabled =>
      PremiumEntitlementService.isDeveloperPremiumAccessEnabled();

  /// The Firebase UID of the currently logged-in user.
  /// Used to scope RevenueCat identity and entitlement cache.
  String? _currentUid;

  PremiumProvider() {
    Purchases.addCustomerInfoUpdateListener((customerInfo) {
      _updatePremiumStatus(customerInfo);
    });
  }

  void _updatePremiumStatus(CustomerInfo customerInfo) {
    if (PremiumEntitlementService.isDeveloperPremiumAccessEnabled()) {
      if (!_isPremium) {
        _isPremium = true;
        notifyListeners();
      }
      return;
    }

    final newPremiumState =
        customerInfo.entitlements.all["P.E.T Premium"]?.isActive == true;
    if (_isPremium != newPremiumState) {
      _isPremium = newPremiumState;
      notifyListeners();
    }
  }

  /// Initialize RevenueCat SDK and check entitlement.
  ///
  /// Re-entrancy guard prevents duplicate concurrent calls.
  /// try/catch ensures `_isLoading` is always reset (no infinite spinner).
  Future<void> load() async {
    // Re-entrancy guard — prevent duplicate concurrent loads
    if (_isLoading && _currentUid != null) return;

    _isLoading = true;
    notifyListeners();

    try {
      await PremiumEntitlementService.init();
      _isPremium = await PremiumEntitlementService.isPremiumEnabled(
        uid: _currentUid,
      );
      _experimentalEnabled =
          await PremiumEntitlementService.isExperimentalEnabled();
    } catch (e) {
      AppLogger.error('load() failed', error: e, label: 'PremiumProvider');
      // Ensure premium defaults to false on unrecoverable errors
      _isPremium = false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Identify the RevenueCat user with the Firebase UID.
  /// Must be called after successful sign-in.
  Future<void> logInUser(String uid) async {
    _currentUid = uid;
    await PremiumEntitlementService.logIn(uid);
    // Re-check entitlement for this specific user
    _isPremium = await PremiumEntitlementService.isPremiumEnabled(uid: uid);
    notifyListeners();
  }

  /// Reset RevenueCat identity on sign-out.
  Future<void> logOutUser() async {
    await PremiumEntitlementService.logOut();
    _currentUid = null;
  }

  /// Reset all premium state. Must be called during sign-out to prevent
  /// entitlement leaking to the next user on the same device.
  Future<void> clearData() async {
    await logOutUser();
    _isPremium = false;
    _experimentalEnabled = false;
    _isLoading = false;
    notifyListeners();
  }

  Future<void> setExperimental(bool enabled) async {
    await PremiumEntitlementService.setExperimentalEnabled(enabled);
    _experimentalEnabled = enabled;
    notifyListeners();
  }

  /// Toggle developer premium access (debug builds only).
  ///
  /// When enabled, all premium features are unlocked without a subscription.
  /// When disabled, normal RevenueCat entitlement checking resumes.
  /// No-op in release builds.
  Future<void> setDeveloperPremiumAccess(bool enabled) async {
    PremiumEntitlementService.setDeveloperPremiumAccess(enabled);
    // Re-evaluate premium state immediately
    if (enabled) {
      _isPremium = true;
    } else {
      // Falling back to real entitlement — re-check via RevenueCat
      try {
        _isPremium = await PremiumEntitlementService.isPremiumEnabled(
          uid: _currentUid,
        );
      } catch (_) {
        _isPremium = false;
      }
    }
    notifyListeners();
  }
}

