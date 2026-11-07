import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences key for the "Detect transactions from SMS" switch.
///
/// The native SMS receiver reads the same value (as `flutter.smsFeatureEnabled`
/// in `FlutterSharedPreferences`), so keep the name in sync with
/// `SmsBroadcastReceiver.kt`.
const String kSmsFeatureEnabledKey = 'smsFeatureEnabled';

/// SharedPreferences key set while a local (offline) guest is signed in.
const String kIsLocalGuestKey = 'isLocalGuest';

/// Decides whether a background task may import transactions.
///
/// Background isolates run without the UI, so they cannot rely on provider
/// state. Without this check, a bank SMS that arrives after sign-out or
/// account deletion would be imported and then handed to whoever signs in
/// next.
class BackgroundImportGate {
  BackgroundImportGate._();

  /// How long to wait for Firebase to restore a saved session.
  static const Duration authRestoreTimeout = Duration(seconds: 5);

  /// Whether someone is signed in: a local guest, or a restored Firebase user.
  ///
  /// [firebaseUserPresent] is for tests; by default it waits for Firebase to
  /// report the restored session (the first auth event), because
  /// `currentUser` can still be null right after `initializeApp` in a fresh
  /// isolate.
  static Future<bool> hasSignedInUser({
    Future<bool> Function()? firebaseUserPresent,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    if (prefs.getBool(kIsLocalGuestKey) ?? false) return true;
    return (firebaseUserPresent ?? _restoredFirebaseUser)();
  }

  /// Whether SMS import may run: SMS detection is on and someone is signed in.
  static Future<bool> smsImportAllowed({
    Future<bool> Function()? firebaseUserPresent,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    if (!(prefs.getBool(kSmsFeatureEnabledKey) ?? false)) return false;
    return hasSignedInUser(firebaseUserPresent: firebaseUserPresent);
  }

  static Future<bool> _restoredFirebaseUser() async {
    if (Firebase.apps.isEmpty) return false;
    final auth = FirebaseAuth.instance;
    try {
      final user =
          await auth.authStateChanges().first.timeout(authRestoreTimeout);
      return user != null;
    } catch (_) {
      return auth.currentUser != null;
    }
  }
}
