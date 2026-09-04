import 'dart:math';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/premium/models/app_alert.dart';
import 'package:pet/premium/models/cashflow_forecast.dart';
import 'package:pet/premium/models/recurring_payment.dart';
import 'package:pet/premium/models/saving_goal.dart';
import 'package:pet/premium/services/anomaly_detection_service.dart';
import 'package:pet/premium/services/cashflow_forecast_service.dart';
import 'package:uuid/uuid.dart';

/// Pure, deterministic static evaluation engine for financial alerts.
///
/// Can be safely invoked from both foreground (providers, coordinators)
/// and background WorkManager isolates without widget or UI dependencies.
class AlertEvaluator {
  AlertEvaluator._();

  static const _uuid = Uuid();

  /// Computes historical monthly spending baseline per category over completed months.
  ///
  /// Strictly excludes the current calendar month ([referenceTime].year, [referenceTime].month)
  /// so that in-progress spending never contaminates the historical baseline.
  static Map<String, double> computeBaseline(
    List<TransactionRecord> transactions, {
    DateTime? now,
  }) {
    final referenceTime = now ?? DateTime.now();
    // Window: 3 completed calendar months prior to current month
    final to = DateTime(referenceTime.year, referenceTime.month, 1);
    final from = DateTime(referenceTime.year, referenceTime.month - 3, 1);

    final byCategory = <String, double>{};
    final months = <String, Set<String>>{};

    for (final t in transactions) {
      if (t.type != TransactionType.expense) continue;
      // Skip if before the 3-month window OR if in/after the current month
      if (t.date.isBefore(from) || !t.date.isBefore(to)) continue;

      byCategory[t.categoryId] = (byCategory[t.categoryId] ?? 0) + t.amount;
      months.putIfAbsent(t.categoryId, () => <String>{});
      months[t.categoryId]!.add('${t.date.year}-${t.date.month}');
    }

    final baseline = <String, double>{};
    for (final entry in byCategory.entries) {
      final count = months[entry.key]?.length ?? 1;
      baseline[entry.key] = entry.value / count;
    }
    return baseline;
  }

  /// Evaluates budget thresholds and returns a list of [AppAlert]s.
  ///
  /// Stages:
  /// - progress >= 1.25 -> critical overrun stage (`budget:<cat>:<period>:critical`)
  /// - 1.0 <= progress < 1.25 -> exceeded stage (`budget:<cat>:<period>:exceeded`)
  /// - 0.9 <= progress < 1.0 -> warning stage (`budget:<cat>:<period>:warning`)
  /// - progress < 0.9 -> no alert
  static List<AppAlert> evaluateBudgetAlerts({
    required Map<String, double> budgets,
    required Map<String, double> spent,
    DateTime? now,
    Uuid? uuid,
  }) {
    final referenceTime = now ?? DateTime.now();
    final idGenerator = uuid ?? _uuid;
    final period =
        '${referenceTime.year}-${referenceTime.month.toString().padLeft(2, '0')}';
    final alerts = <AppAlert>[];

    for (final entry in budgets.entries) {
      final categoryId = entry.key;
      final budgetAmount = entry.value;
      final spentAmount = spent[categoryId] ?? 0;
      if (budgetAmount <= 0) continue;

      final progress = spentAmount / budgetAmount;
      if (progress < 0.9) continue;

      final AppAlertStage stage;
      final AlertSeverity severity;
      final String title;
      final String message;
      final String stageKey;

      if (progress >= 1.25) {
        stage = AppAlertStage.critical;
        severity = AlertSeverity.critical;
        title = 'Critical budget overrun';
        final percentOver = ((progress - 1.0) * 100).toStringAsFixed(0);
        final amountOver = (spentAmount - budgetAmount).toStringAsFixed(0);
        message =
            'Spending is $percentOver% over your monthly budget (₹$amountOver over).';
        stageKey = 'critical';
      } else if (progress >= 1.0) {
        stage = AppAlertStage.exceeded;
        severity = AlertSeverity.critical;
        title = 'Budget exceeded';
        final amountOver = (spentAmount - budgetAmount).toStringAsFixed(0);
        message = amountOver == '0'
            ? 'You have reached 100% of your budget in this category.'
            : 'You have crossed your budget by ₹$amountOver in this category.';
        stageKey = 'exceeded';
      } else {
        stage = AppAlertStage.warning;
        severity = AlertSeverity.warning;
        title = 'Budget warning';
        final percentUsed = (progress * 100).toStringAsFixed(0);
        message =
            'You are close to your budget limit ($percentUsed% used).';
        stageKey = 'warning';
      }

      final alert = AppAlert(
        id: idGenerator.v4(),
        type: AppAlertType.budget,
        stage: stage,
        severity: severity,
        title: title,
        message: message,
        categoryId: categoryId,
        amount: spentAmount,
        targetAmount: budgetAmount,
        ratio: progress,
        period: period,
        createdAt: referenceTime,
        alertKey: 'budget:$categoryId:$period:$stageKey',
        actionType: AlertActionType.viewTransactions,
        actionPayload: categoryId,
      );
      alerts.add(alert);
    }

    return alerts;
  }

