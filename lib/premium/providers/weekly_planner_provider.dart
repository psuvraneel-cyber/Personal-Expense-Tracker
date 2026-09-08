import 'dart:async';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:pet/core/utils/app_logger.dart';
import 'package:pet/core/utils/calendar_utils.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/premium/models/weekly_limit.dart';
import 'package:pet/premium/repositories/weekly_planner_repository.dart';
import 'package:pet/premium/services/alert_evaluation_coordinator.dart';
import 'package:pet/services/firestore_sync_service.dart';

/// A single day's aggregated spend for the weekly planner strip.
class DaySpend {
  final DateTime date;
  final double spent;

  const DaySpend({required this.date, required this.spent});

  String get shortLabel => CalendarUtils.formatWeekday(date);
}

/// Weekly planner entry for one category.
class WeeklyPlannerEntry {
  final String categoryId;
  final String categoryName;
  final double weeklyLimit;
  double weeklySpent;
  final WeeklyRecurrencePolicy recurrencePolicy;
  final DateTime? periodStart;

  WeeklyPlannerEntry({
    required this.categoryId,
    required this.categoryName,
    required this.weeklyLimit,
    this.weeklySpent = 0,
    this.recurrencePolicy = WeeklyRecurrencePolicy.recurring,
    this.periodStart,
  });

  double get progress =>
      weeklyLimit > 0 ? (weeklySpent / weeklyLimit).clamp(0.0, 1.0) : 0.0;
  bool get isOverBudget => weeklySpent > weeklyLimit;
  double get remaining => (weeklyLimit - weeklySpent).clamp(0, double.infinity);
  double get surplus => (weeklyLimit - weeklySpent).clamp(0, double.infinity);
  double get overage => isOverBudget ? (weeklySpent - weeklyLimit) : 0.0;

  WeeklyLimit toLimit({required DateTime now}) {
    return WeeklyLimit(
      id: categoryId,
      categoryId: categoryId,
      categoryName: categoryName,
      weeklyLimit: weeklyLimit,
      createdAt: now,
      updatedAt: now,
      recurrencePolicy: recurrencePolicy,
      periodStart: periodStart,
    );
  }
}

class WeeklyPlannerProvider extends ChangeNotifier {
  final WeeklyPlannerRepository _repository;
  final FirestoreSyncService? _firestoreSync;
  static const Uuid _uuid = Uuid();

  WeeklyPlannerProvider({
    WeeklyPlannerRepository? repository,
    FirestoreSyncService? firestoreSync,
  })  : _repository = repository ?? WeeklyPlannerRepository(),
        _firestoreSync = firestoreSync;

  FirestoreSyncService? get _sync {
    if (_firestoreSync != null) return _firestoreSync;
    try {
      return FirestoreSyncService();
    } catch (_) {
      return null;
    }
  }

  StreamSubscription<List<WeeklyLimit>>? _firestoreSubscription;

  List<WeeklyPlannerEntry> _entries = [];
  List<DaySpend> _weekDays = [];
  double _totalWeekSpent = 0;
  double _totalWeekLimit = 0;
  int? _lastFingerprint;
  String? _lastWeekKey;
  List<TransactionRecord>? _cachedTransactions;

  List<WeeklyPlannerEntry> get entries => _entries;
  List<DaySpend> get weekDays => _weekDays;
  double get totalWeekSpent => _totalWeekSpent;
  double get totalWeekLimit => _totalWeekLimit;
  bool get hasLimits => _entries.isNotEmpty;

  /// Budget surplus: amount unspent under the configured weekly limit.
  double get weeklyBudgetSurplus =>
      (_totalWeekLimit - _totalWeekSpent).clamp(0.0, double.infinity);

  Future<void> load() async {
    await _reloadLocal();
    _subscribeToFirestore();
  }

