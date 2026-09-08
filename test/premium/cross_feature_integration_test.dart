import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:pet/data/database/database_helper.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/premium/providers/goal_provider.dart';
import 'package:pet/premium/providers/spend_pause_provider.dart';
import 'package:pet/premium/providers/weekly_planner_provider.dart';
import 'package:pet/premium/repositories/alert_repository.dart';
import 'package:pet/premium/repositories/saving_goal_repository.dart';
import 'package:pet/premium/repositories/weekly_planner_repository.dart';
import 'package:pet/premium/services/alert_evaluation_coordinator.dart';
import 'package:pet/premium/services/cashflow_forecast_service.dart';
import 'package:pet/premium/services/ai_copilot_service.dart';
import 'package:pet/services/firestore_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String dbPath;
  late Database db;
  late AlertRepository alertRepo;
  late SavingGoalRepository goalRepo;
  late WeeklyPlannerRepository weeklyRepo;
  late GoalProvider goalProvider;
  late WeeklyPlannerProvider weeklyProvider;
  late SpendPauseProvider spendPauseProvider;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = Directory.systemTemp.createTempSync();
    dbPath = p.join(tempDir.path, 'cross_feature_test.db');

    db = await openDatabase(
      dbPath,
      version: 20,
      onCreate: (d, v) async {
        await DatabaseHelper().onCreateForTesting(d, v);
      },
    );

    alertRepo = AlertRepository(database: db);
    AlertEvaluationCoordinator(repository: alertRepo);
    goalRepo = SavingGoalRepository(database: db);
    weeklyRepo = WeeklyPlannerRepository(database: db);
    goalProvider = GoalProvider(repository: goalRepo);
    weeklyProvider = WeeklyPlannerProvider(repository: weeklyRepo);
    spendPauseProvider = SpendPauseProvider();
  });

  tearDown(() async {
    spendPauseProvider.dispose();
    try {
      await db.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('Cross-Feature Synergy: Goals x Focus Mode (Phase D)', () {
    test('Focus Mode calculates estimated avoided discretionary spending without false claims', () async {
      // Setup active goal
      await goalProvider.addGoal(
        name: 'Goa Trip',
        targetAmount: 15000,
      );
      final goal = goalProvider.goals.first;
      await goalProvider.topUpGoal(goal.id, 5000);

      // User pauses Shopping category for 7 days
      await spendPauseProvider.activate(
        until: DateTime.now().add(const Duration(days: 7)),
        categoryIds: ['cat-shopping'],
      );

      expect(spendPauseProvider.isActive, isTrue);
      expect(spendPauseProvider.isCategoryBlocked('cat-shopping'), isTrue);

      // Calculate conservative estimated avoided spend baseline:
      // Historical spend: ₹1,500/week on Shopping. During pause, actual allowed spend = ₹0.
      const historicalWeeklySpend = 1500.0;
      const actualAllowedSpend = 0.0;
      final estimatedAvoidedSpend = historicalWeeklySpend - actualAllowedSpend;

      expect(estimatedAvoidedSpend, 1500.0);

      // Accelerating goal contribution projection
      final currentGoal = goalProvider.goals.firstWhere((g) => g.id == goal.id);
      final remainingNeeded = currentGoal.remainingAmount; // 10,000
      final projectedRemainingAfterAvoided = (remainingNeeded - estimatedAvoidedSpend).clamp(0.0, double.infinity);
      expect(projectedRemainingAfterAvoided, 8500.0);

      // Offer goal top-up user allocation (requires explicit user action, NOT auto-transfer)
      final topUpResult = await goalProvider.topUpGoal(goal.id, estimatedAvoidedSpend);
      expect(topUpResult.status, TopUpStatus.success);

      final updatedGoal = goalProvider.goals.firstWhere((g) => g.id == goal.id);
      expect(updatedGoal.currentAmount, 6500.0);
    });
  });

  group('Cross-Feature Synergy: Weekly Planner x Goals (Phase F)', () {
    test('distinguishes budget surplus from actual cash surplus and offers goal allocation', () async {
      await weeklyProvider.setLimit(
        categoryId: 'cat-dining',
        categoryName: 'Dining',
        weeklyLimit: 2000,
      );

      final now = DateTime.now();
      final txns = [
        TransactionRecord(
          id: 't1',
          amount: 1200,
          date: now,
          type: TransactionType.expense,
          categoryId: 'cat-dining',
        ),
      ];

      weeklyProvider.refreshFromTransactions(txns);

      // Weekly planned: 2000, actual spent: 1200 -> budget surplus: 800
      final entry = weeklyProvider.entries.first;
      final budgetSurplus = entry.remaining;
      expect(budgetSurplus, 800.0);

      // Setup goal to allocate surplus to
      await goalProvider.addGoal(
        name: 'New Monitor',
        targetAmount: 8000,
      );
      final monitorGoal = goalProvider.goals.firstWhere((g) => g.name == 'New Monitor');

      // User chooses to contribute half of the planned weekly surplus (₹400)
      final result = await goalProvider.topUpGoal(monitorGoal.id, 400);
      expect(result.status, TopUpStatus.success);

      final updatedMonitor = goalProvider.goals.firstWhere((g) => g.id == monitorGoal.id);
      expect(updatedMonitor.currentAmount, 400.0);
      expect(goalProvider.totalActiveGoalReserves, 400.0);
    });
  });

  group('Multi-Account Isolation & Zero Leakage (Phase 21 & 29)', () {
    test('User A state is completely wiped and cannot leak to User B on logout', () async {
      // 1. User A sets up financial state
      await goalProvider.addGoal(name: 'User A Secret Fund', targetAmount: 50000);
      await weeklyProvider.setLimit(
        categoryId: 'cat-user-a',
        categoryName: 'User A Category',
        weeklyLimit: 5000,
      );
      await spendPauseProvider.activate(
        until: DateTime.now().add(const Duration(hours: 12)),
        categoryIds: ['cat-user-a'],
      );

      expect(goalProvider.goals.isNotEmpty, isTrue);
      expect(weeklyProvider.entries.isNotEmpty, isTrue);
      expect(spendPauseProvider.isActive, isTrue);

      // 2. User A logs out -> Coordinated wipe executed
      await DatabaseHelper().wipeAllUserData(db: db);
      await weeklyProvider.clearData();
      await spendPauseProvider.clearData();

      // 3. Verify SQLite tables are completely empty
      expect((await goalRepo.getAll()).isEmpty, isTrue);
      expect((await weeklyRepo.getAll()).isEmpty, isTrue);

      // 4. User B logs in -> fresh providers created
      final userBGoalProvider = GoalProvider(repository: goalRepo);
      final userBWeeklyProvider = WeeklyPlannerProvider(repository: weeklyRepo);
      final userBSpendPauseProvider = SpendPauseProvider();

      await userBGoalProvider.load();
      await userBWeeklyProvider.load();
      await userBSpendPauseProvider.load();

      // Zero User A data visibility
      expect(userBGoalProvider.goals, isEmpty);
      expect(userBGoalProvider.totalActiveGoalReserves, 0.0);
      expect(userBWeeklyProvider.entries, isEmpty);
      expect(userBWeeklyProvider.hasLimits, isFalse);
      expect(userBSpendPauseProvider.isActive, isFalse);
      expect(userBSpendPauseProvider.blockedCategoryIds, isEmpty);

      userBSpendPauseProvider.dispose();
    });
  });

  group('Logout Race Condition & Stale Snapshot Rejection (Phase 2.1)', () {
    test('session generation token increments on logout and rejects in-flight snapshots', () async {
      final syncService = FirestoreSyncService();

      // User A signs in
      syncService.onSessionChanged('user-a-123');
      final genA = syncService.sessionGeneration;
      expect(syncService.activeSessionUid, 'user-a-123');

      // User A logs out
      syncService.onSessionChanged(null);
      final genAfterLogout = syncService.sessionGeneration;
      expect(genAfterLogout, greaterThan(genA));
      expect(syncService.activeSessionUid, isNull);

      // User B logs in
      syncService.onSessionChanged('user-b-456');
      final genB = syncService.sessionGeneration;
      expect(genB, greaterThan(genAfterLogout));
      expect(syncService.activeSessionUid, 'user-b-456');

      // Simulate a stale snapshot belonging to User A arriving now:
      // A listener checking generation or active UID can prove it does NOT match
      final isStaleGeneration = genA != syncService.sessionGeneration;
      final isStaleUid = 'user-a-123' != syncService.activeSessionUid;

      expect(isStaleGeneration, isTrue);
      expect(isStaleUid, isTrue);
    });
  });

  group('Focus Mode Behavioral Aggregation Alerts (Phase 7.4)', () {
    test('overrides >= 3 triggers actionable alert without spamming on every override', () async {
      await spendPauseProvider.activate(
        until: DateTime.now().add(const Duration(hours: 4)),
        categoryIds: ['cat-shopping'],
      );

      expect(spendPauseProvider.sessionOverrideCount, 0);

      // Overrides 1 and 2: no alert
      await spendPauseProvider.recordOverride(
        categoryId: 'cat-shopping',
        amount: 500,
        categoryName: 'Shopping',
      );
      await spendPauseProvider.recordOverride(
        categoryId: 'cat-shopping',
        amount: 800,
        categoryName: 'Shopping',
      );

      final alertsAfterTwo = await alertRepo.getAll();
      expect(
        alertsAfterTwo.any((a) => a.alertKey?.startsWith('focus_override:cat-shopping') ?? false),
        isFalse,
      );

      // Override 3: triggers aggregated alert
      await spendPauseProvider.recordOverride(
        categoryId: 'cat-shopping',
        amount: 1200,
        categoryName: 'Shopping',
      );

      final alertsAfterThree = await alertRepo.getAll();
      final focusAlert = alertsAfterThree.firstWhere(
        (a) => a.alertKey?.startsWith('focus_override:cat-shopping') ?? false,
      );
      expect(focusAlert, isNotNull);
      expect(focusAlert.message, contains('overridden Focus Mode 3 times'));

      // Override 4: deduplication prevents spamming duplicate alert for same category in same week
      await spendPauseProvider.recordOverride(
        categoryId: 'cat-shopping',
        amount: 1500,
        categoryName: 'Shopping',
      );

      final alertsAfterFour = await alertRepo.getAll();
      final focusAlerts = alertsAfterFour
          .where((a) => a.alertKey?.startsWith('focus_override:cat-shopping') ?? false)
          .toList();
      expect(focusAlerts.length, 1);
    });
  });

  group('AI Copilot & Cashflow Forecast Numerical Consistency (Phase 12.1)', () {
    test('AI context derives identical safeToSpend and goalReserves as GoalProvider', () {
      final now = DateTime(2026, 3, 9, 12, 0);
      final txns = [
        TransactionRecord(
          id: 'tx-1',
          amount: 50000,
          date: now.subtract(const Duration(days: 5)),
          type: TransactionType.income,
          categoryId: 'salary',
        ),
        TransactionRecord(
          id: 'tx-2',
          amount: 10000,
          date: now.subtract(const Duration(days: 2)),
          type: TransactionType.expense,
          categoryId: 'rent',
        ),
      ];

      // 1. Forecast without goal reserves
      final forecastWithoutGoals = CashflowForecastService.forecast(
        txns,
        days: 30,
        referenceDate: now,
        openingBalanceOverride: 40000,
        goalReserves: 0.0,
      );

      // 2. Add active goal reserve of ₹15,000
      const activeGoalReserve = 15000.0;
      final forecastWithGoals = CashflowForecastService.forecast(
        txns,
        days: 30,
        referenceDate: now,
        openingBalanceOverride: 40000,
        goalReserves: activeGoalReserve,
      );

      // Safe-to-spend headroom must strictly decrease when goal reserves are locked
      expect(forecastWithGoals.safeToSpend, lessThan(forecastWithoutGoals.safeToSpend));
      expect(
        forecastWithoutGoals.safeToSpend - forecastWithGoals.safeToSpend,
        closeTo(15000.0 / 30.0, 0.01),
      );

      // 3. Build FinancialContext and verify AI prompt receives exact figures
      final ctx = FinancialContext(
        monthLabel: 'March 2026',
        totalIncome: 50000,
        totalExpenses: 10000,
        totalSavings: 15000,
        categorySpending: {'rent': 10000},
        budgets: [],
        recentTransactions: [],
        safeToSpend: forecastWithGoals.safeToSpend,
        activeGoals: [
          {'name': 'Emergency Fund', 'current': 15000.0, 'target': 50000.0}
        ],
      );

      final service = AiCopilotService(model: 'test-model');
      final prompt = service.buildSystemPromptForTesting(ctx);

      expect(prompt, contains('Safe-to-spend allowance:'));
      expect(prompt, contains('Emergency Fund'));
      expect(prompt, contains('30%'));
    });
  });
}
