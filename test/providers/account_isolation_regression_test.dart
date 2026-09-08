import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pet/data/database/database_helper.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/models/account_session.dart';
import 'package:pet/data/models/category.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/data/repositories/category_repository.dart';
import 'package:pet/data/repositories/transaction_repository.dart';
import 'package:pet/premium/models/saving_goal.dart';
import 'package:pet/premium/providers/goal_provider.dart';
import 'package:pet/premium/repositories/saving_goal_repository.dart';
import 'package:pet/premium/services/cashflow_forecast_service.dart';
import 'package:pet/providers/category_provider.dart';
import 'package:pet/providers/transaction_provider.dart';
import 'package:pet/services/firestore_sync_service.dart';
import 'package:flutter/material.dart';

class MockMultiSessionSyncService implements FirestoreSyncService {
  String? _uid;
  int _generation = 1;

  final StreamController<List<TransactionRecord>> txController =
      StreamController<List<TransactionRecord>>.broadcast();
  final StreamController<List<Map<String, dynamic>>> tombController =
      StreamController<List<Map<String, dynamic>>>.broadcast();
  final StreamController<List<Category>> catController =
      StreamController<List<Category>>.broadcast();
  final StreamController<List<SavingGoal>> goalController =
      StreamController<List<SavingGoal>>.broadcast();

  void setSession(String? uid, int generation) {
    _uid = uid;
    _generation = generation;
  }

  @override
  bool get isAuthenticated => _uid != null;

  @override
  String? get currentUserIdOrNull => _uid;

  @override
  String get currentUserId {
    if (_uid == null) throw StateError('FirestoreSyncService: user not authenticated');
    return _uid!;
  }

  @override
  int get sessionGeneration => _generation;

  @override
  AccountSession get currentSession => AccountSession(uid: _uid, generation: _generation);

  @override
  Stream<List<TransactionRecord>> transactionsStream({int? limit = 1000}) => txController.stream;

  @override
  Stream<List<Map<String, dynamic>>> tombstonesStream() => tombController.stream;

  @override
  Stream<List<Category>> categoriesStream() => catController.stream;

  @override
  Stream<List<SavingGoal>> savingGoalsStream() => goalController.stream;

  @override
  Future<void> upsertTransaction(TransactionRecord t) async {}

  @override
  Future<void> deleteTransaction(String id) async {}

  @override
  Future<void> createTombstone(String id) async {}

  @override
  Future<void> deleteTombstone(String id) async {}

  @override
  Future<void> upsertCategory(Category c) async {}

  @override
  Future<void> deleteCategory(String id) async {}

  @override
  Future<void> upsertSavingGoal(SavingGoal g) async {}

  @override
  Future<void> deleteSavingGoal(String id) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late MockMultiSessionSyncService fakeSync;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(
      inMemoryDatabasePath,
      version: 20,
      onCreate: (db, version) async {
        await DatabaseHelper().onCreateForTesting(db, version);
      },
    );
    DatabaseHelper.setTestDatabase(db);
    fakeSync = MockMultiSessionSyncService();
  });

  tearDown(() async {
    await db.close();
    DatabaseHelper.setTestDatabase(null);
  });

  group('Account Isolation Across Providers', () {
    test('TransactionProvider discards delayed snapshots from superseded session', () async {
      fakeSync.setSession('user_a', 1);
      final repo = TransactionRepository();
      final provider = TransactionProvider(
        repository: repo,
        firestoreSync: fakeSync,
      );

      await provider.loadTransactions();
      expect(provider.transactions, isEmpty);

      // Session switches to User B (e.g., account change)
      fakeSync.setSession('user_b', 2);

      // Stale event arriving from User A's stream
      final staleTx = TransactionRecord(
        id: 'tx_user_a',
        amount: 99.0,
        type: TransactionType.expense,
        categoryId: 'cat_food',
        date: DateTime.now(),
      );
      fakeSync.txController.add([staleTx]);

      // Give stream time to process
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // User B's state MUST NOT contain User A's transaction
      expect(provider.transactions.any((t) => t.id == 'tx_user_a'), isFalse);

      provider.dispose();
    });

    test('CategoryProvider discards delayed custom category snapshot on session switch', () async {
      fakeSync.setSession('user_a', 1);
      final repo = CategoryRepository();
      final provider = CategoryProvider(
        repository: repo,
        firestoreSync: fakeSync,
      );

      await provider.loadCategories();

      // Session switches to User B
      fakeSync.setSession('user_b', 2);

      // Stale event arriving from User A's categories stream
      final staleCat = Category(
        id: 'cat_custom_user_a',
        name: 'User A Custom Secret',
        icon: Icons.star,
        color: Colors.amber,
        isCustom: true,
        type: 'expense',
      );
      fakeSync.catController.add([staleCat]);

      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Provider MUST NOT contain User A's custom category
      expect(provider.categories.any((c) => c.id == 'cat_custom_user_a'), isFalse);

      provider.dispose();
    });

    test('GoalProvider drops stale snapshot without throwing StateError on logout', () async {
      fakeSync.setSession('user_a', 1);
      final repo = SavingGoalRepository();
      final provider = GoalProvider(
        repository: repo,
        firestoreSync: fakeSync,
      );

      await provider.load();

      // Simulate sign out: uid becomes null, generation advances
      fakeSync.setSession(null, 2);

      // Emitting snapshot while logged out MUST be dropped safely without crashing with StateError
      final staleGoal = SavingGoal(
        id: 'goal_user_a',
        name: 'User A Secret Car',
        targetAmount: 50000,
        currentAmount: 1000,
        createdAt: DateTime.now(),
      );

      expect(() => fakeSync.goalController.add([staleGoal]), returnsNormally);

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(provider.goals.any((g) => g.id == 'goal_user_a'), isFalse);

      provider.dispose();
    });

    test('CashflowForecastService isolates cache by userId', () {
      CashflowForecastService.clearCache();

      final txns = [
        TransactionRecord(
          id: 'tx_1',
          amount: 50.0,
          type: TransactionType.expense,
          categoryId: 'groceries',
          date: DateTime.now().subtract(const Duration(days: 2)),
        ),
      ];

      final forecastA = CashflowForecastService.forecast(
        txns,
        openingBalanceOverride: 1000.0,
        userId: 'user_a',
      );

      final forecastB = CashflowForecastService.forecast(
        txns,
        openingBalanceOverride: 500.0,
        userId: 'user_b',
      );

      expect(forecastA.startingBalance, 1000.0);
      expect(forecastB.startingBalance, 500.0);
      expect(forecastA.startingBalance != forecastB.startingBalance, isTrue);
    });
  });
}
