import 'package:flutter_test/flutter_test.dart';
import 'package:pet/services/sms_parser/entity_extractor.dart';
import 'package:pet/services/sms_parser/self_consistency_checker.dart';
import 'package:pet/services/transaction_parser.dart';

void main() {
  final timestamp = DateTime(2026, 10, 5, 12, 0);

  group('merchant identity safety', () {
    test('reference-like tokens are not display merchant names', () {
      for (final value in [
        'Q900000001',
        'Q900000002',
        '9000000001 1',
        '04:41 PM',
      ]) {
        expect(EntityExtractor.isUsableMerchantName(value), isFalse,
            reason: value);
      }
    });

    test('real merchant names with small numeric parts remain usable', () {
      expect(EntityExtractor.isUsableMerchantName('7-Eleven'), isTrue);
      expect(
          EntityExtractor.isUsableMerchantName('Sharma Kirana Store'), isTrue);
    });

    test('numeric UPI identifiers remain evidence but not merchant labels', () {
      const body = 'Rs 500 debited from A/c XX1234 to VPA '
          '9876543210@ybl on 05-Oct-26. UPI Ref 412345678901.';
      final modular = SelfConsistencyChecker.check(
        body: body,
        sender: 'AD-HDFCBK',
        timestamp: timestamp,
      ).result;
      final legacy = TransactionParser.parse(body, 'AD-HDFCBK', timestamp);

      expect(modular.upiId, '9876543210@ybl');
      expect(modular.merchant, 'Unknown');
      expect(legacy, isNotNull);
      expect(legacy!.upiId, '9876543210@ybl');
      expect(legacy.merchantName, 'Unknown');
    });

    test('a named VPA payee is preserved', () {
      final result = SelfConsistencyChecker.check(
        body: 'Rs 450 debited from A/c XX1234 to VPA '
            'shop@okaxis (SHARMA KIRANA STORE) on 05-Oct-26. '
            'UPI Ref 512345678901.',
        sender: 'AD-HDFCBK',
        timestamp: timestamp,
      ).result;
      expect(result.merchant, 'SHARMA KIRANA STORE');
      expect(result.upiId, 'shop@okaxis');
    });
  });
}
