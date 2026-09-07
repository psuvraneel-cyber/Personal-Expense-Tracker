import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pet/data/database/database_helper.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/data/repositories/transaction_repository.dart';
import 'package:pet/premium/models/app_alert.dart';
import 'package:pet/premium/models/recurring_payment.dart';
import 'package:pet/premium/providers/alert_provider.dart';
import 'package:pet/premium/repositories/alert_repository.dart';
import 'package:pet/premium/repositories/recurring_payment_repository.dart';
import 'package:pet/premium/services/alert_evaluation_coordinator.dart';
import 'package:pet/premium/services/alert_evaluator.dart';
import 'package:pet/premium/services/cashflow_forecast_service.dart';

class MockPathProviderPlatform extends PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async {
    return Directory.systemTemp.path;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String dbPath;
  late Database db;
  late AlertRepository alertRepo;
  late RecurringPaymentRepository recurringRepo;
  late TransactionRepository transactionRepo;
  late AlertProvider provider;
  late AlertEvaluationCoordinator coordinator;

  final now = DateTime(2026, 7, 20, 10, 0);

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    PathProviderPlatform.instance = MockPathProviderPlatform();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'),
      (MethodCall methodCall) async {
        return null;
      },
    );
  });

  setUp(() async {
    CashflowForecastService.clearCache();
    tempDir = Directory.systemTemp.createTempSync();
    dbPath = p.join(tempDir.path, 'cashflow_alerts_test.db');

    db = await openDatabase(
      dbPath,
      version: 17,
      onCreate: (db, version) async {
        await DatabaseHelper().onCreateForTesting(db, version);
      },
    );

    DatabaseHelper.setTestDatabase(db);
    alertRepo = AlertRepository(database: db);
    recurringRepo = RecurringPaymentRepository();
    transactionRepo = TransactionRepository();
    coordinator = AlertEvaluationCoordinator(
      repository: alertRepo,
      recurringRepository: recurringRepo,
      transactionRepository: transactionRepo,
    );
    provider = AlertProvider(repository: alertRepo, coordinator: coordinator);
    coordinator.attachProvider(provider);
  });

  tearDown(() async {
    coordinator.detachProvider();
    DatabaseHelper.setTestDatabase(null);
    await db.close();
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('CF-06: Reference Date Propagation', () {
    test('evaluateCashflowRisk produces deterministic alerts for a historical or simulated referenceDate', () {
      final simDate = DateTime(2026, 3, 15, 12, 0);
      // Ensure >= 7 days of history so confidence is not insufficientData
      final deficitTxns = [
        TransactionRecord(
          id: 't_exp_old',
          amount: 5000,
          date: simDate.subtract(const Duration(days: 14)),
          categoryId: 'bills',
          type: TransactionType.expense,
        ),
        TransactionRecord(
          id: 't_exp_recent',
          amount: 25000,
          date: simDate.subtract(const Duration(days: 2)),
          categoryId: 'shopping',
          type: TransactionType.expense,
        ),
      ];

      final alert = AlertEvaluator.evaluateCashflowRisk(
        transactions: deficitTxns,
        now: simDate,
      );

      expect(alert, isNotNull);
      expect(alert!.alertKey, equals('cashflow:2026-03:critical'));
      expect(alert.type, equals(AppAlertType.cashflow));
    });
  });

  group('CF-07 & CF-08: Recurring Commitments in Alert Coordinator', () {
    test('onTransactionsChanged includes confirmed bills from RecurringPaymentRepository', () async {
      // Insert a confirmed upcoming rent liability into repository
      final bill = RecurringPayment(
        id: 'rec_rent_major',
        merchantName: 'Landlord Mega Rent',
        amount: 50000,
        frequency: 'monthly',
        lastPaidAt: now.subtract(const Duration(days: 20)),
        nextDueAt: now.add(const Duration(days: 5)),
        categoryId: 'housing',
        status: RecurringStatus.confirmed,
      );
      await recurringRepo.upsert(bill);

      // User has 10 days of history, ₹15,000 income, but rent is ₹50,000
      final txns = [
        TransactionRecord(
          id: 't_inc',
          amount: 15000,
          date: now.subtract(const Duration(days: 10)),
          categoryId: 'income',
          type: TransactionType.income,
        ),
        TransactionRecord(
          id: 't_exp',
          amount: 5000,
          date: now.subtract(const Duration(days: 2)),
          categoryId: 'food',
          type: TransactionType.expense,
        ),
      ];

      // onTransactionsChanged fetches confirmed bills and detects cashflow deficit
      await coordinator.onTransactionsChanged(txns, now: now);

      final dbAlerts = await alertRepo.getPage();
      final cashflowAlerts = dbAlerts.where((a) => a.type == AppAlertType.cashflow).toList();
      expect(cashflowAlerts.length, equals(1));
      expect(cashflowAlerts.first.title, contains('Cashflow Risk Warning'));
      expect(provider.alerts.any((a) => a.type == AppAlertType.cashflow), isTrue);
    });

    test('onRecurringChanged triggers cashflow risk evaluation alongside bill alert', () async {
      // Insert transactions into repository so onRecurringChanged can read them
      await db.insert('transactions', {
        'id': 't_hist_1',
        'amount': 15000.0,
        'date': now.subtract(const Duration(days: 12)).toIso8601String(),
        'categoryId': 'income',
        'type': 'income',
      });
      await db.insert('transactions', {
        'id': 't_hist_2',
        'amount': 8000.0,
        'date': now.subtract(const Duration(days: 2)).toIso8601String(),
        'categoryId': 'groceries',
        'type': 'expense',
      });

      // An upcoming large quarterly insurance payment that forces cashflow into deficit
      final insuranceBill = RecurringPayment(
        id: 'rec_insurance',
        merchantName: 'Life Insurance Co',
        amount: 80000,
        frequency: 'quarterly',
        lastPaidAt: now.subtract(const Duration(days: 90)),
        nextDueAt: now.add(const Duration(days: 2)), // 2 days -> triggers bill alert too
        categoryId: 'insurance',
        status: RecurringStatus.confirmed,
      );

      await coordinator.onRecurringChanged([insuranceBill], now: now);

      final dbAlerts = await alertRepo.getPage();
      final billAlert = dbAlerts.where((a) => a.type == AppAlertType.bill).toList();
      final cashflowAlert = dbAlerts.where((a) => a.type == AppAlertType.cashflow).toList();

      expect(billAlert.length, equals(1));
      expect(cashflowAlert.length, equals(1));
    });
  });

  group('CF-09 & CF-10: Risk Deduplication & Auto-Reconciliation', () {
    test('reconciles and auto-dismisses cashflow danger alert when salary resolves deficit', () async {
      // 1. Initial state: heavy expenses causing cashflow deficit alert (>= 7 days history)
      final deficitTxns = [
        TransactionRecord(
          id: 't_exp_baseline',
          amount: 2000,
          date: now.subtract(const Duration(days: 14)),
          categoryId: 'food',
          type: TransactionType.expense,
        ),
        TransactionRecord(
          id: 't_exp_huge',
          amount: 40000,
          date: now.subtract(const Duration(days: 3)),
          categoryId: 'medical',
          type: TransactionType.expense,
        ),
      ];

      await coordinator.onTransactionsChanged(deficitTxns, now: now);

      var alerts = await alertRepo.getPage();
      expect(alerts.any((a) => a.type == AppAlertType.cashflow && !a.isDismissed), isTrue);
      expect(provider.alerts.any((a) => a.type == AppAlertType.cashflow), isTrue);

      // 2. User deposits ₹150,000 monthly salary, completely resolving deficit & turning cashflow healthy
      final resolvedTxns = [
        ...deficitTxns,
        TransactionRecord(
          id: 't_salary_relief',
          amount: 150000,
          date: now,
          categoryId: 'salary',
          type: TransactionType.income,
        ),
      ];

      CashflowForecastService.clearCache();
      await coordinator.onTransactionsChanged(resolvedTxns, now: now);

      // 3. Verify cashflow alert was auto-reconciled (dismissed in repo and removed from active provider list)
      alerts = await alertRepo.getPage();
      final unDismissedCashflowAlerts = alerts.where((a) => a.type == AppAlertType.cashflow && !a.isDismissed).toList();
      expect(unDismissedCashflowAlerts, isEmpty);
      expect(provider.alerts.any((a) => a.type == AppAlertType.cashflow), isFalse);
    });
  });
}
