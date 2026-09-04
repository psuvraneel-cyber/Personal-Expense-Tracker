import 'package:flutter/material.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/premium/models/app_alert.dart';
import 'package:pet/premium/repositories/alert_repository.dart';
import 'package:pet/premium/services/alert_evaluation_coordinator.dart';
import 'package:pet/premium/services/alert_evaluator.dart';

/// Maximum number of individual notifications to show per batch before collapsing to a summary.
const int kMaxIndividualAlertNotifications = 2;

/// Window duration for collecting/debouncing rapid alerts before batch dispatch.
const Duration kAlertDebounceWindow = Duration(seconds: 2);

class AlertProvider extends ChangeNotifier {
  final AlertRepository _repository;
  final AlertEvaluationCoordinator _coordinator;

  List<AppAlert> _alerts = [];
  int _unreadCount = 0;
  int _activeCount = 0;
  bool _isLoading = false;
  bool _isLoaded = false;
  bool _hasMore = true;
  static const int _pageSize = 20;

  // Filter state
  AppAlertType? _filterType;
  AlertSeverity? _filterSeverity;
  bool _filterUnreadOnly = false;

  List<TransactionRecord>? _lastTransactionsForAnomalies;
  Map<String, double>? _lastSpentForBudgets;

  AlertProvider({
    AlertRepository? repository,
    AlertEvaluationCoordinator? coordinator,
  })  : _repository = repository ?? AlertRepository(),
        _coordinator = coordinator ?? AlertEvaluationCoordinator() {
    _coordinator.attachProvider(this);
  }

  List<AppAlert> get alerts => _alerts;
  int get unreadCount => _unreadCount;
  int get activeCount => _activeCount;
  bool get isLoading => _isLoading;
  bool get isLoaded => _isLoaded;
  bool get hasMore => _hasMore;
  AppAlertType? get filterType => _filterType;
  AlertSeverity? get filterSeverity => _filterSeverity;
  bool get filterUnreadOnly => _filterUnreadOnly;

  /// Loads the first page of alerts along with direct SQL badge counts.
  Future<void> load({bool refresh = true}) async {
    _isLoading = true;
    notifyListeners();

    try {
      _unreadCount = await _repository.getUnreadCount();
      _activeCount = await _repository.getActiveCount();

      final firstPage = await _repository.getPage(
        limit: _pageSize,
        offset: 0,
        type: _filterType,
        severity: _filterSeverity,
        unreadOnly: _filterUnreadOnly ? true : null,
      );

      _alerts = firstPage;
      _hasMore = firstPage.length >= _pageSize;

      // Retention cleanup: purge dismissed/read alerts older than 90 days in background
      _repository.purgeOldDismissedAlerts().catchError((_) => 0);
    } catch (_) {
      // Keep existing alerts on failure
    } finally {
      _isLoading = false;
      _isLoaded = true;
      notifyListeners();
    }
  }

