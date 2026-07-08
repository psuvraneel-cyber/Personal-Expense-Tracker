import 'package:firebase_auth/firebase_auth.dart';
import 'package:pet/services/firebase_auth_service.dart';

/// Backward-compatible façade over [FirebaseAuthService].
///
/// Existing call-sites that depend on `AuthService.*` continue to compile
/// unchanged.  New code should use [FirebaseAuthService] directly.
class AuthService {
  static final _service = FirebaseAuthService();

  // ── Getters ────────────────────────────────────────────────────────

  /// Current authenticated user, or null.
  static User? get currentUser => _service.currentUser;

  /// Whether the user is currently signed in.
  static bool get isLoggedIn => _service.isLoggedIn;

  /// Display name from Google account.
  static String? get userName => _service.userName;

  /// User's email address.
  static String? get userEmail => _service.userEmail;

  /// Google profile photo URL.
  static String? get photoUrl => _service.photoUrl;

  /// Whether the user is currently signed in as a local guest.
  static bool get isLocalGuest => _service.isLocalGuest;

  // ── Actions ────────────────────────────────────────────────────────

  /// Sign in with Google (replaces email/password).
  static Future<UserCredential?> signInWithGoogle() =>
      _service.signInWithGoogle();

  /// Sign in as a guest.
  static Future<bool> signInAsGuest(String username) =>
      _service.signInAsGuest(username);

  /// Sign out the current user and clear the session.
  static Future<void> signOut() => _service.signOut();

  /// Stream of auth-state changes (sign-in, sign-out…).
  static Stream<User?> get onAuthStateChange => _service.authStateChanges();
}
