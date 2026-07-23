import 'package:flutter_test/flutter_test.dart';
import 'package:pet/services/sms_parser/self_consistency_checker.dart';
import 'package:pet/services/sms_parser/sms_parser.dart';

/// Comprehensive test suite for the production-grade SMS transaction parser.
///
/// Covers:
/// - 20+ labeled SMS examples (positive and negative)
/// - All Indian bank variants (HDFC, SBI, ICICI, Axis, Kotak, PNB, etc.)
/// - UPI apps (Google Pay, PhonePe, Paytm, BHIM, Amazon Pay)
/// - Negative filter rejection (OTP, promo, scam, loan, KYC, reminder)
/// - Intent detection edge cases
/// - Confidence scoring thresholds
/// - Amount extraction variants
/// - Entity extraction (merchant, bank, ref, UPI ID, date)
/// - User feedback store
/// - Deduplication and batch parsing
///
/// Each test asserts:
/// - isTransaction / isUncertain / rejection
/// - direction (debit/credit)
/// - amount
/// - confidence above/below expected thresholds
void main() {
  // ═════════════════════════════════════════════════════════════════
  //  LABELED SMS DATASET — TRANSACTIONS
  // ═════════════════════════════════════════════════════════════════

  group('Labeled Dataset — TRANSACTION (CREDIT)', () {
    // 1) "INR 2,750.00 credited to A/c XX1234 on 13-Feb-2026. UPI Ref: 1234567890. HDFC Bank"
    //    → TRANSACTION, CREDIT, amount=2750, ref=1234567890
    test('Case 1: HDFC credit via UPI', () {
      final r = SmsTransactionParser.parse(
        body:
            'INR 2,750.00 credited to A/c XX1234 on 13-Feb-2026. UPI Ref: 1234567890. HDFC Bank',
        sender: 'AD-HDFCBK',
        timestamp: DateTime(2026, 2, 13),
      );

      expect(r.isTransaction, isTrue, reason: 'Should be a transaction');
      expect(r.direction, TransactionDirection.credit);
      expect(r.amount, 2750.0);
      expect(r.reference, '1234567890');
      expect(r.bank, 'HDFC Bank');
      expect(r.confidence, greaterThanOrEqualTo(55));
    });

    // 6) "IMPS credit of ₹2,000 to A/c XX1111 on 01-02-2026. Balance: ₹10,000."
    //    → TRANSACTION, CREDIT
    test('Case 6: IMPS credit with balance', () {
      final r = SmsTransactionParser.parse(
        body:
            'IMPS credit of ₹2,000 to A/c XX1111 on 01-02-2026. Balance: ₹10,000.',
        sender: 'AD-SBIINB',
        timestamp: DateTime(2026, 2, 1),
      );

      expect(r.isTransaction, isTrue);
      expect(r.direction, TransactionDirection.credit);
      expect(r.amount, 2000.0);
      // Amount should NOT be the balance (10,000)
      expect(r.amount, isNot(10000.0));
    });

    // 11) "A/c XX3456 credited through NEFT amount INR 5,000. Ref: NEFT123"
    //     → TRANSACTION, CREDIT
    test('Case 11: NEFT credit', () {
      final r = SmsTransactionParser.parse(
        body: 'A/c XX3456 credited through NEFT amount INR 5,000. Ref: NEFT123',
        sender: 'AD-HDFCBK',
        timestamp: DateTime(2026, 2, 13),
      );

      expect(r.isTransaction, isTrue);
      expect(r.direction, TransactionDirection.credit);
      expect(r.amount, 5000.0);
    });

    // 13) "Refund of ₹120 to A/c XX3333 for order #A12345"
    //     → TRANSACTION, CREDIT (refund)
    test('Case 13: Refund credited', () {
      final r = SmsTransactionParser.parse(
        body:
            'Refund of ₹120 credited to A/c XX3333 for order #A12345. HDFC Bank.',
        sender: 'AD-HDFCBK',
        timestamp: DateTime(2026, 2, 13),
      );

      expect(r.isTransaction, isTrue);
      expect(r.direction, TransactionDirection.credit);
      expect(r.amount, 120.0);
      expect(r.subType, TransactionSubType.refund);
    });
  });

  group('Labeled Dataset — TRANSACTION (DEBIT)', () {
    // 2) "Rs. 450.00 debited from A/c XX9876 on 14/02/2026. Ref: TXNID12345"
    //    → TRANSACTION, DEBIT, amount=450
    test('Case 2: Debit with Ref', () {
      final r = SmsTransactionParser.parse(
        body:
            'Rs. 450.00 debited from A/c XX9876 on 14/02/2026. Ref: TXNID12345',
        sender: 'AD-HDFCBK',
        timestamp: DateTime(2026, 2, 14),
      );

      expect(r.isTransaction, isTrue);
      expect(r.direction, TransactionDirection.debit);
      expect(r.amount, 450.0);
    });

    // 4) "PhonePe: ₹1,200 sent to merchant @paytm (Ref: UPI12345). Remaining balance ₹3,500."
    //    → TRANSACTION, DEBIT
    test('Case 4: PhonePe debit with balance', () {
      final r = SmsTransactionParser.parse(
        body:
            'PhonePe: ₹1,200 sent to merchant@paytm (Ref: UPI12345). Remaining balance ₹3,500.',
        sender: 'AD-PHONEPE',
        timestamp: DateTime(2026, 2, 13),
      );

      expect(r.isTransaction, isTrue);
      expect(r.direction, TransactionDirection.debit);
      expect(r.amount, 1200.0);
      // Amount should NOT be the balance
      expect(r.amount, isNot(3500.0));
    });

    // 8) "Payment of INR 350 paid using UPI to ELECTRICALS. Ref No: 987654"
    //    → TRANSACTION, DEBIT
    test('Case 8: UPI payment to merchant', () {
      final r = SmsTransactionParser.parse(
        body:
            'Payment of INR 350 paid using UPI to ELECTRICALS. Ref No: 987654',
        sender: 'AD-HDFCBK',
        timestamp: DateTime(2026, 2, 13),
      );

      expect(r.isTransaction, isTrue);
      expect(r.direction, TransactionDirection.debit);
      expect(r.amount, 350.0);
    });

    // 14) "Rs 99 paid to Zomato on 12-Feb-2026 via UPI"
    //     → TRANSACTION, DEBIT
    test('Case 14: Small UPI payment', () {
      final r = SmsTransactionParser.parse(
        body:
            'Rs 99 paid to Zomato on 12-Feb-2026 via UPI from HDFC Bank A/c XX1234.',
        sender: 'AD-HDFCBK',
        timestamp: DateTime(2026, 2, 12),
      );

      expect(r.isTransaction, isTrue);
      expect(r.direction, TransactionDirection.debit);
      expect(r.amount, 99.0);
    });
  });

  // ═════════════════════════════════════════════════════════════════
  //  LABELED SMS DATASET — NON-TRANSACTIONS
  // ═════════════════════════════════════════════════════════════════

  group('Labeled Dataset — NON-TRANSACTION', () {
    // 3) "Your OTP for HDFC bank is 123456. Do not share it."
    //    → NON-TRANSACTION (OTP)
    test('Case 3: OTP message rejected', () {
      final r = SmsTransactionParser.parse(
        body:
            'Your OTP for HDFC bank is 123456. Do not share it with anyone. Valid for 10 minutes.',
        sender: 'AD-HDFCBK',
        timestamp: DateTime(2026, 2, 13),
      );

      expect(r.isTransaction, isFalse);
      expect(r.isUncertain, isFalse);
      expect(r.reasons, anyElement(contains('OTP')));
    });

    // 5) "Congratulations! You have won ₹5000. Click http... to claim."
    //    → NON-TRANSACTION (scam/contest)
    test('Case 5: Scam/contest message rejected', () {
      final r = SmsTransactionParser.parse(
        body:
            'Congratulations! You have won ₹5000. Click http://claim.xyz to claim your prize now!',
        sender: 'VK-PROMO',
        timestamp: DateTime(2026, 2, 13),
      );

      expect(r.isTransaction, isFalse);
      expect(r.isUncertain, isFalse);
    });

    // 9) "Loan overdue reminder: Pay ₹15,000 by 20-Feb-2026"
    //    → NON-TRANSACTION (reminder)
    test('Case 9: Loan reminder rejected', () {
      final r = SmsTransactionParser.parse(
        body:
            'Loan overdue reminder: Pay ₹15,000 by 20-Feb-2026 to avoid penalty charges. HDFC Bank.',
        sender: 'AD-HDFCBK',
        timestamp: DateTime(2026, 2, 13),
      );

      expect(r.isTransaction, isFalse);
      expect(r.isUncertain, isFalse);
    });

    // 10) "VK-PAYTM: Get 20% cashback up to ₹100. Visit https://..."
    //     → NON-TRANSACTION (promo sender + promo content)
    test('Case 10: Promotional sender + content rejected', () {
      final r = SmsTransactionParser.parse(
        body:
            'VK-PAYTM: Get 20% cashback up to ₹100 on your next recharge. Visit https://paytm.com/offers',
        sender: 'VK-PAYTM',
        timestamp: DateTime(2026, 2, 13),
      );

      expect(r.isTransaction, isFalse);
      expect(r.isUncertain, isFalse);
    });

    // 12) "Your account balance is ₹1,234.56 as on 13-02-2026"
    //     → NON-TRANSACTION (balance only)
    test('Case 12: Balance-only SMS rejected', () {
      final r = SmsTransactionParser.parse(
        body:
            'Your HDFC Bank account balance is ₹1,234.56 as on 13-02-2026. Visit netbanking for details.',
        sender: 'AD-HDFCBK',
        timestamp: DateTime(2026, 2, 13),
      );

      // No debit/credit keyword → no intent → rejected
      expect(r.isTransaction, isFalse);
    });
  });

  // ═════════════════════════════════════════════════════════════════
  //  COLLECT REQUEST HANDLING
  // ═════════════════════════════════════════════════════════════════

  group('UPI Collect Request Handling', () {
    // 7a) "UPI collect request from Rahul for ₹250 accepted."
    //     → TRANSACTION, DEBIT (money left)
    test('Case 7a: Collect request accepted = DEBIT', () {
      final r = SmsTransactionParser.parse(
        body:
            'UPI collect request from Rahul for ₹250 accepted. Debited from A/c XX1234. HDFC Bank.',
        sender: 'AD-HDFCBK',
        timestamp: DateTime(2026, 2, 13),
      );

      expect(r.isTransaction, isTrue);
      expect(r.direction, TransactionDirection.debit);
      expect(r.amount, 250.0);
    });

    // 7b) "UPI collect request from Rahul for ₹250 received."
    //     → NON-TRANSACTION (pending, no money moved)
    test('Case 7b: Collect request pending = rejected', () {
      final r = SmsTransactionParser.parse(
        body:
            'UPI collect request received from Rahul for ₹250. Accept or decline in your UPI app.',
        sender: 'AD-HDFCBK',
        timestamp: DateTime(2026, 2, 13),
      );

      // Pending collect is not a completed transaction
      expect(r.isTransaction, isFalse);
    });

    test('Collect request declined = rejected', () {
      final r = SmsTransactionParser.parse(
        body:
            'UPI collect request from Merchant for ₹500 has been declined. HDFC Bank.',
        sender: 'AD-HDFCBK',
        timestamp: DateTime(2026, 2, 13),
      );

      expect(r.isTransaction, isFalse);
    });
  });

  // ═════════════════════════════════════════════════════════════════
  //  ADDITIONAL BANK-SPECIFIC FORMATS (15-20+)
  // ═════════════════════════════════════════════════════════════════

  group('Additional Bank-Specific SMS', () {
    // 15) SBI debit
    test('Case 15: SBI debit via UPI', () {
      final r = SmsTransactionParser.parse(
        body:
            'Your a/c no. XXXXXXXX1234 is debited by Rs.500.00 on 13Feb26 by transfer to merchant@upi-UPI Ref No 412345678901.',
        sender: 'AD-SBIINB',
        timestamp: DateTime(2026, 2, 13),
      );

      expect(r.isTransaction, isTrue);
      expect(r.direction, TransactionDirection.debit);
      expect(r.amount, 500.0);
      expect(r.bank, 'SBI');
    });

    // 16) ICICI credit
    test('Case 16: ICICI credit from UPI', () {
      final r = SmsTransactionParser.parse(
        body:
            'Dear Customer, Rs 1000.00 is credited to your ICICI Bank a/c XX5678 on 13-Feb-26 from UPI-person@okaxis. UPI Ref: 412345678901.',
        sender: 'AD-ICICIB',
        timestamp: DateTime(2026, 2, 13),
      );

      expect(r.isTransaction, isTrue);
      expect(r.direction, TransactionDirection.credit);
      expect(r.amount, 1000.0);
      expect(r.bank, 'ICICI Bank');
    });

    // 17) Axis Bank with UPI/Name/Ref/ID pattern
    test('Case 17: Axis Bank debit', () {
      final r = SmsTransactionParser.parse(
        body:
            'Rs.500 debited from A/c no. XX1234 on 13-Feb-26 for UPI/Swiggy/Ref/412345678901.',
        sender: 'AD-AXISBK',
        timestamp: DateTime(2026, 2, 13),
      );

      expect(r.isTransaction, isTrue);
      expect(r.direction, TransactionDirection.debit);
      expect(r.amount, 500.0);
      expect(r.bank, 'Axis Bank');
    });

    // 18) Kotak sent
    test('Case 18: Kotak sent via UPI', () {
      final r = SmsTransactionParser.parse(
        body:
            'Sent Rs.500.00 from Kotak Bank AC 1234 to merchant@upi on 13-02-26. UPI Ref 412345678901. Not you? Call 18602662666.',
        sender: 'AD-KOTAKB',
        timestamp: DateTime(2026, 2, 13),
      );

      expect(r.isTransaction, isTrue);
      expect(r.direction, TransactionDirection.debit);
      expect(r.amount, 500.0);
      expect(r.bank, 'Kotak Bank');
    });

    // 19) Google Pay payment
    test('Case 19: Google Pay debit', () {
      final r = SmsTransactionParser.parse(
        body:
            'You paid Rs.350 to Zomato Online Order. UPI transaction ID: 412345678903. Google Pay.',
        sender: 'AD-GPAY',
        timestamp: DateTime(2026, 2, 13),
      );

      expect(r.isTransaction, isTrue);
      expect(r.direction, TransactionDirection.debit);
      expect(r.amount, 350.0);
    });

    // 20) PhonePe received
    test('Case 20: PhonePe credit', () {
      final r = SmsTransactionParser.parse(
        body:
            'Rs.750 received from Rahul Kumar via PhonePe. UPI Ref: 412345678904. Credited to your bank account.',
        sender: 'AD-PHONEPE',
        timestamp: DateTime(2026, 2, 13),
      );

      expect(r.isTransaction, isTrue);
      expect(r.direction, TransactionDirection.credit);
      expect(r.amount, 750.0);
    });

    // 21) Paytm paid
    test('Case 21: Paytm debit', () {
      final r = SmsTransactionParser.parse(
        body:
            'You have paid Rs 200 to Amazon via UPI. Txn ID: 412345678905. Paytm.',
        sender: 'AD-PAYTM',
        timestamp: DateTime(2026, 2, 13),
      );

      expect(r.isTransaction, isTrue);
      expect(r.direction, TransactionDirection.debit);
      expect(r.amount, 200.0);
    });

    // 22) PNB debit
    test('Case 22: PNB debit', () {
      final r = SmsTransactionParser.parse(
        body:
            'Rs.500.00 debited from your PNB A/c XX1234 on 13-02-26. UPI Ref 412345678928. If not you, call 18001802222.',
        sender: 'AD-PNBSMS',
        timestamp: DateTime(2026, 2, 13),
      );

      expect(r.isTransaction, isTrue);
      expect(r.direction, TransactionDirection.debit);
      expect(r.amount, 500.0);
      expect(r.bank, 'PNB');
    });

    // 23) HDFC Info: Payment to pattern
    test('Case 23: HDFC Info payment pattern', () {
      final r = SmsTransactionParser.parse(
        body:
            'Rs 1250.00 debited from A/c *5678 on 13-02-26. Info: Payment to swiggy@paytm. UPI Ref No 412345678902.',
        sender: 'AD-HDFCBK',
        timestamp: DateTime(2026, 2, 13),
      );

      expect(r.isTransaction, isTrue);
      expect(r.direction, TransactionDirection.debit);
      expect(r.amount, 1250.0);
    });

    // 24) Cashback credited (should be CREDIT, not rejected as promo)
    test('Case 24: Cashback credited = valid CREDIT', () {
      final r = SmsTransactionParser.parse(
        body:
            'Cashback of Rs.50 credited to your HDFC Bank account XX1234. Enjoy your rewards!',
        sender: 'AD-HDFCBK',
        timestamp: DateTime(2026, 2, 13),
      );

      expect(r.isTransaction, isTrue);
      expect(r.direction, TransactionDirection.credit);
      expect(r.amount, 50.0);
      expect(r.subType, TransactionSubType.cashback);
    });

    // 25) Large lakh-format amount
    test('Case 25: Large amount in Indian notation', () {
      final r = SmsTransactionParser.parse(
        body:
            'Rs.1,00,000.50 debited from HDFC Bank A/c XX1234 on 13-02-26. UPI Ref 412345678909.',
        sender: 'AD-HDFCBK',
        timestamp: DateTime(2026, 2, 13),
      );

      expect(r.isTransaction, isTrue);
      expect(r.amount, 100000.50);
    });
  });

  // ═════════════════════════════════════════════════════════════════
  //  NEGATIVE FILTER TESTS
  // ═════════════════════════════════════════════════════════════════

  group('Negative Filter Module', () {
    test('OTP filter rejects verification code', () {
      final result = NegativeFilter.apply(
        'Your verification code for Rs 500 transaction is 123456. Valid for 5 minutes.',
        'AD-HDFCBK',
      );
      expect(result.rejected, isTrue);
      expect(result.filterName, 'otp_filter');
    });

    test('Scam filter rejects contest winner', () {
      final result = NegativeFilter.apply(
        'You have won a lucky draw prize of Rs 10,00,000. Call +91-9876543210 to claim your reward now.',
        'VK-PROMO',
      );
      expect(result.rejected, isTrue);
    });

    test('Loan filter rejects pre-approved offers', () {
      final result = NegativeFilter.apply(
        'Dear Customer, you are pre-approved for a personal loan of Rs 5,00,000 at 10.5% interest. Apply now.',
        'AD-HDFCBK',
      );
      expect(result.rejected, isTrue);
      expect(result.filterName, 'promo_keyword_filter');
    });

    test('KYC filter rejects update notice', () {
      final result = NegativeFilter.apply(
        'Dear Customer, your KYC update is pending. Complete it at the nearest HDFC Bank branch by 28-Feb-2026.',
        'AD-HDFCBK',
      );
      expect(result.rejected, isTrue);
      expect(result.filterName, 'kyc_update_filter');
    });

    test('URL filter rejects promotional links', () {
      final result = NegativeFilter.apply(
        'Exciting offer on credit cards! Get 5% cashback on all purchases. Click here https://hdfc.co/offer to apply.',
        'AD-HDFCBK',
      );
      expect(result.rejected, isTrue);
    });

    test('URL filter allows transaction SMS with URL', () {
      final result = NegativeFilter.apply(
        'Rs 500 debited from A/c XX1234 on 13-02-26. Ref 412345. If not you, visit https://hdfc.com/report',
        'AD-HDFCBK',
      );
      // Should pass because it has strong transaction evidence
      expect(result.rejected, isFalse);
    });

    test('Short message rejected', () {
      final result = NegativeFilter.apply('Rs 500 debited.', 'AD-HDFCBK');
      expect(result.rejected, isTrue);
      expect(result.filterName, 'length_check');
    });

    test('Mandate setup rejected', () {
      final result = NegativeFilter.apply(
        'Mandate creation successful for Rs 499/month towards Netflix. Auto-debit will start from 01-Mar-2026.',
        'AD-HDFCBK',
      );
      expect(result.rejected, isTrue);
      expect(result.filterName, 'mandate_setup_filter');
    });

    test('Payment reminder rejected', () {
      final result = NegativeFilter.apply(
        'EMI due reminder: Your EMI of Rs 15,000 for Home Loan is due on 05-Mar-2026. Please ensure sufficient balance.',
        'AD-HDFCBK',
      );
      expect(result.rejected, isTrue);
      expect(result.filterName, 'reminder_filter');
    });

    test('Insurance offer rejected', () {
      final result = NegativeFilter.apply(
        'Get insurance cover of Rs 5,00,000 for just Rs 499/month. Limited period offer. HDFC Life.',
        'AD-HDFCLF',
      );
      expect(result.rejected, isTrue);
    });

    test('App download push rejected', () {
      final result = NegativeFilter.apply(
        'Download the HDFC Bank app now for seamless banking. Available on Play Store and App Store.',
        'AD-HDFCBK',
      );
      expect(result.rejected, isTrue);
      expect(result.filterName, 'app_download_filter');
    });

    test('Valid transaction passes all filters', () {
      final result = NegativeFilter.apply(
        'Rs 500.00 debited from A/c XX1234 on 13-02-26 via UPI to merchant@ybl. UPI Ref 412345678929.',
        'AD-HDFCBK',
      );
      expect(result.rejected, isFalse);
    });
  });

  // ═════════════════════════════════════════════════════════════════
  //  SENDER TRUST CLASSIFICATION
  // ═════════════════════════════════════════════════════════════════

  group('Sender Trust Classification', () {
    test('AD- prefix = transactional', () {
      expect(
        NegativeFilter.classifySender('AD-HDFCBK'),
        SenderTrust.transactional,
      );
    });

    test('VM- prefix = transactional', () {
      expect(
        NegativeFilter.classifySender('VM-HDFCBK'),
        SenderTrust.transactional,
      );
    });

    test('VK- prefix = promotional', () {
      expect(
        NegativeFilter.classifySender('VK-PAYTM'),
        SenderTrust.promotional,
      );
    });

    test('HP- prefix = promotional', () {
      expect(
        NegativeFilter.classifySender('HP-OFFERS'),
        SenderTrust.promotional,
      );
    });

    test('Phone number = unknown', () {
      expect(
        NegativeFilter.classifySender('+919876543210'),
        SenderTrust.unknown,
      );
    });
  });

  // ═════════════════════════════════════════════════════════════════
  //  INTENT DETECTION
  // ═════════════════════════════════════════════════════════════════

  group('Intent Detection', () {
    test('Exclusive debit keyword', () {
      final r = IntentDetector.detect(
        'Rs 500 debited from your account XX1234.',
      );
      expect(r.hasIntent, isTrue);
      expect(r.direction, TransactionDirection.debit);
    });

    test('Exclusive credit keyword', () {
      final r = IntentDetector.detect(
        'Rs 1000 credited to your account XX5678.',
      );
      expect(r.hasIntent, isTrue);
      expect(r.direction, TransactionDirection.credit);
    });

    test('Both keywords — debit first wins', () {
      final r = IntentDetector.detect(
        'Rs 500 debited from A/c XX1234. Amount credited to beneficiary.',
      );
      expect(r.hasIntent, isTrue);
      expect(r.direction, TransactionDirection.debit);
    });

    test('Both keywords — refund overrides to credit', () {
      final r = IntentDetector.detect(
        'Refund of Rs 200 for cancelled order. Amount debited earlier, now credited.',
      );
      expect(r.hasIntent, isTrue);
      expect(r.direction, TransactionDirection.credit);
      expect(r.subType, TransactionSubType.refund);
    });

    test('No intent keywords = no intent', () {
      final r = IntentDetector.detect(
        'Your account balance is Rs 5,000 as on 13-Feb-2026.',
      );
      expect(r.hasIntent, isFalse);
    });

    test('No currency = no intent', () {
      final r = IntentDetector.detect(
        'Your payment has been debited for the subscription.',
      );
      expect(r.hasIntent, isFalse);
    });

    test('IMPS without UPI = transfer sub-type', () {
      final r = IntentDetector.detect(
        'Rs 5000 debited via IMPS transfer to beneficiary. Ref 412345.',
      );
      expect(r.hasIntent, isTrue);
      expect(r.subType, TransactionSubType.transfer);
    });

    test('Cashback override to credit', () {
      final r = IntentDetector.detect(
        'Rs 50 cashback credited to your account after spending Rs 500.',
      );
      expect(r.hasIntent, isTrue);
      expect(r.direction, TransactionDirection.credit);
      expect(r.subType, TransactionSubType.cashback);
    });
  });

  // ═════════════════════════════════════════════════════════════════
  //  AMOUNT EXTRACTION
  // ═════════════════════════════════════════════════════════════════

  group('Amount Extraction', () {
    test('Rs.500.00 format', () {
      final r = AmountExtractor.extract('Rs.500.00 debited from your account.');
      expect(r.amount, 500.0);
    });

    test('INR 1,500 with comma', () {
      final r = AmountExtractor.extract('INR 1,500 debited for UPI payment.');
      expect(r.amount, 1500.0);
    });

    test('₹ symbol', () {
      final r = AmountExtractor.extract('₹350 paid to Swiggy via UPI.');
      expect(r.amount, 350.0);
    });

    test('Indian lakh notation: 1,00,000.50', () {
      final r = AmountExtractor.extract(
        'Rs.1,00,000.50 debited from your HDFC Bank account.',
      );
      expect(r.amount, 100000.50);
    });

    test('Excludes balance amount', () {
      final r = AmountExtractor.extract(
        'Rs 500 debited from A/c XX1234. Available balance Rs 15,000.',
      );
      // Should extract 500, NOT 15,000
      expect(r.amount, 500.0);
    });

    test('Rejects amount > 1 crore', () {
      final r = AmountExtractor.extract(
        'Rs 50,00,00,000 debited from your account.',
      );
      // 50 crore should be rejected
      expect(r.amount, isNull);
    });

    test('No amount returns null', () {
      final r = AmountExtractor.extract(
        'Your HDFC Bank account has been debited.',
      );
      expect(r.amount, isNull);
    });
  });

  // ═════════════════════════════════════════════════════════════════
  //  ENTITY EXTRACTION
  // ═════════════════════════════════════════════════════════════════

  group('Entity Extraction — Bank', () {
    test('Detect from sender ID', () {
      final reasons = <String>[];
      final bank = EntityExtractor.detectBank(
        'Some SMS body',
        'AD-HDFCBK',
        reasons,
      );
      expect(bank, 'HDFC Bank');
    });

    test('Detect from body text when sender unknown', () {
      final reasons = <String>[];
      final bank = EntityExtractor.detectBank(
        'Rs 500 debited from your ICICI Bank Acct XX1234.',
        'AD-UNKNOWN',
        reasons,
      );
      expect(bank, 'ICICI Bank');
    });

    test('Unknown bank fallback', () {
      final reasons = <String>[];
      final bank = EntityExtractor.detectBank(
        'Rs 500 debited from your account.',
        'AD-XYZBNK',
        reasons,
      );
      expect(bank, 'Unknown Bank');
    });
  });

  group('Entity Extraction — UPI ID', () {
    test('Standard VPA extracted', () {
      final reasons = <String>[];
      final upi = EntityExtractor.extractUpiId(
        'Paid to merchant@ybl via UPI.',
        reasons,
      );
      expect(upi, 'merchant@ybl');
    });

    test('Email address NOT extracted', () {
      final reasons = <String>[];
      final upi = EntityExtractor.extractUpiId(
        'Contact support@gmail.com for help. UPI payment done.',
        reasons,
      );
      expect(upi, isNull);
    });

    test('Phone number UPI extracted', () {
      final reasons = <String>[];
      final upi = EntityExtractor.extractUpiId(
        'Paid to 9876543210@upi. Ref 12345.',
        reasons,
      );
      expect(upi, '9876543210@upi');
    });
  });

  group('Entity Extraction — Reference ID', () {
    test('UPI Ref No pattern', () {
      final reasons = <String>[];
      final ref = EntityExtractor.extractReferenceId(
        'UPI Ref No 412345678920',
        reasons,
      );
      expect(ref, '412345678920');
    });

    test('Axis UPI/Name/Ref/ID format', () {
      final reasons = <String>[];
      final ref = EntityExtractor.extractReferenceId(
        'for UPI/Swiggy/Ref/412345678922',
        reasons,
      );
      expect(ref, '412345678922');
    });

    test('IMPS Ref pattern', () {
      final reasons = <String>[];
      final ref = EntityExtractor.extractReferenceId(
        'IMPS Ref 412345678923',
        reasons,
      );
      expect(ref, '412345678923');
    });

    test('TxnId pattern', () {
      final reasons = <String>[];
      final ref = EntityExtractor.extractReferenceId(
        'TxnId: 412345678924',
        reasons,
      );
      expect(ref, '412345678924');
    });
  });

  group('Entity Extraction — Date', () {
    test('dd-mm-yy format', () {
      final reasons = <String>[];
      final dt = EntityExtractor.extractDate('on 13-02-26', reasons, smsTimestamp: DateTime(2026, 2, 13, 14, 30));
      expect(dt?.day, 13);
      expect(dt?.month, 2);
      expect(dt?.year, 2026);
    });

    test('dd/mm/yyyy format', () {
      final reasons = <String>[];
      final dt = EntityExtractor.extractDate('on 14/02/2026', reasons, smsTimestamp: DateTime(2026, 2, 14, 10, 0));
      expect(dt?.day, 14);
      expect(dt?.month, 2);
      expect(dt?.year, 2026);
    });

    test('ddMonyy format (13Feb26)', () {
      final reasons = <String>[];
      final dt = EntityExtractor.extractDate('on 13Feb26 by transfer', reasons, smsTimestamp: DateTime(2026, 2, 13, 9, 15));
      expect(dt?.day, 13);
      expect(dt?.month, 2);
      expect(dt?.year, 2026);
    });

    test('dd-Mon-yyyy format', () {
      final reasons = <String>[];
      final dt = EntityExtractor.extractDate('on 13-Feb-2026 for UPI', reasons, smsTimestamp: DateTime(2026, 2, 13, 21, 45));
      expect(dt?.day, 13);
      expect(dt?.month, 2);
      expect(dt?.year, 2026);
    });
  });

  // ═════════════════════════════════════════════════════════════════
  //  CONFIDENCE SCORING
  // ═════════════════════════════════════════════════════════════════

  group('Confidence Scoring', () {
    test('All features present = high score', () {
      final score = ConfidenceScorer.score(
        hasIntentKeyword: true,
        hasAmount: true,
        bankName: 'HDFC Bank',
        merchantName: 'Zomato',
        upiId: 'zomato@ybl',
        referenceId: '412345678901',
        accountTail: '1234',
        date: DateTime(2026, 2, 13),
        smsBody:
            'Rs 500 debited via UPI from A/c XX1234 to zomato@ybl. UPI Ref 412345678901.',
        senderTrust: SenderTrust.transactional,
        direction: TransactionDirection.debit,
      );

      expect(score.totalScore, greaterThanOrEqualTo(80));
      expect(score.isAccepted, isTrue);
      expect(score.isUncertain, isFalse);
    });

    test('Minimal features = low score', () {
      final score = ConfidenceScorer.score(
        hasIntentKeyword: true,
        hasAmount: true,
        bankName: 'Unknown Bank',
        merchantName: 'Unknown',
        upiId: null,
        referenceId: null,
        accountTail: null,
        date: null,
        smsBody: 'Rs 500 debited from your account.',
        senderTrust: SenderTrust.unknown,
        direction: TransactionDirection.debit,
      );

      expect(score.totalScore, lessThan(55));
    });

    test('Credit bias: credits need higher threshold', () {
      final score = ConfidenceScorer.score(
        hasIntentKeyword: true,
        hasAmount: true,
        bankName: 'HDFC Bank',
        merchantName: 'Unknown',
        upiId: null,
        referenceId: null,
        accountTail: '1234',
        date: null,
        smsBody: 'Rs 500 credited to your HDFC Bank account.',
        senderTrust: SenderTrust.transactional,
        direction: TransactionDirection.credit,
      );

      // Effective threshold for credit = 55 + 5 = 60
      expect(score.effectiveThreshold, 60);
    });

    test('Promotional sender penalty applied', () {
      final score = ConfidenceScorer.score(
        hasIntentKeyword: true,
        hasAmount: true,
        bankName: 'Paytm Payments Bank',
        merchantName: 'Unknown',
        upiId: null,
        referenceId: null,
        accountTail: null,
        date: null,
        smsBody: 'Rs 500 debited from your Paytm wallet.',
        senderTrust: SenderTrust.promotional,
        direction: TransactionDirection.debit,
      );

      // Should have -10 penalty for promo sender
      expect(score.contributions, anyElement(contains('promotional sender')));
    });
  });

  // ═════════════════════════════════════════════════════════════════
  //  USER FEEDBACK STORE
  // ═════════════════════════════════════════════════════════════════

  group('User Feedback Store', () {
    setUp(() => UserFeedbackStore.clearCache());

    test('Record "not a transaction" feedback', () {
      final feedback = UserFeedbackStore.recordFeedback(
        smsBody: 'Some promotional SMS that was wrongly classified.',
        smsTimestamp: DateTime(2026, 2, 13, 10, 30),
        action: UserFeedbackAction.notTransaction,
      );

      expect(feedback.action, UserFeedbackAction.notTransaction);

      // Check retrieval
      final retrieved = UserFeedbackStore.getFeedback(
        'Some promotional SMS that was wrongly classified.',
        DateTime(2026, 2, 13, 10, 30),
      );
      expect(retrieved, isNotNull);
      expect(retrieved!.action, UserFeedbackAction.notTransaction);
    });

    test('Apply "mark as debit" override', () {
      UserFeedbackStore.recordFeedback(
        smsBody: 'Test SMS body',
        smsTimestamp: DateTime(2026, 2, 13),
        action: UserFeedbackAction.markDebit,
        confirmedAmount: 250.0,
      );

      final result = TransactionParseResult.rejected(
        reasons: ['Was rejected initially'],
      );

      final overridden = UserFeedbackStore.applyFeedback(
        result,
        'Test SMS body',
        DateTime(2026, 2, 13),
      );

      expect(overridden, isNotNull);
      expect(overridden!.isTransaction, isTrue);
      expect(overridden.direction, TransactionDirection.debit);
      expect(overridden.amount, 250.0);
      expect(overridden.confidence, 100);
    });

    test('Build telemetry record has no PII', () {
      final result = TransactionParseResult.uncertain(
        reasons: ['Low confidence'],
        confidence: 42,
        amount: 500.0,
        direction: TransactionDirection.debit,
      );

      final telemetry = UserFeedbackStore.buildTelemetry(
        smsBody: 'Rs 500 debited from A/c XX1234 to Merchant.',
        sender: 'AD-HDFCBK',
        result: result,
        action: UserFeedbackAction.markDebit,
      );

      // Verify no PII
      expect(telemetry.formatHash, isNotEmpty);
      expect(telemetry.formatHash.length, 16); // Truncated hash
      expect(telemetry.senderPrefix, 'AD-');
      expect(telemetry.score, 42);
      expect(telemetry.userAction, 'markDebit');
    });

    test('Pipeline applies recorded user feedback (markCredit override)', () {
      final date = DateTime(2026, 7, 20, 15, 0);
      const body = 'Unclear message about 1000 rupees sent to friend';

      // 1. Record user feedback
      UserFeedbackStore.recordFeedback(
        smsBody: body,
        smsTimestamp: date,
        action: UserFeedbackAction.markCredit,
        confirmedAmount: 1000.0,
      );

      // 2. Parse through SmsTransactionParser
      final parsed = SmsTransactionParser.parse(
        body: body,
        sender: 'AD-HDFCBK',
        timestamp: date,
      );

      expect(parsed.isTransaction, isTrue);
      expect(parsed.direction, TransactionDirection.credit);
      expect(parsed.amount, 1000.0);
      expect(parsed.confidence, 100);

      // 3. Verify through ClassificationRuleEngine
      final consensus = SelfConsistencyChecker.check(
        body: body,
        sender: 'AD-HDFCBK',
        timestamp: date,
      );

      expect(consensus.result.isTransaction, isTrue);
      expect(consensus.result.direction, TransactionDirection.credit);
    });

    test('Pipeline applies recorded user feedback (notTransaction override)', () {
      final date = DateTime(2026, 7, 20, 16, 0);
      const body = 'Rs 500 debited from A/c XX1234 on 20-Jul-26 for Swiggy';

      // 1. Record user feedback as not a transaction
      UserFeedbackStore.recordFeedback(
        smsBody: body,
        smsTimestamp: date,
        action: UserFeedbackAction.notTransaction,
      );

      // 2. Parse through SmsTransactionParser
      final parsed = SmsTransactionParser.parse(
        body: body,
        sender: 'AD-HDFCBK',
        timestamp: date,
      );

      expect(parsed.isTransaction, isFalse);
      expect(parsed.reasons.any((r) => r.contains('USER OVERRIDE')), isTrue);
    });
  });

  // ═════════════════════════════════════════════════════════════════
  //  BATCH PARSING & DEDUPLICATION
  // ═════════════════════════════════════════════════════════════════

  group('Batch Parsing', () {
    test('Processes only new messages (after timestamp)', () {
      final messages = [
        RawSmsMessage(
          id: '1',
          body:
              'Rs 500 debited from A/c XX1234 via UPI. HDFC Bank. Ref 412345.',
          sender: 'AD-HDFCBK',
          dateMillis: DateTime(2026, 2, 10).millisecondsSinceEpoch,
        ),
        RawSmsMessage(
          id: '2',
          body: 'Rs 1000 credited to A/c XX5678 via UPI. SBI. Ref 412346.',
          sender: 'AD-SBIINB',
          dateMillis: DateTime(2026, 2, 13).millisecondsSinceEpoch,
        ),
      ];

      // Only process messages after Feb 11
      final results = BatchParser.parseBatchSync(
        messages: messages,
        lastProcessedTimestamp: DateTime(2026, 2, 11).millisecondsSinceEpoch,
      );

      // Only message 2 should be processed
      expect(results.length, 1);
      expect(results[0].result.amount, 1000.0);
    });

    test('Deduplicates by hash', () {
      final msg = RawSmsMessage(
        id: '1',
        body: 'Rs 500 debited from A/c XX1234 via UPI. HDFC Bank. Ref 412345.',
        sender: 'AD-HDFCBK',
        dateMillis: DateTime(2026, 2, 13).millisecondsSinceEpoch,
      );

      // Same message appearing twice (inbox + sent)
      final messages = [msg, msg];

      final results = BatchParser.parseBatchSync(messages: messages);

      // Should only get one result despite two identical messages
      expect(results.length, 1);
    });

    test('Skips existing hashes', () {
      final msg = RawSmsMessage(
        id: '1',
        body: 'Rs 500 debited from A/c XX1234 via UPI. HDFC Bank. Ref 412345.',
        sender: 'AD-HDFCBK',
        dateMillis: DateTime(2026, 2, 13).millisecondsSinceEpoch,
      );

      final existingHashes = {msg.hash};

      final results = BatchParser.parseBatchSync(
        messages: [msg],
        existingHashes: existingHashes,
      );

      expect(results, isEmpty);
    });

    test('Filters out non-transaction SMS', () {
      final messages = [
        RawSmsMessage(
          id: '1',
          body:
              'Rs 500 debited from A/c XX1234 via UPI. HDFC Bank. Ref 412345.',
          sender: 'AD-HDFCBK',
          dateMillis: DateTime(2026, 2, 13).millisecondsSinceEpoch,
        ),
        RawSmsMessage(
          id: '2',
          body:
              'Your OTP for online transaction is 123456. Do not share with anyone.',
          sender: 'AD-HDFCBK',
          dateMillis: DateTime(2026, 2, 13).millisecondsSinceEpoch,
        ),
        RawSmsMessage(
          id: '3',
          body: 'Happy birthday! Get 50% off today only on all purchases.',
          sender: 'VK-PROMO',
          dateMillis: DateTime(2026, 2, 13).millisecondsSinceEpoch,
        ),
      ];

      final results = BatchParser.parseBatchSync(messages: messages);

      // Only the first message should pass
      expect(results.length, 1);
      expect(results[0].result.amount, 500.0);
    });
  });

  // ═════════════════════════════════════════════════════════════════
  //  EDGE CASES
  // ═════════════════════════════════════════════════════════════════

  group('Edge Cases', () {
    test('Amount with no intent = rejected', () {
      final r = SmsTransactionParser.parse(
        body:
            'Enjoy flat ₹500 off on your next order. Use code SAVE500. T&C apply.',
        sender: 'VK-OFFERS',
        timestamp: DateTime(2026, 2, 13),
      );
      expect(r.isTransaction, isFalse);
    });

    test('Multiple amounts: transaction amount preferred over balance', () {
      final r = SmsTransactionParser.parse(
        body:
            'Rs 500.00 debited from A/c XX1234. Avl Bal Rs 15,000.50. UPI Ref 412345. HDFC Bank.',
        sender: 'AD-HDFCBK',
        timestamp: DateTime(2026, 2, 13),
      );

      expect(r.isTransaction, isTrue);
      expect(r.amount, 500.0, reason: 'Should extract 500, not 15000');
    });

    test('Refund overrides debit keyword to credit', () {
      final r = SmsTransactionParser.parse(
        body:
            'UPI refund of Rs 200 credited to your account XX1234. Original txn was debited on 10-02-26. UPI Ref 412345.',
        sender: 'AD-HDFCBK',
        timestamp: DateTime(2026, 2, 13),
      );

      expect(r.isTransaction, isTrue);
      expect(r.direction, TransactionDirection.credit);
      expect(r.subType, TransactionSubType.refund);
    });

    test('Auto-pay debit detected', () {
      final r = SmsTransactionParser.parse(
        body:
            'Rs 499 debited from HDFC Bank A/c XX1234 towards auto-pay for Netflix subscription. UPI Ref 412345678945.',
        sender: 'AD-HDFCBK',
        timestamp: DateTime(2026, 2, 13),
      );

      expect(r.isTransaction, isTrue);
      expect(r.direction, TransactionDirection.debit);
      expect(r.amount, 499.0);
    });

    test('NEFT without UPI = transfer sub-type', () {
      final r = SmsTransactionParser.parse(
        body:
            'Rs 10000 debited from A/c XX1234 for NEFT transfer to Beneficiary. NEFT Ref 412345678944.',
        sender: 'AD-HDFCBK',
        timestamp: DateTime(2026, 2, 13),
      );

      expect(r.isTransaction, isTrue);
      expect(r.subType, TransactionSubType.transfer);
    });
  });

  // ═════════════════════════════════════════════════════════════════
  //  EXPLAINABILITY
  // ═════════════════════════════════════════════════════════════════

  group('Explainability', () {
    test('Reasons list is populated for accepted transaction', () {
      final r = SmsTransactionParser.parse(
        body:
            'Rs 500 debited from A/c XX1234 via UPI to merchant@ybl. UPI Ref 412345. HDFC Bank.',
        sender: 'AD-HDFCBK',
        timestamp: DateTime(2026, 2, 13),
      );

      expect(r.reasons, isNotEmpty);
      expect(r.reasons, anyElement(contains('Passed all negative filters')));
      expect(r.reasons, anyElement(contains('Debit keyword')));
      expect(r.reasons, anyElement(contains('amount')));
    });

    test('Reasons list explains rejection', () {
      final r = SmsTransactionParser.parse(
        body:
            'Your OTP for Rs 500 transaction is 123456. Valid for 10 minutes. Do not share.',
        sender: 'AD-HDFCBK',
        timestamp: DateTime(2026, 2, 13),
      );

      expect(r.isTransaction, isFalse);
      expect(r.reasons, anyElement(contains('REJECTED')));
      expect(r.reasons, anyElement(contains('OTP')));
    });
  });

  // ═════════════════════════════════════════════════════════════════
  //  PRE-FILTER QUICK CHECKS
  // ═════════════════════════════════════════════════════════════════

  group('Quick Pre-filter', () {
    test('Worth parsing for valid transaction SMS', () {
      expect(
        SmsTransactionParser.isWorthParsing(
          'Rs 500 debited from A/c XX1234 via UPI payment successfully.',
          'AD-HDFCBK',
        ),
        isTrue,
      );
    });

    test('Not worth parsing for short message', () {
      expect(
        SmsTransactionParser.isWorthParsing('Rs 500.', 'AD-HDFCBK'),
        isFalse,
      );
    });

    test('Not worth parsing without amount', () {
      expect(
        SmsTransactionParser.isWorthParsing(
          'Your HDFC Bank account has been debited successfully.',
          'AD-HDFCBK',
        ),
        isFalse,
      );
    });

    test('Not worth parsing without intent', () {
      expect(
        SmsTransactionParser.isWorthParsing(
          'Your account balance is Rs 5,000 as on 13-02-2026.',
          'AD-HDFCBK',
        ),
        isFalse,
      );
    });
  });

  // ═════════════════════════════════════════════════════════════════
  //  TRUECALLER SMS — PRODUCTION PIPELINE
  // ═════════════════════════════════════════════════════════════════

  group('Truecaller SMS', () {
    test('Truecaller debit — UPI payment with pipe separator', () {
      final r = SmsTransactionParser.parse(
        body:
            'Rs 250.00 paid to Swiggy via UPI from A/c XX1234 | HDFC Bank. UPI Ref 412345678999.',
        sender: 'TRUCLR',
        timestamp: DateTime(2026, 2, 13),
      );

      expect(r.isTransaction, isTrue, reason: 'Should be a transaction');
      expect(r.direction, TransactionDirection.debit);
      expect(r.amount, 250.0);
      expect(r.confidence, greaterThanOrEqualTo(55));
    });

    test('Truecaller credit — money received via UPI', () {
      final r = SmsTransactionParser.parse(
        body:
            'Rs 1500.00 received from person@okaxis to A/c XX5678. UPI Ref 412345679000. HDFC Bank.',
        sender: 'TRUCAL',
        timestamp: DateTime(2026, 2, 13),
      );

      expect(r.isTransaction, isTrue, reason: 'Should be a transaction');
      expect(r.direction, TransactionDirection.credit);
      expect(r.amount, 1500.0);
      expect(r.upiId, 'person@okaxis');
      expect(r.confidence, greaterThanOrEqualTo(55));
    });

    test('Truecaller debit — relayed bank SMS (HDFC format)', () {
      final r = SmsTransactionParser.parse(
        body:
            'Rs 500.00 has been debited from account *1234 to VPA merchant@upi on 13-02-26. UPI Ref No 412345679001. If not done by you call 18002586161.',
        sender: 'Truecaller',
        timestamp: DateTime(2026, 2, 13),
      );

      expect(r.isTransaction, isTrue, reason: 'Should be a transaction');
      expect(r.direction, TransactionDirection.debit);
      expect(r.amount, 500.0);
      expect(r.upiId, 'merchant@upi');
      expect(r.reference, '412345679001');
      expect(r.bank, 'Truecaller');
      expect(r.confidence, greaterThanOrEqualTo(55));
    });

    test('Truecaller debit — sent to merchant with Avl Bal', () {
      final r = SmsTransactionParser.parse(
        body:
            'Rs 350 sent to Zomato via UPI. Ref No 412345679002. Avl Bal Rs 4500.00.',
        sender: 'TRUECL',
        timestamp: DateTime(2026, 2, 13),
      );

      expect(r.isTransaction, isTrue, reason: 'Should be a transaction');
      expect(r.direction, TransactionDirection.debit);
      expect(r.amount, 350.0);
      // Amount should NOT be the balance
      expect(r.amount, isNot(4500.0));
    });

    test('Truecaller sender classified as transactional trust', () {
      // Truecaller SMS should not be penalized as unknown sender
      final r = SmsTransactionParser.parse(
        body:
            'INR 2,750.00 credited to A/c XX1234 on 13-Feb-2026. UPI Ref: 1234567890. HDFC Bank',
        sender: 'TRUCLR',
        timestamp: DateTime(2026, 2, 13),
      );

      expect(r.isTransaction, isTrue);
      expect(r.direction, TransactionDirection.credit);
      expect(r.amount, 2750.0);
      // Should have same or similar confidence as a bank sender
      expect(r.confidence, greaterThanOrEqualTo(55));
    });

    test('Truecaller OTP still rejected', () {
      final r = SmsTransactionParser.parse(
        body:
            'Your OTP for HDFC bank is 123456. Do not share it with anyone. Valid for 10 minutes.',
        sender: 'TRUCLR',
        timestamp: DateTime(2026, 2, 13),
      );

      expect(r.isTransaction, isFalse);
      expect(r.isUncertain, isFalse);
      expect(r.reasons, anyElement(contains('OTP')));
    });
  });
}
