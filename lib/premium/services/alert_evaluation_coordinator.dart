import 'dart:async';
import 'package:pet/core/utils/app_logger.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/data/repositories/budget_repository.dart';
import 'package:pet/data/repositories/transaction_repository.dart';
import 'package:pet/premium/models/app_alert.dart';
import 'package:pet/premium/models/notification_category.dart';
import 'package:pet/premium/models/recurring_payment.dart';
import 'package:pet/premium/models/saving_goal.dart';
import 'package:pet/premium/providers/alert_provider.dart';
import 'package:pet/premium/repositories/alert_repository.dart';
import 'package:pet/premium/repositories/recurring_payment_repository.dart';
import 'package:pet/premium/repositories/saving_goal_repository.dart';
import 'package:pet/premium/models/cashflow_forecast.dart';
import 'package:pet/premium/services/cashflow_forecast_service.dart';
import 'package:pet/core/utils/calendar_utils.dart';
import 'package:pet/premium/providers/weekly_planner_provider.dart';
import 'package:pet/premium/services/alert_evaluator.dart';
import 'package:pet/premium/services/notification_service.dart';

/// Central orchestration coordinator for evaluating, deduplicating, persisting,
/// and notifying financial alerts across P.E.T.
///
/// Decoupled from widget build cycles and ProxyProvider.update reconciliations.
/// Safe to invoke from both foreground providers and background services.
class AlertEvaluationCoordinator {
  static AlertEvaluationCoordinator _instance =
      AlertEvaluationCoordinator._internal();

  factory AlertEvaluationCoordinator({
    AlertRepository? repository,
    BudgetRepository? budgetRepository,
    RecurringPaymentRepository? recurringRepository,
    TransactionRepository? transactionRepository,
    SavingGoalRepository? savingGoalRepository,
  }) {
    if (repository != null ||
        budgetRepository != null ||
        recurringRepository != null ||
        transactionRepository != null ||
        savingGoalRepository != null) {
      _instance = AlertEvaluationCoordinator._internal(
        repository: repository,
        budgetRepository: budgetRepository,
        recurringRepository: recurringRepository,
        transactionRepository: transactionRepository,
        savingGoalRepository: savingGoalRepository,
      );
    }
    return _instance;
  }

  final AlertRepository _repository;
  final BudgetRepository _budgetRepository;
  final RecurringPaymentRepository _recurringRepository;
  final TransactionRepository _transactionRepository;
  final SavingGoalRepository _savingGoalRepository;
  AlertProvider? _alertProvider;
  Future<void> _dispatchQueue = Future.value();

  AlertEvaluationCoordinator._internal({
    AlertRepository? repository,
    BudgetRepository? budgetRepository,
    RecurringPaymentRepository? recurringRepository,
    TransactionRepository? transactionRepository,
    SavingGoalRepository? savingGoalRepository,
  })  : _repository = repository ?? AlertRepository(),
        _budgetRepository = budgetRepository ??
            (repository?.database != null
                ? BudgetRepository(database: repository!.database)
                : BudgetRepository()),
        _recurringRepository = recurringRepository ??
            (repository?.database != null
                ? RecurringPaymentRepository() // db helper shares database
                : RecurringPaymentRepository()),
        _transactionRepository =
            transactionRepository ?? TransactionRepository(),
        _savingGoalRepository = savingGoalRepository ??
            (repository?.database != null
                ? SavingGoalRepository(database: repository!.database)
                : SavingGoalRepository());

  /// Attach the UI AlertProvider so live in-memory state is updated after evaluation.
  void attachProvider(AlertProvider provider) {
    _alertProvider = provider;
  }

  void detachProvider() {
    _alertProvider = null;
  }

