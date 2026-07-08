// GENERATED FILE — run `flutterfire configure` to populate.
// See README.md for complete setup instructions.
//
// Steps:
//   1. dart pub global activate flutterfire_cli
//   2. flutterfire configure --project=<your-firebase-project-id>
//   This will overwrite this file with real config values.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

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

  /// Web client ID (type-3 OAuth client from google-services.json).
  static const String webClientId =
      '101986511704-qas7ttsdccrg8d5nti75fss05pjca5el.apps.googleusercontent.com';

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyD0nFjgCbv1-rLVkOiHNVIspdstX7cwRuc',
    appId: '1:101986511704:android:148f37336f6c499205d32d',
    messagingSenderId: '101986511704',
    projectId: 'personal-expense-tracker-6891b',
    authDomain: 'personal-expense-tracker-6891b.firebaseapp.com',
    storageBucket: 'personal-expense-tracker-6891b.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyD0nFjgCbv1-rLVkOiHNVIspdstX7cwRuc',
    appId: '1:101986511704:android:148f37336f6c499205d32d',
    messagingSenderId: '101986511704',
    projectId: 'personal-expense-tracker-6891b',
    storageBucket: 'personal-expense-tracker-6891b.firebasestorage.app',
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
