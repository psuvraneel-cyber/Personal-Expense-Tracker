import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pet/data/database/database_helper.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/recurring_rule.dart';
import 'package:pet/data/repositories/recurring_transaction_repository.dart';
import 'package:pet/providers/recurring_transaction_provider.dart';
import 'package:pet/services/firestore_sync_service.dart';
import 'package:pet/services/recurring_transaction_service.dart';

class FakeRecurringFirestoreSyncService implements FirestoreSyncService {
  final StreamController<List<RecurringRule>> rulesStreamController =
      StreamController<List<RecurringRule>>.broadcast();
  final List<RecurringRule> remoteRules = [];

  @override
  bool get isAuthenticated => true;

  @override
  String get currentUserId => 'test_user_id';

  @override
  Stream<List<RecurringRule>> recurringRulesStream() => rulesStreamController.stream;

  @override
  Future<void> upsertRecurringRule(RecurringRule rule) async {
    remoteRules.removeWhere((r) => r.id == rule.id);
    remoteRules.add(rule);
    rulesStreamController.add(remoteRules);
  }

  @override
  Future<void> deleteRecurringRule(String ruleId) async {
    remoteRules.removeWhere((r) => r.id == ruleId);
    rulesStreamController.add(remoteRules);
  }

  @override
  Future<List<RecurringRule>> fetchAllRecurringRules() async => remoteRules;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late RecurringTransactionRepository repo;
  late RecurringTransactionService service;
  late FakeRecurringFirestoreSyncService fakeSync;
  late RecurringTransactionProvider provider;

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
    service = RecurringTransactionService(repository: repo);
    fakeSync = FakeRecurringFirestoreSyncService();
    provider = RecurringTransactionProvider(
      repository: repo,
      service: service,
      firestoreSync: fakeSync,
    );
  });

  tearDown(() async {
    provider.dispose();
    await db.close();
    DatabaseHelper.setTestDatabase(null);
  });

  group('RecurringTransactionProvider Tests', () {
    test('createRule adds rule to provider and generates initial occurrence', () async {
      await provider.loadRules();
      expect(provider.allRules, isEmpty);

      final startDate = DateTime(2026, 8, 20, 10, 0);
      final result = await provider.createRule(
        amount: 3000,
        type: TransactionType.expense,
        categoryId: 'rent',
        frequency: RecurringFrequency.monthly,
        startDate: startDate,
        note: 'Monthly Studio Rent',
        generateFirstOccurrenceImmediately: true,
      );

      expect(provider.allRules.length, 1);
      expect(provider.activeRules.length, 1);
      expect(result.firstTransaction, isNotNull);
      expect(result.firstTransaction!.amount, 3000);
      expect(result.rule.nextOccurrenceDate, DateTime(2026, 9, 20, 10, 0));
    });

    test('stopRule pauses active rule in provider', () async {
      final startDate = DateTime(2026, 8, 20, 10, 0);
      final result = await provider.createRule(
        amount: 500,
        type: TransactionType.expense,
        categoryId: 'subs',
        frequency: RecurringFrequency.monthly,
        startDate: startDate,
      );

      expect(provider.activeRules.length, 1);

      await provider.stopRule(result.rule.id);

      expect(provider.allRules.length, 1);
      expect(provider.activeRules.length, 0);
      expect(provider.allRules.first.isActive, isFalse);
    });

    test('skipOccurrence advances nextOccurrenceDate', () async {
      final startDate = DateTime(2026, 8, 20, 10, 0);
      final result = await provider.createRule(
        amount: 200,
        type: TransactionType.expense,
        categoryId: 'gym',
        frequency: RecurringFrequency.weekly,
        startDate: startDate,
        generateFirstOccurrenceImmediately: true,
      );

      // Next is Aug 27
      expect(result.rule.nextOccurrenceDate, DateTime(2026, 8, 27, 10, 0));

      await provider.skipOccurrence(
        ruleId: result.rule.id,
        scheduledDate: DateTime(2026, 8, 27, 10, 0),
      );

      final updated = provider.allRules.first;
      expect(updated.nextOccurrenceDate, DateTime(2026, 9, 3, 10, 0));
    });

    test('deleteRuleAndAllOccurrences removes rule from provider', () async {
      final startDate = DateTime(2026, 8, 20, 10, 0);
      final result = await provider.createRule(
        amount: 100,
        type: TransactionType.expense,
        categoryId: 'food',
        frequency: RecurringFrequency.daily,
        startDate: startDate,
      );

      expect(provider.allRules.length, 1);

      await provider.deleteRuleAndAllOccurrences(result.rule.id);

      expect(provider.allRules, isEmpty);
    });
  });
}