  /// Evaluates transactions for anomalies, large transactions, duplicates, and budgets.
  Future<void> onTransactionsChanged(
    List<TransactionRecord> transactions, {
    Map<String, double>? budgets,
    Map<String, double>? spent,
    DateTime? now,
  }) async {
    try {
      if (transactions.isEmpty) return;
      final referenceTime = now ?? DateTime.now();

      // Resolve category budgets: use passed map or query from BudgetRepository
      Map<String, double>? resolvedBudgets = budgets;
      Map<String, double>? resolvedSpent = spent;

      if (resolvedBudgets == null) {
        try {
          final dbBudgets = await _budgetRepository.getBudgetsByMonth(
            referenceTime.month,
            referenceTime.year,
          );
          if (dbBudgets.isNotEmpty) {
            resolvedBudgets = {
              for (final b in dbBudgets) b.categoryId: b.amount,
            };
          }
        } catch (_) {}
      }

      List<AppAlert> anomalyAlerts = [];
      try {
        final baseline = AlertEvaluator.computeBaseline(
          transactions,
          now: referenceTime,
        );
        anomalyAlerts = AlertEvaluator.evaluateAnomalies(
          transactions: transactions,
          baseline: baseline,
          now: referenceTime,
        );
      } catch (e, st) {
        AppLogger.error('Anomaly evaluation error in AlertCoordinator',
            error: e, stack: st, label: 'AlertCoordinator');
      }

      List<AppAlert> largeTxnAlerts = [];
      try {
        largeTxnAlerts = AlertEvaluator.evaluateLargeTransactions(
          transactions: transactions,
          categoryBudgets: resolvedBudgets,
          now: referenceTime,
        );
      } catch (e, st) {
        AppLogger.error(
            'Large transaction evaluation error in AlertCoordinator',
            error: e,
            stack: st,
            label: 'AlertCoordinator');
      }

      List<AppAlert> duplicateAlerts = [];
      try {
        duplicateAlerts = AlertEvaluator.evaluateDuplicateTransactions(
          transactions: transactions,
          now: referenceTime,
        );
      } catch (e, st) {
        AppLogger.error(
            'Duplicate transaction evaluation error in AlertCoordinator',
            error: e,
            stack: st,
            label: 'AlertCoordinator');
      }

      List<RecurringPayment>? confirmedBills;
      try {
        confirmedBills = await _recurringRepository.getConfirmed();
      } catch (_) {}

      double goalReserves = 0.0;
      try {
        final activeGoals = await _savingGoalRepository.getActiveGoals();
        goalReserves = activeGoals.fold<double>(
          0.0,
          (sum, g) => sum + g.currentAmount.clamp(0.0, g.targetAmount),
        );
      } catch (_) {}

      AppAlert? cashflowAlert;
      try {
        cashflowAlert = AlertEvaluator.evaluateCashflowRisk(
          transactions: transactions,
          confirmedBills: confirmedBills,
          now: referenceTime,
          goalReserves: goalReserves,
        );
      } catch (e, st) {
        AppLogger.error('Cashflow evaluation error in AlertCoordinator',
            error: e, stack: st, label: 'AlertCoordinator');
      }

      final alerts = [
        ...anomalyAlerts,
        ...largeTxnAlerts,
        ...duplicateAlerts,
        if (cashflowAlert != null) cashflowAlert,
      ];

      if (resolvedBudgets != null && resolvedBudgets.isNotEmpty) {
        if (resolvedSpent == null) {
          final monthSpent = <String, double>{};
          for (final t in transactions) {
            if (t.type == TransactionType.expense &&
                t.date.year == referenceTime.year &&
                t.date.month == referenceTime.month) {
              monthSpent[t.categoryId] =
                  (monthSpent[t.categoryId] ?? 0.0) + t.amount;
            }
          }
          resolvedSpent = monthSpent;
        }

        final budgetAlerts = AlertEvaluator.evaluateBudgetAlerts(
          budgets: resolvedBudgets,
          spent: resolvedSpent,
          now: referenceTime,
        );
        final pacingAlerts = AlertEvaluator.evaluateBudgetPacing(
          budgets: resolvedBudgets,
          spent: resolvedSpent,
          now: referenceTime,
        );
        alerts.addAll(budgetAlerts);
        alerts.addAll(pacingAlerts);

        final period =
            '${referenceTime.year}-${referenceTime.month.toString().padLeft(2, '0')}';
        await _reconcileBudgetAlerts(
          budgets: resolvedBudgets,
          spent: resolvedSpent,
          period: period,
        );
      }

      // Reconcile cashflow alerts (CF-10)
      await _reconcileCashflowAlerts(
        transactions: transactions,
        confirmedBills: confirmedBills,
        now: referenceTime,
        goalReserves: goalReserves,
      );

      // If transactions were deleted, resolve alerts tied to deleted transactions
      final activeTxnIds = transactions.map((t) => t.id).toSet();
      try {
        final activeAlerts = await _repository.getPage(limit: 500);
        for (final a in activeAlerts) {
          if (a.type == AppAlertType.largeTransaction &&
              a.transactionId != null &&
              !activeTxnIds.contains(a.transactionId)) {
            await _repository.dismissWhere('id = ?', [a.id]);
            _alertProvider?.removeAlertsWhere((al) => al.id == a.id);
          } else if (a.type == AppAlertType.duplicateTransaction &&
              a.alertKey != null &&
              a.alertKey!.startsWith('dup_txn:')) {
            final keyContent = a.alertKey!.substring('dup_txn:'.length);
            String? otherId;
            if (a.transactionId != null) {
              if (keyContent.startsWith('${a.transactionId}_')) {
                otherId = keyContent.substring(a.transactionId!.length + 1);
              } else if (keyContent.endsWith('_${a.transactionId}')) {
                otherId = keyContent.substring(
                    0, keyContent.length - a.transactionId!.length - 1);
              }
            }
            final t1Missing = a.transactionId == null ||
                !activeTxnIds.contains(a.transactionId);
            final t2Missing =
                otherId != null && !activeTxnIds.contains(otherId);
            if (t1Missing || t2Missing) {
              await _repository.dismissWhere('id = ?', [a.id]);
              _alertProvider?.removeAlertsWhere((al) => al.id == a.id);
            }
          }
        }
      } catch (_) {}

      await processAndDispatch(alerts);
    } catch (e, stack) {
      AppLogger.error(
        'Failed to evaluate transactions in AlertCoordinator',
        error: e,
        stack: stack,
        label: 'AlertCoordinator',
      );
    }
  }

