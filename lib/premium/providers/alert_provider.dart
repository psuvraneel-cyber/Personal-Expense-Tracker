import 'package:flutter/material.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/premium/models/budget_alert.dart';
import 'package:pet/premium/models/notification_category.dart';
import 'package:pet/premium/repositories/alert_repository.dart';
import 'package:pet/premium/services/alert_evaluator.dart';
import 'package:pet/premium/services/notification_service.dart';

/// Maximum number of individual notifications to show per batch before collapsing to a summary.
const int kMaxIndividualAlertNotifications = 2;

/// Window duration for collecting/debouncing rapid alerts before batch dispatch.
const Duration kAlertDebounceWindow = Duration(seconds: 2);

class AlertProvider extends ChangeNotifier {
  final AlertRepository _repository = AlertRepository();

  List<BudgetAlert> _alerts = [];
  bool _isLoading = false;
  List<TransactionRecord>? _lastTransactionsForAnomalies;
  Map<String, double>? _lastSpentForBudgets;

  List<BudgetAlert> get alerts => _alerts;
  bool get isLoading => _isLoading;

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();

    _alerts = await _repository.getAll();

    _isLoading = false;
    notifyListeners();
  }

  /// Records a single alert and dispatches notification immediately (if within threshold).
  Future<void> recordAlert(BudgetAlert alert) async {
    await recordAlerts([alert]);
  }

  /// Records a batch of alerts, deduplicates against stored keys, persists to database,
  /// updates provider state, and dispatches throttled/grouped notifications.
  Future<void> recordAlerts(List<BudgetAlert> alerts) async {
    if (alerts.isEmpty) return;

    final newAlerts = <BudgetAlert>[];
    for (final alert in alerts) {
      if (alert.alertKey != null) {
        if (_alerts.any((a) => a.alertKey == alert.alertKey)) continue;
        final exists = await _repository.existsByKey(alert.alertKey!);
        if (exists) continue;
      }

      await _repository.insert(alert);
      _alerts.insert(0, alert);
      newAlerts.add(alert);
    }

    if (newAlerts.isEmpty) return;
    notifyListeners();

    await _dispatchBatchedAlertNotifications(newAlerts);
  }

  Future<void> _dispatchBatchedAlertNotifications(
    List<BudgetAlert> newAlerts,
  ) async {
    if (newAlerts.length <= kMaxIndividualAlertNotifications) {
      // Small batch (<= 2): fire individual notifications immediately
      for (final alert in newAlerts) {
        final category = switch (alert.type) {
          'budget' => NotificationCategory.budget,
          'anomaly' => NotificationCategory.anomaly,
          'bill' => NotificationCategory.bill,
          _ => NotificationCategory.budget,
        };
        final payload = '${alert.type}:${alert.categoryId ?? alert.id}';

        await NotificationService.showInstant(
          id: NotificationService.collisionSafeId(alert.id),
          title: alert.title,
          body: alert.message,
          category: category,
          payload: payload,
        );
      }
    } else {
      // Large batch (> 2): fire at most 2 individual banners, then post summary
      for (var i = 0; i < kMaxIndividualAlertNotifications; i++) {
        final alert = newAlerts[i];
        final category = switch (alert.type) {
          'budget' => NotificationCategory.budget,
          'anomaly' => NotificationCategory.anomaly,
          'bill' => NotificationCategory.bill,
          _ => NotificationCategory.budget,
        };
        final payload = '${alert.type}:${alert.categoryId ?? alert.id}';

        await NotificationService.showInstant(
          id: NotificationService.collisionSafeId(alert.id),
          title: alert.title,
          body: alert.message,
          category: category,
          payload: payload,
        );
      }

      // Post/update group summary for the entire batch
      await NotificationService.postAlertsSummary(
        alerts: newAlerts.map((a) {
          final category = switch (a.type) {
            'budget' => NotificationCategory.budget,
            'anomaly' => NotificationCategory.anomaly,
            'bill' => NotificationCategory.bill,
            _ => NotificationCategory.budget,
          };
          return (title: a.title, body: a.message, category: category);
        }).toList(),
      );
    }
  }

  Future<void> detectAnomalies({
    required List<TransactionRecord> transactions,
    required Map<String, double> baseline,
  }) async {
    final alerts = AlertEvaluator.evaluateAnomalies(
      transactions: transactions,
      baseline: baseline,
    );
    await recordAlerts(alerts);
  }

  Future<void> refreshAnomalies(List<TransactionRecord> transactions) async {
    if (identical(_lastTransactionsForAnomalies, transactions)) return;
    _lastTransactionsForAnomalies = transactions;
    final baseline = AlertEvaluator.computeBaseline(transactions);
    await detectAnomalies(transactions: transactions, baseline: baseline);
  }

  Future<void> refreshBudgetAlerts({
    required Map<String, double> budgets,
    required Map<String, double> spent,
  }) async {
    if (identical(_lastSpentForBudgets, spent)) return;
    _lastSpentForBudgets = spent;
    final alerts = AlertEvaluator.evaluateBudgetAlerts(
      budgets: budgets,
      spent: spent,
    );
    await recordAlerts(alerts);
  }

  Future<void> markRead(String id) async {
    await _repository.markRead(id);
    final index = _alerts.indexWhere((a) => a.id == id);
    if (index == -1) return;
    _alerts[index] = _alerts[index].copyWith(isRead: true);
    notifyListeners();
  }

  void clearData() {
    _alerts = [];
    _isLoading = false;
    _lastTransactionsForAnomalies = null;
    _lastSpentForBudgets = null;
    notifyListeners();
  }
}
