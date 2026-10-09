import 'package:pet/core/utils/app_logger.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service for biometric authentication (fingerprint / face unlock).
///
/// Uses the `local_auth` plugin for platform-native biometric calls.
/// Provides configurable idle timeout and enable/disable toggle.
class BiometricService {
  BiometricService._();
  static final BiometricService _instance = BiometricService._();
  static BiometricService get instance => _instance;

  static const _kEnabled = 'biometricEnabled';
  static const _kTimeout = 'biometricTimeout'; // minutes

  final LocalAuthentication _auth = LocalAuthentication();

  bool _enabled = false;
  int _timeoutMinutes = 5;
  DateTime? _lastActiveTime;
  bool _loaded = false;

  bool get isEnabled => _enabled;
  int get timeoutMinutes => _timeoutMinutes;

  static const MethodChannel _windowChannel =
      MethodChannel('com.pet.tracker/window');

  /// With app lock on, also hide app content from the Recents thumbnail and
  /// block screenshots/screen recording (Android FLAG_SECURE).
  Future<void> applySecureWindow() async {
    try {
      await _windowChannel.invokeMethod('setSecure', {'secure': _enabled});
    } catch (_) {
      // Not available on this platform / in tests.
    }
  }

  /// Whether the app has been idle longer than the configured timeout.
  bool get isLocked {
    if (!_enabled) return false;
    if (_lastActiveTime == null) return true; // First launch with biometric on
    return DateTime.now().difference(_lastActiveTime!).inMinutes >=
        _timeoutMinutes;
  }

  Future<void> init() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_kEnabled) ?? false;
      _timeoutMinutes = prefs.getInt(_kTimeout) ?? 5;
    } catch (e) {
      AppLogger.debug('[Biometric] Init error: $e');
    }
    await applySecureWindow();
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    if (value) markActive(); // Start timeout from now
    await applySecureWindow();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kEnabled, value);
    } catch (e) {
      AppLogger.debug('[Biometric] setEnabled error: $e');
    }
  }

  Future<void> setTimeoutMinutes(int minutes) async {
    _timeoutMinutes = minutes;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kTimeout, minutes);
    } catch (e) {
      AppLogger.debug('[Biometric] setTimeoutMinutes error: $e');
    }
  }

  /// Mark the app as active (call on every user interaction / resume).
  void markActive() {
    _lastActiveTime = DateTime.now();
  }

  /// Check if device supports biometrics.
  Future<bool> canAuthenticate() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isSupported = await _auth.isDeviceSupported();
      return canCheck || isSupported;
    } catch (e) {
      AppLogger.debug('[Biometric] Error checking support: $e');
      return false;
    }
  }

  /// Get the list of available biometric types.
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } catch (e) {
      AppLogger.debug('[Biometric] Error getting available biometrics: $e');
      return [];
    }
  }

  /// Prompt biometric authentication. Returns true if successful.
  Future<bool> authenticate({
    String reason = 'Authenticate to unlock P.E.T',
  }) async {
    try {
      final result = await _auth.authenticate(
        localizedReason: reason,
        // Allow PIN/pattern fallback per Play Store guidelines.
        biometricOnly: false,
        // Formerly `stickyAuth`: survive the app being backgrounded mid-prompt.
        persistAcrossBackgrounding: true,
      );
      if (result) markActive();
      return result;
    } catch (e) {
      AppLogger.debug('[Biometric] Authentication error: $e');
      return false;
    }
  }
}