  /// Evaluates budgets for warnings, exceeded limits, and pacing.
  Future<void> onBudgetsChanged({
    required Map<String, double> budgets,
    required Map<String, double> spent,
    DateTime? now,
  }) async {
    try {
      if (budgets.isEmpty) return;
      final referenceTime = now ?? DateTime.now();

      final budgetAlerts = AlertEvaluator.evaluateBudgetAlerts(
        budgets: budgets,
        spent: spent,
        now: referenceTime,
      );

      final pacingAlerts = AlertEvaluator.evaluateBudgetPacing(
        budgets: budgets,
        spent: spent,
        now: referenceTime,
      );

      final period =
          '${referenceTime.year}-${referenceTime.month.toString().padLeft(2, '0')}';
      await _reconcileBudgetAlerts(
        budgets: budgets,
        spent: spent,
        period: period,
      );

      await processAndDispatch([...budgetAlerts, ...pacingAlerts]);
    } catch (e, stack) {
      AppLogger.error(
        'Failed to evaluate budgets in AlertCoordinator',
        error: e,
        stack: stack,
        label: 'AlertCoordinator',
      );
    }
  }

  /// Reconciles active budget and pacing alerts against current spending ratios.
  /// Dismisses obsolete stages to prevent duplicate or contradictory alerts.
  Future<void> _reconcileBudgetAlerts({
    required Map<String, double> budgets,
    required Map<String, double> spent,
    required String period,
  }) async {
    for (final entry in budgets.entries) {
      final categoryId = entry.key;
      final budgetAmt = entry.value;
      final spentAmt = spent[categoryId] ?? 0.0;

      if (budgetAmt <= 0 || (spentAmt / budgetAmt) < 0.90) {
        // Below 90% or zero budget: auto-resolve all active budget alerts for this category
        await _repository.dismissWhere(
          'alertKey LIKE ? OR alertKey = ?',
          ['budget:$categoryId:$period:%', 'budget_pacing:$categoryId:$period'],
        );
        _alertProvider?.removeAlertsWhere((a) =>
            a.type == AppAlertType.budget &&
            a.categoryId == categoryId &&
            a.period == period);
      } else {
        final progress = spentAmt / budgetAmt;
        if (progress >= 1.25) {
          // Critical stage: dismiss earlier warning and exceeded stages
          await _repository.dismissWhere(
            'alertKey IN (?, ?)',
            [
              'budget:$categoryId:$period:warning',
              'budget:$categoryId:$period:exceeded',
            ],
          );
          _alertProvider?.removeAlertsWhere((a) =>
              a.type == AppAlertType.budget &&
              a.categoryId == categoryId &&
              a.period == period &&
              (a.stage == AppAlertStage.warning ||
                  a.stage == AppAlertStage.exceeded));
        } else if (progress >= 1.0) {
          // Exceeded stage: dismiss warning and any previous critical
          await _repository.dismissWhere(
            'alertKey IN (?, ?)',
            [
              'budget:$categoryId:$period:warning',
              'budget:$categoryId:$period:critical',
            ],
          );
          _alertProvider?.removeAlertsWhere((a) =>
              a.type == AppAlertType.budget &&
              a.categoryId == categoryId &&
              a.period == period &&
              (a.stage == AppAlertStage.warning ||
                  a.stage == AppAlertStage.critical));
        } else {
          // Warning stage: dismiss any previous exceeded or critical stages
          await _repository.dismissWhere(
            'alertKey IN (?, ?)',
            [
              'budget:$categoryId:$period:exceeded',
              'budget:$categoryId:$period:critical',
            ],
          );
          _alertProvider?.removeAlertsWhere((a) =>
              a.type == AppAlertType.budget &&
              a.categoryId == categoryId &&
              a.period == period &&
              (a.stage == AppAlertStage.exceeded ||
                  a.stage == AppAlertStage.critical));
        }
      }
    }
  }

