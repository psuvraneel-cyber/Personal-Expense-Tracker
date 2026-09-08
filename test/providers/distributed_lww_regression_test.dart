import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pet/data/database/database_helper.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/data/repositories/transaction_repository.dart';
import 'package:pet/models/account_session.dart';
import 'package:pet/premium/models/saving_goal.dart';
import 'package:pet/premium/providers/goal_provider.dart';
import 'package:pet/premium/repositories/saving_goal_repository.dart';
import 'package:pet/providers/transaction_provider.dart';
import 'package:pet/services/firestore_sync_service.dart';

class MockSyncForLWW implements FirestoreSyncService {
  final List<TransactionRecord> upsertedTxns = [];
  final List<String> deletedTombstones = [];
  final List<SavingGoal> upsertedGoals = [];

  @override
  bool get isAuthenticated => true;

  @override
  String? get currentUserIdOrNull => 'test_user';

  @override
  String get currentUserId => 'test_user';

  @override
  int get sessionGeneration => 1;

  @override
  AccountSession get currentSession => const AccountSession(uid: 'test_user', generation: 1);

  @override
  Stream<List<TransactionRecord>> transactionsStream({int? limit = 1000}) => const Stream.empty();

  @override
  Stream<List<Map<String, dynamic>>> tombstonesStream() => const Stream.empty();

  @override
  Stream<List<SavingGoal>> savingGoalsStream() => const Stream.empty();

  @override
  Future<void> upsertTransaction(TransactionRecord t) async {
    upsertedTxns.add(t);
  }

  @override
  Future<void> deleteTombstone(String id) async {
    deletedTombstones.add(id);
  }

  @override
  Future<void> upsertSavingGoal(SavingGoal g) async {
    upsertedGoals.add(g);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late MockSyncForLWW mockSync;

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
    mockSync = MockSyncForLWW();
  });

  tearDown(() async {
    await db.close();
    DatabaseHelper.setTestDatabase(null);
  });

  group('Distributed LWW & Tombstone Reconciliation', () {
    test('triggerSyncQueue discards update if tombstone deletedAt is newer than txn updatedAt', () async {
      final repo = TransactionRepository();
      final provider = TransactionProvider(
        repository: repo,
        firestoreSync: mockSync,
      );

      final now = DateTime.now();
      final staleTxn = TransactionRecord(
        id: 'tx_conflict',
        amount: 250.0,
        type: TransactionType.expense,
        categoryId: 'cat_groceries',
        date: now.subtract(const Duration(hours: 3)),
        updatedAt: now.subtract(const Duration(hours: 2)),
      );

      // Enqueue an offline update action
      await repo.enqueueSyncAction(
        'sync_act_1',
        staleTxn.id,
        'update',
        jsonEncode(staleTxn.toMap()),
        'test_user',
      );

      // Record a tombstone that occurred 1 hour ago (after the update 2 hours ago)
      provider.recordTombstoneDeletedAtForTesting(
        'tx_conflict',
        now.subtract(const Duration(hours: 1)),
      );

      // Trigger sync queue
      await provider.triggerSyncQueue();

      // Transaction MUST NOT have been upserted to Firestore
      expect(mockSync.upsertedTxns.any((t) => t.id == 'tx_conflict'), isFalse);

      // The queued action must have been cleared
      final pending = await repo.getPendingSyncActions('test_user');
      expect(pending.where((a) => a['transactionId'] == 'tx_conflict'), isEmpty);

      provider.dispose();
    });

    test('triggerSyncQueue allows update if txn updatedAt is newer than tombstone deletedAt', () async {
      final repo = TransactionRepository();
      final provider = TransactionProvider(
        repository: repo,
        firestoreSync: mockSync,
      );

      final now = DateTime.now();
      final freshTxn = TransactionRecord(
        id: 'tx_fresh',
        amount: 300.0,
        type: TransactionType.expense,
        categoryId: 'cat_dining',
        date: now.subtract(const Duration(hours: 3)),
        updatedAt: now, // Updated now, after tombstone 1 hour ago
      );

      await repo.enqueueSyncAction(
        'sync_act_2',
        freshTxn.id,
        'update',
        jsonEncode(freshTxn.toMap()),
        'test_user',
      );

      provider.recordTombstoneDeletedAtForTesting(
        'tx_fresh',
        now.subtract(const Duration(hours: 1)),
      );

      await provider.triggerSyncQueue();

      // Transaction MUST be upserted to Firestore
      expect(mockSync.upsertedTxns.any((t) => t.id == 'tx_fresh'), isTrue);
      // Stale tombstone must be deleted
      expect(mockSync.deletedTombstones, contains('tx_fresh'));

      provider.dispose();
    });

    test('GoalProvider reconcileRemoteGoals uploads newer local goals to Firestore', () async {
      final repo = SavingGoalRepository();
      final provider = GoalProvider(
        repository: repo,
        firestoreSync: mockSync,
      );

      final now = DateTime.now();
      final localGoal = SavingGoal(
        id: 'goal_newer_local',
        name: 'Local Goal 2.0',
        targetAmount: 5000,
        currentAmount: 2500,
        createdAt: now.subtract(const Duration(days: 2)),
        updatedAt: now,
      );
      await repo.upsert(localGoal);
      await provider.load();

      final olderRemoteGoal = SavingGoal(
        id: 'goal_newer_local',
        name: 'Remote Goal 1.0',
        targetAmount: 5000,
        currentAmount: 1000,
        createdAt: now.subtract(const Duration(days: 2)),
        updatedAt: now.subtract(const Duration(hours: 3)),
      );

      await provider.reconcileRemoteGoals([olderRemoteGoal]);

      // Local goal should not be overwritten
      expect(provider.goals.first.name, 'Local Goal 2.0');
      // Local goal should be synced up to Firestore
      expect(mockSync.upsertedGoals.any((g) => g.id == 'goal_newer_local'), isTrue);

      provider.dispose();
    });
  });
}
