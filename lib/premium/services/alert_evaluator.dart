import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/premium/models/budget_alert.dart';
import 'package:pet/premium/services/anomaly_detection_service.dart';
import 'package:pet/premium/services/cashflow_forecast_service.dart';
import 'package:uuid/uuid.dart';

/// Pure static evaluation engine for budget thresholds, spending anomalies, and cashflow risk.
/// Can be safely invoked from both foreground (providers) and background WorkManager isolates.
class AlertEvaluator {
  AlertEvaluator._();

  static const _uuid = Uuid();

  /// Computes historical spending baseline per category over the last 3 months.
  static Map<String, double> computeBaseline(
    List<TransactionRecord> transactions, {
    DateTime? now,
  }) {
    final referenceTime = now ?? DateTime.now();
    final from = DateTime(referenceTime.year, referenceTime.month - 3, 1);
    final byCategory = <String, double>{};
    final months = <String, Set<int>>{};

    for (final t in transactions) {
      if (t.type != TransactionType.expense) continue;
      if (t.date.isBefore(from)) continue;
      byCategory[t.categoryId] = (byCategory[t.categoryId] ?? 0) + t.amount;
      months.putIfAbsent(t.categoryId, () => <int>{});
      months[t.categoryId]!.add(t.date.month);
    }

    final baseline = <String, double>{};
    for (final entry in byCategory.entries) {
      final count = months[entry.key]?.length ?? 1;
      baseline[entry.key] = entry.value / count;
    }
    return baseline;
  }

  /// Evaluates budget thresholds and returns a list of [BudgetAlert]s.
  ///
  /// Thresholds:
  /// - progress >= 1.0 -> 'Budget exceeded'
  /// - 0.9 <= progress < 1.0 -> 'Budget warning'
  /// - progress < 0.9 -> no alert
  static List<BudgetAlert> evaluateBudgetAlerts({
    required Map<String, double> budgets,
    required Map<String, double> spent,
    DateTime? now,
    Uuid? uuid,
  }) {
    final referenceTime = now ?? DateTime.now();
    final idGenerator = uuid ?? _uuid;
    final alerts = <BudgetAlert>[];

    for (final entry in budgets.entries) {
      final budgetAmount = entry.value;
      final spentAmount = spent[entry.key] ?? 0;
      if (budgetAmount <= 0) continue;

      final progress = spentAmount / budgetAmount;
      if (progress < 0.9) continue;

      final alert = BudgetAlert(
        id: idGenerator.v4(),
        type: 'budget',
        title: progress >= 1.0 ? 'Budget exceeded' : 'Budget warning',
        message: progress >= 1.0
            ? 'You have crossed your budget in this category.'
            : 'You are close to your budget limit.',
        categoryId: entry.key,
        createdAt: referenceTime,
        alertKey: 'budget_${entry.key}_${referenceTime.month}',
      );
      alerts.add(alert);
    }

    return alerts;
  }

  /// Evaluates spending anomalies and returns a list of [BudgetAlert]s.
  static List<BudgetAlert> evaluateAnomalies({
    required List<TransactionRecord> transactions,
    Map<String, double>? baseline,
    DateTime? now,
    Uuid? uuid,
  }) {
    final referenceTime = now ?? DateTime.now();
    final idGenerator = uuid ?? _uuid;
    final calculatedBaseline =
        baseline ?? computeBaseline(transactions, now: referenceTime);
    final spikes = AnomalyDetectionService.detectCategorySpikes(
      transactions,
      calculatedBaseline,
    );

    final alerts = <BudgetAlert>[];
    for (final entry in spikes.entries) {
      final alert = BudgetAlert(
        id: idGenerator.v4(),
        type: 'anomaly',
        title: 'Spending spike detected',
        message:
            'This category is ${entry.value.toStringAsFixed(1)}x higher than usual.',
        categoryId: entry.key,
        createdAt: referenceTime,
        alertKey: 'anomaly_${entry.key}_${referenceTime.month}',
      );
      alerts.add(alert);
    }

    return alerts;
  }

  /// Evaluates 30-day cashflow forecast risk and returns a [BudgetAlert] if a zero/negative balance is projected.
  static BudgetAlert? evaluateCashflowRisk({
    required List<TransactionRecord> transactions,
    DateTime? now,
    Uuid? uuid,
  }) {
    final referenceTime = now ?? DateTime.now();
    final idGenerator = uuid ?? _uuid;

    final forecast = CashflowForecastService.forecast(
      transactions,
      days: 30,
    );

    if (forecast.projectedEndingBalance <= 0 && !forecast.hasInsufficientData) {
      final alertKey = 'cashflow_${referenceTime.year}_${referenceTime.month}';
      return BudgetAlert(
        id: idGenerator.v4(),
        type: 'cashflow',
        title: '⚠️ Cashflow Risk Warning',
        message:
            'Your projected 30-day balance is deficit or zero. Review upcoming bills and expenses.',
        createdAt: referenceTime,
        alertKey: alertKey,
      );
    }

    return null;
  }
}