  /// Evaluates predictive spending pacing for active budgets.
  ///
  /// Predicts whether current run-rate will exhaust the budget before month end.
  /// Suppressed during early days of month (day < 5) to avoid noise.
  static List<AppAlert> evaluateBudgetPacing({
    required Map<String, double> budgets,
    required Map<String, double> spent,
    DateTime? now,
    Uuid? uuid,
  }) {
    final referenceTime = now ?? DateTime.now();
    final idGenerator = uuid ?? _uuid;
    final day = referenceTime.day;
    final daysInMonth =
        DateTime(referenceTime.year, referenceTime.month + 1, 0).day;

    // Minimum data requirement: skip first 4 days and last 2 days of month
    if (day < 5 || day > daysInMonth - 2) return [];

    final period =
        '${referenceTime.year}-${referenceTime.month.toString().padLeft(2, '0')}';
    final alerts = <AppAlert>[];

    for (final entry in budgets.entries) {
      final categoryId = entry.key;
      final budgetAmount = entry.value;
      final spentAmount = spent[categoryId] ?? 0;
      if (budgetAmount <= 0 || spentAmount <= 0) continue;

      final progress = spentAmount / budgetAmount;
      // Skip if already exceeded (handled by evaluateBudgetAlerts)
      if (progress >= 1.0) continue;

      final dailyRate = spentAmount / day;
      final projectedMonthSpend = dailyRate * daysInMonth;

      // Only warn if projected to exceed budget by at least 15%
      if (projectedMonthSpend >= budgetAmount * 1.15) {
        final exhaustionDay = (budgetAmount / dailyRate).floor();
        final daysLeft = (exhaustionDay - day).clamp(1, daysInMonth);

        final alert = AppAlert(
          id: idGenerator.v4(),
          type: AppAlertType.budget,
          stage: AppAlertStage.pacing,
          severity: AlertSeverity.warning,
          title: 'Budget pacing warning',
          message:
              'At your current pace of ₹${dailyRate.toStringAsFixed(0)}/day, your budget may run out in $daysLeft day${daysLeft == 1 ? '' : 's'}.',
          categoryId: categoryId,
          amount: spentAmount,
          targetAmount: budgetAmount,
          ratio: projectedMonthSpend / budgetAmount,
          period: period,
          createdAt: referenceTime,
          alertKey: 'budget_pacing:$categoryId:$period',
          actionType: AlertActionType.adjustBudget,
          actionPayload: categoryId,
        );
        alerts.add(alert);
      }
    }

    return alerts;
  }

