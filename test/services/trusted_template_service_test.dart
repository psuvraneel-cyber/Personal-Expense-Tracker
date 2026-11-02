import 'package:flutter_test/flutter_test.dart';
import 'package:pet/services/sms_service.dart';
import 'package:pet/services/trusted_template_service.dart';

void main() {
  String hash(String sender, String text,
          {bool isIncome = false, String? payee}) =>
      TrustedTemplateService.hashFor(
          sender: sender, isIncome: isIncome, text: text, payee: payee);

  group('message shape', () {
    test('amounts, dates, refs, accounts and UPI IDs do not matter', () {
      const a = 'Rs 450.00 debited from A/c XX1234 on 24-Aug-26 to VPA '
          'shop1@ybl. UPI Ref 412345678901.';
      const b = 'Rs 1,299.50 debited from A/c XX1234 on 03-Sep-26 to VPA '
          'q987654@paytm. UPI Ref 498765432100.';
      expect(hash('JM-HDFCBK-S', a), hash('JM-HDFCBK-S', b));
    });

    test('the payee name does not matter', () {
      expect(
        hash('JM-HDFCBK-S', 'Rs 500 credited by RAHUL SHARMA via UPI.',
            isIncome: true, payee: 'RAHUL SHARMA'),
        hash('JM-HDFCBK-S', 'Rs 900 credited by PRIYA S via UPI.',
            isIncome: true, payee: 'PRIYA S'),
      );
    });

    test('the operator prefix and type suffix of the sender do not matter', () {
      const t = 'Rs 450.00 debited from A/c XX1234.';
      expect(hash('JM-HDFCBK-S', t), hash('VK-HDFCBK', t));
      expect(hash('JM-HDFCBK-S', t), isNot(hash('JM-ICICIB-S', t)));
    });

    test('the stored (redacted) copy has the same shape as the raw text', () {
      const raw = 'Rs 450.00 debited from account 123456789012 to '
          '9876543210@ybl on 24 Aug. Ref 412345678901.';
      expect(hash('HDFCBK', SmsService.redactSensitiveData(raw)),
          hash('HDFCBK', raw));
    });

    test('money in and money out are different shapes', () {
      const t = 'Rs 450.00 transferred, A/c XX1234.';
      expect(hash('HDFCBK', t, isIncome: true),
          isNot(hash('HDFCBK', t, isIncome: false)));
    });

    test('different wording is a different shape', () {
      expect(
        hash('HDFCBK', 'Rs 450.00 debited from A/c XX1234.'),
        isNot(hash('HDFCBK', 'Get Rs 450 cashback on A/c XX1234 today!')),
      );
    });

    test('the shape keeps no numbers or names', () {
      final shape = TrustedTemplateService.shapeOf(
        'Rs 500 credited by RAHUL SHARMA (9876543210@ybl) on 24-Aug-26.',
        payee: 'RAHUL SHARMA',
      );
      expect(shape, isNot(contains(RegExp(r'\d'))));
      expect(shape, isNot(contains('rahul')));
    });
  });
}
