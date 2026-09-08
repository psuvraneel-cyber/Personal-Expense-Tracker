import 'package:flutter_test/flutter_test.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/premium/models/recurring_payment.dart';

void main() {
  group('RecurringPayment Model & Financial Calculations', () {
    test('serializes and deserializes correctly via fromMap / toMap', () {
      final now = DateTime(2026, 8, 15, 10, 0);
      final payment = RecurringPayment(
        id: 'rec_1',
        merchantName: 'Netflix',
        amount: 249.0,
        frequency: 'monthly',
        lastPaidAt: now.subtract(const Duration(days: 30)),
        nextDueAt: now,
        categoryId: 'entertainment',
        confidence: 0.95,
        source: 'sms',
        status: RecurringStatus.confirmed,
        isAutopay: true,
        previousAmount: 199.0,
        priceChangeDetectedAt: now.subtract(const Duration(days: 30)),
        notes: 'Premium 4K plan',
        detectionReason: 'Detected from 4 SMS debits',
      );

      final map = payment.toMap();
      expect(map['id'], 'rec_1');
      expect(map['status'], 'confirmed');
      expect(map['isAutopay'], 1);
      expect(map['previousAmount'], 199.0);

      final deserialized = RecurringPayment.fromMap(map);
      expect(deserialized.id, 'rec_1');
      expect(deserialized.merchantName, 'Netflix');
      expect(deserialized.amount, 249.0);
      expect(deserialized.status, RecurringStatus.confirmed);
      expect(deserialized.isAutopay, isTrue);
      expect(deserialized.isPriceChanged, isTrue);
      expect(deserialized.priceDifference, equals(50.0));
      expect(deserialized.notes, 'Premium 4K plan');
    });

    test('calculates correct annual and monthly equivalent amounts across frequencies', () {
      final baseDate = DateTime(2026, 1, 1);

      // Monthly ₹500 -> Annual = ₹6,000, Monthly = ₹500
      final monthly = RecurringPayment(
        id: '1',
        merchantName: 'Gym',
        amount: 500,
        frequency: 'monthly',
        lastPaidAt: baseDate,
        nextDueAt: baseDate.add(const Duration(days: 30)),
        categoryId: 'fitness',
      );
      expect(monthly.annualAmount, equals(6000.0));
      expect(monthly.monthlyEquivalentAmount, equals(500.0));

      // Quarterly ₹3,000 -> Annual = ₹12,000, Monthly = ₹1,000
      final quarterly = RecurringPayment(
        id: '2',
        merchantName: 'Insurance',
        amount: 3000,
        frequency: 'quarterly',
        lastPaidAt: baseDate,
        nextDueAt: baseDate.add(const Duration(days: 90)),
        categoryId: 'insurance',
      );
      expect(quarterly.annualAmount, equals(12000.0));
      expect(quarterly.monthlyEquivalentAmount, equals(1000.0));

      // Semiannual ₹5,000 -> Annual = ₹10,000, Monthly = ₹833.33
      final semiannual = RecurringPayment(
        id: '3',
        merchantName: 'Term Fee',
        amount: 5000,
        frequency: 'semiannual',
        lastPaidAt: baseDate,
        nextDueAt: baseDate.add(const Duration(days: 180)),
        categoryId: 'education',
      );
      expect(semiannual.annualAmount, equals(10000.0));
      expect(semiannual.monthlyEquivalentAmount, closeTo(833.33, 0.1));

      // Yearly ₹24,000 -> Annual = ₹24,000, Monthly = ₹2,000
      final yearly = RecurringPayment(
        id: '4',
        merchantName: 'Car Insurance',
        amount: 24000,
        frequency: 'yearly',
        lastPaidAt: baseDate,
        nextDueAt: baseDate.add(const Duration(days: 365)),
        categoryId: 'insurance',
      );
      expect(yearly.annualAmount, equals(24000.0));
      expect(yearly.monthlyEquivalentAmount, equals(2000.0));

      // Weekly ₹1,000 -> Annual = ₹52,000, Monthly = ~₹4,333.33
      final weekly = RecurringPayment(
        id: '5',
        merchantName: 'Maid',
        amount: 1000,
        frequency: 'weekly',
        lastPaidAt: baseDate,
        nextDueAt: baseDate.add(const Duration(days: 7)),
        categoryId: 'home',
      );
      expect(weekly.annualAmount, equals(52000.0));
      expect(weekly.monthlyEquivalentAmount, closeTo(4333.33, 0.1));
    });

    test('handles price change detection accurately without false positives', () {
      final now = DateTime.now();

      final noChange = RecurringPayment(
        id: '1',
        merchantName: 'Spotify',
        amount: 119.0,
        frequency: 'monthly',
        lastPaidAt: now,
        nextDueAt: now.add(const Duration(days: 30)),
        categoryId: 'music',
        previousAmount: 119.0, // Same amount
      );
      expect(noChange.isPriceChanged, isFalse);

      final priceHike = RecurringPayment(
        id: '2',
        merchantName: 'Spotify',
        amount: 149.0,
        frequency: 'monthly',
        lastPaidAt: now,
        nextDueAt: now.add(const Duration(days: 30)),
        categoryId: 'music',
        previousAmount: 119.0, // +30 hike
      );
      expect(priceHike.isPriceChanged, isTrue);
      expect(priceHike.priceDifference, equals(30.0));

      final priceDrop = RecurringPayment(
        id: '3',
        merchantName: 'Cloud Storage',
        amount: 80.0,
        frequency: 'monthly',
        lastPaidAt: now,
        nextDueAt: now.add(const Duration(days: 30)),
        categoryId: 'tech',
        previousAmount: 100.0, // -20 discount
      );
      expect(priceDrop.isPriceChanged, isTrue);
      expect(priceDrop.priceDifference, equals(-20.0));
    });
  });
}
