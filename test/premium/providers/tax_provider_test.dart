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
      expect(provider.limits['HRA'], equals(100000.0));
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
  });
}