  void _subscribeToFirestore() {
    final sync = _sync;
    if (sync == null || !sync.isAuthenticated) return;
    _firestoreSubscription?.cancel();
    final expectedSession = sync.currentSession;

    _firestoreSubscription = sync.weeklyLimitsStream().listen(
      (remoteLimits) async {
        if (!sync.currentSession.matches(expectedSession)) return;
        for (final r in remoteLimits) {
          await _repository.upsert(r);
        }
        await _reloadLocal();
      },
      onError: (Object e) {
        AppLogger.warn('WeeklyPlanner firestore stream error: $e', label: 'WeeklyPlanner');
      },
    );
  }

  Future<void> _reloadLocal() async {
    await _repository.migrateFromSharedPreferencesIfNeeded();
    final limits = await _repository.getAll();
    final now = DateTime.now();
    final currentWeekStart = CalendarUtils.getWeekStart(now);

    // Group and resolve effective limit per category for current week.
    // One-off limit designated specifically for current week overrides recurring baseline.
    final effectiveLimitsByCategory = <String, WeeklyLimit>{};
    for (final l in limits) {
      if (!l.isActive) continue;
      if (l.recurrencePolicy == WeeklyRecurrencePolicy.oneOff) {
        if (l.periodStart != null) {
          final limitWeekStart = CalendarUtils.getWeekStart(l.periodStart!);
          if (CalendarUtils.isSameWeek(limitWeekStart, currentWeekStart)) {
            effectiveLimitsByCategory[l.categoryId] = l;
          }
        }
      } else {
        if (!effectiveLimitsByCategory.containsKey(l.categoryId) ||
            effectiveLimitsByCategory[l.categoryId]!.recurrencePolicy != WeeklyRecurrencePolicy.oneOff) {
          effectiveLimitsByCategory[l.categoryId] = l;
        }
      }
    }

    _entries = effectiveLimitsByCategory.values.map((l) {
      return WeeklyPlannerEntry(
        categoryId: l.categoryId,
        categoryName: l.categoryName,
        weeklyLimit: l.weeklyLimit,
        recurrencePolicy: l.recurrencePolicy,
        periodStart: l.periodStart,
      );
    }).toList();

    _totalWeekLimit = _entries.fold(0.0, (s, e) => s + e.weeklyLimit);

    if (_cachedTransactions != null) {
      _computeSpending(_cachedTransactions!, force: true);
    }
    notifyListeners();
  }

  Future<void> setLimit({
    required String categoryId,
    required String categoryName,
    required double weeklyLimit,
    WeeklyRecurrencePolicy recurrencePolicy = WeeklyRecurrencePolicy.recurring,
    DateTime? periodStart,
  }) async {
    if (weeklyLimit <= 0) {
      throw ArgumentError('Weekly limit must be greater than zero');
    }

    final now = DateTime.now();
    final effectivePeriodStart = recurrencePolicy == WeeklyRecurrencePolicy.oneOff
        ? (periodStart != null ? CalendarUtils.getWeekStart(periodStart) : CalendarUtils.getWeekStart(now))
        : null;

    final limit = WeeklyLimit(
      id: _uuid.v4(),
      categoryId: categoryId,
      categoryName: categoryName,
      weeklyLimit: weeklyLimit,
      createdAt: now,
      updatedAt: now,
      recurrencePolicy: recurrencePolicy,
      periodStart: effectivePeriodStart,
    );

    await _repository.upsert(limit);

    final sync = _sync;
    if (sync != null && sync.isAuthenticated) {
      unawaited(sync.upsertWeeklyLimit(limit).catchError((e) {
        AppLogger.warn('Failed to sync weekly limit to Firestore: $e', label: 'WeeklyPlanner');
      }));
    }

    await _reloadLocal();

    unawaited(
      AlertEvaluationCoordinator().onWeeklyPlannerChanged(_entries),
    );
  }