  /// Evaluates upcoming recurring bills and re-evaluates cashflow risk (CF-08).
  Future<void> onRecurringChanged(
    List<RecurringPayment> recurring, {
    DateTime? now,
  }) async {
    try {
      if (recurring.isEmpty) return;
      final referenceTime = now ?? DateTime.now();

      final billAlerts = AlertEvaluator.evaluateBills(
        recurring: recurring,
        now: referenceTime,
      );

      // Re-evaluate cashflow risk when recurring commitments change (CF-08)
      AppAlert? cashflowAlert;
      List<TransactionRecord> transactions = [];
      try {
        transactions = await _transactionRepository.getAllTransactions();
      } catch (_) {}

      final confirmed = recurring
          .where((r) => r.status == RecurringStatus.confirmed)
          .toList();

      if (transactions.isNotEmpty) {
        double goalReserves = 0.0;
        try {
          final activeGoals = await _savingGoalRepository.getActiveGoals();
          goalReserves = activeGoals.fold<double>(
            0.0,
            (sum, g) => sum + g.currentAmount.clamp(0.0, g.targetAmount),
          );
        } catch (_) {}

        try {
          cashflowAlert = AlertEvaluator.evaluateCashflowRisk(
            transactions: transactions,
            confirmedBills: confirmed,
            now: referenceTime,
            goalReserves: goalReserves,
          );
        } catch (e, st) {
          AppLogger.error(
            'Cashflow evaluation error in onRecurringChanged',
            error: e,
            stack: st,
            label: 'AlertCoordinator',
          );
        }

        // Reconcile cashflow alerts (CF-10)
        await _reconcileCashflowAlerts(
          transactions: transactions,
          confirmedBills: confirmed,
          now: referenceTime,
          goalReserves: goalReserves,
        );
      }

      await processAndDispatch([
        ...billAlerts,
        if (cashflowAlert != null) cashflowAlert,
      ]);
    } catch (e, stack) {
      AppLogger.error(
        'Failed to evaluate recurring bills in AlertCoordinator',
        error: e,
        stack: stack,
        label: 'AlertCoordinator',
      );
    }
  }

