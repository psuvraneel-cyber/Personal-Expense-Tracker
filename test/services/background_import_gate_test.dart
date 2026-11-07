import 'package:flutter_test/flutter_test.dart';
import 'package:pet/services/background_import_gate.dart';
import 'package:pet/services/session_reset.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Background tasks must not import anything after sign-out, account
/// deletion or with SMS detection off, or the next account inherits it.
void main() {
  Future<bool> noFirebaseUser() async => false;
  Future<bool> firebaseUser() async => true;

  group('BackgroundImportGate', () {
    test('SMS import is off after a wipe (no preferences)', () async {
      SharedPreferences.setMockInitialValues({});
      expect(
        await BackgroundImportGate.smsImportAllowed(
            firebaseUserPresent: firebaseUser),
        isFalse,
      );
    });

    test('SMS import needs someone signed in, even with detection on',
        () async {
      SharedPreferences.setMockInitialValues({kSmsFeatureEnabledKey: true});
      expect(
        await BackgroundImportGate.smsImportAllowed(
            firebaseUserPresent: noFirebaseUser),
        isFalse,
      );
    });

    test('SMS import runs for a signed-in user with detection on', () async {
      SharedPreferences.setMockInitialValues({kSmsFeatureEnabledKey: true});
      expect(
        await BackgroundImportGate.smsImportAllowed(
            firebaseUserPresent: firebaseUser),
        isTrue,
      );
    });

    test('a local guest counts as signed in', () async {
      SharedPreferences.setMockInitialValues(
          {kSmsFeatureEnabledKey: true, kIsLocalGuestKey: true});
      expect(
        await BackgroundImportGate.smsImportAllowed(
            firebaseUserPresent: noFirebaseUser),
        isTrue,
      );
    });

    test('SMS detection turned off stops import for a signed-in user',
        () async {
      SharedPreferences.setMockInitialValues({kSmsFeatureEnabledKey: false});
      expect(
        await BackgroundImportGate.smsImportAllowed(
            firebaseUserPresent: firebaseUser),
        isFalse,
      );
    });

    test('notification import only needs a signed-in user', () async {
      SharedPreferences.setMockInitialValues({});
      expect(
        await BackgroundImportGate.hasSignedInUser(
            firebaseUserPresent: firebaseUser),
        isTrue,
      );
      expect(
        await BackgroundImportGate.hasSignedInUser(
            firebaseUserPresent: noFirebaseUser),
        isFalse,
      );
    });
  });

  group('DataOwner', () {
    test('unowned data is claimed by the first account', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await DataOwner.isOwnedBy('alice'), isTrue);
      expect(await DataOwner.isOwnedBy('alice'), isTrue);
    });

    test('data owned by another account is refused', () async {
      SharedPreferences.setMockInitialValues({DataOwner.prefKey: 'alice'});
      expect(await DataOwner.isOwnedBy('bob'), isFalse);
    });

    test('claiming after a wipe hands the data to the new account', () async {
      SharedPreferences.setMockInitialValues({DataOwner.prefKey: 'alice'});
      await DataOwner.claim('bob');
      expect(await DataOwner.isOwnedBy('bob'), isTrue);
    });
  });
}
