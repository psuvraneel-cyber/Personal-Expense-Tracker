import 'package:flutter_test/flutter_test.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/premium/models/cashflow_forecast.dart';
import 'package:pet/premium/models/recurring_payment.dart';
import 'package:pet/premium/services/cashflow_forecast_service.dart';

void main() {
  final refDate = DateTime(2026, 7, 15, 10, 0);

  group('CF-01: Historical Averaging & Denominator Logic', () {
    test('no denominator clamping inflation with 730 days (2 years) of transactions', () {
      // Create transactions spanning 730 days: ₹1,000 expense per day
      // In the old broken engine: total = 730,000 / min(730, 365) = 730,000 / 365 = 2,000/day (2x inflation!)
      // In the new engine: 60-day rolling baseline -> only the last 60 days of expenses are counted
      final txns = List.generate(
        730,
        (i) => TransactionRecord(
          id: 't_$i',
          amount: 1000,
          type: TransactionType.expense,
          categoryId: 'groceries',
          date: refDate.subtract(Duration(days: i)),
        ),
      );

      final forecast = CashflowForecastService.forecast(
        txns,
        days: 30,
        referenceDate: refDate,
      );

      // Effective lookback is 60 days. Total expense in 60 days = 60 * 1,000 = 60,000.
      // Daily burn rate should be ~1,000/day, NOT 2,000/day!
      expect(forecast.expectedVariableExpenses, closeTo(30000.0, 1500.0));
      expect(forecast.dailyBurnRate, closeTo(1000.0, 50.0));
    });

    test('rolling baseline accurately computes 30-day and 60-day observation windows', () {
      // 30 days of ₹500/day expenses
      final txns = List.generate(
        30,
        (i) => TransactionRecord(
          id: 't_$i',
          amount: 500,
          type: TransactionType.expense,
          categoryId: 'food',
          date: refDate.subtract(Duration(days: i)),
        ),
      );

      final forecast = CashflowForecastService.forecast(
        txns,
        days: 30,
        referenceDate: refDate,
      );

      // 30 days effective window: daily expense = 500
      // For a 30-day horizon: expected variable expenses = 30 * 500 = 15,000
      expect(forecast.expectedVariableExpenses, closeTo(15000.0, 1000.0));
    });
  });

  group('CF-02 & CF-05: Income Normalization & Risk Model', () {
    test('single monthly salary does not become artificial daily income rate', () {
      // ₹60,000 monthly salary deposited 5 days ago
      final txns = [
        TransactionRecord(
          id: 't_sal',
          amount: 60000,
          type: TransactionType.income,
          categoryId: 'salary',
          date: refDate.subtract(const Duration(days: 5)),
        ),
        // Baseline expenses over 20 days: ₹1,000/day
        ...List.generate(
          20,
          (i) => TransactionRecord(
            id: 't_exp_$i',
            amount: 1000,
            type: TransactionType.expense,
            categoryId: 'daily',
            date: refDate.subtract(Duration(days: i)),
          ),
        ),
      ];

      final forecast = CashflowForecastService.forecast(
        txns,
        days: 30,
        referenceDate: refDate,
      );

      // In the old bug: ₹60,000 / 1 day = ₹60,000/day income!
      // In the new engine: normalized over baseline days (20 days) = ₹60,000 / 20 = ₹3,000/day
      expect(forecast.expectedIncome, lessThan(120000.0));
      expect(forecast.expectedIncome, greaterThan(30000.0));
      expect(forecast.isCashflowPositive, isTrue);
    });

    test('stable salary with small cashback does NOT trigger false high risk', () {
      // Stable salary + tiny cashback of ₹50
      final txns = [
        TransactionRecord(
          id: 't_sal1',
          amount: 80000,
          type: TransactionType.income,
          categoryId: 'salary',
          date: refDate.subtract(const Duration(days: 35)),
        ),
        TransactionRecord(
          id: 't_sal2',
          amount: 80000,
          type: TransactionType.income,
          categoryId: 'salary',
          date: refDate.subtract(const Duration(days: 5)),
        ),
        TransactionRecord(
          id: 't_cashback',
          amount: 50,
          type: TransactionType.income,
          categoryId: 'cashback',
          date: refDate.subtract(const Duration(days: 10)),
        ),
        ...List.generate(
          35,
          (i) => TransactionRecord(
            id: 't_exp_$i',
            amount: 1500,
            type: TransactionType.expense,
            categoryId: 'living',
            date: refDate.subtract(Duration(days: i)),
          ),
        ),
      ];

      final forecast = CashflowForecastService.forecast(
        txns,
        days: 30,
        referenceDate: refDate,
      );

      // Old engine flagged high risk because CV between 80,000 and 50 was huge.
      // New engine identifies strong recurring salary consistency.
      expect(forecast.riskLevel, isNot(equals(CashflowRiskLevel.deficitExpected)));
      expect(forecast.riskLevel, equals(CashflowRiskLevel.healthy));
    });

    test('zero income data yields Insufficient Data rather than Low Risk', () {
      // Only expenses, zero income recorded
      final txns = List.generate(
        10,
        (i) => TransactionRecord(
          id: 't_exp_$i',
          amount: 500,
          type: TransactionType.expense,
          categoryId: 'food',
          date: refDate.subtract(Duration(days: i)),
        ),
      );

      final forecast = CashflowForecastService.forecast(
        txns,
        days: 30,
        referenceDate: refDate,
      );

      expect(forecast.riskLevel, isNot(equals(CashflowRiskLevel.healthy)));
    });
  });

  group('CF-03: Rolling Safe-to-Spend & Month-End Cliff Resistance', () {
    test('safe-to-spend does not jump or collapse across month boundary (day 28 vs day 1)', () {
      final txns = [
        TransactionRecord(
          id: 't_inc',
          amount: 60000,
          type: TransactionType.income,
          categoryId: 'salary',
          date: refDate.subtract(const Duration(days: 15)),
        ),
        ...List.generate(
          15,
          (i) => TransactionRecord(
            id: 't_e_$i',
            amount: 1000,
            type: TransactionType.expense,
            categoryId: 'daily',
            date: refDate.subtract(Duration(days: i)),
          ),
        ),
      ];

      // Test on July 28 (3 days before month end)
      final endOfMonthDate = DateTime(2026, 7, 28, 10, 0);
      final forecastEnd = CashflowForecastService.forecast(
        txns,
        days: 30,
        referenceDate: endOfMonthDate,
      );

      // Test on August 1 (beginning of next month)
      final nextMonthDate = DateTime(2026, 8, 1, 10, 0);
      final forecastStart = CashflowForecastService.forecast(
        txns,
        days: 30,
        referenceDate: nextMonthDate,
      );

      // In the old broken engine: remaining balance was divided by 3 days on July 28 (massive spike),
      // then divided by 31 days on August 1 (massive crash - 10x cliff!).
      // In the new engine: derived from 30-day horizon headroom. Daily rate is smooth.
      expect((forecastEnd.safeToSpend - forecastStart.safeToSpend).abs(), lessThan(500.0));
    });

    test('upcoming bill in next month correctly depresses safe-to-spend', () {
      final txns = [
        TransactionRecord(
          id: 't_inc',
          amount: 30000,
          type: TransactionType.income,
          categoryId: 'salary',
          date: refDate.subtract(const Duration(days: 15)),
        ),
        TransactionRecord(
          id: 't_exp',
          amount: 20000,
          type: TransactionType.expense,
          categoryId: 'food',
          date: refDate.subtract(const Duration(days: 2)),
        ),
      ];

      final noBillForecast = CashflowForecastService.forecast(
        txns,
        days: 30,
        referenceDate: refDate,
      );

      // Major rent commitment due on August 1 (17 days ahead)
      // Rent of ₹30,000 exceeds accumulated daily net change and depresses lowest balance below Day 0
      final bills = [
        RecurringPayment(
          id: 'b_rent',
          merchantName: 'Landlord Rent',
          amount: 30000,
          frequency: 'monthly',
          lastPaidAt: refDate.subtract(const Duration(days: 15)),
          nextDueAt: refDate.add(const Duration(days: 17)),
          categoryId: 'housing',
          status: RecurringStatus.confirmed,
        ),
      ];

      final withBillForecast = CashflowForecastService.forecast(
        txns,
        confirmedBills: bills,
        days: 30,
        referenceDate: refDate,
      );

      expect(withBillForecast.expectedBills, equals(30000.0));
      expect(withBillForecast.safeToSpend, lessThan(noBillForecast.safeToSpend));
      expect(withBillForecast.lowestProjectedBalance, lessThan(noBillForecast.lowestProjectedBalance));
    });
  });

  group('CF-04: Overdue Bills Preservation', () {
    test('unpaid active overdue bill is placed on Day 0 and impacts risk immediately', () {
      final txns = [
        TransactionRecord(
          id: 't_inc',
          amount: 15000,
          type: TransactionType.income,
          categoryId: 'freelance',
          date: refDate.subtract(const Duration(days: 8)),
        ),
      ];

      // Bill was due 3 days AGO (unpaid and confirmed)
      final overdueBills = [
        RecurringPayment(
          id: 'b_overdue',
          merchantName: 'Overdue Electricity',
          amount: 12000,
          frequency: 'monthly',
          lastPaidAt: refDate.subtract(const Duration(days: 33)),
          nextDueAt: refDate.subtract(const Duration(days: 3)), // Overdue!
          categoryId: 'utilities',
          status: RecurringStatus.confirmed,
        ),
      ];

      final forecast = CashflowForecastService.forecast(
        txns,
        confirmedBills: overdueBills,
        days: 30,
        referenceDate: refDate,
      );

      // In the new engine: the overdue bill is mapped to Day 0 (today) as an immediate liability,
      // and its subsequent regular occurrence within 30 days is also preserved (total = 24,000).
      expect(forecast.expectedBills, equals(24000.0));
      final day0 = forecast.dailyPoints.first;
      expect(day0.billsAmount, equals(12000.0));
      expect(day0.billNames, contains('Overdue Electricity (Overdue)'));
    });
  });

  group('CF-12 & CF-19: Multi-Horizon & Runway Implementation', () {
    test('all horizons (14D, 30D, 60D, 90D) produce exact daily points', () {
      final txns = [
        TransactionRecord(
          id: 't_inc',
          amount: 50000,
          type: TransactionType.income,
          categoryId: 'salary',
          date: refDate.subtract(const Duration(days: 10)),
        ),
        TransactionRecord(
          id: 't_exp',
          amount: 15000,
          type: TransactionType.expense,
          categoryId: 'food',
          date: refDate.subtract(const Duration(days: 2)),
        ),
      ];

      for (final horizon in [14, 30, 60, 90]) {
        final forecast = CashflowForecastService.forecast(
          txns,
          days: horizon,
          referenceDate: refDate,
        );
        expect(forecast.horizonDays, equals(horizon));
        expect(forecast.dailyPoints.length, equals(horizon));
      }
    });

    test('runway reflects accurate cashflow positive vs net daily burn rate', () {
      // Cashflow positive user
      final posTxns = [
        TransactionRecord(
          id: 't_inc',
          amount: 70000,
          type: TransactionType.income,
          categoryId: 'salary',
          date: refDate.subtract(const Duration(days: 15)),
        ),
        ...List.generate(
          15,
          (i) => TransactionRecord(
            id: 't_e_$i',
            amount: 1000,
            type: TransactionType.expense,
            categoryId: 'daily',
            date: refDate.subtract(Duration(days: i)),
          ),
        ),
      ];

      final posForecast = CashflowForecastService.forecast(
        posTxns,
        days: 30,
        referenceDate: refDate,
      );

      expect(posForecast.isCashflowPositive, isTrue);
      expect(posForecast.monthlyNetCashflow, greaterThan(0));

      // Net burn user (expenses > income)
      final burnTxns = [
        TransactionRecord(
          id: 't_inc',
          amount: 10000,
          type: TransactionType.income,
          categoryId: 'freelance',
          date: refDate.subtract(const Duration(days: 10)),
        ),
        ...List.generate(
          10,
          (i) => TransactionRecord(
            id: 't_e_$i',
            amount: 2500,
            type: TransactionType.expense,
            categoryId: 'shopping',
            date: refDate.subtract(Duration(days: i)),
          ),
        ),
      ];

      final burnForecast = CashflowForecastService.forecast(
        burnTxns,
        days: 30,
        referenceDate: refDate,
      );

      expect(burnForecast.isCashflowPositive, isFalse);
      expect(burnForecast.dailyBurnRate, greaterThan(0));
    });
  });

  group('CF-17: "Can I Afford This?" What-If Scenario Simulator', () {
    test('simulateExpense evaluates purchase impact without mutating baseline data', () {
      final txns = [
        TransactionRecord(
          id: 't_inc',
          amount: 60000,
          type: TransactionType.income,
          categoryId: 'salary',
          date: refDate.subtract(const Duration(days: 10)),
        ),
        TransactionRecord(
          id: 't_exp',
          amount: 15000,
          type: TransactionType.expense,
          categoryId: 'living',
          date: refDate.subtract(const Duration(days: 2)),
        ),
      ];

      final baseForecast = CashflowForecastService.forecast(
        txns,
        days: 30,
        referenceDate: refDate,
      );

      final purchaseDate = refDate.add(const Duration(days: 5));
      final simulated = CashflowForecastService.simulateExpense(
        baseForecast,
        amount: 25000,
        date: purchaseDate,
      );

      // Verify baseline forecast was not mutated
      expect(baseForecast.lowestProjectedBalance, greaterThan(40000.0));
      expect(baseForecast.safeToSpend, greaterThan(simulated.safeToSpend));

      // Verify simulated forecast captures the impact
      expect(simulated.lowestProjectedBalance, closeTo(44545.45, 1.0));
      expect(simulated.lowestProjectedBalance, lessThan(baseForecast.lowestProjectedBalance));
      expect(simulated.expectedBills, equals(baseForecast.expectedBills + 25000.0));

      // Check points before and after purchase date
      final ptBefore = simulated.dailyPoints[4]; // Day 4
      final ptAfter = simulated.dailyPoints[6]; // Day 6
      expect(ptBefore.scenarioBalance, equals(ptBefore.balance));
      expect(ptAfter.scenarioBalance, equals(ptAfter.balance - 25000.0));
    });
  });
}