  /// Reconciles active cashflow alerts against current forecast (CF-10).
  /// Dismisses cashflow deficit/warning alerts when the cashflow condition has resolved,
  /// or cleans up lower stages when risk escalates.
  Future<void> _reconcileCashflowAlerts({
    required List<TransactionRecord> transactions,
    List<RecurringPayment>? confirmedBills,
    required DateTime now,
    double goalReserves = 0.0,
  }) async {
    try {
      final period = '${now.year}-${now.month.toString().padLeft(2, '0')}';
      final forecast = CashflowForecastService.forecast(
        transactions,
        confirmedBills: confirmedBills,
        days: 30,
        referenceDate: now,
        goalReserves: goalReserves,
      );

      final alertWindowPoints = forecast.dailyPoints.take(14).toList();
      final lowestPoint = alertWindowPoints.fold<CashflowPoint?>(
        null,
        (min, pt) => (min == null || pt.balance < min.balance) ? pt : min,
      );

      final lowestBal = lowestPoint?.balance ?? 0.0;
      final hasImminentDeficit = lowestBal < 0;
      final hasEndingDeficit = forecast.projectedEndingBalance <= 0;
      final hasBufferBreach =
          lowestBal < CashflowForecastService.defaultSafetyBuffer;

      if (!hasImminentDeficit && !hasEndingDeficit && !hasBufferBreach) {
        // Cashflow is completely healthy - auto-resolve/dismiss active cashflow alerts for this period
        await _repository.dismissWhere(
          'alertKey LIKE ?',
          ['cashflow:$period%'],
        );
        _alertProvider?.removeAlertsWhere(
          (a) => a.type == AppAlertType.cashflow && a.period == period,
        );
      } else if (hasImminentDeficit || hasEndingDeficit) {
        // Critical deficit: dismiss lower-severity buffer warning if present
        await _repository.dismissWhere(
          'alertKey = ?',
          ['cashflow:$period:warning'],
        );
        _alertProvider?.removeAlertsWhere(
          (a) =>
              a.type == AppAlertType.cashflow &&
              a.period == period &&
              a.stage == AppAlertStage.warning,
        );

        // If an existing critical alert has materially worsened (deficit deepened by >= ₹2,000),
        // dismiss the older critical alert so the escalated alert can be inserted (Defect 2 Fix)
        try {
          final existing = await _repository.getPage(
            period: period,
            type: AppAlertType.cashflow,
          );
          final currentDeficit =
              hasImminentDeficit ? lowestBal : forecast.projectedEndingBalance;
          for (final a in existing) {
            if (a.stage == AppAlertStage.critical && a.amount != null) {
              final oldBal = a.amount!;
              if (currentDeficit < oldBal - 2000) {
                await _repository.dismissWhere('id = ?', [a.id]);
                _alertProvider?.removeAlertsWhere((al) => al.id == a.id);
              }
            }
          }
        } catch (_) {}
      }
    } catch (e, st) {
      AppLogger.error(
        'Failed to reconcile cashflow alerts in AlertCoordinator',
        error: e,
        stack: st,
        label: 'AlertCoordinator',
      );
    }
  }

