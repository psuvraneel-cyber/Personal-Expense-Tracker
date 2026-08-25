import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pet/data/database/database_helper.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/recurring_occurrence.dart';
import 'package:pet/data/models/recurring_rule.dart';
import 'package:pet/data/repositories/recurring_transaction_repository.dart';
import 'package:pet/data/repositories/transaction_repository.dart';
import 'package:pet/services/recurring_transaction_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late RecurringTransactionRepository repo;
  late TransactionRepository txnRepo;
  late RecurringTransactionService service;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(
      inMemoryDatabasePath,
      version: 15,
      onCreate: (db, version) async {
        await DatabaseHelper().onCreateForTesting(db, version);
      },
    );
    DatabaseHelper.setTestDatabase(db);
    repo = RecurringTransactionRepository();
    txnRepo = TransactionRepository();
    service = RecurringTransactionService(repository: repo);
  });

  tearDown(() async {
    await db.close();
    DatabaseHelper.setTestDatabase(null);
  });

  group('Recurring Transactions Concurrency & Idempotency Tests', () {
    test('1. Parallel concurrent execution: 10 racing workers generate exactly 1 transaction', () async {
      final now = DateTime(2026, 8, 20, 10, 0);
      final startDate = DateTime(2026, 8, 1, 10, 0);

      // Create a monthly rule due on Aug 1
      final rule = RecurringRule(
        id: 'rule_concurrent_test',
        amount: 2500,
        type: TransactionType.expense,
        categoryId: 'utilities',
        frequency: RecurringFrequency.monthly,
        startDate: startDate,
        nextOccurrenceDate: startDate,
        createdAt: startDate,
        updatedAt: startDate,
      );
      await repo.insertRule(rule);

      // Launch 10 simultaneous workers executing generateDueOccurrences at the exact same moment
      final futures = List.generate(
        10,
        (_) => service.generateDueOccurrences(now: now),
      );

      final results = await Future.wait(futures);

      // Count total generated transactions across all workers
      final totalGenerated = results.expand((list) => list).length;
      expect(totalGenerated, equals(1), reason: 'Only exactly 1 transaction should be generated across all 10 racing workers');

      // Verify transactions table in SQLite has exactly 1 row
      final allTxns = await txnRepo.getAllTransactions();
      expect(allTxns.length, equals(1));
      expect(allTxns.first.amount, equals(2500));
      expect(allTxns.first.recurringRuleId, equals('rule_concurrent_test'));

      // Verify occurrences table has exactly 1 row
      final occurrences = await repo.getOccurrencesForRule('rule_concurrent_test');
      expect(occurrences.length, equals(1));
      expect(occurrences.first.status, equals(RecurringOccurrenceStatus.generated));
      expect(occurrences.first.transactionId, equals(allTxns.first.id));
    });

    test('2. Sequential retry idempotency: Repeated calls produce zero duplicate transactions', () async {
      final now = DateTime(2026, 8, 20, 10, 0);
      final startDate = DateTime(2026, 8, 1, 10, 0);

      final rule = RecurringRule(
        id: 'rule_retry_test',
        amount: 1200,
        type: TransactionType.expense,
        categoryId: 'entertainment',
        frequency: RecurringFrequency.monthly,
        startDate: startDate,
        nextOccurrenceDate: startDate,
        createdAt: startDate,
        updatedAt: startDate,
      );
      await repo.insertRule(rule);

      // First run: generates 1 occurrence
      final firstRun = await service.generateDueOccurrences(now: now);
      expect(firstRun.length, equals(1));

      // Second run: immediately afterwards at the same timestamp
      final secondRun = await service.generateDueOccurrences(now: now);
      expect(secondRun, isEmpty);

      // Third run: 5 minutes later before next month
      final thirdRun = await service.generateDueOccurrences(now: now.add(const Duration(minutes: 5)));
      expect(thirdRun, isEmpty);

      // Verify DB has strictly 1 transaction
      final txns = await txnRepo.getAllTransactions();
      expect(txns.length, equals(1));
    });

    test('3. Skipped occurrence invariant: Skipped occurrence is NEVER re-generated during reconciliation', () async {
      final now = DateTime(2026, 9, 5, 10, 0);
      final startDate = DateTime(2026, 8, 1, 10, 0);

      // Create rule and skip Aug 1 occurrence
      final rule = RecurringRule(
        id: 'rule_skip_test',
        amount: 3000,
        type: TransactionType.expense,
        categoryId: 'rent',
        frequency: RecurringFrequency.monthly,
        startDate: startDate,
        nextOccurrenceDate: DateTime(2026, 9, 1, 10, 0),
        createdAt: startDate,
        updatedAt: startDate,
      );
      await repo.insertRule(rule);

      // User skips Aug 1 occurrence
      await service.skipOccurrence(
        ruleId: 'rule_skip_test',
        scheduledDate: startDate,
      );

      // Verify occurrence recorded as skipped
      final occ = await repo.getOccurrence('rule_skip_test', startDate);
      expect(occ, isNotNull);
      expect(occ!.status, equals(RecurringOccurrenceStatus.skipped));

      // Run generation at Sep 5 (due for Sep 1)
      final generated = await service.generateDueOccurrences(now: now);
      expect(generated.length, equals(1));
      expect(generated.first.date, equals(DateTime(2026, 9, 1, 10, 0)));

      // Verify Aug 1 was NEVER generated into transactions table
      final allTxns = await txnRepo.getAllTransactions();
      expect(allTxns.length, equals(1));
      expect(allTxns.first.date, equals(DateTime(2026, 9, 1, 10, 0)));
    });

    test('4. Delete occurrence and skip: Deleting transaction marks occurrence skipped and prevents re-creation', () async {
      final now = DateTime(2026, 8, 20, 10, 0);

      // Create rule and generate first transaction immediately
      final created = await service.createRule(
        amount: 800,
        type: TransactionType.expense,
        categoryId: 'coffee',
        frequency: RecurringFrequency.weekly,
        startDate: DateTime(2026, 8, 1, 10, 0),
      );

      final firstTxn = created.firstTransaction!;
      expect(firstTxn, isNotNull);

      // Verify transaction exists
      var allTxns = await txnRepo.getAllTransactions();
      expect(allTxns.length, equals(1));

      // Delete the first occurrence transaction
      await service.deleteOccurrenceTransaction(
        transactionId: firstTxn.id,
        ruleId: created.rule.id,
        scheduledDate: DateTime(2026, 8, 1, 10, 0),
      );

      // Verify transaction removed
      allTxns = await txnRepo.getAllTransactions();
      expect(allTxns, isEmpty);

      // Run reconciliation / catch-up again at Aug 20
      await service.generateDueOccurrences(now: now);

      // Aug 1 must NOT be re-created, but Aug 8 and Aug 15 should be generated
      allTxns = await txnRepo.getAllTransactions();
      final dates = allTxns.map((t) => t.date).toList();
      expect(dates.contains(DateTime(2026, 8, 1, 10, 0)), isFalse);
      expect(dates.contains(DateTime(2026, 8, 8, 10, 0)), isTrue);
      expect(dates.contains(DateTime(2026, 8, 15, 10, 0)), isTrue);
    });

    test('5. Bounded multi-month catch-up: Generates past occurrences in chronological order and advances rule', () async {
      final now = DateTime(2026, 11, 15, 10, 0);
      final startDate = DateTime(2026, 8, 31, 10, 0);

      final rule = RecurringRule(
        id: 'rule_catchup_test',
        amount: 15000,
        type: TransactionType.expense,
        categoryId: 'rent',
        frequency: RecurringFrequency.monthly,
        startDate: startDate,
        nextOccurrenceDate: DateTime(2026, 8, 31, 10, 0),
        createdAt: startDate,
        updatedAt: startDate,
      );
      await repo.insertRule(rule);

      // Run catch-up
      final generated = await service.generateDueOccurrences(now: now);

      // Expected occurrences: Aug 31, Sep 30, Oct 31
      expect(generated.length, equals(3));
      expect(generated[0].date, equals(DateTime(2026, 8, 31, 10, 0)));
      expect(generated[1].date, equals(DateTime(2026, 9, 30, 10, 0)));
      expect(generated[2].date, equals(DateTime(2026, 10, 31, 10, 0)));

      // Verify rule's nextOccurrenceDate advanced to Nov 30
      final updatedRule = await repo.getRuleById('rule_catchup_test');
      expect(updatedRule!.nextOccurrenceDate, equals(DateTime(2026, 11, 30, 10, 0)));
    });
  });
}
