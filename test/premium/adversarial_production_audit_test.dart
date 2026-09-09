import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pet/data/database/database_helper.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/sms_transaction.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/premium/models/app_alert.dart';
import 'package:pet/premium/models/cashflow_forecast.dart';
import 'package:pet/premium/models/recurring_payment.dart';
import 'package:pet/premium/models/saving_goal.dart';
import 'package:pet/premium/providers/alert_provider.dart';
import 'package:pet/premium/providers/goal_provider.dart';
import 'package:pet/premium/providers/recurring_provider.dart';
import 'package:pet/premium/repositories/alert_repository.dart';
import 'package:pet/premium/repositories/recurring_payment_repository.dart';
import 'package:pet/premium/repositories/saving_goal_repository.dart';
import 'package:pet/premium/services/alert_evaluation_coordinator.dart';
import 'package:pet/premium/services/alert_evaluator.dart';
import 'package:pet/premium/services/cashflow_forecast_service.dart';
import 'package:pet/premium/services/notification_preferences_service.dart';
import 'package:pet/premium/services/notification_service.dart';
import 'package:pet/premium/services/recurring_detection_service.dart';
import 'package:pet/services/recurrence_calculator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database testDb;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    NotificationService.resetForTest();
    await NotificationPreferencesService.instance.load();
    CashflowForecastService.clearCache();

    // Fresh in-memory DB initialized with all tables up to schema v18
    testDb = await openDatabase(
      inMemoryDatabasePath,
      version: 18,
      onCreate: (db, version) async {
        await DatabaseHelper().onCreateForTesting(db, version);
      },
    );
    DatabaseHelper.setTestDatabase(testDb);
  });

  tearDown(() async {
    DatabaseHelper.setTestDatabase(null);
    await testDb.close();
  });

  // ===========================================================================
  // SECTION 1: ACCOUNT ISOLATION, DATA DESTRUCTION & RESURRECTION DEFENSE
  // ===========================================================================
  group('Phase A: Account Isolation & Data Destruction Invariants', () {
    test(
        'User A data wiped completely from SQLite and memory on logout; User B sees zero leaked state',
        () async {
      final goalRepo = SavingGoalRepository();
      final recurringRepo = RecurringPaymentRepository();
      final alertRepo = AlertRepository();

      // 1. User A creates premium assets
      final goalA = SavingGoal(
        id: 'goal_user_a',
        name: 'Europe Trip',
        targetAmount: 200000,
        currentAmount: 50000,
        targetDate: DateTime.now().add(const Duration(days: 180)),
        createdAt: DateTime.now(),
      );
      await goalRepo.upsert(goalA);

      final billA = RecurringPayment(
        id: 'bill_user_a',
        merchantName: 'AWS Cloud',
        amount: 4500,
        frequency: 'monthly',
        lastPaidAt: DateTime.now().subtract(const Duration(days: 10)),
        nextDueAt: DateTime.now().add(const Duration(days: 20)),
        categoryId: 'business',
        status: RecurringStatus.confirmed,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await recurringRepo.upsert(billA);

      final alertA = AppAlert(
        id: 'alert_user_a',
        type: AppAlertType.bill,
        title: 'AWS Bill Due',
        message: 'Your bill of ₹4500 is due in 20 days',
        createdAt: DateTime.now(),
        alertKey: 'bill:bill_user_a:2026-09-28',
      );
      await alertRepo.insert(alertA);

      // Verify User A rows exist in SQLite
      expect((await goalRepo.getAll()).length, equals(1));
      expect((await recurringRepo.getAll()).length, equals(1));
      expect((await alertRepo.getAll()).length, equals(1));

      // 2. User A logs out: Providers clear data & DatabaseHelper wipes all user data
      final goalProv = GoalProvider(repository: goalRepo);
      final recProv = RecurringProvider(repository: recurringRepo);
      final alertProv = AlertProvider(repository: alertRepo);

      await Future.wait([
        goalProv.clearData(),
        recProv.clearData(),
        alertProv.clearData(),
      ]);
      await DatabaseHelper().wipeAllUserData();

      // 3. Invariant: SQLite tables must be completely empty of user data
      expect(await goalRepo.getAll(), isEmpty,
          reason: 'SQLite saving_goals must be empty after logout');
      expect(await recurringRepo.getAll(), isEmpty,
          reason: 'SQLite recurring_payments must be empty after logout');
      expect(await alertRepo.getAll(), isEmpty,
          reason: 'SQLite alerts must be empty after logout');

      final txnCount =
          (await testDb.rawQuery('SELECT COUNT(*) as c FROM transactions'))
              .first['c'] as int;
      final smsCount =
          (await testDb.rawQuery('SELECT COUNT(*) as c FROM sms_transactions'))
              .first['c'] as int;
      expect(txnCount, equals(0));
      expect(smsCount, equals(0));

      // System categories must survive wipe
      final catCount =
          (await testDb.rawQuery('SELECT COUNT(*) as c FROM categories'))
              .first['c'] as int;
      expect(catCount, greaterThan(0),
          reason: 'System defaults like categories must be preserved');

      // 4. User B logs in on same device: initializes fresh providers
      final goalProvB = GoalProvider(repository: goalRepo);
      final recProvB = RecurringProvider(repository: recurringRepo);
      final alertProvB = AlertProvider(repository: alertRepo);
      await recProvB.load();

      expect(goalProvB.goals, isEmpty,
          reason: 'User B must not see User A goals');
      expect(goalProvB.totalActiveGoalReserves, equals(0.0));
      expect(recProvB.confirmedBills, isEmpty,
          reason: 'User B must not see User A bills');
      expect(alertProvB.alerts, isEmpty,
          reason: 'User B must not see User A alerts');
    });

    test(
        'Old implementation failure regression: in-memory clear without DB wipe leaks data on reload',
        () async {
      final goalRepo = SavingGoalRepository();
      await goalRepo.upsert(SavingGoal(
        id: 'stale_goal',
        name: 'Car Fund',
        targetAmount: 500000,
        currentAmount: 150000,
        targetDate: DateTime.now().add(const Duration(days: 300)),
        createdAt: DateTime.now(),
      ));

      // Simulate the flawed old audit behavior: only clearing in-memory list without DB wipe
      List<SavingGoal> inMemoryState = await goalRepo.getAll();
      expect(inMemoryState.length, equals(1));
      inMemoryState = []; // Simulated memory-only wipe

      // If DB was not wiped, reloading immediately resurrects old user data
      final leakedReload = await goalRepo.getAll();
      expect(leakedReload.length, equals(1),
          reason: 'Proves failure mode: un-wiped DB leaks to next session');

      // Now apply production fix: wipeAllUserData
      await DatabaseHelper().wipeAllUserData();
      final postFixReload = await goalRepo.getAll();
      expect(postFixReload, isEmpty,
          reason: 'Production fix prevents resurrection');
    });
  });

  // ===========================================================================
  // SECTION 2: CASHFLOW FORECAST INVARIANTS & MATHEMATICAL RIGOR
  // ===========================================================================
  group(
      'Phase C & C2: Cashflow Mathematical Invariants & Adversarial Scenarios',
      () {
    final refDate = DateTime(2026, 7, 1, 10, 0);

    test(
        'Invariant 1: Goal Reserve deduction monotonically reduces or preserves Safe-to-Spend',
        () {
      final txns = [
        TransactionRecord(
          id: 'salary_1',
          amount: 60000,
          date: refDate.subtract(const Duration(days: 25)),
          type: TransactionType.income,
          categoryId: 'salary',
        ),
      ];

      final fc0 = CashflowForecastService.forecast(
        txns,
        days: 30,
        referenceDate: refDate,
        openingBalanceOverride: 50000,
        safetyBuffer: 5000,
        goalReserves: 0,
      );

      final fc5k = CashflowForecastService.forecast(
        txns,
        days: 30,
        referenceDate: refDate,
        openingBalanceOverride: 50000,
        safetyBuffer: 5000,
        goalReserves: 5000,
      );

      final fc20k = CashflowForecastService.forecast(
        txns,
        days: 30,
        referenceDate: refDate,
        openingBalanceOverride: 50000,
        safetyBuffer: 5000,
        goalReserves: 20000,
      );

      final fc60k = CashflowForecastService.forecast(
        txns,
        days: 30,
        referenceDate: refDate,
        openingBalanceOverride: 50000,
        safetyBuffer: 5000,
        goalReserves: 60000, // Exceeds balance
      );

      expect(fc0.safeToSpend, greaterThan(fc5k.safeToSpend));
      expect(fc5k.safeToSpend, greaterThan(fc20k.safeToSpend));
      expect(fc60k.safeToSpend, equals(0.0),
          reason: 'Headroom cannot be negative; must clamp to 0');
      expect(fc20k.expectedGoalReserves, equals(20000));
    });

    test(
        'Invariant 2: Path-dependent Safe-to-Spend is constrained by trough, not ending balance',
        () {
      // Scenario: Starting ₹50,000. Rent ₹42,000 on day 4 (trough = ₹8,000). Salary ₹80,000 on day 10.
      // Ending balance is ₹88,000.
      // With safety buffer ₹5,000: spendable headroom is constrained by trough: 8,000 - 5,000 = 3,000.
      // A naive sum-based algorithm would compute (88,000 - 5,000) = 83,000, which would cause an overdraft on day 4!
      final rentBill = RecurringPayment(
        id: 'rent_july',
        merchantName: 'Landlord Rent',
        amount: 42000,
        frequency: 'monthly',
        lastPaidAt: refDate.subtract(const Duration(days: 26)),
        nextDueAt: refDate.add(const Duration(days: 4)),
        categoryId: 'housing',
        status: RecurringStatus.confirmed,
        createdAt: refDate,
        updatedAt: refDate,
      );

      final forecast = CashflowForecastService.forecast(
        [],
        confirmedBills: [rentBill],
        days: 30,
        referenceDate: refDate,
        openingBalanceOverride: 50000,
        safetyBuffer: 5000,
      );

      expect(forecast.lowestProjectedBalance, equals(8000.0));
      expect(forecast.troughDriver, contains('Landlord Rent'));
      expect(forecast.totalSafeToSpend, equals(3000.0),
          reason:
              '8,000 lowest balance - 5,000 safety buffer = 3,000 headroom');
      expect(forecast.safeToSpend, closeTo(3000.0 / 30.0, 0.01));
    });

    test(
        'Invariant 3: What-If simulation does not alter points prior to simulation date',
        () {
      final base = CashflowForecastService.forecast(
        [],
        days: 30,
        referenceDate: refDate,
        openingBalanceOverride: 30000,
        safetyBuffer: 5000,
      );

      final simDate = DateTime(refDate.year, refDate.month, refDate.day + 10);
      const simAmount = 15000.0;
      final sim = CashflowForecastService.simulateExpense(
        base,
        amount: simAmount,
        date: simDate,
      );

      for (int i = 0; i < base.dailyPoints.length; i++) {
        final basePt = base.dailyPoints[i];
        final simPt = sim.dailyPoints[i];

        if (basePt.date.isBefore(simDate)) {
          expect(simPt.balance, equals(basePt.balance),
              reason:
                  'Point at index $i before simulation date must be invariant');
          expect(
              simPt.scenarioBalance ?? simPt.balance, equals(basePt.balance));
        } else {
          expect(simPt.balance, equals(basePt.balance),
              reason: 'Base trajectory balance at index $i is preserved');
          expect(simPt.scenarioBalance, equals(basePt.balance - simAmount),
              reason:
                  'Scenario curve at index $i on/after simulation date must reflect purchase reduction');
        }
      }
      expect(sim.projectedEndingBalance,
          equals(base.projectedEndingBalance - simAmount));
    });

    test(
        'Invariant 4: Recurring commitments are excluded from variable baseline spend to avoid double counting',
        () {
      final txns = [
        TransactionRecord(
          id: 'netflix_1',
          amount: 649,
          date: refDate.subtract(const Duration(days: 30)),
          type: TransactionType.expense,
          categoryId: 'entertainment',
          isRecurring: true,
          merchantName: 'Netflix',
        ),
        TransactionRecord(
          id: 'grocery_1',
          amount: 3000,
          date: refDate.subtract(const Duration(days: 5)),
          type: TransactionType.expense,
          categoryId: 'food',
          isRecurring: false,
          merchantName: 'Blinkit',
        ),
      ];

      final netflixBill = RecurringPayment(
        id: 'netflix_bill',
        merchantName: 'Netflix',
        amount: 649,
        frequency: 'monthly',
        lastPaidAt: refDate.subtract(const Duration(days: 30)),
        nextDueAt: refDate.add(const Duration(days: 2)),
        categoryId: 'entertainment',
        status: RecurringStatus.confirmed,
        createdAt: refDate,
        updatedAt: refDate,
      );

      final forecast = CashflowForecastService.forecast(
        txns,
        confirmedBills: [netflixBill],
        days: 30,
        referenceDate: refDate,
        openingBalanceOverride: 10000,
      );

      // Total expected bills must be ₹649
      expect(forecast.expectedBills, equals(649.0));
      // Baseline variable expense should only reflect Blinkit (₹3000 over 31 effective days), excluding Netflix
      expect(forecast.expectedVariableExpenses,
          closeTo((3000.0 / 31.0) * 30.0, 1.0));
    });

    test(
        'Invariant 5: Zero transactions degrades gracefully to insufficientData with safeToSpend = 0',
        () {
      final forecast = CashflowForecastService.forecast(
        [],
        days: 30,
        referenceDate: refDate,
      );

      expect(forecast.hasInsufficientData, isTrue);
      expect(forecast.riskLevel, equals(CashflowRiskLevel.insufficientData));
      expect(forecast.confidence, equals(CashflowConfidence.insufficientData));
      expect(forecast.safeToSpend, equals(0.0));
    });

    test('Invariant 6: Chart safety buffer matches forecast safetyBuffer', () {
      const customBuffer = 12500.0;
      final forecast = CashflowForecastService.forecast(
        [],
        days: 30,
        referenceDate: refDate,
        openingBalanceOverride: 40000,
        safetyBuffer: customBuffer,
      );

      expect(forecast.safetyBuffer, equals(customBuffer));
      expect(forecast.lowestProjectedBalance - customBuffer,
          equals(forecast.totalSafeToSpend));
    });
  });

  // ===========================================================================
  // SECTION 3: RECURRENCE MATHEMATICS & CALENDAR ANCHOR ACCURACY
  // ===========================================================================
  group('Phase E: Recurrence Mathematics & Detection Integrity', () {
    test(
        'Invariant 7: Month-end anchor day preservation across 28/29/30/31 day months',
        () {
      final jan31 = DateTime(2026, 1, 31);

      // Advance to Feb: 2026 is non-leap year -> Feb 28
      final feb = RecurrenceCalculator.computeNextOccurrence(
        anchorDate: jan31,
        currentOccurrence: jan31,
        frequency: RecurringFrequency.monthly,
      );
      expect(feb.year, equals(2026));
      expect(feb.month, equals(2));
      expect(feb.day, equals(28));

      // Advance Feb 28 to March: must restore original 31 anchor day!
      final mar = RecurrenceCalculator.computeNextOccurrence(
        anchorDate: jan31,
        currentOccurrence: feb,
        frequency: RecurringFrequency.monthly,
      );
      expect(mar.year, equals(2026));
      expect(mar.month, equals(3));
      expect(mar.day, equals(31),
          reason: 'Anchor day 31 must be restored in March');

      // Leap year test: 2024
      final jan31_2024 = DateTime(2024, 1, 31);
      final feb2024 = RecurrenceCalculator.computeNextOccurrence(
        anchorDate: jan31_2024,
        currentOccurrence: jan31_2024,
        frequency: RecurringFrequency.monthly,
      );
      expect(feb2024.year, equals(2024));
      expect(feb2024.month, equals(2));
      expect(feb2024.day, equals(29),
          reason: 'Leap year Feb 29 must be respected');

      final mar2024 = RecurrenceCalculator.computeNextOccurrence(
        anchorDate: jan31_2024,
        currentOccurrence: feb2024,
        frequency: RecurringFrequency.monthly,
      );
      expect(mar2024.month, equals(3));
      expect(mar2024.day, equals(31));
    });

    test(
        'Invariant 8: False-positive rejection in recurring detection heuristics',
        () {
      final erraticSms = [
        SmsTransaction(
          id: 'swiggy_1',
          amount: 340,
          merchantName: 'Swiggy',
          bankName: 'HDFC',
          transactionType: 'debit',
          timestamp: DateTime(2026, 6, 2),
          rawSmsBody: 'Swiggy 340',
          smsSender: 'HDFC-BANK',
          smsHash: 'h1',
        ),
        SmsTransaction(
          id: 'swiggy_2',
          amount: 512,
          merchantName: 'Swiggy',
          bankName: 'HDFC',
          transactionType: 'debit',
          timestamp: DateTime(2026, 6, 8),
          rawSmsBody: 'Swiggy 512',
          smsSender: 'HDFC-BANK',
          smsHash: 'h2',
        ),
        SmsTransaction(
          id: 'swiggy_3',
          amount: 220,
          merchantName: 'Swiggy',
          bankName: 'HDFC',
          transactionType: 'debit',
          timestamp: DateTime(2026, 6, 17),
          rawSmsBody: 'Swiggy 220',
          smsSender: 'HDFC-BANK',
          smsHash: 'h3',
        ),
      ];

      final detected = RecurringDetectionService.detect(erraticSms);
      expect(
          detected
              .where((d) => d.merchantName.toLowerCase().contains('swiggy')),
          isEmpty,
          reason:
              'Erratic dining expenses must not be classified as recurring subscriptions');
    });

    test(
        'Invariant 9: Legitimate monthly subscription is detected with price-hike detection',
        () {
      final subSms = [
        SmsTransaction(
          id: 'gym_1',
          amount: 2000,
          merchantName: 'Cult.Fit Gym',
          bankName: 'ICICI',
          transactionType: 'debit',
          timestamp: DateTime(2026, 4, 5),
          rawSmsBody: 'Cult 2000',
          smsSender: 'ICICI-BANK',
          smsHash: 'g1',
        ),
        SmsTransaction(
          id: 'gym_2',
          amount: 2000,
          merchantName: 'Cult.Fit Gym',
          bankName: 'ICICI',
          transactionType: 'debit',
          timestamp: DateTime(2026, 5, 5),
          rawSmsBody: 'Cult 2000',
          smsSender: 'ICICI-BANK',
          smsHash: 'g2',
        ),
        SmsTransaction(
          id: 'gym_3',
          amount: 2500, // Price hike!
          merchantName: 'Cult.Fit Gym',
          bankName: 'ICICI',
          transactionType: 'debit',
          timestamp: DateTime(2026, 6, 5),
          rawSmsBody: 'Cult 2500',
          smsSender: 'ICICI-BANK',
          smsHash: 'g3',
        ),
      ];

      final detected = RecurringDetectionService.detect(subSms);
      expect(detected.isNotEmpty, isTrue);
      final gym = detected.firstWhere((d) => d.merchantName.contains('Cult'));
      expect(gym.amount, equals(2500.0));
      expect(gym.previousAmount, equals(2000.0),
          reason:
              'Must capture previous baseline amount for price hike warning');
    });
  });

  // ===========================================================================
  // SECTION 4: ALERTS LIFECYCLE & DEDUPLICATION INTEGRITY
  // ===========================================================================
  group('Phase D: Alerts Deduplication & Lifecycle', () {
    test(
        'Invariant 10: AlertEvaluator budget thresholds escalate and prevent duplicate spamming',
        () {
      final now = DateTime(2026, 7, 15);

      // Warning stage (92% used)
      final alertsWarning = AlertEvaluator.evaluateBudgetAlerts(
        budgets: {'cat_dining': 10000},
        spent: {'cat_dining': 9200},
        now: now,
      );
      expect(alertsWarning.length, equals(1));
      expect(alertsWarning.first.stage, equals(AppAlertStage.warning));
      expect(alertsWarning.first.alertKey,
          equals('budget:cat_dining:2026-07:warning'));

      // Re-evaluate at 95% (still warning stage) -> alertKey is identical for deduplication
      final alertsWarning2 = AlertEvaluator.evaluateBudgetAlerts(
        budgets: {'cat_dining': 10000},
        spent: {'cat_dining': 9500},
        now: now,
      );
      expect(
          alertsWarning2.first.alertKey, equals(alertsWarning.first.alertKey),
          reason:
              'AlertKey must remain stable across same stage for idempotent deduplication');

      // Escalate to exceeded stage (105% used)
      final alertsExceeded = AlertEvaluator.evaluateBudgetAlerts(
        budgets: {'cat_dining': 10000},
        spent: {'cat_dining': 10500},
        now: now,
      );
      expect(alertsExceeded.first.stage, equals(AppAlertStage.exceeded));
      expect(alertsExceeded.first.alertKey,
          equals('budget:cat_dining:2026-07:exceeded'));

      // Escalate to critical stage (130% used)
      final alertsCritical = AlertEvaluator.evaluateBudgetAlerts(
        budgets: {'cat_dining': 10000},
        spent: {'cat_dining': 13000},
        now: now,
      );
      expect(alertsCritical.first.stage, equals(AppAlertStage.critical));
      expect(alertsCritical.first.alertKey,
          equals('budget:cat_dining:2026-07:critical'));
    });

    test(
        'Invariant 11: Alert reconciliation on transaction resolution / bill cancellation',
        () async {
      final repo = AlertRepository();
      final alert = AppAlert(
        id: 'bill_alert_test',
        type: AppAlertType.bill,
        title: 'Electricity Due',
        message: 'Bill due tomorrow',
        createdAt: DateTime.now(),
        alertKey: 'bill:elec_123:2026-07-15',
      );
      await repo.insert(alert);

      expect((await repo.getAll()).length, equals(1));

      // Bill is paid/cancelled: AlertCoordinator calls onBillResolved
      AlertEvaluationCoordinator().onBillResolved('elec_123');

      // Give event-queue microtask a tick to resolve
      await Future.delayed(const Duration(milliseconds: 50));

      // Alert should be reconciled/dismissed
      final active = await repo.getAll();
      expect(active.where((a) => a.alertKey?.contains('elec_123') ?? false),
          isEmpty);
    });
  });
}