  /// Evaluates savings goal milestones.
  Future<void> onGoalsChanged(
    List<SavingGoal> goals, {
    DateTime? now,
  }) async {
    try {
      if (goals.isEmpty) return;
      final referenceTime = now ?? DateTime.now();

      // Regression cleanup: if a goal regressed below a milestone (e.g. from withdrawals),
      // dismiss the stale milestone alert so it does not persist incorrectly.
      for (final goal in goals) {
        final progress = goal.targetAmount > 0
            ? (goal.currentAmount / goal.targetAmount)
            : 0.0;
        if (progress < 1.0) {
          await _repository.dismissWhere(
            'alertKey = ?',
            ['goal_achieved:${goal.id}'],
          );
          _alertProvider?.removeAlertsWhere(
            (a) => a.alertKey == 'goal_achieved:${goal.id}',
          );
        }
        if (progress < 0.75) {
          await _repository.dismissWhere(
            'alertKey = ?',
            ['goal_milestone:${goal.id}:75'],
          );
          _alertProvider?.removeAlertsWhere(
            (a) => a.alertKey == 'goal_milestone:${goal.id}:75',
          );
        }
        if (progress < 0.50) {
          await _repository.dismissWhere(
            'alertKey = ?',
            ['goal_milestone:${goal.id}:50'],
          );
          _alertProvider?.removeAlertsWhere(
            (a) => a.alertKey == 'goal_milestone:${goal.id}:50',
          );
        }
        if (progress < 0.25) {
          await _repository.dismissWhere(
            'alertKey = ?',
            ['goal_milestone:${goal.id}:25'],
          );
          _alertProvider?.removeAlertsWhere(
            (a) => a.alertKey == 'goal_milestone:${goal.id}:25',
          );
        }
      }

      final goalAlerts = AlertEvaluator.evaluateGoals(
        goals: goals,
        now: referenceTime,
      );

      await processAndDispatch(goalAlerts);
    } catch (e, stack) {
      AppLogger.error(
        'Failed to evaluate goals in AlertCoordinator',
        error: e,
        stack: stack,
        label: 'AlertCoordinator',
      );
    }
  }

  /// Evaluates weekly planner limits and reconciles obsolete/expired alerts.
  Future<void> onWeeklyPlannerChanged(
    List<WeeklyPlannerEntry> entries, {
    DateTime? now,
  }) async {
    try {
      if (entries.isEmpty) return;
      final referenceTime = now ?? DateTime.now();

      final weeklyAlerts = AlertEvaluator.evaluateWeeklyLimits(
        entries: entries,
        now: referenceTime,
      );

      final weekKey = CalendarUtils.weekPeriodKey(referenceTime);
      await _reconcileWeeklyPlannerAlerts(
        entries: entries,
        weekKey: weekKey,
      );

      await processAndDispatch(weeklyAlerts);
    } catch (e, stack) {
      AppLogger.error(
        'Failed to evaluate weekly limits in AlertCoordinator',
        error: e,
        stack: stack,
        label: 'AlertCoordinator',
      );
    }
  }

  /// Reconciles active weekly planner alerts against current spending ratios.
  Future<void> _reconcileWeeklyPlannerAlerts({
    required List<WeeklyPlannerEntry> entries,
    required String weekKey,
  }) async {
    try {
      // 1. Dismiss alerts for past weeks (lifecycle ended)
      await _repository.dismissWhere(
        'alertKey LIKE ? AND period != ?',
        ['weekly_limit:%', weekKey],
      );
      _alertProvider?.removeAlertsWhere(
        (a) =>
            a.alertKey != null &&
            a.alertKey!.startsWith('weekly_limit:') &&
            a.period != weekKey,
      );

      // 2. Reconcile current week per category
      for (final entry in entries) {
        final categoryId = entry.categoryId;
        final limit = entry.weeklyLimit;
        final spent = entry.weeklySpent;

        if (limit <= 0 || (spent / limit) < 0.80) {
          // Below 80% or zero limit: auto-resolve all active weekly alerts for this category
          await _repository.dismissWhere(
            'alertKey LIKE ?',
            ['weekly_limit:$categoryId:$weekKey:%'],
          );
          _alertProvider?.removeAlertsWhere(
            (a) =>
                a.alertKey != null &&
                a.alertKey!.startsWith('weekly_limit:$categoryId:$weekKey:'),
          );
        } else {
          final progress = spent / limit;
          if (progress >= 1.0) {
            // 100% exceeded: dismiss 80% and 90% warnings
            await _repository.dismissWhere(
              'alertKey IN (?, ?)',
              [
                'weekly_limit:$categoryId:$weekKey:80',
                'weekly_limit:$categoryId:$weekKey:90',
              ],
            );
            _alertProvider?.removeAlertsWhere(
              (a) =>
                  a.alertKey == 'weekly_limit:$categoryId:$weekKey:80' ||
                  a.alertKey == 'weekly_limit:$categoryId:$weekKey:90',
            );
          } else if (progress >= 0.90) {
            // 90%: dismiss 80% and 100%
            await _repository.dismissWhere(
              'alertKey IN (?, ?)',
              [
                'weekly_limit:$categoryId:$weekKey:80',
                'weekly_limit:$categoryId:$weekKey:100',
              ],
            );
            _alertProvider?.removeAlertsWhere(
              (a) =>
                  a.alertKey == 'weekly_limit:$categoryId:$weekKey:80' ||
                  a.alertKey == 'weekly_limit:$categoryId:$weekKey:100',
            );
          } else {
            // 80%: dismiss 90% and 100%
            await _repository.dismissWhere(
              'alertKey IN (?, ?)',
              [
                'weekly_limit:$categoryId:$weekKey:90',
                'weekly_limit:$categoryId:$weekKey:100',
              ],
            );
            _alertProvider?.removeAlertsWhere(
              (a) =>
                  a.alertKey == 'weekly_limit:$categoryId:$weekKey:90' ||
                  a.alertKey == 'weekly_limit:$categoryId:$weekKey:100',
            );
          }
        }
      }
    } catch (e, st) {
      AppLogger.error(
        'Failed to reconcile weekly planner alerts in AlertCoordinator',
        error: e,
        stack: st,
        label: 'AlertCoordinator',
      );
    }
  }

