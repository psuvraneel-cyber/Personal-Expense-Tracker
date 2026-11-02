import 'package:flutter_test/flutter_test.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/premium/services/cashflow_forecast_service.dart';

TransactionRecord _salary(DateTime date, [double amount = 50000]) =>
    TransactionRecord(
      id: 'sal_${date.toIso8601String()}',
      amount: amount,
      type: TransactionType.income,
      categoryId: 'cat_salary',
      date: date,
    );

TransactionRecord _expense(DateTime date, double amount) => TransactionRecord(
      id: 'exp_${date.toIso8601String()}',
      amount: amount,
      type: TransactionType.expense,
      categoryId: 'cat_food',
      date: date,
    );

/// ₹1,000 of spending every day for the 90 days before [now].
List<TransactionRecord> _dailySpending(DateTime now) => [
      for (var i = 1; i <= 90; i++)
        _expense(now.subtract(Duration(days: i)), 1000),
    ];

void main() {
  setUp(CashflowForecastService.clearCache);

  group('detectPayday', () {
    final now = DateTime(2026, 11, 10);

    test('salary on the same day each month', () {
      final schedule = CashflowForecastService.detectPayday([
        _salary(DateTime(2026, 8, 1)),
        _salary(DateTime(2026, 9, 1), 52000),
        _salary(DateTime(2026, 10, 2)),
        _salary(DateTime(2026, 11, 1)),
      ], now);
      expect(schedule!.dayOfMonth, 1);
      expect(schedule.amount, 50000);
    });

    test('a month-end payday that sometimes slips to the 1st', () {
      final schedule = CashflowForecastService.detectPayday([
        _salary(DateTime(2026, 7, 31)),
        _salary(DateTime(2026, 8, 30)),
        _salary(DateTime(2026, 10, 1)),
        _salary(DateTime(2026, 10, 30)),
      ], now);
      expect(schedule!.dayOfMonth, 31);
    });

    test('irregular or too little salary history gives no payday', () {
      expect(
        CashflowForecastService.detectPayday([
          _salary(DateTime(2026, 9, 3)),
          _salary(DateTime(2026, 10, 19)),
        ], now),
        isNull,
      );
      expect(
        CashflowForecastService.detectPayday(
            [_salary(DateTime(2026, 11, 1))], now),
        isNull,
      );
    });

    test('other income categories are ignored', () {
      final freelance = [
        for (final m in [8, 9, 10])
          TransactionRecord(
            id: 'f$m',
            amount: 20000,
            type: TransactionType.income,
            categoryId: 'cat_freelance',
            date: DateTime(2026, m, 5),
          ),
      ];
      expect(CashflowForecastService.detectPayday(freelance, now), isNull);
    });
  });

  group('forecast with a payday', () {
    test('salary lands on payday, so the low point is the day before', () {
      final now = DateTime(2026, 11, 10);
      final forecast = CashflowForecastService.forecast(
        [
          ..._dailySpending(now),
          for (final m in [8, 9, 10, 11]) _salary(DateTime(2026, m, 1)),
        ],
        referenceDate: now,
        openingBalanceOverride: 30000,
        days: 30,
      );

      expect(forecast.paydayDayOfMonth, 1);
      final paydays = forecast.dailyPoints.where((p) => p.isSalaryDeposit);
      expect(paydays.map((p) => p.date), [DateTime(2026, 12, 1)]);
      expect(paydays.single.salaryAmount, 50000);
      expect(forecast.expectedSalary, 50000);
      expect(forecast.lowestProjectedDate, DateTime(2026, 11, 30));
      expect(
        forecast.majorEvents.where((e) => e.isIncome).map((e) => e.title),
        ['Salary'],
      );
    });

    test("this month's salary already received is not expected again", () {
      final now = DateTime(2026, 11, 1, 18);
      final forecast = CashflowForecastService.forecast(
        [
          ..._dailySpending(now),
          for (final m in [8, 9, 10, 11]) _salary(DateTime(2026, m, 1, 9)),
        ],
        referenceDate: now,
        openingBalanceOverride: 30000,
        days: 30,
      );
      expect(forecast.dailyPoints.where((p) => p.isSalaryDeposit), isEmpty);
    });

    test('without a payday pattern, no day is shown as a salary deposit', () {
      final now = DateTime(2026, 11, 10);
      final forecast = CashflowForecastService.forecast(
        [
          ..._dailySpending(now),
          TransactionRecord(
            id: 'gift',
            amount: 9000,
            type: TransactionType.income,
            categoryId: 'cat_gift_income',
            date: DateTime(2026, 10, 20),
          ),
        ],
        referenceDate: now,
        openingBalanceOverride: 30000,
      );
      expect(forecast.paydayDayOfMonth, isNull);
      expect(forecast.dailyPoints.where((p) => p.isSalaryDeposit), isEmpty);
      expect(forecast.dailyPoints.first.incomeAmount, greaterThan(0));
    });
  });
}
