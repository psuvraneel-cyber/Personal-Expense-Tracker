import 'package:flutter_test/flutter_test.dart';
import 'package:pet/services/sms_parser/transaction_evidence.dart';

/// Real money movements vs offers that only look like them.
void main() {
  group('TransactionEvidence.assess', () {
    test('a plain bank alert is clean', () {
      expect(
        TransactionEvidence.assess(
          'Rs 500.00 debited from A/c XX1234 at Swiggy. Ref 412345678901.',
          accountTail: '1234',
          referenceId: '412345678901',
        ),
        OfferVerdict.clean,
      );
    });

    test('a real alert with an ad footer stays clean', () {
      expect(
        TransactionEvidence.assess(
          'Rs 2,000 credited to A/c XX1234. Avl Bal Rs 15,400. Get a '
          'pre-approved personal loan up to 5 lakh, apply now.',
          accountTail: '1234',
          balanceAfter: 15400,
        ),
        OfferVerdict.clean,
      );
    });

    test('an offer dressed as a credit is rejected', () {
      expect(
        TransactionEvidence.assess(
          'Congrats! Get Rs 500 cashback credited to your account. Use code '
          'SAVE50. T&C apply.',
        ),
        OfferVerdict.reject,
      );
    });

    test('offer wording with only weak evidence goes to review', () {
      expect(
        TransactionEvidence.assess(
          'Rs 100 credited to your Paytm wallet. Earn more on your next '
          'recharge.',
          referenceId: '987654321',
        ),
        OfferVerdict.review,
      );
    });

    test('a payment-app notification without offer words is clean', () {
      expect(
        TransactionEvidence.assess('Paid ₹350 to Starbucks'),
        OfferVerdict.clean,
      );
    });

    test('evidence counts account, reference and balance only', () {
      expect(
        TransactionEvidence.hardEvidence(
          accountTail: '1234',
          referenceId: '123', // too short to be a real reference
          balanceAfter: 10,
        ),
        2,
      );
    });
  });
}