  /// Resolves alerts for a deleted weekly limit.
  Future<void> onWeeklyLimitDeleted(String categoryId,
      {String? weekKey}) async {
    try {
      if (weekKey != null) {
        await _repository.dismissWhere(
          'alertKey LIKE ?',
          ['weekly_limit:$categoryId:$weekKey:%'],
        );
        _alertProvider?.removeAlertsWhere(
          (a) =>
              a.alertKey != null &&
              a.alertKey!.startsWith('weekly_limit:$categoryId:$weekKey:'),
        );
      } else {
        await _repository.dismissWhere(
          'alertKey LIKE ?',
          ['weekly_limit:$categoryId:%'],
        );
        _alertProvider?.removeAlertsWhere(
          (a) =>
              a.alertKey != null &&
              a.alertKey!.startsWith('weekly_limit:$categoryId:'),
        );
      }
    } catch (_) {}
  }

  /// Resolves alerts for a paid or deleted recurring bill.
  Future<void> onBillResolved(String recurringPaymentId) async {
    try {
      await _repository.dismissWhere(
        'recurringPaymentId = ? OR alertKey LIKE ?',
        [recurringPaymentId, 'bill:$recurringPaymentId:%'],
      );
      _alertProvider?.removeAlertsWhere((a) =>
          a.recurringPaymentId == recurringPaymentId ||
          (a.alertKey?.startsWith('bill:$recurringPaymentId:') ?? false));
    } catch (_) {}
  }

  /// Resolves alerts for a deleted savings goal.
  Future<void> onGoalDeleted(String goalId) async {
    try {
      await _repository.dismissWhere(
        'goalId = ? OR alertKey LIKE ?',
        [goalId, 'goal%:$goalId%'],
      );
      _alertProvider?.removeAlertsWhere(
          (a) => a.goalId == goalId || (a.alertKey?.contains(goalId) ?? false));
    } catch (_) {}
  }

  /// Evaluates aggregate Focus Mode override events (e.g., >= 3 overrides).
  /// Prevents alert spam on individual "Spend Anyway" overrides while surfacing
  /// actionable aggregate behavioral insights without notification fatigue.
  Future<void> onFocusModeRepeatedOverrides({
    required int overrideCount,
    required String categoryId,
    String? categoryName,
    DateTime? now,
  }) async {
    try {
      if (overrideCount < 3) return;
      final referenceTime = now ?? DateTime.now();
      final weekKey = CalendarUtils.weekPeriodKey(referenceTime);
      final alertKey = 'focus_override:$categoryId:$weekKey';

      final displayName = categoryName ?? 'Protected Category';
      final alert = AppAlert(
        id: 'focus_override_${categoryId}_$weekKey',
        title: 'Frequent Spend Overrides',
        message:
            'You have overridden Focus Mode $overrideCount times this week for $displayName. Consider reviewing this spending impulse or adjusting your limits.',
        type: AppAlertType.system,
        severity: AlertSeverity.warning,
        stage: AppAlertStage.warning,
        categoryId: categoryId,
        period: weekKey,
        alertKey: alertKey,
        createdAt: referenceTime,
      );

      await processAndDispatch([alert]);
    } catch (e, stack) {
      AppLogger.error(
        'Failed to evaluate focus mode repeated overrides in AlertCoordinator',
        error: e,
        stack: stack,
        label: 'AlertCoordinator',
      );
    }
  }

