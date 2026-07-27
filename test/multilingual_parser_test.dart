import 'package:flutter_test/flutter_test.dart';
import 'package:pet/services/sms_parser/sms_parser.dart';

void main() {
  group('Multilingual & Unicode Parser — Reproduction of Hindi Word Boundary Bug', () {
    test('Hindi Credit 1: Pure Hindi जमा (Jama) in bank SMS', () {
      final r = SmsTransactionParser.parse(
        body: 'आपके खाता में ₹1,000.00 जमा किया गया है। UPI Ref: 9876543210. SBI',
        sender: 'AD-SBIINB',
        timestamp: DateTime(2026, 7, 15),
      );

      expect(r.isTransaction, isTrue, reason: 'Hindi credit SMS with जमा should be detected as a transaction');
      expect(r.direction, TransactionDirection.credit, reason: 'जमा indicates credit intent');
      expect(r.amount, 1000.0);
    });

    test('Hindi Credit 2: Hindi प्राप्ति / वापसी (Refund / Credit)', () {
      final r = SmsTransactionParser.parse(
        body: 'खाते XX1111 में ₹500.00 की वापसी हुई है। Ref: 1122334455. PNB',
        sender: 'AD-PNBSMS',
        timestamp: DateTime(2026, 7, 15),
      );

      expect(r.isTransaction, isTrue, reason: 'Hindi refund SMS with वापसी should be detected');
      expect(r.direction, TransactionDirection.credit, reason: 'वापसी indicates credit/refund intent');
      expect(r.amount, 500.0);
    });

    test('Hindi Debit 1: Pure Hindi नामे (Naame) in bank SMS', () {
      final r = SmsTransactionParser.parse(
        body: 'आपके खाता से ₹750.00 नामे किया गया है। UPI Ref: 1234567890. PNB',
        sender: 'AD-PNBSMS',
        timestamp: DateTime(2026, 7, 15),
      );

      expect(r.isTransaction, isTrue, reason: 'Hindi debit SMS with नामे should be detected as a transaction');
      expect(r.direction, TransactionDirection.debit, reason: 'नामे indicates debit intent');
      expect(r.amount, 750.0);
    });

    test('Hindi Debit 2: Pure Hindi भुगतान / कटौती (Bhugtan / Katauti)', () {
      final r = SmsTransactionParser.parse(
        body: '₹350.00 का भुगतान सफ़ल रहा। UPI Ref: 4433221100',
        sender: 'AD-BOBSMS',
        timestamp: DateTime(2026, 7, 15),
      );

      expect(r.isTransaction, isTrue, reason: 'Hindi payment SMS with भुगतान should be detected');
      expect(r.direction, TransactionDirection.debit, reason: 'भुगतान indicates debit intent');
      expect(r.amount, 350.0);
    });

    test('Hindi Debit 3: खाते से (Khate se)', () {
      final r = SmsTransactionParser.parse(
        body: 'खाते से ₹1,200.00 की निकासी की गई। Ref: 9988776655',
        sender: 'AD-UNIONB',
        timestamp: DateTime(2026, 7, 15),
      );

      expect(r.isTransaction, isTrue, reason: 'Hindi withdrawal SMS with खाते से / निकासी should be detected');
      expect(r.direction, TransactionDirection.debit, reason: 'निकासी indicates debit intent');
      expect(r.amount, 1200.0);
    });

    test('Edge Case: Trailing ₹ symbol after intent keyword', () {
      final r = SmsTransactionParser.parse(
        body: 'sent ₹ 500.00 to merchant@upi Ref 1234567890',
        sender: 'AD-HDFCBK',
        timestamp: DateTime(2026, 7, 15),
      );

      expect(r.isTransaction, isTrue, reason: 'sent ₹ should be detected as debit');
      expect(r.direction, TransactionDirection.debit);
      expect(r.amount, 500.0);
    });
  });

  group('Unicode Formatting & Robustness Edge Cases', () {
    test('Non-breaking space (U+00A0) in amount and intent', () {
      final r = SmsTransactionParser.parse(
        body: 'INR\u00A02,500.00\u00A0credited to A/c XX1234. Ref: 1234567890',
        sender: 'AD-HDFCBK',
        timestamp: DateTime(2026, 7, 15),
      );

      expect(r.isTransaction, isTrue);
      expect(r.direction, TransactionDirection.credit);
      expect(r.amount, 2500.0);
    });

    test('Zero-width spaces (U+200B) inside SMS body', () {
      final r = SmsTransactionParser.parse(
        body: 'Rs\u200B500\u200Bdebited from A/c XX1234 on 15-Jul-2026. Ref: 1234567890',
        sender: 'AD-ICICIB',
        timestamp: DateTime(2026, 7, 15),
      );

      expect(r.isTransaction, isTrue);
      expect(r.direction, TransactionDirection.debit);
      expect(r.amount, 500.0);
    });

    test('RTL markers and Emoji in SMS body do not crash or alter amount', () {
      final r = SmsTransactionParser.parse(
        body: '\u200ERs 1,200 💸 debited from A/c XX9999 for Swiggy 🍔. Ref: 5566778899',
        sender: 'AD-AXISBK',
        timestamp: DateTime(2026, 7, 15),
      );

      expect(r.isTransaction, isTrue);
      expect(r.direction, TransactionDirection.debit);
      expect(r.amount, 1200.0);
    });
  });
}
