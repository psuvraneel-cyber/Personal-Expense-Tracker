import 'package:flutter_test/flutter_test.dart';
import 'package:pet/data/models/financial_observation.dart';
import 'package:pet/services/classification_rule_engine.dart';
import 'package:pet/services/financial_ingestion_service.dart';
import 'package:pet/services/sms_parser/sender_identity.dart';

/// Bank alerts that do not name the other party (e.g. Bank of Baroda UPI
/// credits) are imported without review when they come from the bank's own
/// service sender ID and carry a reference number.
void main() {
  final when = DateTime(2026, 10, 10, 12, 41, 40);

  Future<ClassifiedTransaction?> classify(String body, String sender) =>
      ClassificationRuleEngine.classify(body, sender, when, logUnknown: false);

  Future<bool> verified(
    String body,
    String sender, {
    FinancialObservationSource source = FinancialObservationSource.sms,
  }) async {
    final c = await classify(body, sender);
    if (c == null) return false;
    return FinancialIngestionService.isVerifiedBankAlertFor(
      source: source,
      sender: sender,
      classified: c,
    );
  }

  const bobCredit = 'Dear BOB UPI User: Your account is credited with INR '
      '75.00 on 2026-10-10 12:41:33 PM by UPI Ref No 628300011122; '
      'AvlBal: Rs305.77 - BOB';

  group('SenderIdentity.isBankServiceSender', () {
    test('bank service and transactional headers, any operator/circle', () {
      for (final s in [
        'JK-BOBSMS-S',
        'VK-BOBSMS-S',
        'VM-HDFCBK-T',
        'AD-SBIUPI',
        'jd-icicit-s',
      ]) {
        expect(SenderIdentity.isBankServiceSender(s), isTrue, reason: s);
      }
    });

    test('promotional bank headers, merchants and phone numbers', () {
      for (final s in [
        'JK-BOBSMS-P',
        'TX-SWIGGY-S',
        'CP-URBNCP-S',
        'JK-JIOPAY-S',
        '+919876543210',
        'BOBSMS',
      ]) {
        expect(SenderIdentity.isBankServiceSender(s), isFalse, reason: s);
      }
    });
  });

  group('verified bank alert', () {
    test('BoB UPI credit without a payee is auto-accepted', () async {
      final c = await classify(bobCredit, 'JK-BOBSMS-S');
      expect(c, isNotNull);
      expect(c!.transactionType, 'credit');
      expect(c.merchantName, 'Unknown');
      // Below the 0.80 bar on confidence alone: this is the rule doing it.
      expect(c.confidence, lessThan(0.80));
      expect(await verified(bobCredit, 'JK-BOBSMS-S'), isTrue);
      expect(FinancialIngestionService.unnamedPayeeLabel(c), 'UPI credit');
    });

    test('same text from a promotional header is not trusted', () async {
      expect(await verified(bobCredit, 'JK-BOBSMS-P'), isFalse);
    });

    test('same text from an unregistered or personal sender is not trusted',
        () async {
      expect(await verified(bobCredit, 'AD-OFFERS'), isFalse);
      expect(await verified(bobCredit, '+919876543210'), isFalse);
    });

    test('a payment-app notification is never a verified bank alert', () async {
      expect(
        await verified(
          bobCredit,
          'JK-BOBSMS-S',
          source: FinancialObservationSource.notification,
        ),
        isFalse,
      );
    });

    test('merchant payment confirmations stay in review', () async {
      const swiggy = 'Payment Confirmed! Your Swiggy Order 2208123456789 of '
          'Rs. 124.00 was successfully paid on 22/09/26 at 4:41 PM. '
          'Txn ID: 9988776655. Enjoy your order!';
      expect(await verified(swiggy, 'TX-SWIGGY-S'), isFalse);
    });

    test('a bank alert without a reference number is not enough', () async {
      const noRef = 'Dear BOB UPI User: Your account is credited with INR '
          '75.00 on 2026-10-10 12:41:33 PM; AvlBal: Rs305.77 - BOB';
      expect(await verified(noRef, 'JK-BOBSMS-S'), isFalse);
    });
  });
}