  /// Core deduplication, persistence, notification dispatch, and state propagation pipeline.
  /// Execution is serialized via an async FIFO queue to prevent concurrent race conditions.
  Future<void> processAndDispatch(List<AppAlert> alerts) {
    return _dispatchQueue =
        _dispatchQueue.then((_) => _processAndDispatchInternal(alerts));
  }

  Future<void> _processAndDispatchInternal(List<AppAlert> alerts) async {
    if (alerts.isEmpty) return;

    final newAlerts = <AppAlert>[];
    for (final alert in alerts) {
      // Insert or reactivate into repository safely
      final inserted = await _repository.insert(alert);
      if (inserted) {
        newAlerts.add(alert);
      }
    }

    if (newAlerts.isEmpty) return;

    // Update in-memory AlertProvider if attached
    if (_alertProvider != null) {
      _alertProvider!.injectNewAlerts(newAlerts);
    }

    // Dispatch system notifications
    await _dispatchNotifications(newAlerts);
  }

  Future<void> _dispatchNotifications(List<AppAlert> newAlerts) async {
    if (newAlerts.isEmpty) return;

    if (newAlerts.length <= kMaxIndividualAlertNotifications) {
      // Small batch (<= 2): fire individual notifications immediately
      for (final alert in newAlerts) {
        final category = _mapCategory(alert.type);
        final payload = _buildPayload(alert);

        await NotificationService.showInstant(
          id: NotificationService.collisionSafeId(alert.id),
          title: alert.title,
          body: alert.message,
          category: category,
          payload: payload,
        );
      }
    } else {
      // Large batch (> 2): show top 2 individual banners, then post summary
      for (var i = 0; i < kMaxIndividualAlertNotifications; i++) {
        final alert = newAlerts[i];
        final category = _mapCategory(alert.type);
        final payload = _buildPayload(alert);

        await NotificationService.showInstant(
          id: NotificationService.collisionSafeId(alert.id),
          title: alert.title,
          body: alert.message,
          category: category,
          payload: payload,
        );
      }

      await NotificationService.postAlertsSummary(
        alerts: newAlerts.map((a) {
          return (
            title: a.title,
            body: a.message,
            category: _mapCategory(a.type),
          );
        }).toList(),
      );
    }
  }

  static NotificationCategory _mapCategory(AppAlertType type) {
    return switch (type) {
      AppAlertType.budget => NotificationCategory.budget,
      AppAlertType.anomaly => NotificationCategory.anomaly,
      AppAlertType.largeTransaction => NotificationCategory.anomaly,
      AppAlertType.duplicateTransaction => NotificationCategory.anomaly,
      AppAlertType.cashflow => NotificationCategory.cashflow,
      AppAlertType.bill => NotificationCategory.bill,
      AppAlertType.goal => NotificationCategory.goalProgress,
      AppAlertType.system => NotificationCategory.budget,
    };
  }

  static String _buildPayload(AppAlert alert) {
    return switch (alert.type) {
      AppAlertType.bill => 'bill:${alert.recurringPaymentId ?? alert.id}',
      AppAlertType.goal => 'goal:${alert.goalId ?? alert.id}',
      AppAlertType.cashflow => 'cashflow:${alert.id}',
      AppAlertType.budget => 'budget:${alert.categoryId ?? alert.id}',
      _ => 'anomaly:${alert.categoryId ?? alert.id}',
    };
  }
}