  /// Loads the next page for pagination.
  Future<void> loadMore() async {
    if (_isLoading || !_hasMore) return;

    _isLoading = true;
    notifyListeners();

    try {
      final nextPage = await _repository.getPage(
        limit: _pageSize,
        offset: _alerts.length,
        type: _filterType,
        severity: _filterSeverity,
        unreadOnly: _filterUnreadOnly ? true : null,
      );

      _alerts = [..._alerts, ...nextPage];
      _hasMore = nextPage.length >= _pageSize;
    } catch (_) {
      // Keep state
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Set type filter (null for all).
  Future<void> setFilterType(AppAlertType? type) async {
    if (_filterType == type) return;
    _filterType = type;
    await load();
  }

  /// Set severity filter (null for all).
  Future<void> setFilterSeverity(AlertSeverity? severity) async {
    if (_filterSeverity == severity) return;
    _filterSeverity = severity;
    await load();
  }

  /// Toggle or set unread-only filter.
  Future<void> setFilterUnreadOnly(bool unreadOnly) async {
    if (_filterUnreadOnly == unreadOnly) return;
    _filterUnreadOnly = unreadOnly;
    await load();
  }

  Future<void> clearFilters() async {
    _filterType = null;
    _filterSeverity = null;
    _filterUnreadOnly = false;
    await load();
  }

  /// Called by the Coordinator to inject newly persisted alerts into in-memory state.
  void injectNewAlerts(List<AppAlert> newAlerts) {
    if (newAlerts.isEmpty) return;

    // Eagerly materialize to avoid lazy re-evaluation against mutated _alerts
    final fresh =
        newAlerts.where((na) => !_alerts.any((a) => a.id == na.id)).toList();
    if (fresh.isEmpty) return;

    _alerts = [...fresh, ..._alerts];
    _unreadCount += fresh.where((a) => !a.isRead).length;
    _activeCount += fresh.length;
    notifyListeners();
  }

  /// Records a single alert and dispatches through coordinator pipeline.
  Future<void> recordAlert(AppAlert alert) async {
    await recordAlerts([alert]);
  }

  /// Records a batch of alerts, deduplicates against stored keys, persists to database,
  /// updates provider state, and dispatches throttled/grouped notifications.
  Future<void> recordAlerts(List<AppAlert> alerts) async {
    await _coordinator.processAndDispatch(alerts);
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

  /// Mark an alert as read.
  Future<void> markRead(String id) async {
    await _repository.markRead(id);
    final index = _alerts.indexWhere((a) => a.id == id);
    if (index != -1) {
      if (!_alerts[index].isRead) {
        _unreadCount = (_unreadCount - 1).clamp(0, 999999);
      }
      _alerts = List<AppAlert>.from(_alerts)
        ..[index] = _alerts[index].copyWith(isRead: true);
      notifyListeners();
    }
  }

  /// Mark all active alerts as read in a single SQL operation.
  Future<void> markAllRead() async {
    await _repository.markAllRead(type: _filterType);
    _unreadCount = 0;
    _alerts = _alerts.map((a) => a.copyWith(isRead: true)).toList();
    notifyListeners();
  }

  /// Soft-dismiss an alert.
  Future<void> dismiss(String id) async {
    final index = _alerts.indexWhere((a) => a.id == id);
    if (index == -1) return;

    final alert = _alerts[index];
    _alerts = List<AppAlert>.from(_alerts)..removeAt(index);
    _activeCount = (_activeCount - 1).clamp(0, 999999);
    if (!alert.isRead) {
      _unreadCount = (_unreadCount - 1).clamp(0, 999999);
    }
    notifyListeners();

    await _repository.dismiss(id);
  }

  /// Undo soft-dismissal.
  Future<void> undoDismiss(AppAlert alert) async {
    final restored = alert.copyWith(
      isDismissed: false,
      updatedAt: DateTime.now(),
    );
    _alerts = [restored, ..._alerts];
    _activeCount++;
    if (!alert.isRead) {
      _unreadCount++;
    }
    notifyListeners();
    await _repository.undoDismiss(alert.id);
  }

  /// Dismiss all read alerts.
  Future<void> dismissAllRead() async {
    await _repository.dismissAllRead();
    final dismissedCount = _alerts.where((a) => a.isRead).length;
    _alerts = _alerts.where((a) => !a.isRead).toList();
    _activeCount = (_activeCount - dismissedCount).clamp(0, 999999);
    notifyListeners();
  }

  /// Removes alerts matching the predicate from in-memory state and updates badge counts.
  void removeAlertsWhere(bool Function(AppAlert) test) {
    final removed = _alerts.where(test).toList();
    if (removed.isEmpty) return;

    _alerts = _alerts.where((a) => !test(a)).toList();
    _activeCount = (_activeCount - removed.length).clamp(0, 999999);
    final unreadRemoved = removed.where((a) => !a.isRead).length;
    _unreadCount = (_unreadCount - unreadRemoved).clamp(0, 999999);
    notifyListeners();
  }

  void clearData() {
    _alerts = [];
    _unreadCount = 0;
    _activeCount = 0;
    _isLoading = false;
    _hasMore = true;
    _lastTransactionsForAnomalies = null;
    _lastSpentForBudgets = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _coordinator.detachProvider();
    super.dispose();
  }
}
