import 'package:flutter_test/flutter_test.dart';
import 'package:pet/services/transaction_parser.dart';

/// Comprehensive test suite for TransactionParser.
///
/// Tests real-world SMS formats from Indian banks, UPI apps, and edge cases.
/// Each test group covers a specific bank format or feature.
void main() {
  // ═══════════════════════════════════════════════════════════════════
  //  HDFC BANK
  // ═══════════════════════════════════════════════════════════════════

  group('HDFC Bank SMS', () {
    test('Debit via UPI with ref and merchant', () {
      final result = TransactionParser.parse(
        'Rs 500.00 has been debited from account *1234 to VPA merchant@upi on 13-02-26. UPI Ref No 412345678901. If not done by you call on 18002586161.',
        'AD-HDFCBK',
        DateTime(2026, 2, 13),
      );

      expect(result, isNotNull);
      expect(result!.amount, 500.00);
      expect(result.transactionType, 'debit');
      expect(result.bankName, 'HDFC Bank');
      expect(result.referenceId, '412345678901');
      expect(result.upiId, 'merchant@upi');
      expect(result.accountTail, '1234');
    });

    test('Credit via UPI', () {
      final result = TransactionParser.parse(
        'Money Received! Rs.2000.00 credited to HDFC Bank A/c **1234 on 13-02-26 by UPI Ref 412345678901. Avl Bal Rs.15000.50.',
        'AD-HDFCBK',
        DateTime(2026, 2, 13),
      );

      expect(result, isNotNull);
      expect(result!.amount, 2000.00);
      expect(result.transactionType, 'credit');
      expect(result.bankName, 'HDFC Bank');
      expect(result.referenceId, '412345678901');
    });

    test('Debit with Info: Payment to pattern', () {
      final result = TransactionParser.parse(
        'Rs 1250.00 debited from A/c *5678 on 13-02-26. Info: Payment to swiggy@paytm. UPI Ref No 412345678902.',
        'AD-HDFCBK',
        DateTime(2026, 2, 13),
      );

      expect(result, isNotNull);
      expect(result!.amount, 1250.00);
      expect(result.transactionType, 'debit');
      expect(result.merchantName, 'swiggy@paytm');
      expect(result.upiId, 'swiggy@paytm');
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  //  SBI
  // ═══════════════════════════════════════════════════════════════════

  group('SBI SMS', () {
    test('Debit with transfer to pattern', () {
      final result = TransactionParser.parse(
        'Your a/c no. XXXXXXXX1234 is debited by Rs.500.00 on 13Feb26 by transfer to merchant@upi-UPI Ref No 412345678901.',
        'AD-SBIINB',
        DateTime(2026, 2, 13),
      );

      expect(result, isNotNull);
      expect(result!.amount, 500.00);
      expect(result.transactionType, 'debit');
      expect(result.bankName, 'SBI');
    });

    test('Credit with from pattern', () {
      final result = TransactionParser.parse(
        'Rs.1000.00 credited to your a/c XXXXXXXX5678 on 13Feb26 by a]friend-Name(UPI Ref No 412345678901).',
        'AD-SBIINB',
        DateTime(2026, 2, 13),
      );

      expect(result, isNotNull);
      expect(result!.amount, 1000.00);
      expect(result.transactionType, 'credit');
      expect(result.bankName, 'SBI');
      expect(result.referenceId, '412345678901');
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  //  ICICI BANK
  // ═══════════════════════════════════════════════════════════════════

  group('ICICI Bank SMS', () {
    test('Debit for UPI-merchant', () {
      final result = TransactionParser.parse(
        'Dear Customer, Rs 500.00 has been debited from your ICICI Bank Acct XX1234 on 13-Feb-26 for UPI-merchant@upi. UPI Ref:412345678901.',
        'AD-ICICIB',
        DateTime(2026, 2, 13),
      );

      expect(result, isNotNull);
      expect(result!.amount, 500.00);
      expect(result.transactionType, 'debit');
      expect(result.bankName, 'ICICI Bank');
      expect(result.referenceId, '412345678901');
    });

    test('Credit from UPI', () {
      final result = TransactionParser.parse(
        'Dear Customer, Rs 1000.00 is credited to your ICICI Bank a/c XX5678 on 13-Feb-26 from UPI-person@okaxis. UPI Ref: 412345678901.',
        'AD-ICICIB',
        DateTime(2026, 2, 13),
      );

      expect(result, isNotNull);
      expect(result!.amount, 1000.00);
      expect(result.transactionType, 'credit');
      expect(result.bankName, 'ICICI Bank');
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  //  AXIS BANK
  // ═══════════════════════════════════════════════════════════════════

  group('Axis Bank SMS', () {
    test('Debit with UPI/Name/Ref/ID pattern', () {
      final result = TransactionParser.parse(
        'Rs.500 debited from A/c no. XX1234 on 13-Feb-26 for UPI/Swiggy/Ref/412345678901.',
        'AD-AXISBK',
        DateTime(2026, 2, 13),
      );

      expect(result, isNotNull);
      expect(result!.amount, 500.00);
      expect(result.transactionType, 'debit');
      expect(result.bankName, 'Axis Bank');
      expect(result.referenceId, '412345678901');
    });

    test('Credit via UPI', () {
      final result = TransactionParser.parse(
        'Rs.1000 credited to A/c no. XX5678 on 13-Feb-26 for UPI/JohnDoe/Ref/412345678902.',
        'AD-AXISBK',
        DateTime(2026, 2, 13),
      );

      expect(result, isNotNull);
      expect(result!.amount, 1000.00);
      expect(result.transactionType, 'credit');
      expect(result.bankName, 'Axis Bank');
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  //  KOTAK BANK
  // ═══════════════════════════════════════════════════════════════════

  group('Kotak Bank SMS', () {
    test('Sent via UPI', () {
      final result = TransactionParser.parse(
        'Sent Rs.500.00 from Kotak Bank AC 1234 to merchant@upi on 13-02-26. UPI Ref 412345678901. Not you? Call 18602662666.',
        'AD-KOTAKB',
        DateTime(2026, 2, 13),
      );

      expect(result, isNotNull);
      expect(result!.amount, 500.00);
      expect(result.transactionType, 'debit');
      expect(result.bankName, 'Kotak Bank');
      expect(result.upiId, 'merchant@upi');
    });

    test('Received via UPI', () {
      final result = TransactionParser.parse(
        'Received Rs.1000.00 in Kotak Bank AC 5678 from person@okaxis on 13-02-26. UPI Ref 412345678902.',
        'AD-KOTAKB',
        DateTime(2026, 2, 13),
      );

      expect(result, isNotNull);
      expect(result!.amount, 1000.00);
      expect(result.transactionType, 'credit');
      expect(result.bankName, 'Kotak Bank');
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  //  UPI APP NOTIFICATIONS (GPay, PhonePe, Paytm)
  // ═══════════════════════════════════════════════════════════════════

  group('UPI App SMS', () {
    test('Google Pay - You paid', () {
      final result = TransactionParser.parse(
        'You paid Rs.350 to Zomato Online Order. UPI transaction ID: 412345678903. Google Pay.',
        'AD-GPAY',
        DateTime(2026, 2, 13),
      );

      expect(result, isNotNull);
      expect(result!.amount, 350.00);
      expect(result.transactionType, 'debit');
    });

    test('PhonePe - Received', () {
      final result = TransactionParser.parse(
        'Rs.750 received from Rahul Kumar via PhonePe. UPI Ref: 412345678904. Credited to your bank account.',
        'AD-PHONEPE',
        DateTime(2026, 2, 13),
      );

      expect(result, isNotNull);
      expect(result!.amount, 750.00);
      expect(result.transactionType, 'credit');
    });

    test('Paytm - Paid to', () {
      final result = TransactionParser.parse(
        'You have paid Rs 200 to Amazon. Txn ID: 412345678905. Paytm.',
        'AD-PAYTM',
        DateTime(2026, 2, 13),
      );

      expect(result, isNotNull);
      expect(result!.amount, 200.00);
      expect(result.transactionType, 'debit');
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  //  TRANSACTION SUB-TYPES
  // ═══════════════════════════════════════════════════════════════════

  group('Sub-type Classification', () {
    test('Refund detected', () {
      final result = TransactionParser.parse(
        'Refund of Rs.200.00 has been credited to A/c XX1234. UPI Ref: 412345678906. HDFC Bank.',
        'AD-HDFCBK',
        DateTime(2026, 2, 13),
      );

      expect(result, isNotNull);
      expect(result!.amount, 200.00);
      expect(result.transactionType, 'credit');
      expect(result.transactionSubType, 'refund');
    });

    test('Cashback detected', () {
      final result = TransactionParser.parse(
        'Cashback of Rs.50 credited to your HDFC Bank account XX1234. Enjoy your rewards!',
        'AD-HDFCBK',
        DateTime(2026, 2, 13),
      );

      expect(result, isNotNull);
      expect(result!.amount, 50.00);
      expect(result.transactionType, 'credit');
      expect(result.transactionSubType, 'cashback');
    });

    test('Collect request detected', () {
      final result = TransactionParser.parse(
        'Rs.500 has been debited from account XX1234 on 13-02-26 for UPI Collect request from merchant@upi. UPI Ref No 412345678907.',
        'AD-HDFCBK',
        DateTime(2026, 2, 13),
      );

      expect(result, isNotNull);
      expect(result!.amount, 500.00);
      expect(result.transactionType, 'debit');
      expect(result.transactionSubType, 'collect');
    });

    test('IMPS transfer detected', () {
      final result = TransactionParser.parse(
        'IMPS of Rs 5000.00 debited from A/c XX1234 to person@upi on 13-Feb-26. IMPS Ref 412345678908.',
        'AD-HDFCBK',
        DateTime(2026, 2, 13),
      );

      expect(result, isNotNull);
      expect(result!.amount, 5000.00);
      expect(result.transactionType, 'debit');
      // UPI indicator is present, so subType should be 'payment' not 'transfer'
      expect(result.transactionSubType, 'payment');
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  //  AMOUNT PARSING
  // ═══════════════════════════════════════════════════════════════════

  group('Amount Extraction', () {
    test('Indian comma notation (1,00,000)', () {
      final result = TransactionParser.parse(
        'Rs.1,00,000.50 debited from HDFC Bank A/c XX1234 on 13-02-26. UPI Ref 412345678909.',
        'AD-HDFCBK',
        DateTime(2026, 2, 13),
      );

      expect(result, isNotNull);
      expect(result!.amount, 100000.50);
    });

    test('INR prefix', () {
      final result = TransactionParser.parse(
        'INR 499.00 spent on UPI txn at Amazon. A/c XX1234. Ref 412345678910.',
        'AD-HDFCBK',
        DateTime(2026, 2, 13),
      );

      expect(result, isNotNull);
      expect(result!.amount, 499.00);
    });

    test('₹ symbol', () {
      final result = TransactionParser.parse(
        'You paid ₹350 to Swiggy via UPI. Ref No 412345678911.',
        'AD-GPAY',
        DateTime(2026, 2, 13),
      );

      expect(result, isNotNull);
      expect(result!.amount, 350.00);
    });

    test('Amount without decimal', () {
      final result = TransactionParser.parse(
        'Rs 500 debited from A/c XX1234 via UPI. Ref 412345678912.',
        'AD-HDFCBK',
        DateTime(2026, 2, 13),
      );

      expect(result, isNotNull);
      expect(result!.amount, 500.00);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  //  DATE PARSING
  // ═══════════════════════════════════════════════════════════════════

  group('Date Extraction', () {
    test('dd-mm-yy format', () {
      final result = TransactionParser.parse(
        'Rs.500 debited from A/c XX1234 on 13-02-26 via UPI. Ref 412345678913.',
        'AD-HDFCBK',
        DateTime(2026, 2, 13),
      );

      expect(result, isNotNull);
      expect(result!.parsedDate?.day, 13);
      expect(result.parsedDate?.month, 2);
      expect(result.parsedDate?.year, 2026);
    });

    test('dd/mm/yyyy format', () {
      final result = TransactionParser.parse(
        'Rs.500 debited from A/c XX1234 on 13/02/2026 via UPI. Ref 412345678914.',
        'AD-HDFCBK',
        DateTime(2026, 2, 13),
      );

      expect(result, isNotNull);
      expect(result!.parsedDate?.day, 13);
      expect(result.parsedDate?.month, 2);
      expect(result.parsedDate?.year, 2026);
    });

    test('ddMonyy format (13Feb26)', () {
      final result = TransactionParser.parse(
        'Your a/c XXXXXXXX1234 is debited by Rs.500.00 on 13Feb26 by transfer to merchant@upi.',
        'AD-SBIINB',
        DateTime(2026, 2, 13),
      );

      expect(result, isNotNull);
      expect(result!.parsedDate?.day, 13);
      expect(result.parsedDate?.month, 2);
      expect(result.parsedDate?.year, 2026);
    });

    test('dd-Mon-yyyy format (13-Feb-2026)', () {
      final result = TransactionParser.parse(
        'Rs 500 debited from A/c XX1234 on 13-Feb-2026 for UPI. Ref 412345678915.',
        'AD-ICICIB',
        DateTime(2026, 2, 13),
      );

      expect(result, isNotNull);
      expect(result!.parsedDate?.day, 13);
      expect(result.parsedDate?.month, 2);
      expect(result.parsedDate?.year, 2026);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  //  UPI ID EXTRACTION & VALIDATION
  // ═══════════════════════════════════════════════════════════════════

  group('UPI ID Extraction', () {
    test('Standard UPI ID (merchant@ybl)', () {
      final result = TransactionParser.parse(
        'Rs 500 debited from A/c XX1234. Paid to merchant@ybl. UPI Ref 412345678916.',
        'AD-HDFCBK',
        DateTime(2026, 2, 13),
      );

      expect(result, isNotNull);
      expect(result!.upiId, 'merchant@ybl');
    });

    test('Phone number UPI ID (9876543210@upi)', () {
      final result = TransactionParser.parse(
        'Rs 500 debited from A/c XX1234. Paid to 9876543210@upi. UPI Ref 412345678917.',
        'AD-HDFCBK',
        DateTime(2026, 2, 13),
      );

      expect(result, isNotNull);
      expect(result!.upiId, '9876543210@upi');
    });

    test('okaxis handle', () {
      final result = TransactionParser.parse(
        'Rs 1000 credited to A/c XX1234 from person@okaxis. UPI Ref 412345678918.',
        'AD-AXISBK',
        DateTime(2026, 2, 13),
      );

      expect(result, isNotNull);
      expect(result!.upiId, 'person@okaxis');
    });

    test('Email address NOT extracted as UPI ID', () {
      // This SMS contains an email-like address but also a real transaction
      final result = TransactionParser.parse(
        'Rs 500 debited from A/c XX1234 via UPI. Contact support@gmail.com for help. Ref 412345678919.',
        'AD-HDFCBK',
        DateTime(2026, 2, 13),
      );

      expect(result, isNotNull);
      expect(result!.upiId, isNull); // gmail.com should be rejected
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  //  FALSE POSITIVE REJECTION
  // ═══════════════════════════════════════════════════════════════════

  group('False Positive Rejection', () {
    test('OTP message rejected', () {
      final result = TransactionParser.parse(
        'Your OTP for Rs 500 transaction is 123456. Valid for 10 minutes. Do not share.',
        'AD-HDFCBK',
        DateTime(2026, 2, 13),
      );

      expect(result, isNull);
    });

    test('Promotional message rejected', () {
      final result = TransactionParser.parse(
        'Congratulations! You are pre-approved for a loan of Rs 5,00,000. Apply now at hdfc.com.',
        'AD-HDFCBK',
        DateTime(2026, 2, 13),
      );

      expect(result, isNull);
    });

    test('KYC update message rejected', () {
      final result = TransactionParser.parse(
        'Dear Customer, your KYC update is pending. Rs 0 charge. Complete it at nearest branch.',
        'AD-HDFCBK',
        DateTime(2026, 2, 13),
      );

      expect(result, isNull);
    });

    test('Insurance promo rejected', () {
      final result = TransactionParser.parse(
        'Get insurance cover of Rs 5,00,000 for just Rs 499/month. Limited period offer. Click here.',
        'AD-HDFCBK',
        DateTime(2026, 2, 13),
      );

      expect(result, isNull);
    });

    test('Short message rejected', () {
      final result = TransactionParser.parse(
        'Rs 500 debited.',
        'AD-HDFCBK',
        DateTime(2026, 2, 13),
      );

      expect(result, isNull); // Too short (<30 chars)
    });

    test('Message without amount rejected', () {
      final result = TransactionParser.parse(
        'Your HDFC Bank account has been debited. Please check your statement for details.',
        'AD-HDFCBK',
        DateTime(2026, 2, 13),
      );

      expect(result, isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  //  REFERENCE ID EXTRACTION
  // ═══════════════════════════════════════════════════════════════════

  group('Reference ID Extraction', () {
    test('UPI Ref No', () {
      final result = TransactionParser.parse(
        'Rs 500 debited from A/c XX1234 via UPI. UPI Ref No 412345678920.',
        'AD-HDFCBK',
        DateTime(2026, 2, 13),
      );

      expect(result, isNotNull);
      expect(result!.referenceId, '412345678920');
    });

    test('UPI Ref:', () {
      final result = TransactionParser.parse(
        'Rs 500 debited from ICICI Bank A/c XX1234 for UPI-merchant@upi. UPI Ref:412345678921.',
        'AD-ICICIB',
        DateTime(2026, 2, 13),
      );

      expect(result, isNotNull);
      expect(result!.referenceId, '412345678921');
    });

    test('Axis Bank UPI/Name/Ref/ID format', () {
      final result = TransactionParser.parse(
        'Rs.500 debited from A/c XX1234 on 13-Feb-26 for UPI/Swiggy/Ref/412345678922.',
        'AD-AXISBK',
        DateTime(2026, 2, 13),
      );

      expect(result, isNotNull);
      expect(result!.referenceId, '412345678922');
    });

    test('IMPS Ref', () {
      final result = TransactionParser.parse(
        'Rs 5000 debited from A/c XX1234 via IMPS. IMPS Ref 412345678923. Transferred to Person.',
        'AD-HDFCBK',
        DateTime(2026, 2, 13),
      );

      expect(result, isNotNull);
      expect(result!.referenceId, '412345678923');
    });

    test('Txn ID', () {
      final result = TransactionParser.parse(
        'You paid Rs 200 to Amazon via UPI. TxnId: 412345678924.',
        'AD-PAYTM',
        DateTime(2026, 2, 13),
      );

      expect(result, isNotNull);
      expect(result!.referenceId, '412345678924');
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  //  BANK DETECTION
  // ═══════════════════════════════════════════════════════════════════

  group('Bank Detection', () {
    test('Detect from sender ID', () {
      final result = TransactionParser.parse(
        'Rs 500 debited from A/c XX1234 via UPI. Ref 412345678925.',
        'VM-HDFCBK',
        DateTime(2026, 2, 13),
      );

      expect(result, isNotNull);
      expect(result!.bankName, 'HDFC Bank');
    });

    test('Detect from body text when sender unknown', () {
      final result = TransactionParser.parse(
        'Rs 500 debited from your ICICI Bank Acct XX1234 via UPI. Ref 412345678926.',
        'AD-UNKNOWN',
        DateTime(2026, 2, 13),
      );

      expect(result, isNotNull);
      expect(result!.bankName, 'ICICI Bank');
    });

    test('Unknown bank fallback', () {
      final result = TransactionParser.parse(
        'Rs 500 debited from A/c XX1234 via UPI payment. Ref 412345678927.',
        'AD-XYZBNK',
        DateTime(2026, 2, 13),
      );

      expect(result, isNotNull);
      expect(result!.bankName, 'Unknown Bank');
    });

    test('Detect PNB', () {
      final result = TransactionParser.parse(
        'Rs.500.00 debited from your PNB A/c XX1234 on 13-02-26. UPI Ref 412345678928.',
        'AD-PNBSMS',
        DateTime(2026, 2, 13),
      );

      expect(result, isNotNull);
      expect(result!.bankName, 'PNB');
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  //  CONFIDENCE SCORING
  // ═══════════════════════════════════════════════════════════════════

  group('Confidence Scoring', () {
    test('High confidence: all fields present', () {
      final result = TransactionParser.parse(
        'Rs 500.00 debited from HDFC Bank A/c XX1234 to VPA merchant@ybl on 13-02-26. UPI Ref No 412345678929.',
        'AD-HDFCBK',
        DateTime(2026, 2, 13),
      );

      expect(result, isNotNull);
      // Bank + merchant + UPI ID + ref + UPI keyword + account = high score
      expect(result!.confidence, greaterThan(0.8));
    });

    test('Low confidence: minimal fields', () {
      final result = TransactionParser.parse(
        'Rs 500 debited from your account via UPI payment transaction successfully completed.',
        'AD-XYZBNK',
        DateTime(2026, 2, 13),
      );

      expect(result, isNotNull);
      // No bank, no merchant name, no ref, no UPI ID = lower score
      expect(result!.confidence, lessThan(0.7));
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  //  MERCHANT EXTRACTION EDGE CASES
  // ═══════════════════════════════════════════════════════════════════

  group('Merchant Extraction', () {
    test('Merchant from "at MERCHANT on" pattern', () {
      final result = TransactionParser.parse(
        'INR 499 spent on UPI txn at Amazon India on 13-02-26. A/c XX1234. Ref 412345678930.',
        'AD-HDFCBK',
        DateTime(2026, 2, 13),
      );

      expect(result, isNotNull);
      expect(result!.merchantName, contains('Amazon'));
    });

    test('Merchant from "paid to" pattern', () {
      final result = TransactionParser.parse(
        'Rs 350 paid to Zomato via UPI from A/c XX1234. Ref 412345678931.',
        'AD-HDFCBK',
        DateTime(2026, 2, 13),
      );

      expect(result, isNotNull);
      expect(result!.merchantName, contains('Zomato'));
    });

    test('Merchant from "received from" pattern', () {
      final result = TransactionParser.parse(
        'Rs 1000 received from Rahul Kumar via UPI. Credited to A/c XX1234. Ref 412345678932.',
        'AD-HDFCBK',
        DateTime(2026, 2, 13),
      );

      expect(result, isNotNull);
      expect(result!.merchantName, contains('Rahul'));
    });

    test('Falls back to UPI ID as merchant', () {
      final result = TransactionParser.parse(
        'Rs 500 debited from A/c XX1234 via UPI. VPA: unknownshop@ybl. Ref 412345678933.',
        'AD-HDFCBK',
        DateTime(2026, 2, 13),
      );

      expect(result, isNotNull);
      // Should either extract UPI ID or use it as merchant name
      final hasUpiOrMerchant = result!.upiId == 'unknownshop@ybl' ||
          result.merchantName.contains('unknownshop');
      expect(hasUpiOrMerchant, isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  //  BATCH PARSING
  // ═══════════════════════════════════════════════════════════════════

  group('Batch Parsing', () {
    test('Processes multiple messages and returns only valid ones', () {
      final messages = [
        (
          body: 'Rs 500 debited from A/c XX1234 via UPI. Ref 412345678934.',
          sender: 'AD-HDFCBK',
          timestamp: DateTime(2026, 2, 13),
        ),
        (
          body: 'Your OTP is 123456. Do not share.',
          sender: 'AD-HDFCBK',
          timestamp: DateTime(2026, 2, 13),
        ),
        (
          body: 'Rs 1000 credited to A/c XX5678 via UPI. Ref 412345678935.',
          sender: 'AD-SBIINB',
          timestamp: DateTime(2026, 2, 13),
        ),
        (
          body: 'Happy birthday! Enjoy 50% off today.',
          sender: 'AD-PROMO',
          timestamp: DateTime(2026, 2, 13),
        ),
      ];

      final results = TransactionParser.parseBatch(messages);

      expect(results.length, 2); // Only the two valid transactions
      expect(results[0].index, 0); // First valid was at index 0
      expect(results[1].index, 2); // Second valid was at index 2
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  //  isTransactionSms & isUpiTransaction
  // ═══════════════════════════════════════════════════════════════════

  group('Pre-filter Methods', () {
    test('isTransactionSms returns true for transaction SMS', () {
      expect(
        TransactionParser.isTransactionSms(
          'Rs 500 debited from A/c XX1234 via UPI. Ref 412345678936.',
        ),
        isTrue,
      );
    });

    test('isTransactionSms returns false for OTP', () {
      expect(
        TransactionParser.isTransactionSms(
          'Your OTP for Rs 500 transaction is 123456.',
        ),
        isFalse,
      );
    });

    test('isUpiTransaction returns true for UPI SMS', () {
      expect(
        TransactionParser.isUpiTransaction(
          'Rs 500 debited from A/c XX1234 via UPI. Ref 412345678937.',
        ),
        isTrue,
      );
    });

    test('isUpiTransaction returns true for SMS with UPI VPA', () {
      expect(
        TransactionParser.isUpiTransaction(
          'Rs 500 debited from A/c XX1234. Paid to merchant@ybl. Ref 412345678938.',
        ),
        isTrue,
      );
    });

    test('isUpiTransaction returns false for non-UPI transaction', () {
      expect(
        TransactionParser.isUpiTransaction(
          'Rs 500 debited from A/c XX1234 for ATM withdrawal at Mumbai branch.',
        ),
        isFalse,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  //  LESS COMMON BANKS
  // ═══════════════════════════════════════════════════════════════════

  group('Less Common Banks', () {
    test('Bank of Baroda', () {
      final result = TransactionParser.parse(
        'Rs.500.00 debited from Bank of Baroda A/c XX1234 via UPI on 13-02-26. Ref 412345678939.',
        'AD-BARODA',
        DateTime(2026, 2, 13),
      );

      expect(result, isNotNull);
      expect(result!.bankName, 'Bank of Baroda');
    });

    test('IDFC First Bank', () {
      final result = TransactionParser.parse(
        'Rs.500.00 debited from IDFC First Bank A/c XX1234 via UPI payment. Ref 412345678940.',
        'AD-IDFCFB',
        DateTime(2026, 2, 13),
      );

      expect(result, isNotNull);
      expect(result!.bankName, 'IDFC First Bank');
    });

    test('Federal Bank', () {
      final result = TransactionParser.parse(
        'Rs 500 debited from Federal Bank A/c XX1234 via UPI. Ref No 412345678941.',
        'AD-FEDBNK',
        DateTime(2026, 2, 13),
      );

      expect(result, isNotNull);
      expect(result!.bankName, 'Federal Bank');
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  //  MIXED / REAL-WORLD COMPLEX SCENARIOS
  // ═══════════════════════════════════════════════════════════════════

  group('Complex Real-World Scenarios', () {
    test('Transaction with balance info (debit + available balance)', () {
      final result = TransactionParser.parse(
        'Rs 500.00 debited from A/c XX1234 on 13-02-26 via UPI to merchant@ybl. Avl Bal Rs 15,000.50. UPI Ref 412345678942.',
        'AD-HDFCBK',
        DateTime(2026, 2, 13),
      );

      expect(result, isNotNull);
      expect(result!.amount, 500.00); // Should extract 500, not 15000
      expect(result.transactionType, 'debit');
    });

    test('Both credit and debit keywords (refund scenario)', () {
      final result = TransactionParser.parse(
        'UPI refund of Rs 200 credited to your account XX1234. Original txn was debited on 10-02-26. UPI Ref 412345678943.',
        'AD-HDFCBK',
        DateTime(2026, 2, 13),
      );

      expect(result, isNotNull);
      // "refund" should force credit classification
      expect(result!.transactionType, 'credit');
      expect(result.transactionSubType, 'refund');
    });

    test('NEFT without UPI indicator', () {
      final result = TransactionParser.parse(
        'Rs 10000 debited from A/c XX1234 for NEFT transfer to Beneficiary. NEFT Ref 412345678944.',
        'AD-HDFCBK',
        DateTime(2026, 2, 13),
      );

      expect(result, isNotNull);
      expect(
        result!.transactionSubType,
        'transfer',
      ); // NEFT without UPI = transfer
    });

    test('Auto-pay / mandate', () {
      final result = TransactionParser.parse(
        'Rs 499 debited from HDFC Bank A/c XX1234 towards auto-pay for Netflix subscription. UPI Ref 412345678945.',
        'AD-HDFCBK',
        DateTime(2026, 2, 13),
      );

      expect(result, isNotNull);
      expect(result!.amount, 499);
      expect(result.transactionType, 'debit');
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  //  TRUECALLER SMS
  // ═══════════════════════════════════════════════════════════════════

  group('Truecaller SMS', () {
    test('Truecaller debit - paid to merchant with pipe separator', () {
      final result = TransactionParser.parse(
        'Rs 250.00 paid to Swiggy via UPI from A/c XX1234 | HDFC Bank. UPI Ref 412345678999.',
        'TRUCLR',
        DateTime(2026, 2, 13),
      );

      expect(result, isNotNull);
      expect(result!.amount, 250.00);
      expect(result.transactionType, 'debit');
      expect(result.bankName, 'Truecaller');
    });

    test('Truecaller credit - money received', () {
      final result = TransactionParser.parse(
        'Rs 1500.00 received from JohnDoe@okaxis to A/c XX5678. UPI Ref 412345679000. HDFC Bank.',
        'TRUCAL',
        DateTime(2026, 2, 13),
      );

      expect(result, isNotNull);
      expect(result!.amount, 1500.00);
      expect(result.transactionType, 'credit');
    });

    test('Truecaller debit - standard bank relay format', () {
      final result = TransactionParser.parse(
        'Rs 500.00 has been debited from account *1234 to VPA merchant@upi on 13-02-26. UPI Ref No 412345679001. If not done by you call 18002586161.',
        'Truecaller',
        DateTime(2026, 2, 13),
      );

      expect(result, isNotNull);
      expect(result!.amount, 500.00);
      expect(result.transactionType, 'debit');
      expect(result.upiId, 'merchant@upi');
      expect(result.referenceId, '412345679001');
    });

    test('Truecaller debit - sent to merchant', () {
      final result = TransactionParser.parse(
        'Rs 350 sent to Zomato via UPI. Ref No 412345679002. Avl Bal Rs 4500.00.',
        'TRUECL',
        DateTime(2026, 2, 13),
      );

      expect(result, isNotNull);
      expect(result!.amount, 350.00);
      expect(result.transactionType, 'debit');
    });
  });
}
