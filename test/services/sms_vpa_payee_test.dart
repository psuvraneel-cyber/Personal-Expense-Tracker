import 'package:flutter_test/flutter_test.dart';
import 'package:pet/services/sms_parser/self_consistency_checker.dart';
import 'package:pet/services/sms_parser/sms_parser.dart';
import 'package:pet/services/transaction_parser.dart';

/// Payee extraction for "from own account … to VPA id (NAME)" SMS.
///
/// The account after "debited from" is the user's own; the counterparty is
/// the party after "to VPA" (debit) or "from VPA" (credit), with the
/// bracketed name preferred over the UPI ID.
void main() {
  final date = DateTime(2026, 11, 2);

  /// Merchant and UPI ID as [ClassificationRuleEngine] would see them.
  ({String? merchant, String? upiId}) consensus(String body, String sender) {
    final r = SelfConsistencyChecker.check(
      body: body,
      sender: sender,
      timestamp: date,
    ).result;
    expect(r.isTransaction, isTrue, reason: body);
    return (merchant: r.merchant, upiId: r.upiId);
  }

  group('VPA payee — bracketed name preferred', () {
    const hdfcDebit =
        'Rs 450.00 debited from HDFC Bank A/c XX1234 on 02-Nov-26 to VPA '
        'sharmakirana@okbizaxis (SHARMA KIRANA STORE). UPI Ref 512345678901. '
        'Avl Bal Rs 25550.00';
    const upiCredit =
        'Rs 1,200.00 credited to HDFC Bank A/c XX1234 on 02-Nov-26 from VPA '
        '9876543210@ybl (RAHUL SHARMA). UPI Ref 512345678902.';

    test('debit: payee is the name after "to VPA", not own account', () {
      final r = consensus(hdfcDebit, 'JM-HDFCBK-S');
      expect(r.merchant, 'SHARMA KIRANA STORE');
      expect(r.upiId, 'sharmakirana@okbizaxis');
    });

    test('credit: payer is the name after "from VPA", not the UPI ID', () {
      final r = consensus(upiCredit, 'JM-HDFCBK-S');
      expect(r.merchant, 'RAHUL SHARMA');
      expect(r.upiId, '9876543210@ybl');
    });

    test('modular parser picks the payee', () {
      final r = SmsTransactionParser.parse(
        body: hdfcDebit,
        sender: 'JM-HDFCBK-S',
        timestamp: date,
      );
      expect(r.direction, TransactionDirection.debit);
      expect(r.amount, 450.0);
      expect(r.merchant, 'SHARMA KIRANA STORE');
      expect(r.upiId, 'sharmakirana@okbizaxis');
      expect(r.accountTail, '1234');
    });

    test('legacy parser picks the payee', () {
      final debit = TransactionParser.parse(hdfcDebit, 'JM-HDFCBK-S', date);
      expect(debit!.merchantName, 'SHARMA KIRANA STORE');
      expect(debit.upiId, 'sharmakirana@okbizaxis');

      final credit = TransactionParser.parse(upiCredit, 'JM-HDFCBK-S', date);
      expect(credit!.merchantName, 'RAHUL SHARMA');
      expect(credit.upiId, '9876543210@ybl');
    });

    test('VPA without a name keeps the UPI ID as payee', () {
      final r = consensus(
        'Rs 450.00 debited from HDFC Bank A/c XX1234 on 02-Nov-26 to VPA '
            'sharmakirana@okbizaxis. UPI Ref 512345678901.',
        'JM-HDFCBK-S',
      );
      expect(r.merchant, 'sharmakirana@okbizaxis');
      expect(r.upiId, 'sharmakirana@okbizaxis');
    });

    test('extractVpaPayee respects direction', () {
      expect(
        EntityExtractor.extractVpaPayee(hdfcDebit, 'credit'),
        isNull,
        reason: '"to VPA" is the payee of a debit, not the payer of a credit',
      );
      expect(
        EntityExtractor.extractVpaPayee(upiCredit, 'credit'),
        (vpa: '9876543210@ybl', name: 'RAHUL SHARMA'),
      );
    });
  });

  group('Existing bank formats — no regression', () {
    test('HDFC "to VPA merchant@upi on"', () {
      final r = consensus(
        'Rs 500.00 has been debited from account *1234 to VPA merchant@upi '
            'on 13-02-26. UPI Ref No 412345678901. If not done by you call '
            'on 18002586161.',
        'AD-HDFCBK',
      );
      expect(r.merchant, 'merchant@upi');
      expect(r.upiId, 'merchant@upi');
    });

    test('BOB "Dr. … Cr. to VPA"', () {
      final r = consensus(
        'Rs.250.00 Dr. from A/C XXXXXX2170 and Cr. to grocer@ybl. '
            'Ref:412345678901. AvlBal:Rs1,000.00(2026:02:13 10:15:30) - '
            'Bank of Baroda',
        'AD-BOBTXN',
      );
      expect(r.merchant, 'grocer@ybl');
      expect(r.upiId, 'grocer@ybl');
    });

    test('ICICI "for UPI-merchant"', () {
      final r = consensus(
        'ICICI Bank Acct XX123 debited for Rs 750.00 on 13-Feb-26; '
            'Swiggy credited. UPI:412345678903. Call 18002662 for dispute.',
        'AD-ICICIB',
      );
      expect(r.merchant, isNot(contains('XX123')));
    });

    test('GPay "You paid ₹X to Merchant"', () {
      final r = consensus(
        'You paid ₹320 to Zomato. UPI transaction ID 412345678904.',
        'AD-GOOGPY',
      );
      expect(r.merchant, 'Zomato');
    });

    test('SBI "by transfer to"', () {
      final r = consensus(
        'Dear Customer, Your A/c X5678 debited by Rs.1000.00 on 13Feb26 by '
            'transfer to RAMESH KUMAR. Ref No 412345678905 -SBI',
        'AD-SBIINB',
      );
      expect(r.merchant, 'RAMESH KUMAR');
    });

    test('Credit "from friend@ybl" without VPA keyword', () {
      final r = consensus(
        'Rs 1,500.00 credited to A/C XX2170 from friend@ybl. '
            'UPI Ref: 445566778899. AvlBal:Rs 4,539.55. Bank of Baroda.',
        'AD-BOBRDA',
      );
      expect(r.merchant, 'friend@ybl');
      expect(r.upiId, 'friend@ybl');
    });
  });
}
