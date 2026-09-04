import 'package:flutter_test/flutter_test.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/premium/services/cashflow_forecast_service.dart';

void main() {
  group('CashflowForecastService', () {
    final now = DateTime.now();

    test('calculates positive net baseline and daily projections correctly with sufficient data', () {
      final txns = <TransactionRecord>[
        TransactionRecord(
          id: '1',
          amount: 50000,
          type: TransactionType.income,
          categoryId: 'salary',
          date: now.subtract(const Duration(days: 12)),
        ),
        TransactionRecord(
          id: '2',
          amount: 20000,
          type: TransactionType.expense,
          categoryId: 'rent',
          date: now.subtract(const Duration(days: 2)),
        ),
      ];

      final forecast = CashflowForecastService.forecast(txns, days: 30);

      expect(forecast.startingBalance, equals(30000.0));
      expect(forecast.hasNegativeStartingBalance, isFalse);
      expect(forecast.hasInsufficientData, isFalse); // Span is 10 + 1 = 11 days >= 7
      expect(forecast.safeToSpend, greaterThan(0));
      expect(forecast.dailyPoints.length, equals(30));
    });

    test('retains negative baseline when recorded expenses exceed income', () {
      final txns = <TransactionRecord>[
        TransactionRecord(
          id: '1',
          amount: 15000,
          type: TransactionType.expense,
          categoryId: 'shopping',
          date: now.subtract(const Duration(days: 10)),
        ),
        TransactionRecord(
          id: '2',
          amount: 5000,
          type: TransactionType.income,
          categoryId: 'freelance',
          date: now.subtract(const Duration(days: 1)),
        ),
      ];

      final forecast = CashflowForecastService.forecast(txns, days: 30);

      // Starting balance should be exactly 5000 - 15000 = -10000, not clamped to 0!
      expect(forecast.startingBalance, equals(-10000.0));
      expect(forecast.hasNegativeStartingBalance, isTrue);
      // Safe to spend should be 0 when in deficit
      expect(forecast.safeToSpend, equals(0.0));
      // Daily projection points should start from true negative balance
      expect(forecast.dailyPoints.first.balance, isNotNull);
    });

    test('flags hasInsufficientData when transaction span is less than 7 days', () {
      final txns = <TransactionRecord>[
        TransactionRecord(
          id: '1',
          amount: 1000,
          type: TransactionType.expense,
          categoryId: 'food',
          date: now.subtract(const Duration(days: 2)),
        ),
      ];

      final forecast = CashflowForecastService.forecast(txns, days: 30);
      expect(forecast.hasInsufficientData, isTrue);
    });

    test('handles zero transactions safely', () {
      final forecast = CashflowForecastService.forecast(<TransactionRecord>[], days: 30);

      expect(forecast.startingBalance, equals(0.0));
      expect(forecast.projectedEndingBalance, equals(0.0));
      expect(forecast.safeToSpend, equals(0.0));
      expect(forecast.hasInsufficientData, isTrue);
      expect(forecast.hasNegativeStartingBalance, isFalse);
    });
  });
}
