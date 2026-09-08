import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:pet/data/database/database_helper.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/premium/models/weekly_limit.dart';
import 'package:pet/premium/providers/weekly_planner_provider.dart';
import 'package:pet/premium/repositories/weekly_planner_repository.dart';

void main() {
  late Directory tempDir;
  late String dbPath;
  late Database db;
  late WeeklyPlannerRepository repository;
  late WeeklyPlannerProvider provider;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync();
    dbPath = p.join(tempDir.path, 'weekly_prov_test.db');

    db = await openDatabase(
      dbPath,
      version: 20,
      onCreate: (d, v) async {
        await DatabaseHelper().onCreateForTesting(d, v);
      },
    );

    repository = WeeklyPlannerRepository(database: db);
    provider = WeeklyPlannerProvider(repository: repository);
  });

  tearDown(() async {
    try {
      await db.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('WeeklyPlannerProvider Tests', () {
    test('setLimit persists to repository and updates in-memory state', () async {
      await provider.setLimit(
        categoryId: 'cat-groceries',
        categoryName: 'Groceries',
        weeklyLimit: 3000,
      );

      expect(provider.hasLimits, isTrue);
      expect(provider.entries.length, 1);
      final entry = provider.entries.first;
      expect(entry.categoryId, 'cat-groceries');
      expect(entry.categoryName, 'Groceries');
      expect(entry.weeklyLimit, 3000.0);
      expect(entry.weeklySpent, 0.0);
      expect(entry.remaining, 3000.0);
      expect(entry.isOverBudget, isFalse);

      // Verify persisted in SQLite
      final repoLimit = await repository.getLimit('cat-groceries');
      expect(repoLimit, isNotNull);
      expect(repoLimit!.weeklyLimit, 3000.0);
    });

    test('removeLimit removes from repository and in-memory state', () async {
      await provider.setLimit(
        categoryId: 'cat-dining',
        categoryName: 'Dining',
        weeklyLimit: 1500,
      );
      expect(provider.entries.length, 1);

      await provider.removeLimit('cat-dining');
      expect(provider.entries.isEmpty, isTrue);
      expect(await repository.getLimit('cat-dining'), isNull);
    });

    test('refreshFromTransactions computes spend correctly and updates entry status', () async {
      await provider.setLimit(
        categoryId: 'cat-shopping',
        categoryName: 'Shopping',
        weeklyLimit: 2000,
      );

      final now = DateTime.now();
      final txns = [
        TransactionRecord(
          id: 't1',
          amount: 800,
          date: now,
          type: TransactionType.expense,
          categoryId: 'cat-shopping',
        ),
        TransactionRecord(
          id: 't2',
          amount: 1500,
          date: now,
          type: TransactionType.expense,
          categoryId: 'cat-shopping',
        ),
        TransactionRecord(
          id: 't3',
          amount: 5000,
          date: now,
          type: TransactionType.income, // Income should not be counted as expense
          categoryId: 'cat-shopping',
        ),
      ];

      provider.refreshFromTransactions(txns);

      expect(provider.entries.length, 1);
      final entry = provider.entries.first;
      expect(entry.weeklySpent, 2300.0); // 800 + 1500
      expect(entry.isOverBudget, isTrue);
      expect(entry.remaining, 0.0);
      expect(entry.progress, 1.0);
      expect(provider.totalWeekSpent, 2300.0);
    });

    test('robust fingerprinting recomputes on modified list with same length', () async {
      await provider.setLimit(
        categoryId: 'cat-tech',
        categoryName: 'Tech',
        weeklyLimit: 5000,
      );

      final now = DateTime.now();
      final txns1 = [
        TransactionRecord(
          id: 't1',
          amount: 1000,
          date: now,
          type: TransactionType.expense,
          categoryId: 'cat-tech',
        ),
      ];
      provider.refreshFromTransactions(txns1);
      expect(provider.entries.first.weeklySpent, 1000.0);

      // Recreating a new List instance with altered amount (same length, different fingerprint)
      final txns2 = [
        TransactionRecord(
          id: 't1',
          amount: 2500,
          date: now,
          type: TransactionType.expense,
          categoryId: 'cat-tech',
        ),
      ];
      provider.refreshFromTransactions(txns2);
      // Must not rely on fragile identical() memoization
      expect(provider.entries.first.weeklySpent, 2500.0);
    });

    test('clearData wipes memory and repository on logout', () async {
      await provider.setLimit(
        categoryId: 'cat-bills',
        categoryName: 'Bills',
        weeklyLimit: 1000,
      );
      expect(provider.entries.isNotEmpty, isTrue);

      await provider.clearData();
      expect(provider.entries.isEmpty, isTrue);
      expect(provider.totalWeekSpent, 0.0);
      expect(provider.totalWeekLimit, 0.0);
      expect((await repository.getAll()).isEmpty, isTrue);
    });

    test('commutative transaction fingerprint ignores list ordering but invalidates on any mutation', () async {
      await provider.setLimit(
        categoryId: 'cat-books',
        categoryName: 'Books',
        weeklyLimit: 2000,
      );

      final now = DateTime.now();
      final t1 = TransactionRecord(
        id: 'txn-1',
        amount: 500,
        date: now,
        type: TransactionType.expense,
        categoryId: 'cat-books',
      );
      final t2 = TransactionRecord(
        id: 'txn-2',
        amount: 800,
        date: now,
        type: TransactionType.expense,
        categoryId: 'cat-books',
      );

      // Pass in order [t1, t2]
      provider.refreshFromTransactions([t1, t2]);
      expect(provider.entries.first.weeklySpent, 1300.0);

      // Pass reversed list [t2, t1] -> should have same fingerprint, cache reused
      provider.refreshFromTransactions([t2, t1]);
      expect(provider.entries.first.weeklySpent, 1300.0);

      // Mutate amount on t1 -> different fingerprint, recomputes
      final t1Mutated = TransactionRecord(
        id: 'txn-1',
        amount: 900,
        date: now,
        type: TransactionType.expense,
        categoryId: 'cat-books',
      );
      provider.refreshFromTransactions([t2, t1Mutated]);
      expect(provider.entries.first.weeklySpent, 1700.0);

      // Mutate type on t2 from expense to income -> different fingerprint, recomputes
      final t2Income = TransactionRecord(
        id: 'txn-2',
        amount: 800,
        date: now,
        type: TransactionType.income,
        categoryId: 'cat-books',
      );
      provider.refreshFromTransactions([t2Income, t1Mutated]);
      expect(provider.entries.first.weeklySpent, 900.0);
    });

    test('load resolves one-off limit over recurring limit for current week', () async {
      final now = DateTime.now();
      final monday = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: (now.weekday - 1) % 7));

      final recurring = WeeklyLimit(
        id: 'rule-rec',
        categoryId: 'cat-groceries',
        categoryName: 'Groceries',
        weeklyLimit: 3000,
        createdAt: now,
        updatedAt: now,
        recurrencePolicy: WeeklyRecurrencePolicy.recurring,
      );
      final oneOff = WeeklyLimit(
        id: 'rule-oneoff',
        categoryId: 'cat-groceries',
        categoryName: 'Groceries',
        weeklyLimit: 6000,
        createdAt: now,
        updatedAt: now,
        recurrencePolicy: WeeklyRecurrencePolicy.oneOff,
        periodStart: monday,
      );

      await repository.upsert(recurring);
      await repository.upsert(oneOff);

      await provider.load();
      expect(provider.entries.length, 1);
      final entry = provider.entries.first;
      // One-off limit of 6000 takes priority over recurring 3000
      expect(entry.weeklyLimit, 6000.0);
      expect(entry.recurrencePolicy, WeeklyRecurrencePolicy.oneOff);
    });
  });
}
