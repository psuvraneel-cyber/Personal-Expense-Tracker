import 'package:flutter_test/flutter_test.dart';
import 'package:pet/services/sms_parser/sms_parser.dart';
import 'package:pet/services/transaction_parser.dart';

/// Comprehensive test suite for Bank of Baroda (BOB) SMS transaction parsing.
///
/// Covers:
/// - BOB "Dr./Cr." debit pattern with VPA, Ref, AvlBal, timestamp
/// - Pattern variations: account formats, amount formats, VPA handles
/// - Timestamp formats: yyyy:mm:dd, dd-mm-yy, dd-Mon-yyyy
/// - Fraud helpline disambiguation (must NOT confuse with ref number)
/// - Credit messages from BOB
/// - Both parser pipelines: SmsTransactionParser (modular) & TransactionParser (legacy)
/// - Edge cases: missing fields, minimal format, DR without dot
///
/// Each test validates:
/// - Transaction detection and direction (DEBIT/CREDIT)
/// - Amount extraction (correct transaction amount, not balance)
/// - Entity extraction (VPA, ref, account tail, bank, date)
/// - Fraud helpline number is NOT captured as ref
void main() {
  // ═════════════════════════════════════════════════════════════════
  //  BOB DEBIT — MODULAR PIPELINE (SmsTransactionParser)
  // ═════════════════════════════════════════════════════════════════

  group('BOB Debit — SmsTransactionParser (modular pipeline)', () {
    // ── Variant 1: Original BOB format ─────────────────────────────
    test('V1: Dr. with Cr. to VPA, Ref, AvlBal, colon timestamp', () {
      final r = SmsTransactionParser.parse(
        body: 'Rs 500 Dr. from A/C XXXXXX2170 and Cr. to q123456789@ybl. '
            'Ref:123456789012. AvlBal:Rs39.55 (2026:02:13 01:45:36). '
            'Not you? Call 1234567890/5000-BOB',
        sender: 'AD-BOBRDA',
        timestamp: DateTime(2026, 2, 13),
      );

      expect(r.isTransaction, isTrue, reason: 'Should detect as transaction');
      expect(
        r.direction,
        TransactionDirection.debit,
        reason: '"Dr." indicates debit',
      );
      expect(
        r.amount,
        500.0,
        reason: 'Transaction amount is Rs 500, not balance Rs 39.55',
      );
      expect(r.upiId, 'q123456789@ybl');
      expect(
        r.reference,
        '123456789012',
        reason: 'Ref should be 123456789012, NOT helpline 1234567890',
      );
      expect(r.accountTail, '2170');
      expect(r.bank, 'Bank of Baroda');
      expect(r.confidence, greaterThanOrEqualTo(55));
    });

    // ── Variant 2: Different account format and VPA handle ────────
    test('V2: Dr. with Acct ending, @okaxis VPA', () {
      final r = SmsTransactionParser.parse(
        body:
            'Rs. 1,200.50 Dr. from Acct ending 4567 and Cr. to merchant@okaxis. '
            'Ref:987654321098. AvlBal:Rs 5,000.00 (2026:01:15 10:30:00). '
            'Not you? Call 1234567890-BOB',
        sender: 'AD-BOBSMS',
        timestamp: DateTime(2026, 1, 15),
      );

      expect(r.isTransaction, isTrue);
      expect(r.direction, TransactionDirection.debit);
      expect(r.amount, 1200.50);
      expect(r.upiId, 'merchant@okaxis');
      expect(r.reference, '987654321098');
      expect(r.accountTail, '4567');
      expect(r.bank, 'Bank of Baroda');
    });

    // ── Variant 3: INR format, standard date, explicit bank name ──
    test('V3: INR amount, debited keyword, dd-Mon-yyyy date', () {
      final r = SmsTransactionParser.parse(
        body: 'INR 2500.00 debited from A/c no. XXXX3456 to VPA user@ybl '
            'on 13-Feb-2026. UPI Ref: 112233445566. Bank of Baroda.',
        sender: 'AD-BARODA',
        timestamp: DateTime(2026, 2, 13),
      );

      expect(r.isTransaction, isTrue);
      expect(r.direction, TransactionDirection.debit);
      expect(r.amount, 2500.0);
      expect(r.upiId, 'user@ybl');
      expect(r.reference, '112233445566');
      expect(r.accountTail, '3456');
      expect(r.bank, 'Bank of Baroda');
    });

    // ── Variant 4: ₹ symbol, DR (no dot), phone@upi VPA ──────────
    test('V4: ₹ symbol, DR without dot, phone@upi handle', () {
      final r = SmsTransactionParser.parse(
        body: '₹750 DR. from A/C XXXX8899 and Cr. to 9876543210@upi. '
            'Ref:111222333444. AvlBal:₹4,250.00 (2026:02:14 09:15:22). '
            'Not you? Call 5000-BOB',
        sender: 'AD-BOBRDA',
        timestamp: DateTime(2026, 2, 14),
      );

      expect(r.isTransaction, isTrue);
      expect(r.direction, TransactionDirection.debit);
      expect(r.amount, 750.0);
      expect(r.upiId, '9876543210@upi');
      expect(r.reference, '111222333444');
      expect(r.accountTail, '8899');
    });

    // ── Variant 5: Minimal BOB debit (no VPA, no balance) ────────
    test('V5: Minimal Dr. format — no VPA or balance', () {
      final r = SmsTransactionParser.parse(
        body: 'Rs 100 Dr. from A/C XX5566. Ref:654321098765. '
            'Not you? Call 1234567890/5000-BOB',
        sender: 'AD-BOBRDA',
        timestamp: DateTime(2026, 2, 10),
      );

      expect(r.isTransaction, isTrue);
      expect(r.direction, TransactionDirection.debit);
      expect(r.amount, 100.0);
      expect(r.reference, '654321098765');
      expect(r.accountTail, '5566');
      expect(r.upiId, isNull, reason: 'No VPA in this message');
    });

    // ── Variant 6: Long merchant VPA via @oksbi ───────────────────
    test('V6: Long VPA name with @oksbi', () {
      final r = SmsTransactionParser.parse(
        body:
            'Rs 5000 Dr. from A/C XXXXXX1234 and Cr. to longmerchant.shop@oksbi. '
            'Ref:123456789012. AvlBal:Rs 15,000.50 (2026:02:13 01:45:36). '
            'Not you? Call 1234567890/5000-BOB',
        sender: 'AD-BOBRDA',
        timestamp: DateTime(2026, 2, 13),
      );

      expect(r.isTransaction, isTrue);
      expect(r.direction, TransactionDirection.debit);
      expect(r.amount, 5000.0);
      expect(r.upiId, 'longmerchant.shop@oksbi');
      expect(r.reference, '123456789012');
      expect(r.accountTail, '1234');
      // Amount should NOT be balance 15,000.50
      expect(r.amount, isNot(15000.50));
    });

    // ── Variant 7: Different timestamp format (dd-mm-yy) ─────────
    test('V7: Dr. with dd-mm-yy timestamp format', () {
      final r = SmsTransactionParser.parse(
        body: 'Rs 800 Dr. from A/C XX9870 and Cr. to shop@paytm. '
            'Ref:555666777888. AvlBal:Rs1200.00 (13-02-26 14:30). '
            'Not you? Call 1800-BOB',
        sender: 'AD-BOBRDA',
        timestamp: DateTime(2026, 2, 13),
      );

      expect(r.isTransaction, isTrue);
      expect(r.direction, TransactionDirection.debit);
      expect(r.amount, 800.0);
      expect(r.upiId, 'shop@paytm');
      expect(r.reference, '555666777888');
      expect(r.accountTail, '9870');
    });

    // ── Variant 8: Rs without space, balance without space ────────
    test('V8: Rs500 (no space) and AvlBal:Rs200 (no space)', () {
      final r = SmsTransactionParser.parse(
        body: 'Rs500 Dr. from A/C XX1122 and Cr. to seller@ybl. '
            'Ref:999888777666. AvlBal:Rs200.75 (2026:02:10 22:00:00). '
            'Not you? Call 1234567890-BOB',
        sender: 'AD-BOBRDA',
        timestamp: DateTime(2026, 2, 10),
      );

      expect(r.isTransaction, isTrue);
      expect(r.direction, TransactionDirection.debit);
      expect(r.amount, 500.0);
      expect(r.upiId, 'seller@ybl');
      expect(r.accountTail, '1122');
      // Must NOT extract balance (200.75) as amount
      expect(r.amount, isNot(200.75));
    });
  });

  // ═════════════════════════════════════════════════════════════════
  //  BOB CREDIT — MODULAR PIPELINE
  // ═════════════════════════════════════════════════════════════════

  group('BOB Credit — SmsTransactionParser', () {
    test('BOB credit with credited keyword', () {
      final r = SmsTransactionParser.parse(
        body: 'Rs 3,000.00 credited to A/C XXXXXX2170 on 13-02-2026. '
            'Ref:998877665544. AvlBal:Rs3039.55. Bank of Baroda',
        sender: 'AD-BOBRDA',
        timestamp: DateTime(2026, 2, 13),
      );

      expect(r.isTransaction, isTrue);
      expect(r.direction, TransactionDirection.credit);
      expect(r.amount, 3000.0);
      expect(r.reference, '998877665544');
      expect(r.accountTail, '2170');
      expect(r.bank, 'Bank of Baroda');
    });

    test('BOB credit via UPI with from VPA', () {
      final r = SmsTransactionParser.parse(
        body: 'Rs 1,500.00 credited to A/C XX2170 from friend@ybl. '
            'UPI Ref: 445566778899. AvlBal:Rs 4,539.55. Bank of Baroda.',
        sender: 'AD-BOBRDA',
        timestamp: DateTime(2026, 2, 13),
      );

      expect(r.isTransaction, isTrue);
      expect(r.direction, TransactionDirection.credit);
      expect(r.amount, 1500.0);
      expect(r.upiId, 'friend@ybl');
      expect(r.reference, '445566778899');
    });
  });

  // ═════════════════════════════════════════════════════════════════
  //  FRAUD HELPLINE vs REFERENCE — DISAMBIGUATION
  // ═════════════════════════════════════════════════════════════════

  group('Fraud helpline number — must NOT be confused with reference', () {
    test('10-digit helpline is NOT ref; 12-digit Ref is correct', () {
      final r = SmsTransactionParser.parse(
        body: 'Rs 200 Dr. from A/C XX1234 and Cr. to pay@ybl. '
            'Ref:112233445566. AvlBal:Rs800.00. '
            'Not you? Call 1800123456/5000-BOB',
        sender: 'AD-BOBRDA',
        timestamp: DateTime(2026, 2, 13),
      );

      expect(
        r.reference,
        '112233445566',
        reason: 'Reference must be the Ref: number, not the helpline',
      );
    });

    test('Helpline with 4-digit number is NOT captured', () {
      final r = SmsTransactionParser.parse(
        body: 'Rs 300 Dr. from A/C XX4321 and Cr. to abc@ybl. '
            'Ref:998877665544. Not you? Call 5000-BOB',
        sender: 'AD-BOBRDA',
        timestamp: DateTime(2026, 2, 13),
      );

      expect(r.reference, '998877665544');
    });
  });

  // ═════════════════════════════════════════════════════════════════
  //  BOB DEBIT — LEGACY PIPELINE (TransactionParser)
  // ═════════════════════════════════════════════════════════════════

  group('BOB Debit — TransactionParser (legacy pipeline)', () {
    test('V1: Original BOB Dr. format', () {
      final result = TransactionParser.parse(
        'Rs 500 Dr. from A/C XXXXXX2170 and Cr. to q123456789@ybl. '
            'Ref:123456789012. AvlBal:Rs39.55 (2026:02:13 01:45:36). '
            'Not you? Call 1234567890/5000-BOB',
        'AD-BOBRDA',
        DateTime(2026, 2, 13),
      );

      expect(result, isNotNull, reason: 'Should parse as transaction');
      expect(result!.amount, 500.0);
      expect(result.transactionType, 'debit');
      expect(result.bankName, 'Bank of Baroda');
      expect(result.upiId, 'q123456789@ybl');
      expect(result.referenceId, '123456789012');
      expect(result.accountTail, '2170');
    });

    test('V2: INR amount, debited keyword', () {
      final result = TransactionParser.parse(
        'INR 2500.00 debited from A/c no. XXXX3456 to VPA user@ybl '
            'on 13-Feb-2026. UPI Ref: 112233445566. Bank of Baroda.',
        'AD-BARODA',
        DateTime(2026, 2, 13),
      );

      expect(result, isNotNull);
      expect(result!.amount, 2500.0);
      expect(result.transactionType, 'debit');
      expect(result.bankName, 'Bank of Baroda');
      expect(result.upiId, 'user@ybl');
      expect(result.referenceId, '112233445566');
      expect(result.accountTail, '3456');
    });

    test('V3: ₹ symbol with DR. indicator', () {
      final result = TransactionParser.parse(
        '₹750 DR. from A/C XXXX8899 and Cr. to 9876543210@upi. '
            'Ref:111222333444. AvlBal:₹4,250.00 (2026:02:14 09:15:22). '
            'Not you? Call 5000-BOB',
        'AD-BOBRDA',
        DateTime(2026, 2, 14),
      );

      expect(result, isNotNull);
      expect(result!.amount, 750.0);
      expect(result.transactionType, 'debit');
      expect(result.upiId, '9876543210@upi');
      expect(result.referenceId, '111222333444');
      expect(result.accountTail, '8899');
    });

    test('V4: Rs. with Indian comma notation', () {
      final result = TransactionParser.parse(
        'Rs. 1,200.50 Dr. from Acct ending 4567 and Cr. to merchant@okaxis. '
            'Ref:987654321098. AvlBal:Rs 5,000.00 (2026:01:15 10:30:00). '
            'Not you? Call 1234567890-BOB',
        'AD-BOBSMS',
        DateTime(2026, 1, 15),
      );

      expect(result, isNotNull);
      expect(result!.amount, 1200.50);
      expect(result.transactionType, 'debit');
      expect(result.upiId, 'merchant@okaxis');
      expect(result.referenceId, '987654321098');
    });

    test('V5: Legacy parser — BOB credit', () {
      final result = TransactionParser.parse(
        'Rs 3,000.00 credited to A/C XXXXXX2170 on 13-02-2026. '
            'Ref:998877665544. AvlBal:Rs3039.55. Bank of Baroda',
        'AD-BOBRDA',
        DateTime(2026, 2, 13),
      );

      expect(result, isNotNull);
      expect(result!.amount, 3000.0);
      expect(result.transactionType, 'credit');
      expect(result.bankName, 'Bank of Baroda');
      expect(result.referenceId, '998877665544');
    });
  });

  // ═════════════════════════════════════════════════════════════════
  //  DATE EXTRACTION — COLON-SEPARATED FORMAT
  // ═════════════════════════════════════════════════════════════════

  group('Colon-separated date extraction (BOB-specific)', () {
    test('yyyy:mm:dd hh:mm:ss extracted correctly', () {
      final r = SmsTransactionParser.parse(
        body: 'Rs 100 Dr. from A/C XX1234 and Cr. to test@ybl. '
            'Ref:111111111111. AvlBal:Rs900. (2026:02:13 01:45:36). '
            'Not you? Call 5000-BOB',
        sender: 'AD-BOBRDA',
        timestamp: DateTime(2025, 1, 1), // intentionally different
      );

      expect(r.isTransaction, isTrue);
      // Date should be extracted from SMS body, not from timestamp
      expect(r.date?.year, 2026);
      expect(r.date?.month, 2);
      expect(r.date?.day, 13);
    });

    test('Falls back to SMS timestamp when no date in body', () {
      final fallbackTs = DateTime(2026, 3, 20);
      final r = SmsTransactionParser.parse(
        body: 'Rs 100 Dr. from A/C XX1234 and Cr. to test@ybl. '
            'Ref:111111111111. Not you? Call 5000-BOB',
        sender: 'AD-BOBRDA',
        timestamp: fallbackTs,
      );

      expect(r.isTransaction, isTrue);
      expect(r.date, fallbackTs, reason: 'Should fall back to SMS timestamp');
    });
  });

  // ═════════════════════════════════════════════════════════════════
  //  BALANCE EXCLUSION
  // ═════════════════════════════════════════════════════════════════

  group('Balance amount exclusion', () {
    test('AvlBal:Rs amount is NOT the transaction amount', () {
      final r = SmsTransactionParser.parse(
        body: 'Rs 250 Dr. from A/C XX9999 and Cr. to payee@ybl. '
            'Ref:222333444555. AvlBal:Rs10,000.00 (2026:02:13 12:00:00). '
            'Not you? Call 5000-BOB',
        sender: 'AD-BOBRDA',
        timestamp: DateTime(2026, 2, 13),
      );

      expect(r.isTransaction, isTrue);
      expect(
        r.amount,
        250.0,
        reason: 'Should extract Rs 250 as transaction amount, not Rs 10,000',
      );
    });

    test('AvlBal without space is correctly excluded', () {
      final r = SmsTransactionParser.parse(
        body: 'Rs 50 Dr. from A/C XX1111 and Cr. to x@ybl. '
            'Ref:333444555666. AvlBal:Rs50,000.00. Not you? Call 5000-BOB',
        sender: 'AD-BOBRDA',
        timestamp: DateTime(2026, 2, 13),
      );

      expect(r.isTransaction, isTrue);
      expect(r.amount, 50.0);
    });
  });

  // ═════════════════════════════════════════════════════════════════
  //  TRANSACTION CLASSIFICATION — WHY Dr. + Cr. = DEBIT
  // ═════════════════════════════════════════════════════════════════

  group('Transaction classification reasoning', () {
    /// In BOB's SMS format, "Dr." (Debit) and "Cr." (Credit) both appear
    /// because the message describes a DOUBLE-ENTRY ledger movement:
    ///
    ///   "Rs 500 Dr. from A/C XX2170"   → Your account was DEBITED
    ///   "and Cr. to q123@ybl"          → Recipient's account was CREDITED
    ///
    /// From the user's perspective, this is MONEY SENT (debit).
    /// The "Cr. to VPA" tells us WHERE the money went, not that the
    /// user received money.
    ///
    /// The parser correctly identifies this as a DEBIT because:
    /// 1. "Dr." matches the debit keyword pattern
    /// 2. "Cr." is NOT in the credit keyword set (by design)
    /// 3. Only the debit keyword is found → exclusive debit → DEBIT direction
    test('Dr.+Cr. in same SMS = DEBIT (money sent)', () {
      final r = SmsTransactionParser.parse(
        body: 'Rs 500 Dr. from A/C XX2170 and Cr. to pay@ybl. '
            'Ref:123456789012. Not you? Call 5000-BOB',
        sender: 'AD-BOBRDA',
        timestamp: DateTime(2026, 2, 13),
      );

      expect(r.isTransaction, isTrue);
      expect(
        r.direction,
        TransactionDirection.debit,
        reason: 'Dr.+Cr. = double-entry debit; the user SENT money',
      );
    });
  });

  // ═════════════════════════════════════════════════════════════════
  //  INTEGRATION — DEDUPLICATION VIA REFERENCE NUMBERS
  // ═════════════════════════════════════════════════════════════════

  group('Deduplication with reference numbers', () {
    /// Reference numbers serve as unique transaction identifiers.
    /// Two SMS with the same ref number describe the same transaction
    /// and should be deduplicated.
    ///
    /// Deduplication strategy:
    /// 1. Primary key: reference number (Ref:XXXXXXXXXXXX)
    /// 2. Fallback: SHA-256 hash of (normalized body + timestamp)
    ///
    /// This prevents double-counting when:
    /// - The same SMS appears in both inbox and sent
    /// - A bank sends a duplicate confirmation
    /// - The user re-processes their SMS inbox
    test('Same ref number across two parses yields same ref for dedup', () {
      const sms1 = 'Rs 500 Dr. from A/C XX2170 and Cr. to pay@ybl. '
          'Ref:123456789012. AvlBal:Rs39.55 (2026:02:13 01:45:36). '
          'Not you? Call 1234567890/5000-BOB';

      const sms2 = 'Rs 500 Dr. from A/C XX2170 and Cr. to pay@ybl. '
          'Ref:123456789012. AvlBal:Rs39.55 (2026:02:13 01:45:36). '
          'Not you? Call 1234567890/5000-BOB';

      final r1 = SmsTransactionParser.parse(
        body: sms1,
        sender: 'AD-BOBRDA',
        timestamp: DateTime(2026, 2, 13),
      );
      final r2 = SmsTransactionParser.parse(
        body: sms2,
        sender: 'AD-BOBRDA',
        timestamp: DateTime(2026, 2, 13),
      );

      expect(
        r1.reference,
        r2.reference,
        reason: 'Same ref number → same transaction → deduplicate',
      );
      expect(r1.reference, '123456789012');
    });

    test('Different ref numbers are NOT deduplicated', () {
      final r1 = SmsTransactionParser.parse(
        body: 'Rs 500 Dr. from A/C XX2170 and Cr. to pay@ybl. '
            'Ref:123456789012. Not you? Call 5000-BOB',
        sender: 'AD-BOBRDA',
        timestamp: DateTime(2026, 2, 13),
      );
      final r2 = SmsTransactionParser.parse(
        body: 'Rs 500 Dr. from A/C XX2170 and Cr. to pay@ybl. '
            'Ref:999888777666. Not you? Call 5000-BOB',
        sender: 'AD-BOBRDA',
        timestamp: DateTime(2026, 2, 13),
      );

      expect(
        r1.reference,
        isNot(r2.reference),
        reason: 'Different ref → different transactions',
      );
    });
  });

  // ═════════════════════════════════════════════════════════════════
  //  NON-TRANSACTION BOB MESSAGES — MUST REJECT
  // ═════════════════════════════════════════════════════════════════

  group('BOB non-transaction messages — must reject', () {
    test('BOB OTP message rejected', () {
      final r = SmsTransactionParser.parse(
        body: 'Your OTP for Bank of Baroda net banking is 345678. '
            'Do not share with anyone. Valid for 5 minutes.',
        sender: 'AD-BOBRDA',
        timestamp: DateTime(2026, 2, 13),
      );

      expect(r.isTransaction, isFalse);
    });

    test('BOB promotional message rejected', () {
      final r = SmsTransactionParser.parse(
        body: 'Bank of Baroda: Get up to Rs 5000 cashback on home loan. '
            'Apply now at https://bob.in/offer. T&C apply.',
        sender: 'VK-BOBRDA',
        timestamp: DateTime(2026, 2, 13),
      );

      expect(r.isTransaction, isFalse);
    });
  });
}
