import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:pet/data/database/database_helper.dart';
import 'package:pet/premium/models/saving_goal.dart';
import 'package:pet/premium/models/goal_history_item.dart';
import 'package:pet/premium/providers/goal_provider.dart';
import 'package:pet/premium/repositories/alert_repository.dart';
import 'package:pet/premium/repositories/saving_goal_repository.dart';
import 'package:pet/premium/services/alert_evaluation_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String dbPath;
  late Database db;
  late SavingGoalRepository repository;
  late GoalProvider provider;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync();
    dbPath = p.join(tempDir.path, 'goal_prov_test.db');

    db = await openDatabase(
      dbPath,
      version: 20,
      onCreate: (d, v) async {
        await DatabaseHelper().onCreateForTesting(d, v);
      },
    );

    AlertEvaluationCoordinator(repository: AlertRepository(database: db));
    repository = SavingGoalRepository(database: db);
    provider = GoalProvider(repository: repository);
  });

  tearDown(() async {
    try {
      await db.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('GoalProvider Top-Up Invariants (Phase A2)', () {
    test('exact target top-up succeeds and marks goal achieved', () async {
      await provider.addGoal(
        name: 'New Bike',
        targetAmount: 20000,
      );
      final goal = provider.goals.first;

      final result = await provider.topUpGoal(goal.id, 20000);
      expect(result.status, TopUpStatus.success);
      expect(result.isSuccess, isTrue);

      final updated = provider.goals.firstWhere((g) => g.id == goal.id);
      expect(updated.currentAmount, 20000.0);
      expect(updated.isAchieved, isTrue);

      // Verify audit history was recorded
      final history = await repository.getHistory(goal.id);
      expect(history.length, 2); // 1 created + 1 topUp
      final topUpEntry = history.firstWhere((h) => h.actionType == 'topUp');
      expect(topUpEntry.amount, 20000.0);
    });

    test(
        'overshoot top-up without allowOverfunding returns exceedsTarget status and does not inflate goal',
        () async {
      await provider.addGoal(
        name: 'Goa Trip',
        targetAmount: 10000,
      );
      final goal = provider.goals.first;
      await provider.topUpGoal(goal.id, 8000);

      // Remaining is 2000. Attempting to top up 5000:
      final result = await provider.topUpGoal(goal.id, 5000);

      expect(result.status, TopUpStatus.exceedsTarget);
      expect(result.isSuccess, isFalse);
      expect(result.allowedAmount, 2000.0);
      expect(result.overage, 3000.0);

      // Current amount must NOT have mutated
      final updated = provider.goals.firstWhere((g) => g.id == goal.id);
      expect(updated.currentAmount, 8000.0);
    });

    test(
        'overshoot top-up with intentional allowOverfunding succeeds but reserves remain capped at target',
        () async {
      await provider.addGoal(
        name: 'Goa Trip',
        targetAmount: 10000,
      );
      final goal = provider.goals.first;

      final result = await provider.topUpGoal(
        goal.id,
        15000,
        allowOverfunding: true,
      );

      expect(result.status, TopUpStatus.success);
      final updated = provider.goals.firstWhere((g) => g.id == goal.id);
      expect(updated.currentAmount, 15000.0);

      // Product invariant: Safe-to-spend / Goal reserve cannot be inflated past targetAmount
      expect(updated.activeReserveAmount, 10000.0);
      expect(provider.totalActiveGoalReserves, 10000.0);
    });

    test('top-up with zero or negative amount returns invalidAmount', () async {
      await provider.addGoal(name: 'Watch', targetAmount: 5000);
      final goal = provider.goals.first;

      expect((await provider.topUpGoal(goal.id, 0)).status,
          TopUpStatus.invalidAmount);
      expect((await provider.topUpGoal(goal.id, -100)).status,
          TopUpStatus.invalidAmount);
    });

    test('top-up on paused goal returns goalPaused', () async {
      await provider.addGoal(name: 'Watch', targetAmount: 5000);
      final goal = provider.goals.first;
      await provider.togglePause(goal.id);

      final result = await provider.topUpGoal(goal.id, 1000);
      expect(result.status, TopUpStatus.goalPaused);
    });
  });

  group('GoalProvider Reserve Calculations (Phase A3)', () {
    test(
        'totalActiveGoalReserves excludes paused goals and clamps overfunded goals',
        () async {
      // Goal 1: Active, 5,000 of 10,000
      await provider.addGoal(name: 'Goal 1', targetAmount: 10000);
      final g1 = provider.goals.first;
      await provider.topUpGoal(g1.id, 5000);

      // Goal 2: Paused, 8,000 of 10,000 -> contributes 0
      await provider.addGoal(name: 'Goal 2', targetAmount: 10000);
      final g2 = provider.goals.firstWhere((g) => g.name == 'Goal 2');
      await provider.topUpGoal(g2.id, 8000);
      await provider.togglePause(g2.id);

      // Goal 3: Overfunded, 15,000 of 10,000 -> capped at 10,000
      await provider.addGoal(name: 'Goal 3', targetAmount: 10000);
      final g3 = provider.goals.firstWhere((g) => g.name == 'Goal 3');
      await provider.topUpGoal(g3.id, 15000, allowOverfunding: true);

      // Total active reserve = 5,000 (Goal 1) + 0 (Goal 2 paused) + 10,000 (Goal 3 capped) = 15,000
      expect(provider.totalActiveGoalReserves, 15000.0);
    });
  });

  group('GoalProvider Offline Survival & LWW Reconciliation', () {
    test('offline local goals are preserved when absent from remote snapshot',
        () async {
      // Seed a local goal from 1 hour ago
      final offlineGoal = SavingGoal(
        id: 'offline-created-goal',
        name: 'Offline Goal',
        targetAmount: 5000,
        currentAmount: 2000,
        createdAt: DateTime.now().subtract(const Duration(hours: 1)),
      );
      await repository.upsert(offlineGoal);
      await provider.load();
      expect(provider.goals.length, 1);

      // When remote snapshot delivers empty list, local goal must NOT be deleted
      await provider.reconcileRemoteGoals([]);

      expect(provider.goals.length, 1);
      expect(provider.goals.first.id, 'offline-created-goal');
      expect(await repository.getById('offline-created-goal'), isNotNull);
    });

    test('LWW preserves newer local modifications over older remote snapshots',
        () async {
      final now = DateTime.now();
      final localGoal = SavingGoal(
        id: 'lww-goal',
        name: 'Local Newer Name',
        targetAmount: 10000,
        currentAmount: 5000,
        createdAt: now.subtract(const Duration(days: 5)),
        updatedAt: now,
      );
      await repository.upsert(localGoal);
      await provider.load();

      final olderRemoteGoal = SavingGoal(
        id: 'lww-goal',
        name: 'Old Remote Name',
        targetAmount: 10000,
        currentAmount: 1000,
        createdAt: now.subtract(const Duration(days: 5)),
        updatedAt: now.subtract(const Duration(hours: 2)),
      );

      await provider.reconcileRemoteGoals([olderRemoteGoal]);

      final reconciled = provider.goals.firstWhere((g) => g.id == 'lww-goal');
      expect(reconciled.name, 'Local Newer Name');
      expect(reconciled.currentAmount, 5000.0);
    });
  });

  group('GoalProvider Goal Editing & Nullable Clearing', () {
    test(
        'editGoal updates properties and explicitly clears nullable targetDate and emoji',
        () async {
      final initialDate = DateTime(2026, 12, 31);
      await provider.addGoal(
        name: 'Initial Goal',
        targetAmount: 50000,
        targetDate: initialDate,
        emoji: '🏖️',
      );
      final goal = provider.goals.first;
      expect(goal.targetDate, initialDate);
      expect(goal.emoji, '🏖️');

      // Edit name, target, and explicitly clear targetDate and emoji by passing null
      await provider.editGoal(
        id: goal.id,
        name: 'Updated Goal Name',
        targetAmount: 60000,
        targetDate: null,
        emoji: null,
      );

      final updated = provider.goals.firstWhere((g) => g.id == goal.id);
      expect(updated.name, 'Updated Goal Name');
      expect(updated.targetAmount, 60000.0);
      expect(updated.targetDate, isNull);
      expect(updated.emoji, isNull);

      // Verify audit history log was appended
      final history = await repository.getHistory(goal.id);
      final editEntry = history.firstWhere((h) => h.actionType == 'goalEdited');
      expect(editEntry, isNotNull);
      expect(editEntry.note, contains('Updated Goal Name'));
    });
  });

  group('GoalProvider Withdrawals & Audit Trail', () {
    test('withdrawFromGoal deducts amount and records audit trail', () async {
      await provider.addGoal(
        name: 'College Fund',
        targetAmount: 100000,
      );
      final goal = provider.goals.first;
      await provider.topUpGoal(goal.id, 40000);

      expect(provider.goals.first.currentAmount, 40000.0);

      // Withdraw ₹15,000
      await provider.withdrawFromGoal(
        goal.id,
        15000,
        note: 'Semester fees',
      );

      final updated = provider.goals.firstWhere((g) => g.id == goal.id);
      expect(updated.currentAmount, 25000.0);

      // Verify audit trail entry
      final history = await repository.getHistory(goal.id);
      final withdrawalEntry =
          history.firstWhere((h) => h.actionType == 'withdrawal');
      expect(withdrawalEntry.amount, -15000.0);
      expect(withdrawalEntry.previousAmount, 40000.0);
      expect(withdrawalEntry.resultingAmount, 25000.0);
      expect(withdrawalEntry.note, 'Semester fees');
    });

    test(
        'withdrawFromGoal with amount exceeding currentAmount throws ArgumentError',
        () async {
      await provider.addGoal(name: 'Short Term', targetAmount: 5000);
      final goal = provider.goals.first;
      await provider.topUpGoal(goal.id, 1000);

      expect(
        () async => await provider.withdrawFromGoal(goal.id, 2000),
        throwsA(isA<ArgumentError>()),
      );
      expect(provider.goals.first.currentAmount, 1000.0);
    });
  });

  group('Goal History Append-Only Invariant', () {
    test('duplicate history ID cannot overwrite existing record', () async {
      await provider.addGoal(name: 'Immutable Audit Goal', targetAmount: 10000);
      final goal = provider.goals.first;

      final historyItem1 = GoalHistoryItem(
        id: 'hist-audit-unique-1',
        goalId: goal.id,
        amount: 1000,
        previousAmount: 0,
        resultingAmount: 1000,
        actionType: 'topUp',
        createdAt: DateTime.now(),
        source: 'manual',
      );
      await repository.addHistory(historyItem1);

      // Attempting to overwrite existing history ID must fail (abort)
      final historyItemDuplicate = GoalHistoryItem(
        id: 'hist-audit-unique-1',
        goalId: goal.id,
        amount: 9999,
        previousAmount: 0,
        resultingAmount: 9999,
        actionType: 'topUp',
        createdAt: DateTime.now(),
        source: 'tampered',
      );

      expect(
        () async => await repository.addHistory(historyItemDuplicate),
        throwsA(isA<DatabaseException>()),
      );

      // Verify original item remains unchanged
      final history = await repository.getHistory(goal.id);
      final item = history.firstWhere((h) => h.id == 'hist-audit-unique-1');
      expect(item.amount, 1000.0);
      expect(item.source, 'manual');
    });
  });
}
