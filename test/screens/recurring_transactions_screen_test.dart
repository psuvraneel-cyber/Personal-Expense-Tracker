import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pet/data/models/category.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/data/models/recurring_rule.dart';
import 'package:pet/data/repositories/recurring_transaction_repository.dart';
import 'package:pet/providers/category_provider.dart';
import 'package:pet/providers/recurring_transaction_provider.dart';
import 'package:pet/providers/transaction_provider.dart';
import 'package:pet/screens/transactions/recurring_transactions_screen.dart';
import 'package:pet/services/firestore_sync_service.dart';
import 'package:pet/services/recurring_transaction_service.dart';

class FakeRecurringTransactionRepository extends RecurringTransactionRepository {
  final List<RecurringRule> rules = [];

  @override
  Future<List<RecurringRule>> getAllRules({String? userId}) async => List.from(rules);

  @override
  Future<void> insertRule(RecurringRule rule) async {
    rules.removeWhere((r) => r.id == rule.id);
    rules.add(rule);
  }

  @override
  Future<void> updateRule(RecurringRule rule) async {
    rules.removeWhere((r) => r.id == rule.id);
    rules.add(rule);
  }

  @override
  Future<void> deleteRule(String ruleId) async {
    rules.removeWhere((r) => r.id == ruleId);
  }
}

class FakeFirestoreSyncServiceForWidgetTest implements FirestoreSyncService {
  @override
  bool get isAuthenticated => false;

  @override
  String get currentUserId => 'test_user';

  @override
  Stream<List<RecurringRule>> recurringRulesStream() => const Stream.empty();

  @override
  Stream<List<Category>> categoriesStream() => const Stream.empty();

  @override
  Stream<List<TransactionRecord>> transactionsStream({int? limit = 1000}) => const Stream.empty();

  @override
  Stream<List<Map<String, dynamic>>> tombstonesStream() => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget createWidgetUnderTest({
    required RecurringTransactionProvider recurringProvider,
    required CategoryProvider catProvider,
    required TransactionProvider txnProvider,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: catProvider),
        ChangeNotifierProvider.value(value: txnProvider),
        ChangeNotifierProvider.value(value: recurringProvider),
      ],
      child: const MaterialApp(
        home: RecurringTransactionsScreen(),
      ),
    );
  }

  group('RecurringTransactionsScreen Widget Tests', () {
    testWidgets('Renders empty state when no rules exist', (tester) async {
      final fakeRepo = FakeRecurringTransactionRepository();
      final fakeSync = FakeFirestoreSyncServiceForWidgetTest();
      final recurringProvider = RecurringTransactionProvider(
        repository: fakeRepo,
        service: RecurringTransactionService(repository: fakeRepo),
        firestoreSync: fakeSync,
      );
      final catProvider = CategoryProvider(firestoreSync: fakeSync);
      final txnProvider = TransactionProvider(firestoreSync: fakeSync);

      await tester.pumpWidget(
        createWidgetUnderTest(
          recurringProvider: recurringProvider,
          catProvider: catProvider,
          txnProvider: txnProvider,
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Recurring Transactions'), findsOneWidget);
      expect(find.text('No Recurring Transactions'), findsOneWidget);
      expect(find.text('New Rule'), findsOneWidget);

      recurringProvider.dispose();
      catProvider.dispose();
      txnProvider.dispose();
    });

    testWidgets('Renders list of recurring rules correctly', (tester) async {
      final fakeRepo = FakeRecurringTransactionRepository();
      final rule = RecurringRule(
        id: 'rule_sub_netflix',
        amount: 649,
        type: TransactionType.expense,
        categoryId: 'entertainment',
        note: 'Netflix Subscription',
        frequency: RecurringFrequency.monthly,
        startDate: DateTime(2026, 8, 20, 10, 0),
        nextOccurrenceDate: DateTime(2026, 9, 20, 10, 0),
        createdAt: DateTime(2026, 8, 20),
        updatedAt: DateTime(2026, 8, 20),
      );
      await fakeRepo.insertRule(rule);

      final fakeSync = FakeFirestoreSyncServiceForWidgetTest();
      final recurringProvider = RecurringTransactionProvider(
        repository: fakeRepo,
        service: RecurringTransactionService(repository: fakeRepo),
        firestoreSync: fakeSync,
      );
      final catProvider = CategoryProvider(firestoreSync: fakeSync);
      final txnProvider = TransactionProvider(firestoreSync: fakeSync);

      await recurringProvider.loadRules();

      await tester.pumpWidget(
        createWidgetUnderTest(
          recurringProvider: recurringProvider,
          catProvider: catProvider,
          txnProvider: txnProvider,
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Netflix Subscription'), findsOneWidget);
      expect(find.text('-₹649'), findsOneWidget);
      expect(find.text('Monthly'), findsOneWidget);
      expect(find.text('Next: 20 Sep 2026'), findsOneWidget);

      recurringProvider.dispose();
      catProvider.dispose();
      txnProvider.dispose();
    });
  });
}
