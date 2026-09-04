import 'package:flutter_test/flutter_test.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/sms_transaction.dart';
import 'package:pet/premium/services/recurring_detection_service.dart';

SmsTransaction _createSms({
  required String id,
  required String merchantName,
  required double amount,
  required DateTime timestamp,
}) {
  final body = 'Debited Rs.$amount at $merchantName on ${timestamp.toIso8601String()}';
  return SmsTransaction(
    id: id,
    amount: amount,
    merchantName: merchantName,
    bankName: 'HDFC',
    transactionType: 'debit',
    timestamp: timestamp,
    rawSmsBody: body,
    smsSender: 'HDFC-BANK',
    smsHash: SmsTransaction.generateHash(body, timestamp),
  );
}

void main() {
  group('RecurringDetectionService Intelligence & Deduplication', () {
    test('normalizes merchant names conservatively', () {
      expect(
        RecurringDetectionService.normalizeMerchantName('NETFLIX INDIA PVT LTD'),
        equals('Netflix'),
      );
      expect(
        RecurringDetectionService.normalizeMerchantName('Spotify.com'),
        equals('Spotify'),
      );
      expect(
        RecurringDetectionService.normalizeMerchantName('UPI/BESCOM Electricity/41234'),
        equals('Bescom Electricity 41234'),
      );
      expect(
        RecurringDetectionService.normalizeMerchantName('Pay to Cult.fit India'),
        equals('Cult Fit'),
      );
      expect(
        RecurringDetectionService.normalizeMerchantName('Amazon Prime Video'),
        equals('Amazon Prime Video'),
      );
    });

    test('detects monthly recurring subscription from 3 consistent transactions', () {
      final txns = <SmsTransaction>[
        _createSms(
          id: '1',
          merchantName: 'NETFLIX INDIA',
          amount: 249.0,
          timestamp: DateTime(2026, 5, 20),
        ),
        _createSms(
          id: '2',
          merchantName: 'Netflix.com',
          amount: 249.0,
          timestamp: DateTime(2026, 6, 20),
        ),
        _createSms(
          id: '3',
          merchantName: 'Netflix',
          amount: 249.0,
          timestamp: DateTime(2026, 7, 20),
        ),
      ];

      final results = RecurringDetectionService.detect(txns);
      expect(results.length, equals(1));
      final detected = results.first;
      expect(detected.merchantName, equals('Netflix'));
      expect(detected.amount, equals(249.0));
      expect(detected.frequency, equals('monthly'));
      expect(detected.status, equals(RecurringStatus.detected));
      expect(detected.confidence, equals(0.85));
      expect(detected.isPriceChanged, isFalse);
      expect(detected.nextDueAt.month, equals(8));
      expect(detected.nextDueAt.day, equals(20));
    });

    test('detects price hike when subscription amount increases from baseline', () {
      final txns = <SmsTransaction>[
        _createSms(
          id: '1',
          merchantName: 'Netflix',
          amount: 199.0,
          timestamp: DateTime(2026, 4, 15),
        ),
        _createSms(
          id: '2',
          merchantName: 'Netflix',
          amount: 199.0,
          timestamp: DateTime(2026, 5, 15),
        ),
        _createSms(
          id: '3',
          merchantName: 'Netflix',
          amount: 249.0,
          timestamp: DateTime(2026, 6, 15),
        ),
      ];

      final results = RecurringDetectionService.detect(txns);
      expect(results.length, equals(1));
      final detected = results.first;
      expect(detected.merchantName, equals('Netflix'));
      expect(detected.amount, equals(249.0));
      expect(detected.previousAmount, equals(199.0));
      expect(detected.isPriceChanged, isTrue);
      expect(detected.priceDifference, equals(50.0));
      expect(detected.detectionReason, contains('price change from ₹199 to ₹249'));
    });

    test('rejects erratic variable spending (e.g. Swiggy food delivery) from recurring detection', () {
      final txns = <SmsTransaction>[
        _createSms(
          id: '1',
          merchantName: 'Swiggy',
          amount: 145.0,
          timestamp: DateTime(2026, 5, 1),
        ),
        _createSms(
          id: '2',
          merchantName: 'Swiggy',
          amount: 890.0,
          timestamp: DateTime(2026, 5, 12),
        ),
        _createSms(
          id: '3',
          merchantName: 'Swiggy',
          amount: 320.0,
          timestamp: DateTime(2026, 6, 3),
        ),
      ];

      final results = RecurringDetectionService.detect(txns);
      expect(results, isEmpty);
    });

    test('detects quarterly (every 3 months) recurring commitments', () {
      final txns = <SmsTransaction>[
        _createSms(
          id: '1',
          merchantName: 'Society Maintenance',
          amount: 1500.0,
          timestamp: DateTime(2026, 1, 1),
        ),
        _createSms(
          id: '2',
          merchantName: 'Society Maintenance',
          amount: 1500.0,
          timestamp: DateTime(2026, 4, 1),
        ),
      ];

      final results = RecurringDetectionService.detect(txns);
      expect(results.length, equals(1));
      expect(results.first.frequency, equals('quarterly'));
      expect(results.first.nextDueAt.month, equals(7));
      expect(results.first.nextDueAt.day, equals(1));
    });
  });
}
