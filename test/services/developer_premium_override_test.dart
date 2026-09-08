import 'package:flutter_test/flutter_test.dart';
import 'package:pet/premium/services/premium_entitlement_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Developer Premium Access — Debug/Release Behavior', () {
    setUp(() {
      // Reset to default state before each test for isolation
      PremiumEntitlementService.resetDeveloperOverrideForTesting();
    });

    // ── Test 1: Debug + override ON ─────────────────────────────────────────
    test('Debug build + override ON → isDeveloperPremiumAccessEnabled = true', () {
      // Default is ON in debug
      final result = PremiumEntitlementService.isDeveloperPremiumAccessEnabled(
        isDebugOverride: true,
        isReleaseOverride: false,
      );

      expect(result, isTrue);
    });

    // ── Test 2: Debug + override OFF ────────────────────────────────────────
    test('Debug build + override OFF → isDeveloperPremiumAccessEnabled = false', () {
      PremiumEntitlementService.setDeveloperPremiumAccess(
        false,
        isDebugOverride: true,
        isReleaseOverride: false,
      );

      final result = PremiumEntitlementService.isDeveloperPremiumAccessEnabled(
        isDebugOverride: true,
        isReleaseOverride: false,
      );

      expect(result, isFalse);
    });

    // ── Test 3: Release → override always false ─────────────────────────────
    test('Release build → isDeveloperPremiumAccessEnabled always false', () {
      // Even though the in-memory flag is true (default), release should
      // always return false.
      final result = PremiumEntitlementService.isDeveloperPremiumAccessEnabled(
        isDebugOverride: false,
        isReleaseOverride: true,
      );

      expect(result, isFalse);
    });

    // ── Test 4: Release → setDeveloperPremiumAccess is a no-op ──────────────
    test('Release build → setDeveloperPremiumAccess is a no-op', () {
      // First, turn it off in debug
      PremiumEntitlementService.setDeveloperPremiumAccess(
        false,
        isDebugOverride: true,
        isReleaseOverride: false,
      );

      // Attempt to turn it on in "release" mode
      PremiumEntitlementService.setDeveloperPremiumAccess(
        true,
        isDebugOverride: false,
        isReleaseOverride: true,
      );

      // Should still be false when checked in debug
      // (the release setter was a no-op, so it remains whatever debug set it to)
      final result = PremiumEntitlementService.isDeveloperPremiumAccessEnabled(
        isDebugOverride: true,
        isReleaseOverride: false,
      );

      expect(result, isFalse);
    });

    // ── Test 5: Debug + override ON → isPremiumEnabled returns true ──────────
    test('Debug build + override ON → isPremiumEnabled() returns true immediately', () async {
      final isPremium = await PremiumEntitlementService.isPremiumEnabled(
        isDebugMode: true,
        isReleaseMode: false,
      );

      expect(isPremium, isTrue);
    });

    // ── Test 6: Release + override ON → isPremiumEnabled does NOT bypass ─────
    test('Release build + override ON → isPremiumEnabled does NOT bypass RevenueCat', () async {
      // The override is ON (default), but we're simulating a release check.
      // isPremiumEnabled should NOT short-circuit — it will fall through to
      // the RevenueCat check (which will throw since we're in a test env).
      // The catch block in isPremiumEnabled returns false as fallback.
      final isPremium = await PremiumEntitlementService.isPremiumEnabled(
        isDebugMode: false,
        isReleaseMode: true,
      );

      // Should be false because RevenueCat SDK isn't configured in test,
      // and developer override is disabled in release mode.
      expect(isPremium, isFalse);
    });

    // ── Test 7: Toggle ON → OFF → verify state transitions ──────────────────
    test('Toggle ON → OFF → ON produces correct state transitions', () {
      // Initially ON
      expect(
        PremiumEntitlementService.isDeveloperPremiumAccessEnabled(
          isDebugOverride: true,
          isReleaseOverride: false,
        ),
        isTrue,
      );

      // Toggle OFF
      PremiumEntitlementService.setDeveloperPremiumAccess(
        false,
        isDebugOverride: true,
        isReleaseOverride: false,
      );

      expect(
        PremiumEntitlementService.isDeveloperPremiumAccessEnabled(
          isDebugOverride: true,
          isReleaseOverride: false,
        ),
        isFalse,
      );

      // Toggle back ON
      PremiumEntitlementService.setDeveloperPremiumAccess(
        true,
        isDebugOverride: true,
        isReleaseOverride: false,
      );

      expect(
        PremiumEntitlementService.isDeveloperPremiumAccessEnabled(
          isDebugOverride: true,
          isReleaseOverride: false,
        ),
        isTrue,
      );
    });

    // ── Test 8: Profile mode (neither debug nor release) → always false ─────
    test('Profile build (debug=false, release=false) → override always false', () {
      final result = PremiumEntitlementService.isDeveloperPremiumAccessEnabled(
        isDebugOverride: false,
        isReleaseOverride: false,
      );

      expect(result, isFalse);
    });

    // ── Test 9: Release build cannot read the override flag ──────────────────
    test('Release build cannot read developer override regardless of stored state', () {
      // Simulate: developer turns override ON in debug
      PremiumEntitlementService.setDeveloperPremiumAccess(
        true,
        isDebugOverride: true,
        isReleaseOverride: false,
      );

      // Verify it's ON in debug
      expect(
        PremiumEntitlementService.isDeveloperPremiumAccessEnabled(
          isDebugOverride: true,
          isReleaseOverride: false,
        ),
        isTrue,
      );

      // Same state, but checked as release → must be false
      expect(
        PremiumEntitlementService.isDeveloperPremiumAccessEnabled(
          isDebugOverride: false,
          isReleaseOverride: true,
        ),
        isFalse,
      );
    });
  });

  group('Developer Premium Access — No UID Dependency', () {
    setUp(() {
      PremiumEntitlementService.resetDeveloperOverrideForTesting();
    });

    test('Override works without any UID (null uid)', () async {
      final isPremium = await PremiumEntitlementService.isPremiumEnabled(
        uid: null,
        isDebugMode: true,
        isReleaseMode: false,
      );

      expect(isPremium, isTrue);
    });

    test('Override works with any UID', () async {
      final isPremium = await PremiumEntitlementService.isPremiumEnabled(
        uid: 'any_random_user_123',
        isDebugMode: true,
        isReleaseMode: false,
      );

      expect(isPremium, isTrue);
    });

    test('Override works with empty UID', () async {
      final isPremium = await PremiumEntitlementService.isPremiumEnabled(
        uid: '',
        isDebugMode: true,
        isReleaseMode: false,
      );

      expect(isPremium, isTrue);
    });
  });
}
