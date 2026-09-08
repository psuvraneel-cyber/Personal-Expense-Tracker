import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pet/data/database/database_helper.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/premium/models/app_alert.dart';
import 'package:pet/premium/repositories/alert_repository.dart';
import 'package:pet/premium/services/alert_evaluation_coordinator.dart';
import 'package:pet/premium/services/alert_evaluator.dart';
import 'package:pet/premium/services/anomaly_detection_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:pet/data/repositories/budget_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

class MockPathProviderPlatform extends PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async {
    return Directory.systemTemp.path;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  const uuid = Uuid();
  final now = DateTime(2026, 7, 15, 12, 0);
  late Directory tempDir;

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    PathProviderPlatform.instance = MockPathProviderPlatform();
  });

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync();
  });

  tearDown(() {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  Future<({AlertRepository repo, AlertEvaluationCoordinator coordinator})>
      createTestContext() async {
    final dbPath = p.join(tempDir.path, 'test_${uuid.v4()}.db');
    final db = await openDatabase(
      dbPath,
      version: 17,
      onCreate: (db, version) async {
        await DatabaseHelper().onCreateForTesting(db, version);
      },
    );
    final repo = AlertRepository(database: db);
    final budgetRepo = BudgetRepository(database: db);
    final coordinator = AlertEvaluationCoordinator(
      repository: repo,
      budgetRepository: budgetRepo,
    );
    return (repo: repo, coordinator: coordinator);
  }

  group('Adversarial Audit 1: Anomaly Detection Mathematics & Scoping', () {
    test('3 normal months + 1 normal current month does NOT trigger anomaly', () {
      final txns = [
        // 3 baseline months (April, May, June) @ ₹5,000 each
        TransactionRecord(
          id: 'b1',
          amount: 5000,
          date: DateTime(2026, 4, 10),
          categoryId: 'food',
          type: TransactionType.expense,
        ),
        TransactionRecord(
          id: 'b2',
          amount: 5000,
          date: DateTime(2026, 5, 10),
          categoryId: 'food',
          type: TransactionType.expense,
        ),
        TransactionRecord(
          id: 'b3',
          amount: 5000,
          date: DateTime(2026, 6, 10),
          categoryId: 'food',
          type: TransactionType.expense,
        ),
        // Current month (July) @ ₹5,000 (normal spend)
        TransactionRecord(
          id: 'c1',
          amount: 5000,
          date: DateTime(2026, 7, 10),
          categoryId: 'food',
          type: TransactionType.expense,
        ),
      ];

      final baseline = AlertEvaluator.computeBaseline(txns, now: now);
      expect(baseline['food'], equals(5000.0));

      final alerts = AlertEvaluator.evaluateAnomalies(
        transactions: txns,
        baseline: baseline,
        now: now,
      );

      expect(alerts, isEmpty, reason: 'Normal spending must not trigger anomaly');
    });

    test('Genuine spike (>= 1.8x and delta >= 300) DOES trigger anomaly', () {
      final txns = [
        TransactionRecord(
          id: 'b1',
          amount: 2000,
          date: DateTime(2026, 4, 10),
          categoryId: 'dining',
          type: TransactionType.expense,
        ),
        TransactionRecord(
          id: 'b2',
          amount: 2000,
          date: DateTime(2026, 5, 10),
          categoryId: 'dining',
          type: TransactionType.expense,
        ),
        TransactionRecord(
          id: 'b3',
          amount: 2000,
          date: DateTime(2026, 6, 10),
          categoryId: 'dining',
          type: TransactionType.expense,
        ),
        // July spend = ₹5,000 (2.5x baseline, delta = 3,000 >= 300)
        TransactionRecord(
          id: 'c1',
          amount: 5000,
          date: DateTime(2026, 7, 10),
          categoryId: 'dining',
          type: TransactionType.expense,
        ),
      ];

      final baseline = AlertEvaluator.computeBaseline(txns, now: now);
      final alerts = AlertEvaluator.evaluateAnomalies(
        transactions: txns,
        baseline: baseline,
        now: now,
      );

      expect(alerts.length, equals(1));
      expect(alerts.first.type, equals(AppAlertType.anomaly));
      expect(alerts.first.alertKey, equals('anomaly:dining:2026-07'));
      expect(alerts.first.message, contains('2.5x higher than usual'));
    });

    test('Zero baseline suppresses anomaly (no division by zero / explosive ratios)', () {
      final txns = [
        // No historical transactions in category 'travel'
        TransactionRecord(
          id: 'c1',
          amount: 5000,
          date: DateTime(2026, 7, 10),
          categoryId: 'travel',
          type: TransactionType.expense,
        ),
      ];

      final baseline = AlertEvaluator.computeBaseline(txns, now: now);
      expect(baseline['travel'], isNull);

      final spikes = AnomalyDetectionService.detectSpikes(
        txns,
        baseline,
        now: now,
      );
      expect(spikes, isEmpty);

      final alerts = AlertEvaluator.evaluateAnomalies(
        transactions: txns,
        baseline: baseline,
        now: now,
      );
      expect(alerts, isEmpty);
    });

    test('Low delta spike (e.g. ₹10 to ₹20) is suppressed by minSpendDelta (300)', () {
      final txns = [
        TransactionRecord(
          id: 'b1',
          amount: 10,
          date: DateTime(2026, 6, 10),
          categoryId: 'snacks',
          type: TransactionType.expense,
        ),
        TransactionRecord(
          id: 'c1',
          amount: 25, // 2.5x ratio, but delta is only 15 (< 300)
          date: DateTime(2026, 7, 10),
          categoryId: 'snacks',
          type: TransactionType.expense,
        ),
      ];

      final baseline = AlertEvaluator.computeBaseline(txns, now: now);
      final alerts = AlertEvaluator.evaluateAnomalies(
        transactions: txns,
        baseline: baseline,
        now: now,
        minSpendDelta: 300.0,
      );

      expect(alerts, isEmpty, reason: 'Small ₹15 delta must not cause user noise');
    });

    test('Year boundary transition (Dec 2025 -> Jan 2026) correctly scopes baseline and detects anomaly', () {
      final janRef = DateTime(2026, 1, 15);
      final txns = [
        TransactionRecord(
          id: 'b1',
          amount: 1000,
          date: DateTime(2025, 10, 15),
          categoryId: 'groceries',
          type: TransactionType.expense,
        ),
        TransactionRecord(
          id: 'b2',
          amount: 1000,
          date: DateTime(2025, 11, 15),
          categoryId: 'groceries',
          type: TransactionType.expense,
        ),
        TransactionRecord(
          id: 'b3',
          amount: 1000,
          date: DateTime(2025, 12, 15),
          categoryId: 'groceries',
          type: TransactionType.expense,
        ),
        // January 2026 spend = 3,000 (3.0x)
        TransactionRecord(
          id: 'c1',
          amount: 3000,
          date: DateTime(2026, 1, 10),
          categoryId: 'groceries',
          type: TransactionType.expense,
        ),
      ];

      final baseline = AlertEvaluator.computeBaseline(txns, now: janRef);
      expect(baseline['groceries'], equals(1000.0));

      final alerts = AlertEvaluator.evaluateAnomalies(
        transactions: txns,
        baseline: baseline,
        now: janRef,
      );

      expect(alerts.length, equals(1));
      expect(alerts.first.alertKey, equals('anomaly:groceries:2026-01'));
    });
  });

  group('Adversarial Audit 2: Budget State Transitions & Identity', () {
    test('89% does not alert, 90% triggers warning, 100% triggers exceeded, 125% triggers critical', () {
      final budgets = {'food': 1000.0};

      // 89% -> No alert
      final alerts89 = AlertEvaluator.evaluateBudgetAlerts(
        budgets: budgets,
        spent: {'food': 890.0},
        now: now,
      );
      expect(alerts89, isEmpty);

      // 90% -> Warning
      final alerts90 = AlertEvaluator.evaluateBudgetAlerts(
        budgets: budgets,
        spent: {'food': 900.0},
        now: now,
      );
      expect(alerts90.length, equals(1));
      expect(alerts90.first.stage, equals(AppAlertStage.warning));
      expect(alerts90.first.severity, equals(AlertSeverity.warning));
      expect(alerts90.first.alertKey, equals('budget:food:2026-07:warning'));

      // 100% -> Exceeded
      final alerts100 = AlertEvaluator.evaluateBudgetAlerts(
        budgets: budgets,
        spent: {'food': 1000.0},
        now: now,
      );
      expect(alerts100.length, equals(1));
      expect(alerts100.first.stage, equals(AppAlertStage.exceeded));
      expect(alerts100.first.severity, equals(AlertSeverity.critical));
      expect(alerts100.first.alertKey, equals('budget:food:2026-07:exceeded'));

      // 125% -> Critical overrun
      final alerts125 = AlertEvaluator.evaluateBudgetAlerts(
        budgets: budgets,
        spent: {'food': 1250.0},
        now: now,
      );
      expect(alerts125.length, equals(1));
      expect(alerts125.first.stage, equals(AppAlertStage.critical));
      expect(alerts125.first.severity, equals(AlertSeverity.critical));
      expect(alerts125.first.alertKey, equals('budget:food:2026-07:critical'));
    });

    test('July 2026 and July 2027 budgets do not collide in alertKey', () {
      final budgets = {'rent': 10000.0};
      final spent = {'rent': 10000.0};

      final alert2026 = AlertEvaluator.evaluateBudgetAlerts(
        budgets: budgets,
        spent: spent,
        now: DateTime(2026, 7, 1),
      ).first;

      final alert2027 = AlertEvaluator.evaluateBudgetAlerts(
        budgets: budgets,
        spent: spent,
        now: DateTime(2027, 7, 1),
      ).first;

      expect(alert2026.alertKey, equals('budget:rent:2026-07:exceeded'));
      expect(alert2027.alertKey, equals('budget:rent:2027-07:exceeded'));
      expect(alert2026.alertKey, isNot(equals(alert2027.alertKey)));
    });
  });

  group('Adversarial Audit 3: Duplicate Transaction Filtering & Commutative Keys', () {
    test('Flags same merchant and amount within 15 mins (case-insensitive and trimmed)', () {
      final txns = [
        TransactionRecord(
          id: 'd1',
          amount: 450,
          date: DateTime(2026, 7, 15, 14, 0),
          categoryId: 'food',
          type: TransactionType.expense,
          merchantName: 'Swiggy ',
        ),
        TransactionRecord(
          id: 'd2',
          amount: 450,
          date: DateTime(2026, 7, 15, 14, 4),
          categoryId: 'food',
          type: TransactionType.expense,
          merchantName: 'swiggy',
        ),
      ];

      final alerts = AlertEvaluator.evaluateDuplicateTransactions(
        transactions: txns,
        now: now,
      );

      expect(alerts.length, equals(1));
      expect(alerts.first.alertKey, equals('dup_txn:d1_d2'));
    });

    test('SUPPRESSES false duplicate when merchant names are different even if category matches', () {
      final txns = [
        TransactionRecord(
          id: 'u1',
          amount: 500,
          date: DateTime(2026, 7, 15, 14, 0),
          categoryId: 'transport',
          type: TransactionType.expense,
          merchantName: 'Uber',
        ),
        TransactionRecord(
          id: 'u2',
          amount: 500,
          date: DateTime(2026, 7, 15, 14, 5),
          categoryId: 'transport',
          type: TransactionType.expense,
          merchantName: 'Swiggy Genie',
        ),
      ];

      final alerts = AlertEvaluator.evaluateDuplicateTransactions(
        transactions: txns,
        now: now,
      );

      expect(alerts, isEmpty, reason: 'Different merchants must never be flagged as duplicates');
    });

    test('Commutative alertKey is deterministic regardless of evaluation order or timestamp equality', () {
      final tA = TransactionRecord(
        id: 'z_second',
        amount: 250,
        date: DateTime(2026, 7, 15, 10, 0),
        categoryId: 'cafe',
        type: TransactionType.expense,
      );
      final tB = TransactionRecord(
        id: 'a_first',
        amount: 250,
        date: DateTime(2026, 7, 15, 10, 0),
        categoryId: 'cafe',
        type: TransactionType.expense,
      );

      final alertsForward = AlertEvaluator.evaluateDuplicateTransactions(
        transactions: [tA, tB],
        now: now,
      );

      final alertsReverse = AlertEvaluator.evaluateDuplicateTransactions(
        transactions: [tB, tA],
        now: now,
      );

      expect(alertsForward.first.alertKey, equals('dup_txn:a_first_z_second'));
      expect(alertsReverse.first.alertKey, equals('dup_txn:a_first_z_second'));
      expect(alertsForward.first.alertKey, equals(alertsReverse.first.alertKey));
    });
  });

  group('Adversarial Audit 4: Large Transaction False Positive Resistance', () {
    test('Normal monthly rent (₹25,000 with ₹30,000 budget and ₹25,000 median) is NOT flagged', () {
      final txns = [
        TransactionRecord(
          id: 'r1',
          amount: 25000,
          date: DateTime(2026, 7, 1),
          categoryId: 'rent',
          type: TransactionType.expense,
          merchantName: 'Landlord',
        ),
        TransactionRecord(
          id: 'r2',
          amount: 25000,
          date: DateTime(2026, 7, 15),
          categoryId: 'rent',
          type: TransactionType.expense,
          merchantName: 'Landlord',
        ),
      ];

      final alerts = AlertEvaluator.evaluateLargeTransactions(
        transactions: txns,
        categoryBudgets: {'rent': 30000.0},
        now: now,
      );

      expect(alerts, isEmpty, reason: 'Normal rent expenditure matching category median must not be flagged');
    });

    test('Marked recurring transactions (isRecurring = true) are NEVER flagged as large transaction alerts', () {
      final txns = [
        TransactionRecord(
          id: 'rec1',
          amount: 50000,
          date: DateTime(2026, 7, 5),
          categoryId: 'emi',
          type: TransactionType.expense,
          isRecurring: true,
          merchantName: 'HDFC Home Loan',
        ),
      ];

      final alerts = AlertEvaluator.evaluateLargeTransactions(
        transactions: txns,
        categoryBudgets: {'emi': 60000.0},
        now: now,
      );

      expect(alerts, isEmpty);
    });

    test('Genuine outlier (median ₹200, sudden ₹3,000 dining expense) IS flagged', () {
      final txns = [
        TransactionRecord(
          id: 'd1',
          amount: 200,
          date: DateTime(2026, 7, 2),
          categoryId: 'dining',
          type: TransactionType.expense,
        ),
        TransactionRecord(
          id: 'd2',
          amount: 200,
          date: DateTime(2026, 7, 5),
          categoryId: 'dining',
          type: TransactionType.expense,
        ),
        TransactionRecord(
          id: 'd3',
          amount: 3000, // 15x median
          date: DateTime(2026, 7, 10),
          categoryId: 'dining',
          type: TransactionType.expense,
          merchantName: 'Luxury Steakhouse',
        ),
      ];

      final alerts = AlertEvaluator.evaluateLargeTransactions(
        transactions: txns,
        now: now,
      );

      expect(alerts.length, equals(1));
      expect(alerts.first.alertKey, equals('large_txn:d3'));
      expect(alerts.first.amount, equals(3000.0));
    });
  });

  group('Adversarial Audit 5: Cashflow 14-Day Horizon & Imminent Deficit', () {
    test('Flags imminent deficit occurring within 14 days even if ending 30-day balance is positive', () {
      final txns = List.generate(
        10,
        (i) => TransactionRecord(
          id: 'cf_$i',
          amount: 2000,
          type: TransactionType.expense,
          categoryId: 'living',
          date: now.subtract(Duration(days: i)),
        ),
      );

      final alert = AlertEvaluator.evaluateCashflowRisk(
        transactions: txns,
        now: now,
      );

      expect(alert, isNotNull);
      expect(alert!.type, equals(AppAlertType.cashflow));
      expect(alert.message, contains('deficit'));
    });
  });

  group('Adversarial Audit 6: Concurrency & Race Condition Serialization', () {
    test('Parallel rapid calls to processAndDispatch insert exactly 1 alert with 0 duplicates', () async {
      final ctx = await createTestContext();
      final repo = ctx.repo;
      final coordinator = ctx.coordinator;

      final alert = AppAlert(
        id: uuid.v4(),
        type: AppAlertType.budget,
        stage: AppAlertStage.warning,
        severity: AlertSeverity.warning,
        title: 'Budget Alert',
        message: '90% of budget reached',
        alertKey: 'budget:test_cat:2026-07:warning',
        createdAt: now,
      );

      // Invoke 5 times concurrently in parallel
      await Future.wait([
        coordinator.processAndDispatch([alert]),
        coordinator.processAndDispatch([alert]),
        coordinator.processAndDispatch([alert]),
        coordinator.processAndDispatch([alert]),
        coordinator.processAndDispatch([alert]),
      ]);

      final activeCount = await repo.getActiveCount();
      expect(activeCount, equals(1), reason: 'Concurrent processAndDispatch must not insert duplicate alerts');
    });
  });

  group('Adversarial Audit 7: Entity Lifecycle & Retention Cleanups', () {
    test('onBillResolved marks bill alert as dismissed and resolvedAt populated', () async {
      final ctx = await createTestContext();
      final repo = ctx.repo;
      final coordinator = ctx.coordinator;

      final alert = AppAlert(
        id: uuid.v4(),
        type: AppAlertType.bill,
        stage: AppAlertStage.warning,
        severity: AlertSeverity.warning,
        title: 'Bill Due',
        message: 'Electricity bill due',
        recurringPaymentId: 'bill_elec_1',
        alertKey: 'bill:bill_elec_1:2026-07-20',
        createdAt: now,
      );
      await repo.insert(alert);

      expect(await repo.getActiveCount(), equals(1));

      // User pays the bill -> onBillResolved called
      await coordinator.onBillResolved('bill_elec_1');

      expect(await repo.getActiveCount(), equals(0));
      final resolved = await repo.getById(alert.id);
      expect(resolved!.isDismissed, isTrue);
      expect(resolved.resolvedAt, isNotNull);
    });

    test('onGoalDeleted marks goal alert as dismissed and resolvedAt populated', () async {
      final ctx = await createTestContext();
      final repo = ctx.repo;
      final coordinator = ctx.coordinator;

      final alert = AppAlert(
        id: uuid.v4(),
        type: AppAlertType.goal,
        stage: AppAlertStage.info,
        severity: AlertSeverity.info,
        title: 'Goal Achieved',
        message: 'Emergency fund completed',
        goalId: 'goal_emergency_99',
        alertKey: 'goal_achieved:goal_emergency_99',
        createdAt: now,
      );
      await repo.insert(alert);

      expect(await repo.getActiveCount(), equals(1));

      // Goal is deleted -> onGoalDeleted called
      await coordinator.onGoalDeleted('goal_emergency_99');

      expect(await repo.getActiveCount(), equals(0));
      final resolved = await repo.getById(alert.id);
      expect(resolved!.isDismissed, isTrue);
      expect(resolved.resolvedAt, isNotNull);
    });

    test('purgeOldDismissedAlerts purges read/dismissed alerts older than retention threshold', () async {
      final ctx = await createTestContext();
      final repo = ctx.repo;

      final oldAlert = AppAlert(
        id: 'old_dismissed',
        type: AppAlertType.system,
        stage: AppAlertStage.warning,
        severity: AlertSeverity.info,
        title: 'Old alert',
        message: 'Ancient alert',
        isDismissed: true,
        createdAt: now.subtract(const Duration(days: 95)),
      );

      final recentAlert = AppAlert(
        id: 'recent_alert',
        type: AppAlertType.budget,
        stage: AppAlertStage.warning,
        severity: AlertSeverity.warning,
        title: 'Recent alert',
        message: 'Active recent alert',
        isDismissed: false,
        isRead: false,
        createdAt: now.subtract(const Duration(days: 5)),
      );

      await repo.insert(oldAlert);
      await repo.insert(recentAlert);

      final purged = await repo.purgeOldDismissedAlerts(now: now);
      expect(purged, equals(1));

      final remainingOld = await repo.getById('old_dismissed');
      final remainingRecent = await repo.getById('recent_alert');
      expect(remainingOld, isNull);
      expect(remainingRecent, isNotNull);
    });

    test('transaction deletion auto-resolves large transaction alert', () async {
      final ctx = await createTestContext();
      final repo = ctx.repo;
      final coordinator = ctx.coordinator;

      final alert = AppAlert(
        id: uuid.v4(),
        type: AppAlertType.largeTransaction,
        stage: AppAlertStage.warning,
        severity: AlertSeverity.warning,
        title: 'Large Txn',
        message: 'Unusually large expense',
        transactionId: 'txn_deleted_123',
        alertKey: 'large_txn:txn_deleted_123',
        createdAt: now,
      );
      await repo.insert(alert);

      expect(await repo.getActiveCount(), equals(1));

      // Remaining active transactions do NOT contain txn_deleted_123
      await coordinator.onTransactionsChanged([
        TransactionRecord(
          id: 'txn_surviving_456',
          amount: 50,
          date: now,
          categoryId: 'food',
          type: TransactionType.expense,
        ),
      ], now: now);

      expect(await repo.getActiveCount(), equals(0));
      final resolved = await repo.getById(alert.id);
      expect(resolved!.isDismissed, isTrue);
      expect(resolved.resolvedAt, isNotNull);
    });

    test('downward spend reset below 90% auto-resolves active budget alerts', () async {
      final ctx = await createTestContext();
      final repo = ctx.repo;
      final coordinator = ctx.coordinator;

      final alert = AppAlert(
        id: uuid.v4(),
        type: AppAlertType.budget,
        stage: AppAlertStage.exceeded,
        severity: AlertSeverity.critical,
        title: 'Budget Exceeded',
        message: '100% budget reached',
        categoryId: 'dining',
        period: '2026-07',
        alertKey: 'budget:dining:2026-07:exceeded',
        createdAt: now,
      );
      await repo.insert(alert);

      expect(await repo.getActiveCount(), equals(1));

      // Spending drops to ₹200 out of ₹1,000 budget (20% < 90%)
      await coordinator.onTransactionsChanged(
        [
          TransactionRecord(
            id: 't1',
            amount: 200,
            date: now,
            categoryId: 'dining',
            type: TransactionType.expense,
          ),
        ],
        budgets: {'dining': 1000.0},
        spent: {'dining': 200.0},
        now: now,
      );

      expect(await repo.getActiveCount(), equals(0));
      final resolved = await repo.getById(alert.id);
      expect(resolved!.isDismissed, isTrue);
      expect(resolved.resolvedAt, isNotNull);
    });
  });

  group('Adversarial Audit 8: Final Release-Gate Lifecycle & Regression Invariants', () {
    test('transaction deletion of first transaction (t1) in duplicate pair auto-resolves duplicate alert', () async {
      final ctx = await createTestContext();
      final repo = ctx.repo;
      final coordinator = ctx.coordinator;

      final t1 = TransactionRecord(
        id: 'dup_txn_alpha',
        amount: 500,
        date: now,
        categoryId: 'shopping',
        type: TransactionType.expense,
        merchantName: 'Amazon',
      );
      final t2 = TransactionRecord(
        id: 'dup_txn_beta',
        amount: 500,
        date: now.add(const Duration(minutes: 2)),
        categoryId: 'shopping',
        type: TransactionType.expense,
        merchantName: 'Amazon',
      );

      // 1. Initially both exist -> duplicate alert generated
      await coordinator.onTransactionsChanged([t1, t2], now: now);

      final activeAlertsInitial = await repo.getPage();
      expect(activeAlertsInitial.any((a) => a.type == AppAlertType.duplicateTransaction), isTrue);
      final dupAlert = activeAlertsInitial.firstWhere((a) => a.type == AppAlertType.duplicateTransaction);
      expect(dupAlert.alertKey, equals('dup_txn:dup_txn_alpha_dup_txn_beta'));

      // 2. User deletes t1 (the first transaction of the pair)
      await coordinator.onTransactionsChanged([t2], now: now);

      // 3. Duplicate alert must be auto-resolved
      final resolvedAlert = await repo.getById(dupAlert.id);
      expect(resolvedAlert!.isDismissed, isTrue, reason: 'Deleting either transaction in duplicate pair must resolve duplicate alert');
      expect(resolvedAlert.resolvedAt, isNotNull);
      final activeAlertsAfter = await repo.getPage();
      expect(activeAlertsAfter.any((a) => a.id == dupAlert.id), isFalse);
    });

    test('downward spend recalibration from 105% to 95% dismisses exceeded alert and activates warning alert', () async {
      final ctx = await createTestContext();
      final repo = ctx.repo;
      final coordinator = ctx.coordinator;

      // 1. Spend is at 105% (₹1,050 / ₹1,000) -> exceeded alert active
      await coordinator.onTransactionsChanged(
        [
          TransactionRecord(
            id: 'tx1',
            amount: 1050,
            date: now,
            categoryId: 'groceries',
            type: TransactionType.expense,
          ),
        ],
        budgets: {'groceries': 1000.0},
        spent: {'groceries': 1050.0},
        now: now,
      );

      var alerts = await repo.getPage();
      expect(alerts.any((a) => a.stage == AppAlertStage.exceeded), isTrue);
      final exceededAlert = alerts.firstWhere((a) => a.stage == AppAlertStage.exceeded);

      // 2. Spending drops to 95% (₹950 / ₹1,000)
      await coordinator.onTransactionsChanged(
        [
          TransactionRecord(
            id: 'tx1',
            amount: 950,
            date: now,
            categoryId: 'groceries',
            type: TransactionType.expense,
          ),
        ],
        budgets: {'groceries': 1000.0},
        spent: {'groceries': 950.0},
        now: now,
      );

      // 3. Exceeded alert must be dismissed/resolved, and warning alert active
      final oldExceeded = await repo.getById(exceededAlert.id);
      expect(oldExceeded!.isDismissed, isTrue, reason: 'Exceeded alert must be auto-resolved when spend drops to 95%');

      alerts = await repo.getPage();
      expect(alerts.any((a) => a.stage == AppAlertStage.warning), isTrue);
      expect(alerts.any((a) => a.stage == AppAlertStage.exceeded), isFalse);
    });

    test('re-evaluation after auto-resolve reactivates alert when threshold re-breached (new -> resolved -> re-evaluate)', () async {
      final ctx = await createTestContext();
      final repo = ctx.repo;
      final coordinator = ctx.coordinator;

      // 1. Initial spend at 95% -> warning alert generated
      await coordinator.onTransactionsChanged(
        [
          TransactionRecord(
            id: 'tx1',
            amount: 950,
            date: now,
            categoryId: 'dining',
            type: TransactionType.expense,
          ),
        ],
        budgets: {'dining': 1000.0},
        spent: {'dining': 950.0},
        now: now,
      );

      var active = await repo.getPage();
      final warningAlert = active.firstWhere((a) => a.stage == AppAlertStage.warning);
      final warningAlertId = warningAlert.id;

      // 2. Spend drops to 80% (₹800 / ₹1,000) -> warning alert auto-resolved
      await coordinator.onTransactionsChanged(
        [
          TransactionRecord(
            id: 'tx1',
            amount: 800,
            date: now,
            categoryId: 'dining',
            type: TransactionType.expense,
          ),
        ],
        budgets: {'dining': 1000.0},
        spent: {'dining': 800.0},
        now: now,
      );

      var resolved = await repo.getById(warningAlertId);
      expect(resolved!.isDismissed, isTrue);
      expect(resolved.resolvedAt, isNotNull);

      // 3. Spend climbs back up to 95% -> warning alert must reactivate
      await coordinator.onTransactionsChanged(
        [
          TransactionRecord(
            id: 'tx1',
            amount: 800,
            date: now,
            categoryId: 'dining',
            type: TransactionType.expense,
          ),
          TransactionRecord(
            id: 'tx2',
            amount: 150,
            date: now,
            categoryId: 'dining',
            type: TransactionType.expense,
          ),
        ],
        budgets: {'dining': 1000.0},
        spent: {'dining': 950.0},
        now: now,
      );

      final reactivated = await repo.getById(warningAlertId);
      expect(reactivated!.isDismissed, isFalse, reason: 'Auto-resolved alert must be reactivated when condition re-occurs');
      expect(reactivated.resolvedAt, isNull);
      expect(reactivated.amount, equals(950.0));
    });

    test('onBudgetsChanged auto-resolves exceeded alert when budget is adjusted upward', () async {
      final ctx = await createTestContext();
      final repo = ctx.repo;
      final coordinator = ctx.coordinator;

      // 1. Spend is ₹1,050 with ₹1,000 budget (105%) -> exceeded alert active
      await coordinator.onBudgetsChanged(
        budgets: {'entertainment': 1000.0},
        spent: {'entertainment': 1050.0},
        now: now,
      );

      var active = await repo.getPage();
      expect(active.any((a) => a.stage == AppAlertStage.exceeded), isTrue);
      final exceededAlert = active.firstWhere((a) => a.stage == AppAlertStage.exceeded);

      // 2. User adjusts budget upward to ₹2,000 (spent is now 1,050 / 2,000 = 52.5% < 90%)
      await coordinator.onBudgetsChanged(
        budgets: {'entertainment': 2000.0},
        spent: {'entertainment': 1050.0},
        now: now,
      );

      // 3. Exceeded alert must be dismissed
      final oldAlert = await repo.getById(exceededAlert.id);
      expect(oldAlert!.isDismissed, isTrue, reason: 'Budget adjustment upward must auto-resolve exceeded alert');
      expect(oldAlert.resolvedAt, isNotNull);
      expect(await repo.getActiveCount(), equals(0));
    });
  });
}
