import 'package:flutter_test/flutter_test.dart';
import 'package:pet/services/sms_parser/sms_transaction_parser.dart';
import 'package:pet/services/sms_parser/transaction_parse_result.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('INVESTMENT-GRADE PARSER FIX: Credit Card & Reminder Parser Tests', () {
    // ═════════════════════════════════════════════════════════════════
    //  SECTION 1: LEGITIMATE BANK TRANSACTIONS WITH REMINDER FOOTERS
    // ═════════════════════════════════════════════════════════════════

    test('1. HDFC Credit Card Txn with "Pay your bill by" footer is ACCEPTED', () {
      final body =
          'Rs 1,250.00 debited from HDFC Bank Credit Card xx1234 at SWIGGY on 25-JUL-26. '
          'Total Available Limit: Rs 45,000. Pay your bill by 10-AUG-26 to avoid charges.';
      final r = SmsTransactionParser.parse(
        body: body,
        sender: 'AD-HDFCBK',
        timestamp: DateTime(2026, 7, 25),
      );

      expect(
        r.isTransaction,
        isTrue,
        reason: 'HDFC CC Txn must not be rejected by reminder footer',
      );
      expect(r.direction, TransactionDirection.debit);
      expect(r.amount, equals(1250.0));
      expect(r.merchant, equals('SWIGGY'));
    });

    test(
      '2. ICICI Credit Card Txn with "Pay your credit card bill by" footer is ACCEPTED',
      () {
        final body =
            'Rs 3,490.00 spent on your ICICI Bank Credit Card xx9876 on 24-Jul-26 at AMAZON. '
            'Pay your credit card bill by 15-Aug-26.';
        final r = SmsTransactionParser.parse(
          body: body,
          sender: 'AD-ICICIB',
          timestamp: DateTime(2026, 7, 24),
        );

        expect(r.isTransaction, isTrue);
        expect(r.direction, TransactionDirection.debit);
        expect(r.amount, equals(3490.0));
      },
    );

    test(
      '3. Axis Bank Card Txn with "Please pay your bill by" footer is ACCEPTED',
      () {
        final body =
            'INR 850.00 debited from Axis Bank Card 5678 at ZOMATO on 24-07-26. '
            'Total Dues: Rs 850. Please pay your bill by 05-Aug-26.';
        final r = SmsTransactionParser.parse(
          body: body,
          sender: 'AD-AXISBK',
          timestamp: DateTime(2026, 7, 24),
        );

        expect(r.isTransaction, isTrue);
        expect(r.amount, equals(850.0));
      },
    );

    test('4. SBI Card Txn with "Pay your bill before" footer is ACCEPTED', () {
      final body =
          'Txn of Rs. 4,500.00 spent on SBI Card 4321 on 25-Jul-26 at RELIANCE DIGITAL. '
          'Min Amt Due: Rs 225. Pay your bill before 12-Aug-26.';
      final r = SmsTransactionParser.parse(
        body: body,
        sender: 'AD-SBICRD',
        timestamp: DateTime(2026, 7, 25),
      );

      expect(r.isTransaction, isTrue);
      expect(r.amount, equals(4500.0));
    });

    test(
      '5. PNB Credit Card Txn with "Pay your dues by" footer is ACCEPTED',
      () {
        final body =
            'Rs 1,500.00 debited from PNB Credit Card xx8899 on 25-07-26. '
            'Pay your dues by 14-Aug-26.';
        final r = SmsTransactionParser.parse(
          body: body,
          sender: 'AD-PNBSMS',
          timestamp: DateTime(2026, 7, 25),
        );

        expect(r.isTransaction, isTrue);
        expect(r.amount, equals(1500.0));
      },
    );

    test('6. Bank of Baroda (BOB) CC Txn with reminder footer is ACCEPTED', () {
      final body =
          'Rs 2,100.00 debited from BOB Credit Card xx6543 on 24-07-26 at D-MART. '
          'Pay your bill by 08-Aug-26.';
      final r = SmsTransactionParser.parse(
        body: body,
        sender: 'AD-BOBTXN',
        timestamp: DateTime(2026, 7, 24),
      );

      expect(r.isTransaction, isTrue);
      expect(r.amount, equals(2100.0));
    });

    test(
      '7. Kotak Mahindra CC Txn with "Pay your bill by" footer is ACCEPTED',
      () {
        final body =
            'Rs 750.00 spent on Kotak Credit Card xx3322 at PVR CINEMAS on 25-Jul-26. '
            'Pay your bill by 18-Aug-26.';
        final r = SmsTransactionParser.parse(
          body: body,
          sender: 'AD-KOTAKB',
          timestamp: DateTime(2026, 7, 25),
        );

        expect(r.isTransaction, isTrue);
        expect(r.amount, equals(750.0));
      },
    );

    test('8. IndusInd Bank CC Txn with reminder footer is ACCEPTED', () {
      final body =
          'Rs 5,200.00 charged on IndusInd Bank Credit Card xx7711 at Croma on 24-Jul-26. '
          'Pay your bill by 22-Aug-26.';
      final r = SmsTransactionParser.parse(
        body: body,
        sender: 'AD-INDUSN',
        timestamp: DateTime(2026, 7, 24),
      );

      expect(r.isTransaction, isTrue);
      expect(r.amount, equals(5200.0));
    });

    test('9. AU Small Finance Bank CC Txn with reminder footer is ACCEPTED', () {
      final body =
          'Rs 1,100.00 debited from AU Bank Credit Card xx4455 on 25-Jul-26 at Shell. '
          'Pay your bill by 11-Aug-26.';
      final r = SmsTransactionParser.parse(
        body: body,
        sender: 'AD-AUBANK',
        timestamp: DateTime(2026, 7, 25),
      );

      expect(r.isTransaction, isTrue);
      expect(r.amount, equals(1100.0));
    });

    test('10. Federal Bank CC Txn with reminder footer is ACCEPTED', () {
      final body =
          'Rs 890.00 spent using Federal Bank Card xx9988 at Swiggy on 25-Jul-26. '
          'Pay your bill by 15-Aug-26.';
      final r = SmsTransactionParser.parse(
        body: body,
        sender: 'AD-FEDBNK',
        timestamp: DateTime(2026, 7, 25),
      );

      expect(r.isTransaction, isTrue);
      expect(r.amount, equals(890.0));
    });

    test('11. Yes Bank CC Txn with reminder footer is ACCEPTED', () {
      final body =
          'INR 3,200.00 debited on Yes Bank Credit Card xx1144 at Flipkart on 24-Jul-26. '
          'Pay your bill by 16-Aug-26.';
      final r = SmsTransactionParser.parse(
        body: body,
        sender: 'AD-YESBNK',
        timestamp: DateTime(2026, 7, 24),
      );

      expect(r.isTransaction, isTrue);
      expect(r.amount, equals(3200.0));
    });

    test('12. IDFC FIRST Bank CC Txn with reminder footer is ACCEPTED', () {
      final body =
          'Rs 2,450.00 spent on IDFC FIRST Bank Credit Card xx5566 on 25-Jul-26 at Myntra. '
          'Pay your bill by 19-Aug-26.';
      final r = SmsTransactionParser.parse(
        body: body,
        sender: 'AD-IDFCFB',
        timestamp: DateTime(2026, 7, 25),
      );

      expect(r.isTransaction, isTrue);
      expect(r.amount, equals(2450.0));
    });

    test('13. Canara Bank CC Txn with reminder footer is ACCEPTED', () {
      final body =
          'Rs 1,800.00 debited from Canara Bank Card xx2233 on 25-Jul-26. '
          'Pay your bill by 12-Aug-26.';
      final r = SmsTransactionParser.parse(
        body: body,
        sender: 'AD-CANBNK',
        timestamp: DateTime(2026, 7, 25),
      );

      expect(r.isTransaction, isTrue);
      expect(r.amount, equals(1800.0));
    });

    test('14. Union Bank of India CC Txn with reminder footer is ACCEPTED', () {
      final body =
          'Rs 950.00 debited from Union Bank Card xx6677 at BigBasket on 24-Jul-26. '
          'Pay your bill by 14-Aug-26.';
      final r = SmsTransactionParser.parse(
        body: body,
        sender: 'AD-UNIONB',
        timestamp: DateTime(2026, 7, 24),
      );

      expect(r.isTransaction, isTrue);
      expect(r.amount, equals(950.0));
    });

    // ═════════════════════════════════════════════════════════════════
    //  SECTION 2: PURE BILL / EMI REMINDERS (MUST BE REJECTED)
    // ═════════════════════════════════════════════════════════════════

    test('15. Pure HDFC Bill Reminder is REJECTED', () {
      final body =
          'Dear Customer, HDFC Bank Credit Card XX1234 bill of Rs 15,400.00 is due on 10-AUG-26. '
          'Pay your bill by 10-AUG-26 to avoid late payment charges.';
      final r = SmsTransactionParser.parse(
        body: body,
        sender: 'AD-HDFCBK',
        timestamp: DateTime(2026, 7, 25),
      );

      expect(
        r.isTransaction,
        isFalse,
        reason: 'Pure reminder must be rejected',
      );
      expect(r.reasons.first, contains('reminder_filter'));
    });

    test('16. Pure ICICI Card Payment Reminder is REJECTED', () {
      final body =
          'Reminder: Payment of Rs 12,300.00 on ICICI Bank Credit Card XX9876 is due on 15-AUG-26. '
          'Please pay your bill on or before due date.';
      final r = SmsTransactionParser.parse(
        body: body,
        sender: 'AD-ICICIB',
        timestamp: DateTime(2026, 7, 25),
      );

      expect(r.isTransaction, isFalse);
    });

    test('17. Pure Axis Bank Due Reminder is REJECTED', () {
      final body =
          'Reminder: Rs 8,500.00 is due on your Axis Bank Credit Card 5678 on 05-AUG-26. '
          'Pay your dues to avoid interest.';
      final r = SmsTransactionParser.parse(
        body: body,
        sender: 'AD-AXISBK',
        timestamp: DateTime(2026, 7, 25),
      );

      expect(r.isTransaction, isFalse);
    });

    test('18. Pure SBI Card Bill Due SMS is REJECTED', () {
      final body =
          'Dear Cardholder, your SBI Card XX4321 Total Dues: Rs 4,500.00, Min Amt Due: Rs 225.00 is due on 12-AUG-26.';
      final r = SmsTransactionParser.parse(
        body: body,
        sender: 'AD-SBICRD',
        timestamp: DateTime(2026, 7, 25),
      );

      expect(r.isTransaction, isFalse);
    });

    test('19. Pure Loan EMI Overdue Notice is REJECTED', () {
      final body =
          'Loan Overdue: Your EMI of Rs 6,500 for Loan A/c XX8899 is overdue. Please pay immediately.';
      final r = SmsTransactionParser.parse(
        body: body,
        sender: 'AD-PNBSMS',
        timestamp: DateTime(2026, 7, 25),
      );

      expect(r.isTransaction, isFalse);
    });

    // ═════════════════════════════════════════════════════════════════
    //  SECTION 3: OTP AND PROMOTIONAL PRESERVATION
    // ═════════════════════════════════════════════════════════════════

    test(
      '20. OTP SMS containing transaction amount is STILL REJECTED by otp_filter',
      () {
        final body =
            'Your HDFC Bank OTP is 482910 for transaction of Rs 1,250.00 at SWIGGY. '
            'Do not share OTP with anyone. Pay your bill by 10-AUG-26.';
        final r = SmsTransactionParser.parse(
          body: body,
          sender: 'AD-HDFCBK',
          timestamp: DateTime(2026, 7, 25),
        );

        expect(r.isTransaction, isFalse);
        expect(r.reasons.first, contains('otp_filter'));
      },
    );

    test('21. Promotional Loan Offer is STILL REJECTED', () {
      final body =
          'Pre-approved personal loan of Rs 5,00,000 available at 10.5% interest rate. '
          'Apply now or pay your bill by 30-Jul.';
      final r = SmsTransactionParser.parse(
        body: body,
        sender: 'AD-HDFCBK',
        timestamp: DateTime(2026, 7, 25),
      );

      expect(r.isTransaction, isFalse);
      expect(r.reasons.first, contains('REJECTED'));
    });

    test('22. Promotional Contest Scam is STILL REJECTED', () {
      final body =
          'Congratulations! You have won Rs 50,000 in HDFC Lucky Draw. '
          'Claim your prize now before 10-AUG-26.';
      final r = SmsTransactionParser.parse(
        body: body,
        sender: 'VK-HDFCBK',
        timestamp: DateTime(2026, 7, 25),
      );

      expect(r.isTransaction, isFalse);
      expect(r.reasons.first, contains('REJECTED'));
    });
  });
}
