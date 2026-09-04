import 'package:flutter_test/flutter_test.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/premium/models/recurring_payment.dart';
import 'package:pet/premium/services/cashflow_forecast_service.dart';

void main() {
  group('CashflowForecastService with Confirmed Recurring Commitments', () {
    final now = DateTime.now();

    test('integrates confirmed upcoming bill without double-counting historical expenses', () {
      final txns = <TransactionRecord>[
        TransactionRecord(
          id: '1',
          amount: 50000,
          type: TransactionType.income,
          categoryId: 'salary',
          date: now.subtract(const Duration(days: 20)),
        ),
        TransactionRecord(
          id: '2',
          amount: 20000,
          type: TransactionType.expense,
          categoryId: 'general',
          date: now.subtract(const Duration(days: 5)),
        ),
      ];

      // Confirmed rent bill due on Day 5 (now.day + 5)
      final confirmedBills = <RecurringPayment>[
        RecurringPayment(
          id: 'rent_1',
          merchantName: 'Landlord Rent',
          amount: 15000,
          frequency: 'monthly',
          lastPaidAt: now.subtract(const Duration(days: 25)),
          nextDueAt: DateTime(now.year, now.month, now.day + 5),
          categoryId: 'rent',
          status: RecurringStatus.confirmed,
        ),
      ];

      final forecastWithBill = CashflowForecastService.forecast(
        txns,
        confirmedBills: confirmedBills,
        days: 30,
      );

      expect(forecastWithBill.startingBalance, equals(30000.0));
      expect(forecastWithBill.dailyPoints.length, equals(30));

      // In loop i=0..29, dailyPoints[i] corresponds to now.day + i.
      // Day 4 is index 4 (now.day + 4), Day 5 is index 5 (now.day + 5).
      final day3ToDay4Growth = forecastWithBill.dailyPoints[4].balance - forecastWithBill.dailyPoints[3].balance;
      final day4ToDay5Growth = forecastWithBill.dailyPoints[5].balance - forecastWithBill.dailyPoints[4].balance;

      // The growth rate drops by exactly ₹15,000 on Day 5 due to the rent bill
      expect(day3ToDay4Growth - day4ToDay5Growth, equals(15000.0));
    });

    test('unconfirmed detected bills are NOT injected into cashflow projection', () {
      final txns = <TransactionRecord>[
        TransactionRecord(
          id: '1',
          amount: 50000,
          type: TransactionType.income,
          categoryId: 'salary',
          date: now.subtract(const Duration(days: 20)),
        ),
      ];

      final unconfirmed = <RecurringPayment>[
        RecurringPayment(
          id: 'unconfirmed_1',
          merchantName: 'Possible Gym',
          amount: 5000,
          frequency: 'monthly',
          lastPaidAt: now.subtract(const Duration(days: 20)),
          nextDueAt: DateTime(now.year, now.month, now.day + 3),
          categoryId: 'other',
          status: RecurringStatus.detected, // Unconfirmed candidate
        ),
      ];

      final forecastWithCandidate = CashflowForecastService.forecast(
        txns,
        confirmedBills: unconfirmed,
        days: 30,
      );

      final forecastPure = CashflowForecastService.forecast(
        txns,
        days: 30,
      );

      // Unconfirmed candidate must not alter the balance projection
      expect(
        forecastWithCandidate.projectedEndingBalance,
        equals(forecastPure.projectedEndingBalance),
      );
    });
  });
}
