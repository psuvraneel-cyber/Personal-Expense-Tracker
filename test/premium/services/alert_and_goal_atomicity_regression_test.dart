import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pet/data/database/database_helper.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/premium/models/app_alert.dart';
import 'package:pet/premium/models/goal_history_item.dart';
import 'package:pet/premium/models/saving_goal.dart';
import 'package:pet/premium/repositories/alert_repository.dart';
import 'package:pet/premium/repositories/saving_goal_repository.dart';
import 'package:pet/premium/services/alert_evaluation_coordinator.dart';
import 'package:pet/premium/services/alert_evaluator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late SavingGoalRepository goalRepo;
  late AlertRepository alertRepo;

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
    goalRepo = SavingGoalRepository(database: db);
    alertRepo = AlertRepository(database: db);
  });

  tearDown(() async {
    await db.close();
    DatabaseHelper.setTestDatabase(null);
  });

  group('SavingGoalRepository Atomicity (mutateGoalWithHistory)', () {
    test('atomically updates goal and inserts history', () async {
      final now = DateTime.now();
      final goal = SavingGoal(
        id: 'goal_atom_1',
        name: 'Atomic Goal',
        targetAmount: 10000,
        currentAmount: 2000,
        createdAt: now,
      );
      final history = GoalHistoryItem(
        id: 'hist_1',
        goalId: 'goal_atom_1',
        amount: 2000,
        actionType: 'topUp',
        createdAt: now,
        note: 'Initial deposit',
        previousAmount: 0,
        resultingAmount: 2000,
        source: 'manual',
      );

      await goalRepo.mutateGoalWithHistory(goal: goal, history: history);

      final retrievedGoal = await goalRepo.getById('goal_atom_1');
      expect(retrievedGoal, isNotNull);
      expect(retrievedGoal!.currentAmount, 2000.0);

      final retrievedHistory = await goalRepo.getHistory('goal_atom_1');
      expect(retrievedHistory.length, 1);
      expect(retrievedHistory.first.id, 'hist_1');
    });

    test('rolls back goal update if history insertion fails', () async {
      final now = DateTime.now();
      final goal = SavingGoal(
        id: 'goal_rollback',
        name: 'Rollback Goal',
        targetAmount: 10000,
        currentAmount: 1000,
        createdAt: now,
      );
      final initialHistory = GoalHistoryItem(
        id: 'hist_unique',
        goalId: 'goal_rollback',
        amount: 1000,
        actionType: 'topUp',
        createdAt: now,
        note: 'First deposit',
        previousAmount: 0,
        resultingAmount: 1000,
        source: 'manual',
      );

      await goalRepo.mutateGoalWithHistory(goal: goal, history: initialHistory);

      // Attempt to mutate goal to 5000, but reuse 'hist_unique' which should abort on conflict
      final updatedGoal = goal.copyWith(currentAmount: 5000);
      final duplicateHistory = GoalHistoryItem(
        id: 'hist_unique', // duplicate ID!
        goalId: 'goal_rollback',
        amount: 4000,
        actionType: 'topUp',
        createdAt: now,
        note: 'Failed deposit',
        previousAmount: 1000,
        resultingAmount: 5000,
        source: 'manual',
      );

      try {
        await goalRepo.mutateGoalWithHistory(goal: updatedGoal, history: duplicateHistory);
        fail('Should have thrown DatabaseException due to abort conflict');
      } catch (e) {
        expect(e, isA<DatabaseException>());
      }

      // Verify the goal was rolled back and is STILL 1000, not 5000
      final storedGoal = await goalRepo.getById('goal_rollback');
      expect(storedGoal!.currentAmount, 1000.0);
    });
  });

  group('AlertEvaluator & Coordinator Goal Reserves Parity', () {
    test('evaluateCashflowRisk triggers alert when goal reserves lower available balance', () {
      final now = DateTime.now();
      // Ledger starting balance = 8,000. Safety buffer = 5,000.
      // Without goal reserves: 8,000 > 5,000 safety buffer -> NO alert.
      // With 4,000 goal reserves: available dips to 4,000 < 5,000 -> triggers Safety Buffer Warning!
      final txns = [
        TransactionRecord(
          id: 'tx_income_1',
          amount: 8000.0,
          type: TransactionType.income,
          categoryId: 'salary',
          date: now.subtract(const Duration(days: 14)),
        ),
        TransactionRecord(
          id: 'tx_income_2',
          amount: 0.0,
          type: TransactionType.income,
          categoryId: 'salary',
          date: now.subtract(const Duration(days: 1)),
        ),
      ];

      final alertWithoutGoals = AlertEvaluator.evaluateCashflowRisk(
        transactions: txns,
        now: now,
        goalReserves: 0.0,
        safetyBuffer: 5000.0,
      );
      expect(alertWithoutGoals, isNull);

      final alertWithGoals = AlertEvaluator.evaluateCashflowRisk(
        transactions: txns,
        now: now,
        goalReserves: 4000.0,
        safetyBuffer: 5000.0,
      );
      expect(alertWithGoals, isNotNull);
      expect(alertWithGoals!.stage, AppAlertStage.warning);
    });

    test('AlertEvaluationCoordinator cleans up milestone alerts on withdrawal regression', () async {
      final coordinator = AlertEvaluationCoordinator(
        repository: alertRepo,
        savingGoalRepository: goalRepo,
      );

      final now = DateTime.now();
      final achievedGoal = SavingGoal(
        id: 'goal_milestone_regress',
        name: 'Europe Trip',
        targetAmount: 10000,
        currentAmount: 10000, // 100% achieved
        createdAt: now,
      );

      // Trigger achievement
      await coordinator.onGoalsChanged([achievedGoal], now: now);

      final activeAlerts = await alertRepo.getPage();
      expect(activeAlerts.any((a) => a.alertKey == 'goal_achieved:goal_milestone_regress'), isTrue);

      // Now regress goal due to withdrawal (drop from 10,000 to 6,000 = 60%)
      final regressedGoal = achievedGoal.copyWith(currentAmount: 6000);
      await coordinator.onGoalsChanged([regressedGoal], now: now);

      final updatedAlerts = await alertRepo.getPage();
      // The 100% achievement alert must have been cleaned up/dismissed!
      expect(updatedAlerts.any((a) => a.alertKey == 'goal_achieved:goal_milestone_regress'), isFalse);
    });
  });
}
