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
import 'package:pet/premium/models/app_alert.dart';
import 'package:pet/premium/models/recurring_payment.dart';
import 'package:pet/premium/models/saving_goal.dart';
import 'package:pet/premium/providers/alert_provider.dart';
import 'package:pet/premium/repositories/alert_repository.dart';
import 'package:pet/premium/services/alert_evaluation_coordinator.dart';

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
  late AlertRepository repository;
  late AlertProvider provider;
  late AlertEvaluationCoordinator coordinator;

  final now = DateTime(2026, 7, 20);
  final List<MethodCall> notificationMethodCalls = [];

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    PathProviderPlatform.instance = MockPathProviderPlatform();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'),
      (MethodCall methodCall) async {
        notificationMethodCalls.add(methodCall);
        return null;
      },
    );
  });

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync();
    dbPath = p.join(tempDir.path, 'coordinator_test.db');

    db = await openDatabase(
      dbPath,
      version: 17,
      onCreate: (db, version) async {
        await DatabaseHelper().onCreateForTesting(db, version);
      },
    );

    repository = AlertRepository(database: db);
    coordinator = AlertEvaluationCoordinator(repository: repository);
    provider = AlertProvider(repository: repository, coordinator: coordinator);
    coordinator.attachProvider(provider);
    notificationMethodCalls.clear();
  });

  tearDown(() async {
    coordinator.detachProvider();
    await db.close();
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('AlertEvaluationCoordinator Tests', () {
    test('onTransactionsChanged evaluates anomalies, deduplicates, persists, and updates provider', () async {
      // 3 baseline months of ₹100/mo, current month has ₹300 spike, and ₹5,000 income to ensure positive cashflow
      final txns = [
        TransactionRecord(
          id: 't_income',
          amount: 5000,
          date: DateTime(2026, 7, 1),
          categoryId: 'cat_salary',
          type: TransactionType.income,
        ),
        TransactionRecord(
          id: 't_base_1',
          amount: 100,
          date: DateTime(2026, 4, 15),
          categoryId: 'cat_gadgets',
          type: TransactionType.expense,
        ),
        TransactionRecord(
          id: 't_base_2',
          amount: 100,
          date: DateTime(2026, 5, 15),
          categoryId: 'cat_gadgets',
          type: TransactionType.expense,
        ),
        TransactionRecord(
          id: 't_base_3',
          amount: 100,
          date: DateTime(2026, 6, 15),
          categoryId: 'cat_gadgets',
          type: TransactionType.expense,
        ),
        TransactionRecord(
          id: 't_spike',
          amount: 300,
          date: DateTime(2026, 7, 10),
          categoryId: 'cat_gadgets',
          type: TransactionType.expense,
        ),
      ];

      await coordinator.onTransactionsChanged(txns, now: now);

      // Verify alert was persisted in repository
      final dbAlerts = await repository.getPage();
      expect(dbAlerts.length, equals(1));
      expect(dbAlerts.first.type, equals(AppAlertType.anomaly));
      expect(dbAlerts.first.alertKey, equals('anomaly:cat_gadgets:2026-07'));

      // Verify in-memory AlertProvider was updated via injectNewAlerts
      expect(provider.alerts.length, equals(1));
      expect(provider.unreadCount, equals(1));
      expect(provider.alerts.first.id, equals(dbAlerts.first.id));

      // Re-invoking onTransactionsChanged should deduplicate against existing alertKey
      await coordinator.onTransactionsChanged(txns, now: now);

      final dbAlertsAfter = await repository.getPage();
      expect(dbAlertsAfter.length, equals(1));
      expect(provider.alerts.length, equals(1));
    });

    test('onBudgetsChanged evaluates warning and exceeded alerts into database and provider', () async {
      final budgets = {'cat_food': 1000.0, 'cat_shopping': 500.0};
      final spent = {'cat_food': 950.0, 'cat_shopping': 600.0}; // 95% and 120%

      await coordinator.onBudgetsChanged(
        budgets: budgets,
        spent: spent,
        now: now,
      );

      final dbAlerts = await repository.getPage();
      expect(dbAlerts.length, equals(3));

      final keys = dbAlerts.map((a) => a.alertKey).toSet();
      expect(keys.contains('budget:cat_food:2026-07:warning'), isTrue);
      expect(keys.contains('budget:cat_shopping:2026-07:exceeded'), isTrue);
      expect(keys.contains('budget_pacing:cat_food:2026-07'), isTrue);

      expect(provider.alerts.length, equals(3));
      expect(provider.unreadCount, equals(3));
    });

    test('onRecurringChanged evaluates upcoming bills due within 3 days', () async {
      final bill = RecurringPayment(
        id: 'rec_spotify',
        merchantName: 'Spotify',
        amount: 119,
        frequency: 'monthly',
        lastPaidAt: DateTime(2026, 6, 22),
        nextDueAt: DateTime(2026, 7, 22), // 2 days from now (July 20)
        categoryId: 'entertainment',
      );

      await coordinator.onRecurringChanged([bill], now: now);

      final dbAlerts = await repository.getPage();
      expect(dbAlerts.length, equals(1));
      expect(dbAlerts.first.type, equals(AppAlertType.bill));
      expect(dbAlerts.first.alertKey, equals('bill:rec_spotify:2026-07-22'));
      expect(provider.alerts.length, equals(1));
    });

    test('onGoalsChanged evaluates goal achievements', () async {
      final goal = SavingGoal(
        id: 'goal_vacation',
        name: 'Goa Trip',
        targetAmount: 20000,
        currentAmount: 20000, // 100%
        createdAt: DateTime(2026, 1, 1),
      );

      await coordinator.onGoalsChanged([goal], now: now);

      final dbAlerts = await repository.getPage();
      expect(dbAlerts.length, equals(1));
      expect(dbAlerts.first.type, equals(AppAlertType.goal));
      expect(dbAlerts.first.title, contains('Goal Achieved'));
      expect(provider.alerts.length, equals(1));
    });
  });
}
