import 'package:flutter_test/flutter_test.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/premium/models/app_alert.dart';
import 'package:pet/premium/models/recurring_payment.dart';
import 'package:pet/premium/services/alert_evaluator.dart';
import 'package:pet/premium/services/cashflow_forecast_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final refDate = DateTime(2026, 3, 15, 10, 0);

  group('DEFECT 1 — Variable Expense Cannibalization Remediation', () {
    test('Scenario 1: New recurring bill absent historically does not reduce variable baseline', () {
      // 30 days of historical variable expenses: ₹20,000 total (~₹667/day)
      final txns = List.generate(
        30,
        (i) => TransactionRecord(
          id: 'v_$i',
          amount: 20000 / 30,
          type: TransactionType.expense,
          categoryId: 'food',
          date: refDate.subtract(Duration(days: i + 1)),
          isRecurring: false,
        ),
      );

      // Baseline forecast with NO recurring bills
      final baseForecast = CashflowForecastService.forecast(
        txns,
        confirmedBills: [],
        days: 30,
        referenceDate: refDate,
        openingBalanceOverride: 50000,
      );

      // Now introduce a NEW recurring bill of ₹15,000/mo that was NOT in historical txns
      final newBill = RecurringPayment(
        id: 'bill_gym',
        merchantName: 'Gold Gym',
        amount: 15000,
        frequency: 'monthly',
        lastPaidAt: refDate.subtract(const Duration(days: 20)),
        nextDueAt: refDate.add(const Duration(days: 10)),
        categoryId: 'fitness',
        status: RecurringStatus.confirmed,
      );

      final withBillForecast = CashflowForecastService.forecast(
        txns,
        confirmedBills: [newBill],
        days: 30,
        referenceDate: refDate,
        openingBalanceOverride: 50000,
      );

      // In the OLD defective engine: variable daily expense was (avgDaily - recurringDailyBurn).
      // Here, avgDailyExpense was ~667/day, recurringDaily was 15000/30 = 500/day.
      // Old: variableDailyExpense became 667 - 500 = 167/day (crushed/cannibalized!).
      // Expected: variableDailyExpense stays at 667/day, and newBill is separately projected as a bill event.
      expect(withBillForecast.expectedVariableExpenses, closeTo(baseForecast.expectedVariableExpenses, 1.0));
      expect(withBillForecast.expectedBills, equals(15000.0));
    });

    test('Scenario 2: Recurring bill historically represented is not double-counted', () {
      // History has ₹20,000 variable expenses + ₹10,000 recurring internet bill
      final txns = <TransactionRecord>[
        ...List.generate(
          30,
          (i) => TransactionRecord(
            id: 'v_$i',
            amount: 20000 / 30,
            type: TransactionType.expense,
            categoryId: 'food',
            date: refDate.subtract(Duration(days: i + 1)),
            isRecurring: false,
          ),
        ),
        TransactionRecord(
          id: 'rec_fiber',
          amount: 10000,
          type: TransactionType.expense,
          categoryId: 'utilities',
          date: refDate.subtract(const Duration(days: 15)),
          isRecurring: true,
          merchantName: 'Airtel Fiber',
        ),
      ];

      final bill = RecurringPayment(
        id: 'bill_fiber',
        merchantName: 'Airtel Fiber',
        amount: 10000,
        frequency: 'monthly',
        lastPaidAt: refDate.subtract(const Duration(days: 15)),
        nextDueAt: refDate.add(const Duration(days: 15)),
        categoryId: 'utilities',
        status: RecurringStatus.confirmed,
      );

      final forecast = CashflowForecastService.forecast(
        txns,
        confirmedBills: [bill],
        days: 30,
        referenceDate: refDate,
        openingBalanceOverride: 50000,
      );

      // Variable baseline must ONLY include the non-recurring ₹20,000, not ₹30,000
      expect(forecast.expectedVariableExpenses, closeTo(20000.0, 1000.0));
      // Future bill is separately counted as expectedBills = 10000
      expect(forecast.expectedBills, equals(10000.0));
      // Total projected outgo = ~20000 variable + 10000 bill = ~30000 (not double counted to 40000!)
      final totalOutgo = forecast.expectedVariableExpenses + forecast.expectedBills;
      expect(totalOutgo, closeTo(30000.0, 1000.0));
    });

    test('Scenario 3: Long-cycle recurring bill does not cannibalize unrelated living expenses', () {
      // 60 days of living expenses: ₹60,000 (~₹1,000/day)
      final txns = List.generate(
        60,
        (i) => TransactionRecord(
          id: 'living_$i',
          amount: 1000,
          type: TransactionType.expense,
          categoryId: 'food',
          date: refDate.subtract(Duration(days: i + 1)),
          isRecurring: false,
        ),
      );

      // Quarterly insurance bill: ₹30,000 due in 20 days
      final quarterlyBill = RecurringPayment(
        id: 'bill_insurance',
        merchantName: 'HDFC Ergo',
        amount: 30000,
        frequency: 'quarterly',
        lastPaidAt: refDate.subtract(const Duration(days: 70)),
        nextDueAt: refDate.add(const Duration(days: 20)),
        categoryId: 'insurance',
        status: RecurringStatus.confirmed,
      );

      final forecast = CashflowForecastService.forecast(
        txns,
        confirmedBills: [quarterlyBill],
        days: 30,
        referenceDate: refDate,
        openingBalanceOverride: 100000,
      );

      // Daily variable spend must remain ~1000/day over 30 days = ₹30,000
      expect(forecast.expectedVariableExpenses, closeTo(30000.0, 50.0));
      expect(forecast.expectedBills, equals(30000.0));
    });

    test('Scenario 4: Recurring bill larger than historical variable spend does not clamp variable spend to zero', () {
      // Modest historical spending: ₹12,000/month (~₹400/day)
      final txns = List.generate(
        30,
        (i) => TransactionRecord(
          id: 'v_$i',
          amount: 400,
          type: TransactionType.expense,
          categoryId: 'groceries',
          date: refDate.subtract(Duration(days: i + 1)),
          isRecurring: false,
        ),
      );

      // Large future recurring commitment: ₹25,000/month
      final largeBill = RecurringPayment(
        id: 'bill_car_loan',
        merchantName: 'Car EMI',
        amount: 25000,
        frequency: 'monthly',
        lastPaidAt: refDate.subtract(const Duration(days: 25)),
        nextDueAt: refDate.add(const Duration(days: 5)),
        categoryId: 'loans',
        status: RecurringStatus.confirmed,
      );

      final forecast = CashflowForecastService.forecast(
        txns,
        confirmedBills: [largeBill],
        days: 30,
        referenceDate: refDate,
        openingBalanceOverride: 50000,
      );

      // In old implementation: (12000 - 25000).clamp(0, ...) became 0!
      // In fixed implementation: variable spending remains representative of historical spend (> 0)
      expect(forecast.expectedVariableExpenses, closeTo(12000.0, 1000.0));
      expect(forecast.expectedBills, equals(25000.0));
    });
  });

  group('DEFECT 2 — Cashflow Alert Escalation Suppressed by Monthly Deduplication Remediation', () {
    test('Scenario 1 & 2: Same risk state produces one alert, repeated evaluation is deduplicated', () {
      // Create transactions where balance dips below safety buffer (₹5,000) but remains positive (~₹4,000)
      // Opening balance: 10,000 (credit). Expenses over 10 days: 6,000 total (600/day).
      final txns = <TransactionRecord>[
        TransactionRecord(
          id: 'inc_init',
          amount: 10000,
          type: TransactionType.income,
          categoryId: 'opening',
          date: refDate.subtract(const Duration(days: 12)),
        ),
        ...List.generate(
          10,
          (i) => TransactionRecord(
            id: 'exp_$i',
            amount: 600,
            type: TransactionType.expense,
            categoryId: 'daily',
            date: refDate.subtract(Duration(days: i + 1)),
          ),
        ),
      ];

      final alert1 = AlertEvaluator.evaluateCashflowRisk(
        transactions: txns,
        now: refDate,
      );

      expect(alert1, isNotNull);
      expect(alert1!.alertKey, equals('cashflow:2026-03:warning'));
      expect(alert1.stage, equals(AppAlertStage.warning));

      // Re-evaluation with exact same state yields identical alertKey for deduplication
      final alert2 = AlertEvaluator.evaluateCashflowRisk(
        transactions: txns,
        now: refDate,
      );
      expect(alert2!.alertKey, equals(alert1.alertKey));
    });

    test('Scenario 3: Warning escalates to Critical in same month with distinct alertKey', () {
      // Step 1: Warning state (positive trough below buffer)
      final warningTxns = <TransactionRecord>[
        TransactionRecord(
          id: 'inc_init',
          amount: 10000,
          type: TransactionType.income,
          categoryId: 'opening',
          date: refDate.subtract(const Duration(days: 12)),
        ),
        ...List.generate(
          10,
          (i) => TransactionRecord(
            id: 'exp_$i',
            amount: 600,
            type: TransactionType.expense,
            categoryId: 'daily',
            date: refDate.subtract(Duration(days: i + 1)),
          ),
        ),
      ];

      final warningAlert = AlertEvaluator.evaluateCashflowRisk(
        transactions: warningTxns,
        now: refDate,
      );

      expect(warningAlert, isNotNull);
      expect(warningAlert!.alertKey, equals('cashflow:2026-03:warning'));

      // Step 2: Critical state (balance dips into negative deficit)
      final criticalTxns = <TransactionRecord>[
        TransactionRecord(
          id: 'inc_init',
          amount: 10000,
          type: TransactionType.income,
          categoryId: 'opening',
          date: refDate.subtract(const Duration(days: 12)),
        ),
        ...List.generate(
          10,
          (i) => TransactionRecord(
            id: 'exp_$i',
            amount: 2000, // 20,000 total expense -> 10k - 20k = -10k deficit!
            type: TransactionType.expense,
            categoryId: 'daily',
            date: refDate.subtract(Duration(days: i + 1)),
          ),
        ),
      ];

      final criticalAlert = AlertEvaluator.evaluateCashflowRisk(
        transactions: criticalTxns,
        now: refDate,
      );

      expect(criticalAlert, isNotNull);
      // In the OLD defect: alertKey was 'cashflow:2026-03' for both, suppressing the critical escalation!
      // In the FIXED code: alertKey is 'cashflow:2026-03:critical'
      expect(criticalAlert!.alertKey, equals('cashflow:2026-03:critical'));
      expect(criticalAlert.stage, equals(AppAlertStage.critical));
      expect(criticalAlert.alertKey, isNot(equals(warningAlert.alertKey)));
    });

    test('Scenario 4: Recovery after critical produces null alert allowing dismissal', () {
      // High income transactions over 10 days -> safe cashflow
      final healthyTxns = List.generate(
        10,
        (i) => TransactionRecord(
          id: 'sal_$i',
          amount: 50000,
          type: TransactionType.income,
          categoryId: 'salary',
          date: refDate.subtract(Duration(days: i + 1)),
        ),
      );

      final alert = AlertEvaluator.evaluateCashflowRisk(
        transactions: healthyTxns,
        now: refDate,
      );

      expect(alert, isNull);
    });
  });

  group('DEFECT 3 — Reachable Safety-Buffer Alert Remediation', () {
    test('Test A: Negative balance produces deficit alert (critical)', () {
      final txns = List.generate(
        10,
        (i) => TransactionRecord(
          id: 'e_$i',
          amount: 5000,
          type: TransactionType.expense,
          categoryId: 'general',
          date: refDate.subtract(Duration(days: i + 1)),
        ),
      );

      final alert = AlertEvaluator.evaluateCashflowRisk(
        transactions: txns,
        now: refDate,
      );

      expect(alert, isNotNull);
      expect(alert!.severity, equals(AlertSeverity.critical));
      expect(alert.stage, equals(AppAlertStage.critical));
      expect(alert.title, contains('Cashflow Risk Warning'));
    });

    test('Test B: Buffer breach while non-negative produces reachable safety-buffer alert (warning)', () {
      // Starting balance: 10,000. Expenses: 6,000. Trough dips to 4,000 (>= 0 and < 5,000 safety buffer).
      // Balance NEVER becomes negative.
      final txns = <TransactionRecord>[
        TransactionRecord(
          id: 'inc_init',
          amount: 10000,
          type: TransactionType.income,
          categoryId: 'opening',
          date: refDate.subtract(const Duration(days: 12)),
        ),
        ...List.generate(
          10,
          (i) => TransactionRecord(
            id: 'exp_$i',
            amount: 600,
            type: TransactionType.expense,
            categoryId: 'daily',
            date: refDate.subtract(Duration(days: i + 1)),
          ),
        ),
      ];

      final alert = AlertEvaluator.evaluateCashflowRisk(
        transactions: txns,
        now: refDate,
      );

      // In the OLD defective code: outer condition was (hasImminentDeficit || hasEndingDeficit),
      // which required rollingBalance < 0. Thus, this branch was DEAD and returned null!
      // In the FIXED code: it produces a reachable safety buffer warning!
      expect(alert, isNotNull);
      expect(alert!.severity, equals(AlertSeverity.warning));
      expect(alert.stage, equals(AppAlertStage.warning));
      expect(alert.title, contains('Safety Buffer Warning'));
      expect(alert.message, contains('5000'));
    });

    test('Test C: Exactly at buffer boundary produces no breach alert', () {
      // Starting balance: 10,000. Expenses: 5,000. Ending balance = 5,000 (exactly equal to buffer).
      final txns = <TransactionRecord>[
        TransactionRecord(
          id: 'inc_init',
          amount: 10000,
          type: TransactionType.income,
          categoryId: 'opening',
          date: refDate.subtract(const Duration(days: 12)),
        ),
        ...List.generate(
          10,
          (i) => TransactionRecord(
            id: 'exp_$i',
            amount: 500,
            type: TransactionType.expense,
            categoryId: 'daily',
            date: refDate.subtract(Duration(days: i + 1)),
          ),
        ),
      ];

      final alert = AlertEvaluator.evaluateCashflowRisk(
        transactions: txns,
        now: refDate,
      );

      // Balance equals buffer, not strictly below buffer
      expect(alert, isNull);
    });

    test('Test D: Above buffer produces no breach alert', () {
      // Starting balance: 20,000. Expenses: 5,000. Ending balance = 15,000 (> 5,000 buffer).
      final txns = <TransactionRecord>[
        TransactionRecord(
          id: 'inc_init',
          amount: 20000,
          type: TransactionType.income,
          categoryId: 'opening',
          date: refDate.subtract(const Duration(days: 12)),
        ),
        ...List.generate(
          10,
          (i) => TransactionRecord(
            id: 'exp_$i',
            amount: 500,
            type: TransactionType.expense,
            categoryId: 'daily',
            date: refDate.subtract(Duration(days: i + 1)),
          ),
        ),
      ];

      final alert = AlertEvaluator.evaluateCashflowRisk(
        transactions: txns,
        now: refDate,
      );

      expect(alert, isNull);
    });
  });

  group('DEFECT 4 — Safe-to-Spend Explanation Consistency Remediation', () {
    test('Scenario where linear component sum != engine Safe-to-Spend: math deconstruction strictly equals engine result', () {
      // Opening: 100,000
      // Large bill due on day 3: 60,000
      // Buffer: 25,000
      // Lowest projected balance reaches 100k - 60k - variable expenses = ~38,500
      // Headroom = 38,500 - 25,000 = 13,500.
      final txns = List.generate(
        30,
        (i) => TransactionRecord(
          id: 'v_$i',
          amount: 500,
          type: TransactionType.expense,
          categoryId: 'food',
          date: refDate.subtract(Duration(days: i + 1)),
          isRecurring: false,
        ),
      );

      final bill = RecurringPayment(
        id: 'bill_tax',
        merchantName: 'Advance Tax',
        amount: 60000,
        frequency: 'monthly',
        lastPaidAt: refDate.subtract(const Duration(days: 27)),
        nextDueAt: refDate.add(const Duration(days: 3)),
        categoryId: 'taxes',
        status: RecurringStatus.confirmed,
      );

      final forecast = CashflowForecastService.forecast(
        txns,
        confirmedBills: [bill],
        days: 30,
        referenceDate: refDate,
        openingBalanceOverride: 100000,
        safetyBuffer: 25000,
      );

      // Verify engine safe-to-spend derivation
      final expectedHeadroom = (forecast.lowestProjectedBalance - forecast.safetyBuffer).clamp(0.0, double.infinity);
      expect(forecast.totalSafeToSpend, equals(expectedHeadroom));
      expect(forecast.safeToSpend, equals(expectedHeadroom / 30));

      // The explanation math deconstruction:
      // Lowest projected balance - safety buffer - goal reserves == totalSafeToSpend
      final mathDeconstructedTotal = (forecast.lowestProjectedBalance - forecast.safetyBuffer - forecast.expectedGoalReserves)
          .clamp(0.0, double.infinity);
      expect(mathDeconstructedTotal, equals(forecast.totalSafeToSpend));
      expect(mathDeconstructedTotal / 30, equals(forecast.safeToSpend));
    });
  });

  group('DEFECT 5 — Canonical Horizon Boundary Remediation', () {
    test('Canonical [referenceDate, referenceDate + H) applies consistently across all collections', () {
      final h = 30;
      final boundaryBill0 = RecurringPayment(
        id: 'bill_day0',
        merchantName: 'Day 0 Bill',
        amount: 1000,
        frequency: 'monthly',
        lastPaidAt: refDate.subtract(const Duration(days: 30)),
        nextDueAt: refDate, // Day 0 (included)
        categoryId: 'bills',
        status: RecurringStatus.confirmed,
      );

      final boundaryBill29 = RecurringPayment(
        id: 'bill_day29',
        merchantName: 'Day 29 Bill',
        amount: 2000,
        frequency: 'monthly',
        lastPaidAt: refDate.subtract(const Duration(days: 30)),
        nextDueAt: DateTime(refDate.year, refDate.month, refDate.day + h - 1), // Day 29 (last included)
        categoryId: 'bills',
        status: RecurringStatus.confirmed,
      );

      final boundaryBill30 = RecurringPayment(
        id: 'bill_day30',
        merchantName: 'Day 30 Bill',
        amount: 4000,
        frequency: 'monthly',
        lastPaidAt: refDate.subtract(const Duration(days: 30)),
        nextDueAt: DateTime(refDate.year, refDate.month, refDate.day + h), // Day 30 (first excluded)
        categoryId: 'bills',
        status: RecurringStatus.confirmed,
      );

      final forecast = CashflowForecastService.forecast(
        [],
        confirmedBills: [boundaryBill0, boundaryBill29, boundaryBill30],
        days: h,
        referenceDate: refDate,
        openingBalanceOverride: 50000,
      );

      // 1. dailyPoints length must be exactly H = 30
      expect(forecast.dailyPoints.length, equals(30));
      expect(forecast.dailyPoints.first.date.day, equals(refDate.day));
      expect(forecast.dailyPoints.last.date.day, equals(DateTime(refDate.year, refDate.month, refDate.day + h - 1).day));

      // 2. Expected bills: Day 0 (1000) + Day 29 (2000) = 3000. Day 30 (4000) MUST BE EXCLUDED!
      expect(forecast.expectedBills, equals(3000.0));

      // 3. majorEvents: must include Day 0 & Day 29, must EXCLUDE Day 30!
      final eventTitles = forecast.majorEvents.map((e) => e.title).toList();
      expect(eventTitles, contains('Day 0 Bill'));
      expect(eventTitles, contains('Day 29 Bill'));
      expect(eventTitles, isNot(contains('Day 30 Bill')));

      // 4. dailyPoints billsAmount: Day 0 has 1000, Day 29 has 2000
      expect(forecast.dailyPoints.first.billsAmount, equals(1000.0));
      expect(forecast.dailyPoints.last.billsAmount, equals(2000.0));
      // No other day has bills
      final totalDailyBills = forecast.dailyPoints.fold(0.0, (sum, pt) => sum + pt.billsAmount);
      expect(totalDailyBills, equals(3000.0));
    });
  });

  group('DEFECT 6 — Correct Forecast Cache Identity Remediation', () {
    setUp(() {
      CashflowForecastService.clearCache();
    });

    test('Scenario A: Merchant rename invalidates cache and returns fresh merchant name', () {
      final bill1 = RecurringPayment(
        id: 'b1',
        merchantName: 'Old Internet Co',
        amount: 1500,
        frequency: 'monthly',
        lastPaidAt: refDate.subtract(const Duration(days: 25)),
        nextDueAt: refDate.add(const Duration(days: 5)),
        categoryId: 'utilities',
        status: RecurringStatus.confirmed,
      );

      final f1 = CashflowForecastService.forecast(
        [],
        confirmedBills: [bill1],
        days: 30,
        referenceDate: refDate,
        openingBalanceOverride: 20000,
      );

      expect(f1.majorEvents.first.title, equals('Old Internet Co'));

      // Mutate ONLY merchant name (count and amount are identical)
      final bill2 = RecurringPayment(
        id: 'b1',
        merchantName: 'New Fiber Provider',
        amount: 1500,
        frequency: 'monthly',
        lastPaidAt: refDate.subtract(const Duration(days: 25)),
        nextDueAt: refDate.add(const Duration(days: 5)),
        categoryId: 'utilities',
        status: RecurringStatus.confirmed,
      );

      final f2 = CashflowForecastService.forecast(
        [],
        confirmedBills: [bill2],
        days: 30,
        referenceDate: refDate,
        openingBalanceOverride: 20000,
      );

      // In the OLD defective cache: only bill count was in cache key!
      // So f2 was returned from cache with stale 'Old Internet Co'!
      // In the FIXED cache: merchantName is in billsHash, so cache invalidates!
      expect(f2.majorEvents.first.title, equals('New Fiber Provider'));
    });

    test('Scenario B: Older transaction mutation invalidates cache without count changing', () {
      final tOld1 = TransactionRecord(
        id: 'tx_old',
        amount: 1000,
        type: TransactionType.expense,
        categoryId: 'food',
        date: refDate.subtract(const Duration(days: 25)),
      );
      final tRecent = TransactionRecord(
        id: 'tx_recent',
        amount: 500,
        type: TransactionType.expense,
        categoryId: 'transport',
        date: refDate.subtract(const Duration(days: 1)),
      );

      final f1 = CashflowForecastService.forecast(
        [tOld1, tRecent],
        confirmedBills: [],
        days: 30,
        referenceDate: refDate,
        openingBalanceOverride: 20000,
      );

      // Mutate older transaction amount to 10,000 (count is still 2, latest date is still tx_recent)
      final tOld2 = TransactionRecord(
        id: 'tx_old',
        amount: 10000,
        type: TransactionType.expense,
        categoryId: 'food',
        date: refDate.subtract(const Duration(days: 25)),
      );

      final f2 = CashflowForecastService.forecast(
        [tOld2, tRecent],
        confirmedBills: [],
        days: 30,
        referenceDate: refDate,
        openingBalanceOverride: 20000,
      );

      expect(f2.expectedVariableExpenses, isNot(equals(f1.expectedVariableExpenses)));
      expect(f2.expectedVariableExpenses, greaterThan(f1.expectedVariableExpenses));
    });

    test('Scenario C: Horizon change creates different cache identity and recomputes', () {
      final f30 = CashflowForecastService.forecast(
        [],
        confirmedBills: [],
        days: 30,
        referenceDate: refDate,
        openingBalanceOverride: 20000,
      );

      final f60 = CashflowForecastService.forecast(
        [],
        confirmedBills: [],
        days: 60,
        referenceDate: refDate,
        openingBalanceOverride: 20000,
      );

      expect(f30.horizonDays, equals(30));
      expect(f60.horizonDays, equals(60));
      expect(f30.dailyPoints.length, equals(30));
      expect(f60.dailyPoints.length, equals(60));
    });

    test('Scenario D: Safety buffer change creates different cache identity and updates safe-to-spend', () {
      final fBuffer5k = CashflowForecastService.forecast(
        [],
        confirmedBills: [],
        days: 30,
        referenceDate: refDate,
        openingBalanceOverride: 20000,
        safetyBuffer: 5000,
      );

      final fBuffer10k = CashflowForecastService.forecast(
        [],
        confirmedBills: [],
        days: 30,
        referenceDate: refDate,
        openingBalanceOverride: 20000,
        safetyBuffer: 10000,
      );

      expect(fBuffer5k.safetyBuffer, equals(5000));
      expect(fBuffer10k.safetyBuffer, equals(10000));
      expect(fBuffer5k.totalSafeToSpend, equals(15000.0)); // 20000 - 5000
      expect(fBuffer10k.totalSafeToSpend, equals(10000.0)); // 20000 - 10000
    });

    test('Scenario E: Equivalent inputs successfully reuse cached instance', () {
      final bill = RecurringPayment(
        id: 'b1',
        merchantName: 'Spotify',
        amount: 299,
        frequency: 'monthly',
        lastPaidAt: refDate.subtract(const Duration(days: 20)),
        nextDueAt: refDate.add(const Duration(days: 10)),
        categoryId: 'entertainment',
        status: RecurringStatus.confirmed,
      );

      final f1 = CashflowForecastService.forecast(
        [],
        confirmedBills: [bill],
        days: 30,
        referenceDate: refDate,
        openingBalanceOverride: 20000,
      );

      final f2 = CashflowForecastService.forecast(
        [],
        confirmedBills: [bill],
        days: 30,
        referenceDate: refDate,
        openingBalanceOverride: 20000,
      );

      // Identical inputs should hit cache and return exact same object reference
      expect(identical(f1, f2), isTrue);
    });
  });
}
