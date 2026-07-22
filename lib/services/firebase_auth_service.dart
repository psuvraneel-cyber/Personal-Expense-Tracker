import 'package:flutter/foundation.dart';
import 'package:pet/core/utils/app_logger.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pet/firebase_options.dart';
import 'package:pet/services/secure_storage_service.dart';

// Conditional import: on web this resolves to a stub; on mobile/desktop it
// resolves to the real dart:io Platform.
import 'platform_stub.dart'
    if (dart.library.io) 'platform_native.dart'
    as platform;

/// Centralized Firebase authentication service wrapping FirebaseAuth.
///
/// **Web**: uses `signInWithPopup(GoogleAuthProvider())` — the correct path
/// for Flutter Web. No `google_sign_in` package client ID is needed.
///
/// **Android / iOS**: uses the `google_sign_in` package with the type-3 web
/// client ID (so that ID tokens are returned), then exchanges the credential
/// via `signInWithCredential`.
class FirebaseAuthService {
  static final FirebaseAuthService _instance = FirebaseAuthService._internal();

  FirebaseAuth? _customFirebaseAuth;

  FirebaseAuth get _firebaseAuth => _customFirebaseAuth ?? FirebaseAuth.instance;

  @visibleForTesting
  set firebaseAuth(FirebaseAuth auth) => _customFirebaseAuth = auth;

  /// Lazily created and only used on mobile — never instantiated on web.
  GoogleSignIn? _mobileGoogleSignIn;

  factory FirebaseAuthService() => _instance;

  FirebaseAuthService._internal();

  bool _isLocalGuest = false;
  String? _localGuestName;

  bool get isLocalGuest => _isLocalGuest;

  // ── Getters ─────────────────────────────────────────────────────────

  User? get currentUser => _firebaseAuth.currentUser;
  String? get currentUserId => _isLocalGuest ? 'guest_user' : currentUser?.uid;
  bool get isLoggedIn => currentUser != null || _isLocalGuest;
  String? get userName => _localGuestName ?? currentUser?.displayName;
  String? get userEmail {
    if (_isLocalGuest) return 'guest@pet.local';
    if (currentUser?.isAnonymous == true) return 'guest@pet.local';
    return currentUser?.email;
  }
  String? get photoUrl => currentUser?.photoURL;

  /// True on Web, Android, and iOS — false on desktop (Windows/Linux/macOS).
  bool get isGoogleSignInSupported {
    if (kIsWeb) return true;
    return platform.isAndroid || platform.isIOS;
  }

  // ── Actions ─────────────────────────────────────────────────────────

  /// Try to silently restore the user's Google + Firebase session on cold start.
  ///
  /// Call this once in `main()` before `runApp()`. Returns `true` if the
  /// session was restored (user is now signed in to Firebase), `false` if
  /// a fresh interactive sign-in is required.
  ///
  /// This is needed on Android because `GoogleSignIn.signInSilently()` must
  /// explicitly be called to restore the Google-side session; Firebase Auth
  /// alone may not have enough to reconstruct the credential on cold start.
  Future<bool> tryRestoreSession() async {
    final prefs = await SharedPreferences.getInstance();

    // Migrate legacy plaintext keys in SharedPreferences to secure storage if found
    if (prefs.containsKey('userName')) {
      final oldName = prefs.getString('userName');
      if (oldName != null && oldName.isNotEmpty) {
        await SecureStorageService.instance.write('userName', oldName);
      }
      await prefs.remove('userName');
    }
    if (prefs.containsKey('userEmail')) {
      final oldEmail = prefs.getString('userEmail');
      if (oldEmail != null && oldEmail.isNotEmpty) {
        await SecureStorageService.instance.write('userEmail', oldEmail);
      }
      await prefs.remove('userEmail');
    }

    if (prefs.getBool('isLocalGuest') == true) {
      _isLocalGuest = true;
      _localGuestName = await SecureStorageService.instance.read('userName') ?? 'Guest';
      AppLogger.debug('[AUTH] Local guest session restored: $_localGuestName');
      return true;
    }

    if (kIsWeb) return _firebaseAuth.currentUser != null;
    if (!isGoogleSignInSupported) return false;

    // If Firebase already has a valid signed-in user, no need to do anything.
    if (_firebaseAuth.currentUser != null) {
      AppLogger.debug(
        '[AUTH] Session already active: ${_firebaseAuth.currentUser!.uid}',
      );
      return true;
    }

    try {
      final googleSignIn = _getOrCreateGoogleSignIn();
      final googleUser = await googleSignIn.signInSilently();
      if (googleUser == null) {
        AppLogger.debug(
          '[AUTH] signInSilently returned null — user needs to sign in interactively',
        );
        return false;
      }

      AppLogger.debug('[AUTH] signInSilently succeeded: ${googleUser.email}');
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final result = await _firebaseAuth.signInWithCredential(credential);
      AppLogger.debug('[AUTH] Firebase session restored: ${result.user?.uid}');
      return result.user != null;
    } catch (e) {
      AppLogger.debug('[AUTH] Silent restore failed: $e');
      return false;
    }
  }

