import 'package:flutter_test/flutter_test.dart';
import 'package:pet/data/models/financial_observation.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/services/canonical_identity_resolver.dart';

void main() {
  group('Phase P0 - FinancialObservation & Provenance Tests', () {
    test('FinancialObservation serialization and copyWith work properly', () {
      final now = DateTime(2026, 9, 4, 12, 30);
      final obs = FinancialObservation(
        observationId: 'obs-123',
        source: FinancialObservationSource.notification,
        sourceIdentifier: 'com.phonepe.app',
        packageName: 'com.phonepe.app',
        title: 'Paid to Starbucks',
        body: 'Rs 350.00 debited from A/c XX1234',
        normalizedText: 'Paid to Starbucks — Rs 350.00 debited from A/c XX1234',
        receivedAt: now,
        sourceTimestamp: now,
        observationHash: 'hash-abc',
        sourceFingerprint: 'fp-xyz',
        confidence: 0.95,
        accountTail: '1234',
        state: FinancialObservationState.accepted,
      );

      final map = obs.toMap();
      expect(map['observationId'], 'obs-123');
      expect(map['source'], 'notification');
      expect(map['accountTail'], '1234');
      expect(map['state'], 'accepted');

      final deserialized = FinancialObservation.fromMap(map);
      expect(deserialized.observationId, obs.observationId);
      expect(deserialized.source, FinancialObservationSource.notification);
      expect(deserialized.accountTail, '1234');
      expect(deserialized.confidence, 0.95);
      expect(deserialized.normalizedText, contains('Starbucks'));
    });

    test('TransactionRecord carries provenance fields', () {
      final txn = TransactionRecord(
        id: 'txn-1',
        amount: 350.0,
        type: TransactionType.expense,
        categoryId: 'cat_food',
        date: DateTime(2026, 9, 4),
        source: TransactionSource.notification,
        sourceObservationId: 'obs-123',
        sourceFingerprint: 'fp-xyz',
      );

      final map = txn.toMap();
      expect(map['sourceObservationId'], 'obs-123');
      expect(map['sourceFingerprint'], 'fp-xyz');
      expect(map['source'], 'notification');

      final fromMap = TransactionRecord.fromMap(map);
      expect(fromMap.sourceObservationId, 'obs-123');
      expect(fromMap.sourceFingerprint, 'fp-xyz');
      expect(fromMap.source, TransactionSource.notification);
    });

    test('CanonicalIdentityResolver clusters identical reference IDs', () {
      final time1 = DateTime(2026, 9, 4, 10, 0);
      final time2 = DateTime(2026, 9, 4, 10, 3); // 3 mins later

      final fp1 = CanonicalIdentityResolver.generateFingerprint(
        referenceId: 'UPI/424512345678',
        amount: 450.0,
        timestamp: time1,
      );

      final fp2 = CanonicalIdentityResolver.generateFingerprint(
        referenceId: '424512345678',
        amount: 450.0,
        timestamp: time2,
      );

      expect(fp1, equals(fp2), reason: 'Reference IDs must match across SMS and notification');
    });

    test('CanonicalIdentityResolver matches account tail and amount within 15 min window', () {
      final time1 = DateTime(2026, 9, 4, 10, 5);
      final time2 = DateTime(2026, 9, 4, 10, 9); // 4 mins later (same 15 min bucket)

      final same = CanonicalIdentityResolver.areSameEvent(
        amount1: 500.0,
        time1: time1,
        tail1: '1234',
        amount2: 500.0,
        time2: time2,
        tail2: '1234',
      );

      expect(same, isTrue);
    });

    test('CanonicalIdentityResolver does not falsely match distinct transactions', () {
      final time1 = DateTime(2026, 9, 4, 10, 0);
      final time2 = DateTime(2026, 9, 4, 10, 45); // 45 mins later

      final same = CanonicalIdentityResolver.areSameEvent(
        amount1: 500.0,
        time1: time1,
        merchant1: 'Starbucks',
        amount2: 500.0,
        time2: time2,
        merchant2: 'Starbucks',
      );

      expect(same, isFalse, reason: 'Transactions 45 mins apart should not be falsely merged without strong reference');
    });
  });
}
