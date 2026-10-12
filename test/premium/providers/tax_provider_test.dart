import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pet/premium/providers/tax_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TaxProvider', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('initializes with default Indian IT Act statutory limits', () {
      final provider = TaxProvider();

      expect(provider.limits['80C'], equals(150000.0));
      expect(provider.limits['80D'], equals(25000.0));
      expect(provider.limits['80DP'], equals(25000.0));
      // HRA exemption is a formula the app can't compute: no fixed limit.
      expect(provider.limits['HRA'], equals(double.infinity));
      expect(provider.limits['LTA'], equals(20000.0));
      expect(provider.limits['80E'], equals(double.infinity));
    });

    test('updates editable limits and ignores 80E mutations', () async {
      final provider = TaxProvider();

      await provider.setLimit('80C', 200000.0);
      expect(provider.limits['80C'], equals(200000.0));

      await provider.setLimit('80E', 50000.0);
      // 80E should remain infinity
      expect(provider.limits['80E'], equals(double.infinity));
    });

    test('resets all limits back to statutory defaults', () async {
      final provider = TaxProvider();

      await provider.setLimit('80C', 300000.0);
      await provider.setLimit('80D', 50000.0);
      expect(provider.limits['80C'], equals(300000.0));

      await provider.resetToDefaults();
      expect(provider.limits['80C'], equals(150000.0));
      expect(provider.limits['80D'], equals(25000.0));
    });

    test('claimable caps each section and leaves out HRA', () {
      final claimable = TaxProvider.claimable(
        {'80C': 200000, '80D': 18000, 'HRA': 240000, '80E': 30000},
        TaxProvider.defaultLimits,
      );
      expect(claimable, 150000 + 18000 + 30000);
    });

    test('tax saving is estimated only under the old regime', () {
      expect(
          TaxProvider.estimatedSaving(
              claimable: 100000, regime: TaxRegime.oldRegime, slabRate: 0.20),
          closeTo(20800, 0.01)); // 20% + 4% cess
      expect(
          TaxProvider.estimatedSaving(
              claimable: 100000, regime: TaxRegime.newRegime, slabRate: 0.30),
          0);
      expect(
          TaxProvider.estimatedSaving(
              claimable: 100000, regime: null, slabRate: 0.30),
          0);
    });

    test('regime and slab choices persist', () async {
      final provider = TaxProvider();
      expect(provider.regime, isNull);
      await provider.setRegime(TaxRegime.oldRegime);
      await provider.setSlabRate(0.30);
      await provider.setSlabRate(0.99); // not a slab: ignored

      final reloaded = TaxProvider();
      await Future<void>.delayed(Duration.zero);
      expect(reloaded.regime, TaxRegime.oldRegime);
      expect(reloaded.slabRate, 0.30);
    });
  });
}
