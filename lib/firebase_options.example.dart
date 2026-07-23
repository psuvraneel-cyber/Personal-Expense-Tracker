// TEMPLATE FILE — Copy to `lib/firebase_options.dart` or run `flutterfire configure`.
// DO NOT commit real API keys or Firebase credentials to source control.
// See README.md for complete setup instructions.
//
// Steps to generate local configuration:
//   1. dart pub global activate flutterfire_cli
//   2. flutterfire configure --project=<your-firebase-project-id>
//   This will generate a local `lib/firebase_options.dart` which is gitignored.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] template.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    FirebaseOptions options;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        options = android;
        break;
      case TargetPlatform.iOS:
        options = ios;
        break;
      case TargetPlatform.windows:
        options = windows;
        break;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }

    if (options.apiKey.contains('REPLACE_WITH')) {
      throw UnsupportedError('Firebase is not configured for this platform.');
    }
    return options;
  }

  /// Web client ID placeholder for OAuth authentication.
  static const String webClientId =
      'YOUR_WEB_CLIENT_ID.apps.googleusercontent.com';

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'REPLACE_WITH_YOUR_WEB_API_KEY',
    appId: 'REPLACE_WITH_YOUR_WEB_APP_ID',
    messagingSenderId: 'REPLACE_WITH_YOUR_SENDER_ID',
    projectId: 'REPLACE_WITH_YOUR_PROJECT_ID',
    authDomain: 'REPLACE_WITH_YOUR_PROJECT_ID.firebaseapp.com',
    storageBucket: 'REPLACE_WITH_YOUR_PROJECT_ID.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'REPLACE_WITH_YOUR_ANDROID_API_KEY',
    appId: 'REPLACE_WITH_YOUR_ANDROID_APP_ID',
    messagingSenderId: 'REPLACE_WITH_YOUR_SENDER_ID',
    projectId: 'REPLACE_WITH_YOUR_PROJECT_ID',
    storageBucket: 'REPLACE_WITH_YOUR_PROJECT_ID.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'REPLACE_WITH_YOUR_IOS_API_KEY',
    appId: 'REPLACE_WITH_YOUR_IOS_APP_ID',
    messagingSenderId: 'REPLACE_WITH_YOUR_SENDER_ID',
    projectId: 'REPLACE_WITH_YOUR_PROJECT_ID',
    storageBucket: 'REPLACE_WITH_YOUR_PROJECT_ID.appspot.com',
    iosBundleId: 'com.example.pet',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'REPLACE_WITH_YOUR_WINDOWS_API_KEY',
    appId: 'REPLACE_WITH_YOUR_WINDOWS_APP_ID',
    messagingSenderId: 'REPLACE_WITH_YOUR_SENDER_ID',
    projectId: 'REPLACE_WITH_YOUR_PROJECT_ID',
    storageBucket: 'REPLACE_WITH_YOUR_PROJECT_ID.appspot.com',
    authDomain: 'REPLACE_WITH_YOUR_PROJECT_ID.firebaseapp.com',
  );
}