  Future<void> removeLimit(String categoryId, {String? ruleId}) async {
    await _repository.delete(categoryId, ruleId: ruleId);

    final sync = _sync;
    if (sync != null && sync.isAuthenticated) {
      unawaited(sync.deleteWeeklyLimit(categoryId).catchError((e) {
        AppLogger.warn('Failed to delete weekly limit from Firestore: $e', label: 'WeeklyPlanner');
      }));
    }

    await _reloadLocal();

    unawaited(
      AlertEvaluationCoordinator().onWeeklyPlannerChanged(_entries),
    );
  }

  /// Refreshes weekly spent calculations from ledger transactions.
  /// Uses deterministic content fingerprinting instead of fragile instance identity.
  void refreshFromTransactions(List<TransactionRecord> transactions) {
    _computeSpending(transactions, force: false);
  }

  void _computeSpending(
    List<TransactionRecord> transactions, {
    required bool force,
  }) {
    _cachedTransactions = transactions;
    final now = DateTime.now();
    final currentWeekKey = CalendarUtils.weekKey(now);
    final fingerprint = _computeTransactionFingerprint(transactions);

    if (!force &&
        _lastFingerprint == fingerprint &&
        _lastWeekKey == currentWeekKey) {
      return; // Content and week are identical; skip re-computation safely
    }

    _lastFingerprint = fingerprint;
    _lastWeekKey = currentWeekKey;

    final weekStart = CalendarUtils.getWeekStart(now);
    final weekEnd = CalendarUtils.getWeekEnd(now);

    // 1. Compute 7-day daily breakdown for current week
    final weekDays = CalendarUtils.getWeekDays(now);
    _weekDays = weekDays.map((day) {
      final daySpent = transactions.where((t) {
        if (t.type != TransactionType.expense) return false;
        return t.date.year == day.year &&
            t.date.month == day.month &&
            t.date.day == day.day;
      }).fold(0.0, (s, t) => s + t.amount);
      return DaySpend(date: day, spent: daySpent);
    }).toList();

    // 2. Filter transactions in current week window [Monday 00:00:00, Sunday 23:59:59]
    final weekTxns = transactions.where((t) {
      if (t.type != TransactionType.expense) return false;
      return !t.date.isBefore(weekStart) && !t.date.isAfter(weekEnd);
    }).toList();

    // 3. Aggregate spend per planned category
    for (final entry in _entries) {
      entry.weeklySpent = weekTxns
          .where(
            (t) => t.categoryId.toLowerCase() == entry.categoryId.toLowerCase(),
          )
          .fold(0.0, (s, t) => s + t.amount);
    }

    _totalWeekSpent = _weekDays.fold(0.0, (s, d) => s + d.spent);

    unawaited(
      AlertEvaluationCoordinator().onWeeklyPlannerChanged(_entries),
    );

    notifyListeners();
  }

  /// Computes a deterministic content fingerprint of transactions.
  /// Includes every property affecting planner aggregation: id, amount, categoryId,
  /// date, type, and source. Uses commutative addition so list permutations
  /// preserve the cache while any mutation invalidates it.
  int _computeTransactionFingerprint(List<TransactionRecord> txns) {
    int hash = txns.length.hashCode;
    for (int i = 0; i < txns.length; i++) {
      final t = txns[i];
      final itemHash = Object.hash(
        t.id,
        (t.amount * 100).round(),
        t.categoryId,
        t.date.millisecondsSinceEpoch,
        t.type.index,
        t.source,
      );
      hash = (hash + itemHash) & 0x7FFFFFFF;
    }
    return hash;
  }

  Future<void> clearData() async {
    _firestoreSubscription?.cancel();
    _firestoreSubscription = null;
    _entries = [];
    _weekDays = [];
    _totalWeekSpent = 0;
    _totalWeekLimit = 0;
    _lastFingerprint = null;
    _lastWeekKey = null;
    _cachedTransactions = null;
    notifyListeners();
    await _repository.deleteAll();
  }

  @override
  void dispose() {
    _firestoreSubscription?.cancel();
    _firestoreSubscription = null;
    super.dispose();
  }
}