  /// Evaluates spending anomalies scoped to the current month.
  static List<AppAlert> evaluateAnomalies({
    required List<TransactionRecord> transactions,
    Map<String, double>? baseline,
    DateTime? now,
    Uuid? uuid,
    double minSpendDelta = 0.0,
  }) {
    final referenceTime = now ?? DateTime.now();
    final idGenerator = uuid ?? _uuid;
    final period =
        '${referenceTime.year}-${referenceTime.month.toString().padLeft(2, '0')}';

    final calculatedBaseline =
        baseline ?? computeBaseline(transactions, now: referenceTime);

    final spikes = AnomalyDetectionService.detectSpikes(
      transactions,
      calculatedBaseline,
      now: referenceTime,
      minSpendDelta: minSpendDelta,
    );

    final alerts = <AppAlert>[];
    for (final spike in spikes) {
      final alert = AppAlert(
        id: idGenerator.v4(),
        type: AppAlertType.anomaly,
        stage: AppAlertStage.warning,
        severity: spike.ratio >= 2.5
            ? AlertSeverity.critical
            : AlertSeverity.warning,
        title: 'Spending spike detected',
        message:
            'This category is ${spike.ratio.toStringAsFixed(1)}x higher than usual.',
        categoryId: spike.categoryId,
        amount: spike.currentSpend,
        targetAmount: spike.baselineSpend,
        ratio: spike.ratio,
        period: period,
        createdAt: referenceTime,
        alertKey: 'anomaly:${spike.categoryId}:$period',
        actionType: AlertActionType.viewTransactions,
        actionPayload: spike.categoryId,
      );
      alerts.add(alert);
    }

    return alerts;
  }

  /// Evaluates unusually large individual transactions relative to category baseline or budget.
  static List<AppAlert> evaluateLargeTransactions({
    required List<TransactionRecord> transactions,
    Map<String, double>? categoryBudgets,
    DateTime? now,
    Uuid? uuid,
  }) {
    final referenceTime = now ?? DateTime.now();
    final idGenerator = uuid ?? _uuid;
    final alerts = <AppAlert>[];

    // Filter to current month expense transactions
    final currentTxns = transactions.where((t) {
      return t.type == TransactionType.expense &&
          t.date.year == referenceTime.year &&
          t.date.month == referenceTime.month;
    }).toList();

    // Group amounts by category to compute medians
    final amountsByCat = <String, List<double>>{};
    for (final t in currentTxns) {
      amountsByCat.putIfAbsent(t.categoryId, () => []).add(t.amount);
    }

    final medians = <String, double>{};
    for (final entry in amountsByCat.entries) {
      if (entry.value.length >= 2) {
        final list = List<double>.from(entry.value)..sort();
        medians[entry.key] = list[list.length ~/ 2];
      }
    }

    for (final t in currentTxns) {
      // Must be at least ₹1,000 to qualify as large transaction alert
      if (t.amount < 1000) continue;
      // Skip scheduled recurring commitments (e.g. rent, EMI, subscription)
      if (t.isRecurring) continue;

      final median = medians[t.categoryId] ?? 0;
      final budget = categoryBudgets?[t.categoryId] ?? 0;

      // If category has an established median and this transaction is within 50%
      // of that median, it represents normal recurring category spend, not an outlier.
      if (median > 0 && t.amount < 1.5 * median) continue;

      final isOutlierAgainstMedian = median > 0 && t.amount >= 3.0 * median;
      final isOutlierAgainstBudget = budget > 0 &&
          t.amount >= 0.70 * budget &&
          (median == 0 || t.amount >= 1.5 * median);

      if (isOutlierAgainstMedian || isOutlierAgainstBudget) {
        final alert = AppAlert(
          id: idGenerator.v4(),
          type: AppAlertType.largeTransaction,
          stage: AppAlertStage.warning,
          severity: AlertSeverity.warning,
          title: 'Large transaction detected',
          message:
              'A payment of ₹${t.amount.toStringAsFixed(0)} ${t.merchantName != null ? 'at ${t.merchantName}' : ''} is unusually large.',
          categoryId: t.categoryId,
          transactionId: t.id,
          amount: t.amount,
          createdAt: t.date,
          alertKey: 'large_txn:${t.id}',
          actionType: AlertActionType.inspectTransaction,
          actionPayload: t.id,
        );
        alerts.add(alert);
      }
    }

    return alerts;
  }

