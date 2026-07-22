import 'package:flutter/material.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/premium/models/budget_alert.dart';
import 'package:pet/premium/repositories/alert_repository.dart';
import 'package:pet/premium/services/anomaly_detection_service.dart';
import 'package:pet/premium/services/notification_service.dart';
import 'package:uuid/uuid.dart';

class AlertProvider extends ChangeNotifier {
  final AlertRepository _repository = AlertRepository();
  final Uuid _uuid = const Uuid();

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

  Future<void> recordAlert(BudgetAlert alert) async {
    if (alert.alertKey != null) {
      if (_alerts.any((a) => a.alertKey == alert.alertKey)) return;
      final exists = await _repository.existsByKey(alert.alertKey!);
      if (exists) return;
    }

    await _repository.insert(alert);
    _alerts.insert(0, alert);
    notifyListeners();

    await NotificationService.showInstant(
      id: NotificationService.collisionSafeId(alert.id),
      title: alert.title,
      body: alert.message,
    );
  }

  Future<void> detectAnomalies({
    required List<TransactionRecord> transactions,
    required Map<String, double> baseline,
  }) async {
    final spikes = AnomalyDetectionService.detectCategorySpikes(
      transactions,
      baseline,
    );
    for (final entry in spikes.entries) {
      final alert = BudgetAlert(
        id: _uuid.v4(),
        type: 'anomaly',
        title: 'Spending spike detected',
        message:
            'This category is ${entry.value.toStringAsFixed(1)}x higher than usual.',
        categoryId: entry.key,
        createdAt: DateTime.now(),
        alertKey: 'anomaly_${entry.key}_${DateTime.now().month}',
      );
      await recordAlert(alert);
    }
  }

  Future<void> refreshAnomalies(List<TransactionRecord> transactions) async {
    if (identical(_lastTransactionsForAnomalies, transactions)) return;
    _lastTransactionsForAnomalies = transactions;
    final baseline = _computeBaseline(transactions);
    await detectAnomalies(transactions: transactions, baseline: baseline);
  }

  Future<void> refreshBudgetAlerts({
    required Map<String, double> budgets,
    required Map<String, double> spent,
  }) async {
    if (identical(_lastSpentForBudgets, spent)) return;
    _lastSpentForBudgets = spent;
    for (final entry in budgets.entries) {
      final budgetAmount = entry.value;
      final spentAmount = spent[entry.key] ?? 0;
      if (budgetAmount <= 0) continue;

      final progress = spentAmount / budgetAmount;
      if (progress < 0.9) continue;

      final alert = BudgetAlert(
        id: _uuid.v4(),
        type: 'budget',
        title: progress >= 1.0 ? 'Budget exceeded' : 'Budget warning',
        message: progress >= 1.0
            ? 'You have crossed your budget in this category.'
            : 'You are close to your budget limit.',
        categoryId: entry.key,
        createdAt: DateTime.now(),
        alertKey: 'budget_${entry.key}_${DateTime.now().month}',
      );
      await recordAlert(alert);
    }
  }

  Map<String, double> _computeBaseline(List<TransactionRecord> transactions) {
    final now = DateTime.now();
    final from = DateTime(now.year, now.month - 3, 1);
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
