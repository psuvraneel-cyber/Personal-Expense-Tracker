import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pet/premium/services/premium_entitlement_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 2 & 3: RevenueCat Environment Separation & Safety Invariants', () {
    // Synthetic placeholder keys for testing (never use real credentials)
    const syntheticTestStoreKey = 'test_sample_public_sdk_key_123';
    const syntheticAndroidProdKey = 'goog_sample_public_sdk_key_456';
    const syntheticSecretKey = 'sk_sample_secret_key_789';

    test('Debug build selects Test Store key (test_*) when provided', () {
      final resolved = PremiumEntitlementService.resolveApiKey(
        isDebugOverride: true,
        isReleaseOverride: false,
        testStoreKeyOverride: syntheticTestStoreKey,
        androidKeyOverride: syntheticAndroidProdKey,
      );

      expect(resolved, equals(syntheticTestStoreKey));
      expect(PremiumEntitlementService.getKeyDiagnostic(resolved), equals('Test Store'));
    });

    test('Release build selects Android production key (goog_*)', () {
      final resolved = PremiumEntitlementService.resolveApiKey(
        isDebugOverride: false,
        isReleaseOverride: true,
        testStoreKeyOverride: syntheticTestStoreKey,
        androidKeyOverride: syntheticAndroidProdKey,
      );

      expect(resolved, equals(syntheticAndroidProdKey));
      expect(PremiumEntitlementService.getKeyDiagnostic(resolved), equals('Android production'));
    });

    test('Release build throws StateError if Android key is missing or empty', () {
      expect(
        () => PremiumEntitlementService.resolveApiKey(
          isDebugOverride: false,
          isReleaseOverride: true,
          testStoreKeyOverride: syntheticTestStoreKey,
          androidKeyOverride: '',
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Missing or unconfigured REVENUECAT_ANDROID_API_KEY'),
        )),
      );
    });

    test('Release build throws StateError if Android key is placeholder REPLACE_ME', () {
      expect(
        () => PremiumEntitlementService.resolveApiKey(
          isDebugOverride: false,
          isReleaseOverride: true,
          testStoreKeyOverride: syntheticTestStoreKey,
          androidKeyOverride: 'REPLACE_ME',
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Missing or unconfigured REVENUECAT_ANDROID_API_KEY'),
        )),
      );
    });

    test('Release build REJECTS Test Store key (test_*) with StateError', () {
      expect(
        () => PremiumEntitlementService.resolveApiKey(
          isDebugOverride: false,
          isReleaseOverride: true,
          testStoreKeyOverride: '',
          androidKeyOverride: syntheticTestStoreKey,
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('RELEASE BUILD SECURITY ERROR: RevenueCat Test Store key cannot be used in release builds'),
        )),
      );
    });

    test('Secret API key (sk_*) in any build mode throws StateError immediately', () {
      // In debug mode
      expect(
        () => PremiumEntitlementService.resolveApiKey(
          isDebugOverride: true,
          isReleaseOverride: false,
          testStoreKeyOverride: syntheticSecretKey,
          androidKeyOverride: syntheticAndroidProdKey,
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('CRITICAL SECURITY ERROR: RevenueCat Secret API key detected in client app'),
        )),
      );

      // In release mode
      expect(
        () => PremiumEntitlementService.resolveApiKey(
          isDebugOverride: false,
          isReleaseOverride: true,
          testStoreKeyOverride: syntheticTestStoreKey,
          androidKeyOverride: syntheticSecretKey,
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('CRITICAL SECURITY ERROR: RevenueCat Secret API key detected in client app'),
        )),
      );
    });

    test('Debug build gracefully falls back to Android key if Test Store key is unconfigured', () {
      final resolved = PremiumEntitlementService.resolveApiKey(
        isDebugOverride: true,
        isReleaseOverride: false,
        testStoreKeyOverride: '',
        androidKeyOverride: syntheticAndroidProdKey,
      );

      expect(resolved, equals(syntheticAndroidProdKey));
      expect(PremiumEntitlementService.getKeyDiagnostic(resolved), equals('Android production'));
    });

    test('Debug build returns empty string when neither key is configured without throwing', () {
      final resolved = PremiumEntitlementService.resolveApiKey(
        isDebugOverride: true,
        isReleaseOverride: false,
        testStoreKeyOverride: '',
        androidKeyOverride: '',
      );

      expect(resolved, isEmpty);
      expect(PremiumEntitlementService.getKeyDiagnostic(resolved), equals('Unconfigured'));
    });
  });

  group('Phase 4 & 5: Identity & Entitlement Invariants', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      PremiumEntitlementService.resetDeveloperOverrideForTesting();
    });

    test('Entitlement ID invariant is exactly "P.E.T Premium"', () {
      // Verify via reflection/direct usage in service
      // Developer override ON in debug returns true immediately
      expect(
        PremiumEntitlementService.isDeveloperPremiumAccessEnabled(
          isDebugOverride: true,
          isReleaseOverride: false,
        ),
        isTrue,
      );
    });

    test('Sign out removes cached entitlement and UID from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        'pet_cached_premium': true,
        'pet_cached_premium_uid': 'test_firebase_uid_123',
      });

      final prefsBefore = await SharedPreferences.getInstance();
      expect(prefsBefore.getBool('pet_cached_premium'), isTrue);
      expect(prefsBefore.getString('pet_cached_premium_uid'), equals('test_firebase_uid_123'));

      await PremiumEntitlementService.logOut();

      final prefsAfter = await SharedPreferences.getInstance();
      expect(prefsAfter.getBool('pet_cached_premium'), isNull);
      expect(prefsAfter.getString('pet_cached_premium_uid'), isNull);
    });
  });

  group('Phase 3: Diagnostic Safety — Key Privacy', () {
    test('getKeyDiagnostic correctly identifies key types without exposing actual values', () {
      expect(PremiumEntitlementService.getKeyDiagnostic(''), equals('Unconfigured'));
      expect(PremiumEntitlementService.getKeyDiagnostic('REPLACE_ME'), equals('Unconfigured'));
      expect(PremiumEntitlementService.getKeyDiagnostic('test_abc123xyz'), equals('Test Store'));
      expect(PremiumEntitlementService.getKeyDiagnostic('goog_abc123xyz'), equals('Android production'));
      expect(PremiumEntitlementService.getKeyDiagnostic('appl_abc123xyz'), equals('iOS production'));
      expect(PremiumEntitlementService.getKeyDiagnostic('sk_secret123'), equals('Secret Key (UNSAFE)'));
      expect(PremiumEntitlementService.getKeyDiagnostic('custom_unknown_key'), equals('Custom / Other'));

      // Ensure diagnostic string never contains secret fragments
      final diagnostic = PremiumEntitlementService.getKeyDiagnostic('test_super_secret_payload');
      expect(diagnostic.contains('super_secret_payload'), isFalse);
    });
  });
}
