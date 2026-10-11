import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:pet/premium/screens/purchase_screen.dart';
import 'package:pet/services/remote_config_service.dart';

void main() {
  tearDown(() => RemoteConfigService.debugOverride = null);

  void serve(Map<String, Object?> values) =>
      RemoteConfigService.debugOverride = (key) => values[key];

  test('uses bundled defaults when nothing is served', () {
    serve({});
    expect(RemoteConfigService.paywallHeadline, 'Unlock P.E.T Premium');
    expect(RemoteConfigService.paywallDefaultPlan, 'annual');
    expect(RemoteConfigService.reviewAutoImportThreshold, 10);
  });

  test('applies valid served values', () {
    serve({
      RemoteConfigService.kPaywallHeadline: '  Go Premium  ',
      RemoteConfigService.kPaywallSubtitle: 'Know where every rupee goes.',
      RemoteConfigService.kPaywallDefaultPlan: 'Monthly',
      RemoteConfigService.kReviewAutoImportThreshold: '15',
    });
    expect(RemoteConfigService.paywallHeadline, 'Go Premium');
    expect(RemoteConfigService.paywallSubtitle, 'Know where every rupee goes.');
    expect(RemoteConfigService.paywallDefaultPlan, 'monthly');
    expect(RemoteConfigService.reviewAutoImportThreshold, 15);
  });

  test('rejects bad console values instead of breaking the paywall', () {
    serve({
      RemoteConfigService.kPaywallHeadline: '',
      RemoteConfigService.kPaywallSubtitle: 'x' * 500,
      RemoteConfigService.kPaywallDefaultPlan: 'weekly',
      RemoteConfigService.kReviewAutoImportThreshold: 'lots',
    });
    expect(RemoteConfigService.paywallHeadline,
        RemoteConfigService.defaults[RemoteConfigService.kPaywallHeadline]);
    expect(RemoteConfigService.paywallSubtitle,
        RemoteConfigService.defaults[RemoteConfigService.kPaywallSubtitle]);
    expect(RemoteConfigService.paywallDefaultPlan, 'annual');
    expect(RemoteConfigService.reviewAutoImportThreshold, 10);
  });

  test('clamps the review threshold to a sane range', () {
    serve({RemoteConfigService.kReviewAutoImportThreshold: 1});
    expect(RemoteConfigService.reviewAutoImportThreshold, 3);
    serve({RemoteConfigService.kReviewAutoImportThreshold: 1000});
    expect(RemoteConfigService.reviewAutoImportThreshold, 50);
  });

  group('defaultPackageIndex', () {
    const types = [
      PackageType.monthly,
      PackageType.annual,
      PackageType.lifetime,
    ];

    test('selects the configured plan', () {
      expect(defaultPackageIndex(types, 'annual'), 1);
      expect(defaultPackageIndex(types, 'monthly'), 0);
      expect(defaultPackageIndex(types, 'lifetime'), 2);
    });

    test('falls back to the first package', () {
      expect(defaultPackageIndex(types, 'first'), 0);
      expect(defaultPackageIndex([PackageType.monthly], 'annual'), 0);
    });
  });
}