  /// Detects possible duplicate transactions (same amount, merchant/category, within 15 mins).
  static List<AppAlert> evaluateDuplicateTransactions({
    required List<TransactionRecord> transactions,
    DateTime? now,
    Uuid? uuid,
  }) {
    final referenceTime = now ?? DateTime.now();
    final idGenerator = uuid ?? _uuid;
    final alerts = <AppAlert>[];

    // Filter to current month expense transactions sorted by date
    final currentTxns = transactions.where((t) {
      return t.type == TransactionType.expense &&
          t.date.year == referenceTime.year &&
          t.date.month == referenceTime.month;
    }).toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    final seenPairs = <String>{};

    for (var i = 0; i < currentTxns.length; i++) {
      for (var j = i + 1; j < currentTxns.length; j++) {
        final t1 = currentTxns[i];
        final t2 = currentTxns[j];

        // Break early if time gap exceeds 15 minutes
        final diff = t2.date.difference(t1.date).abs();
        if (diff.inMinutes > 15) break;

        final hasMerchant1 =
            t1.merchantName != null && t1.merchantName!.trim().isNotEmpty;
        final hasMerchant2 =
            t2.merchantName != null && t2.merchantName!.trim().isNotEmpty;

        final bool isMerchantOrCategoryMatch;
        if (hasMerchant1 && hasMerchant2) {
          // Both specify merchants -> MUST match merchant name (case-insensitive)
          isMerchantOrCategoryMatch = t1.merchantName!.trim().toLowerCase() ==
              t2.merchantName!.trim().toLowerCase();
        } else {
          // At least one lacks merchant name -> fall back to same category
          isMerchantOrCategoryMatch = t1.categoryId == t2.categoryId;
        }

        if ((t1.amount - t2.amount).abs() < 0.01 && isMerchantOrCategoryMatch) {
          final sortedIds = [t1.id, t2.id]..sort();
          final pairKey = '${sortedIds[0]}_${sortedIds[1]}';
          if (seenPairs.contains(pairKey)) continue;
          seenPairs.add(pairKey);

          final mins = max(1, diff.inMinutes);
          final alert = AppAlert(
            id: idGenerator.v4(),
            type: AppAlertType.duplicateTransaction,
            stage: AppAlertStage.warning,
            severity: AlertSeverity.warning,
            title: 'Possible duplicate transaction',
            message:
                'Two payments of ₹${t1.amount.toStringAsFixed(0)} were recorded within $mins minute${mins == 1 ? '' : 's'}.',
            categoryId: t1.categoryId,
            transactionId: t2.id,
            amount: t1.amount,
            createdAt: t2.date,
            alertKey: 'dup_txn:$pairKey',
            actionType: AlertActionType.inspectTransaction,
            actionPayload: t2.id,
          );
          alerts.add(alert);
        }
      }
    }

    return alerts;
  }

  /// Evaluates 30-day cashflow forecast risk (checking 14-day imminent deficit and 30-day ending deficit).
  static AppAlert? evaluateCashflowRisk({
    required List<TransactionRecord> transactions,
    List<RecurringPayment>? confirmedBills,
    DateTime? now,
    Uuid? uuid,
  }) {
    final referenceTime = now ?? DateTime.now();
    final idGenerator = uuid ?? _uuid;

    final forecast = CashflowForecastService.forecast(
      transactions,
      confirmedBills: confirmedBills,
      days: 30,
    );

    // Evaluate across the 14-day imminent horizon as well as the 30-day projection
    final alertWindowPoints = forecast.dailyPoints.take(14).toList();
    final lowestPoint = alertWindowPoints.fold<CashflowPoint?>(
      null,
      (min, pt) => (min == null || pt.balance < min.balance) ? pt : min,
    );

    final hasImminentDeficit = lowestPoint != null && lowestPoint.balance < 0;
    final hasEndingDeficit = forecast.projectedEndingBalance <= 0;

    if ((hasImminentDeficit || hasEndingDeficit) && !forecast.hasInsufficientData) {
      final period =
          '${referenceTime.year}-${referenceTime.month.toString().padLeft(2, '0')}';
      final alertKey = 'cashflow:$period';
      final deficitAmount = hasImminentDeficit
          ? -lowestPoint.balance
          : -forecast.projectedEndingBalance;

      return AppAlert(
        id: idGenerator.v4(),
        type: AppAlertType.cashflow,
        stage: AppAlertStage.critical,
        severity: AlertSeverity.critical,
        title: '⚠️ Cashflow Risk Warning',
        message: deficitAmount > 0
            ? 'Your projected cashflow has a deficit (-₹${deficitAmount.toStringAsFixed(0)}) in the next ${hasImminentDeficit ? '14' : '30'} days. Review upcoming bills and expenses.'
            : 'Your projected 30-day balance reaches zero. Review upcoming bills and expenses.',
        amount: hasImminentDeficit
            ? lowestPoint.balance
            : forecast.projectedEndingBalance,
        period: period,
        createdAt: referenceTime,
        alertKey: alertKey,
        actionType: AlertActionType.viewCashflow,
      );
    }

    return null;
  }