  /// Sign in with Google.
  ///
  /// Returns null if the user cancelled. Throws a user-friendly [Exception]
  /// on failure.
  Future<UserCredential?> signInWithGoogle() async {
    if (!isGoogleSignInSupported) {
      throw Exception(
        'Google Sign-In is only supported on Android, iOS, and Web.',
      );
    }
    try {
      final result = kIsWeb
          ? await _signInWithPopup()
          : await _signInWithGoogleMobile();
      
      if (result != null) {
        _isLocalGuest = false;
        _localGuestName = null;
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('isLocalGuest');
      }
      return result;
    } on FirebaseAuthException catch (e) {
      throw _friendlyAuthError(e);
    }
  }

  /// Sign in as a Guest.
  /// Attempts Firebase Anonymous Auth first; falls back to local mode on failure.
  Future<bool> signInAsGuest(String username) async {
    try {
      final credential = await _firebaseAuth.signInAnonymously();
      await credential.user?.updateDisplayName(username);
      _isLocalGuest = false;
      _localGuestName = null;
      await _cacheUserInfo(name: username, email: 'guest@pet.local');
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('isLocalGuest');
      return true;
    } catch (e) {
      AppLogger.debug('[AUTH] Anonymous sign-in failed, falling back to local guest: $e');
      _isLocalGuest = true;
      _localGuestName = username;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isLocalGuest', true);
      await SecureStorageService.instance.write('userName', username);
      await SecureStorageService.instance.write('userEmail', 'guest@pet.local');
      // Clean up legacy plaintext keys in SharedPreferences
      await prefs.remove('userName');
      await prefs.remove('userEmail');
      return true;
    }
  }

  /// Re-authenticate the current user with Google.
  /// Needed before sensitive operations like account deletion.
  Future<bool> reauthenticateGoogle() async {
    try {
      if (kIsWeb) {
        final provider = GoogleAuthProvider()
          ..addScope('email')
          ..addScope('profile');
        await _firebaseAuth.currentUser?.reauthenticateWithPopup(provider);
        return true;
      } else {
        final googleUser = await _getOrCreateGoogleSignIn().signIn();
        if (googleUser == null) return false;

        final googleAuth = await googleUser.authentication;
        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        await _firebaseAuth.currentUser?.reauthenticateWithCredential(credential);
        return true;
      }
    } catch (e) {
      AppLogger.debug('[AUTH] Re-auth failed: $e');
      return false;
    }
  }

  Future<void> signOut() async {
    if (!kIsWeb) {
      await _mobileGoogleSignIn?.signOut();
    }
    await _firebaseAuth.signOut();
    _isLocalGuest = false;
    _localGuestName = null;
    
    // Clear secure storage values
    await SecureStorageService.instance.delete('userName');
    await SecureStorageService.instance.delete('userEmail');

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('userName');
    await prefs.remove('userEmail');
    await prefs.remove('isLocalGuest');
  }

  Stream<User?> authStateChanges() => _firebaseAuth.authStateChanges();

  // ── Private Methods ──────────────────────────────────────────────────

  Future<UserCredential?> _signInWithPopup() async {
    final provider = GoogleAuthProvider()
      ..addScope('email')
      ..addScope('profile');
    final result = await _firebaseAuth.signInWithPopup(provider);
    await _cacheUserInfo(
      name: result.user?.displayName ?? '',
      email: result.user?.email ?? '',
    );
    return result;
  }

  Future<UserCredential?> _signInWithGoogleMobile() async {
    final googleUser = await _getOrCreateGoogleSignIn().signIn();
    if (googleUser == null) return null; // user cancelled

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final userCredential = await _firebaseAuth.signInWithCredential(credential);
    await _cacheUserInfo(
      name: userCredential.user?.displayName ?? '',
      email: userCredential.user?.email ?? '',
    );
    return userCredential;
  }

  /// Returns or creates the shared GoogleSignIn instance.
  GoogleSignIn _getOrCreateGoogleSignIn() {
    _mobileGoogleSignIn ??= GoogleSignIn(
      // serverClientId = web/server client ID (type 3). Required to get an
      // ID token that Firebase Auth can verify server-side.
      serverClientId: DefaultFirebaseOptions.webClientId,
    );
    return _mobileGoogleSignIn!;
  }

  Future<void> _cacheUserInfo({
    required String name,
    required String email,
  }) async {
    if (name.isNotEmpty) {
      await SecureStorageService.instance.write('userName', name);
    }
    if (email.isNotEmpty) {
      await SecureStorageService.instance.write('userEmail', email);
    }
  }

  Exception _friendlyAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'account-exists-with-different-credential':
        return Exception(
          'This email is already linked to another sign-in method.',
        );
      case 'invalid-credential':
        return Exception('Invalid credentials. Please try again.');
      case 'user-disabled':
        return Exception('This account has been disabled.');
      case 'network-request-failed':
        return Exception('Network error. Please check your connection.');
      case 'popup-closed-by-user':
        return Exception('Sign-in was cancelled.');
      case 'popup-blocked':
        return Exception(
          'Pop-up blocked by your browser. '
          'Allow pop-ups for this site and try again.',
        );
      default:
        return Exception(e.message ?? 'Sign-in failed. Please try again.');
    }
  }
}
