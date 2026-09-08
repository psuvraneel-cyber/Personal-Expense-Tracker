import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pet/data/database/database_helper.dart';
import 'package:pet/data/models/enums.dart';
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

  group('RecurringTransactionService Lifecycle Tests', () {
    test('createRule with generateFirstOccurrenceImmediately creates rule and first transaction', () async {
      final startDate = DateTime(2026, 8, 20, 10, 0);
      final result = await service.createRule(
        amount: 2500,
        type: TransactionType.expense,
        categoryId: 'utilities',
        frequency: RecurringFrequency.monthly,
        startDate: startDate,
        note: 'Internet bill',
        generateFirstOccurrenceImmediately: true,
      );

      expect(result.rule.amount, 2500);
      expect(result.rule.frequency, RecurringFrequency.monthly);
      expect(result.firstTransaction, isNotNull);
      expect(result.firstTransaction!.amount, 2500);
      expect(result.firstTransaction!.date, startDate);
      expect(result.firstTransaction!.recurringRuleId, result.rule.id);

      final rules = await repo.getAllRules();
      expect(rules.length, 1);
      expect(rules.first.nextOccurrenceDate, DateTime(2026, 9, 20, 10, 0));

      final txns = await txnRepo.getAllTransactions();
      expect(txns.length, 1);
    });

    test('createRule without immediate generation only saves rule with nextOccurrenceDate at startDate', () async {
      final startDate = DateTime(2026, 9, 1, 10, 0);
      final result = await service.createRule(
        amount: 15000,
        type: TransactionType.expense,
        categoryId: 'rent',
        frequency: RecurringFrequency.monthly,
        startDate: startDate,
        generateFirstOccurrenceImmediately: false,
      );

      expect(result.firstTransaction, isNull);
      expect(result.rule.nextOccurrenceDate, startDate);

      final txns = await txnRepo.getAllTransactions();
      expect(txns, isEmpty);

      final rules = await repo.getAllRules();
      expect(rules.length, 1);
    });

    test('stopRule deactivates rule and stops subsequent generation', () async {
      final startDate = DateTime(2026, 8, 1, 10, 0);
      final result = await service.createRule(
        amount: 500,
        type: TransactionType.expense,
        categoryId: 'entertainment',
        frequency: RecurringFrequency.daily,
        startDate: startDate,
        generateFirstOccurrenceImmediately: true,
      );

      // Stop rule
      await service.stopRule(result.rule.id);

      final rule = await repo.getRuleById(result.rule.id);
      expect(rule!.isActive, isFalse);

      // Run generation at Aug 10
      final generated = await service.generateDueOccurrences(now: DateTime(2026, 8, 10));
      expect(generated, isEmpty);
    });

    test('deleteRuleAndAllOccurrences removes rule and all associated transactions', () async {
      final startDate = DateTime(2026, 8, 1, 10, 0);
      final result = await service.createRule(
        amount: 1000,
        type: TransactionType.expense,
        categoryId: 'groceries',
        frequency: RecurringFrequency.weekly,
        startDate: startDate,
        generateFirstOccurrenceImmediately: true,
      );

      // Generate additional occurrences up to Aug 15
      await service.generateDueOccurrences(now: DateTime(2026, 8, 15, 12, 0));

      var txns = await txnRepo.getAllTransactions();
      expect(txns.length, 3); // Aug 1, Aug 8, Aug 15

      // Delete rule and all occurrences
      await service.deleteRuleAndAllOccurrences(result.rule.id);

      txns = await txnRepo.getAllTransactions();
      expect(txns, isEmpty);

      final rules = await repo.getAllRules();
      expect(rules, isEmpty);

      final occurrences = await repo.getOccurrencesForRule(result.rule.id);
      expect(occurrences, isEmpty);
    });
  });
}