  /// Evaluates confirmed upcoming bills due within 3 days.
  static List<AppAlert> evaluateBills({
    required List<RecurringPayment> recurring,
    DateTime? now,
    Uuid? uuid,
  }) {
    final referenceTime = now ?? DateTime.now();
    final idGenerator = uuid ?? _uuid;
    final alerts = <AppAlert>[];

    for (final item in recurring) {
      if (item.status != RecurringStatus.confirmed) continue;
      final days = item.nextDueAt.difference(referenceTime).inDays;
      if (days < 0 || days > 3) continue;

      final dueDateStr =
          '${item.nextDueAt.year}-${item.nextDueAt.month.toString().padLeft(2, '0')}-${item.nextDueAt.day.toString().padLeft(2, '0')}';
      final alertKey = 'bill:${item.id}:$dueDateStr';

      final title =
          item.isAutopay ? 'Upcoming autopay due' : 'Upcoming bill due';
      final message = item.isAutopay
          ? '${item.merchantName} (₹${item.amount.toStringAsFixed(0)}) autopay in $days day${days == 1 ? '' : 's'}. Check your balance.'
          : '${item.merchantName} (₹${item.amount.toStringAsFixed(0)}) due in $days day${days == 1 ? '' : 's'}.';

      final alert = AppAlert(
        id: idGenerator.v4(),
        type: AppAlertType.bill,
        stage: AppAlertStage.info,
        severity: item.isAutopay ? AlertSeverity.warning : AlertSeverity.info,
        title: title,
        message: message,
        categoryId: item.categoryId,
        amount: item.amount,
        recurringPaymentId: item.id,
        createdAt: referenceTime,
        alertKey: alertKey,
        actionType: AlertActionType.viewBill,
        actionPayload: item.id,
      );
      alerts.add(alert);
    }

    return alerts;
  }

  /// Evaluates savings goal milestones (e.g. goal achieved).
  static List<AppAlert> evaluateGoals({
    required List<SavingGoal> goals,
    DateTime? now,
    Uuid? uuid,
  }) {
    final referenceTime = now ?? DateTime.now();
    final idGenerator = uuid ?? _uuid;
    final alerts = <AppAlert>[];

    for (final goal in goals) {
      if (goal.targetAmount <= 0) continue;
      final progress = goal.currentAmount / goal.targetAmount;

      if (progress >= 1.0) {
        final alertKey = 'goal_achieved:${goal.id}';
        final alert = AppAlert(
          id: idGenerator.v4(),
          type: AppAlertType.goal,
          stage: AppAlertStage.milestone,
          severity: AlertSeverity.info,
          title: '🎉 Goal Achieved!',
          message: 'Congratulations! You reached your goal: ${goal.name}.',
          goalId: goal.id,
          amount: goal.currentAmount,
          targetAmount: goal.targetAmount,
          ratio: progress,
          createdAt: referenceTime,
          alertKey: alertKey,
          actionType: AlertActionType.viewGoal,
          actionPayload: goal.id,
        );
        alerts.add(alert);
      } else if (progress >= 0.80) {
        final alertKey = 'goal_milestone:${goal.id}:80';
        final alert = AppAlert(
          id: idGenerator.v4(),
          type: AppAlertType.goal,
          stage: AppAlertStage.milestone,
          severity: AlertSeverity.info,
          title: 'Goal milestone reached',
          message:
              'You are at ${(progress * 100).toStringAsFixed(0)}% for ${goal.name} (₹${goal.currentAmount.toStringAsFixed(0)} / ₹${goal.targetAmount.toStringAsFixed(0)}).',
          goalId: goal.id,
          amount: goal.currentAmount,
          targetAmount: goal.targetAmount,
          ratio: progress,
          createdAt: referenceTime,
          alertKey: alertKey,
          actionType: AlertActionType.viewGoal,
          actionPayload: goal.id,
        );
        alerts.add(alert);
      }
    }

    return alerts;
  }
}
