import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/data/repositories/transaction_repository.dart';
import 'package:pet/services/firestore_sync_service.dart';
import 'package:uuid/uuid.dart';

/// Sync status exposed to the UI for the sync indicator chip.
enum SyncStatus { idle, syncing, synced, error }

class TransactionProvider extends ChangeNotifier {
  final TransactionRepository _repository;
  final FirestoreSyncService _firestoreSync;
  final Uuid _uuid = const Uuid();

  TransactionProvider({
    TransactionRepository? repository,
    FirestoreSyncService? firestoreSync,
  })  : _repository = repository ?? TransactionRepository(),
        _firestoreSync = firestoreSync ?? FirestoreSyncService();

  List<TransactionRecord> _transactions = [];
  List<TransactionRecord> _filteredTransactions = [];
  bool _isLoading = false;
  String _searchQuery = '';
  String? _filterCategoryId;
  DateTime? _filterStartDate;
  DateTime? _filterEndDate;
  double? _filterMinAmount;
  double? _filterMaxAmount;
  TransactionType? _filterType;
  PaymentMethod? _filterPaymentMethod;
  String _sortBy = 'date'; // 'date', 'amount', 'category'
  bool _sortAscending = false;

  // Sync status
  SyncStatus _syncStatus = SyncStatus.idle;
  DateTime? _lastSyncAt;
  String? _syncError;
  StreamSubscription<List<TransactionRecord>>? _firestoreSubscription;

  // Current month/year for dashboard
  int _currentMonth = DateTime.now().month;
  int _currentYear = DateTime.now().year;

  // Cached computed values — invalidated on data or month change
  double _cachedTotalIncome = 0;
  double _cachedTotalExpenses = 0;
  Map<String, double> _cachedCategorySpending = {};
  Map<int, double> _cachedDailySpending = {};
  bool _aggregatesDirty = true;

  List<TransactionRecord> get transactions => _filteredTransactions;
  List<TransactionRecord> get allTransactions => _transactions;
  bool get isLoading => _isLoading;
  String get searchQuery => _searchQuery;
  int get currentMonth => _currentMonth;
  int get currentYear => _currentYear;
  String get sortBy => _sortBy;
  bool get sortAscending => _sortAscending;

  // Sync status getters
  SyncStatus get syncStatus => _syncStatus;
  DateTime? get lastSyncAt => _lastSyncAt;
  String? get syncError => _syncError;

  void _recomputeAggregatesIfNeeded() {
    if (!_aggregatesDirty) return;
    _aggregatesDirty = false;

    double income = 0;
    double expenses = 0;
    final Map<String, double> catSpending = {};
    final Map<int, double> daySpending = {};

    for (final t in _transactions) {
      if (t.date.month != _currentMonth || t.date.year != _currentYear) {
        continue;
      }
      if (t.type == TransactionType.income) {
        income += t.amount;
      } else if (t.type == TransactionType.expense) {
        expenses += t.amount;
        catSpending[t.categoryId] = (catSpending[t.categoryId] ?? 0) + t.amount;
        daySpending[t.date.day] = (daySpending[t.date.day] ?? 0) + t.amount;
      }
    }

    _cachedTotalIncome = income;
    _cachedTotalExpenses = expenses;
    _cachedCategorySpending = catSpending;
    _cachedDailySpending = daySpending;
  }

  double get totalIncome {
    _recomputeAggregatesIfNeeded();
    return _cachedTotalIncome;
  }

  double get totalExpenses {
    _recomputeAggregatesIfNeeded();
    return _cachedTotalExpenses;
  }

  double get totalSavings => totalIncome - totalExpenses;

  Map<String, double> get categoryWiseSpending {
    _recomputeAggregatesIfNeeded();
    return _cachedCategorySpending;
  }

  Map<int, double> get dailySpending {
    _recomputeAggregatesIfNeeded();
    return _cachedDailySpending;
  }

  void _invalidateAggregates() {
    _aggregatesDirty = true;
  }

  /// Load transactions.
  ///
  /// On web (sqflite unavailable), and when authenticated, subscribes to the
  /// Firestore real-time stream so the UI stays in sync automatically.
  /// On mobile/desktop falls through to SQLite as before.
  Future<void> loadTransactions() async {
    _isLoading = true;
    notifyListeners();

    if (kIsWeb) {
      // Web: use Firestore real-time stream as the source of truth.
      await _subscribeToFirestoreStream();
    } else {
      // Mobile/desktop: load from SQLite, then attach Firestore listener
      // for real-time cross-device updates in the background.
      try {
        _transactions = await _repository.getAllTransactions();
        _invalidateAggregates();
        _applyFiltersAndSort();
      } catch (e) {
        debugPrint('Error loading transactions from SQLite: $e');
      }
      // Attach real-time listener in the background (non-blocking).
      _subscribeToFirestoreStream();
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Subscribe to the Firestore real-time stream.
  /// Idempotent — cancels any existing subscription first.
  Future<void> _subscribeToFirestoreStream() async {
    await _firestoreSubscription?.cancel();
    _firestoreSubscription = null;

    final stream = _firestoreSync.transactionsStream();

    // On web, we await the first event before returning so loadTransactions()
    // resolves with data already populated.
    if (kIsWeb) {
      final completer = Completer<void>();
      _firestoreSubscription = stream.listen(
        (remoteList) {
          _transactions = remoteList;
          _invalidateAggregates();
          _applyFiltersAndSort();
          _syncStatus = SyncStatus.synced;
          _lastSyncAt = DateTime.now();
          _syncError = null;
          notifyListeners();
          if (!completer.isCompleted) completer.complete();
        },
        onError: (Object e) {
          debugPrint('[Firestore] stream error: $e');
          _syncStatus = SyncStatus.error;
          _syncError = e.toString();
          notifyListeners();
          if (!completer.isCompleted) completer.complete();
        },
      );
      // Wait up to 8 seconds for the first Firestore response.
      await completer.future.timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          debugPrint('[Firestore] stream first event timed out');
        },
      );
    } else {
      // Non-web: always replace in-memory data from Firestore (UID-scoped),
      // and incrementally sync SQLite so it stays consistent as a cache.
      _firestoreSubscription = stream.listen(
        (remoteList) async {
          // Always fully replace in-memory data from Firestore.
          _transactions = remoteList;
          _invalidateAggregates();
          _applyFiltersAndSort();

          // Incrementally sync SQLite: remove stale, add new.
          final remoteIds = remoteList.map((t) => t.id).toSet();
          final localAll = await _repository.getAllTransactions().catchError(
            (_) => <TransactionRecord>[],
          );
          final localIds = localAll.map((t) => t.id).toSet();

          // Delete local rows that are no longer in remote (batch).
          final orphanIds = localIds.where((id) => !remoteIds.contains(id)).toList();
          if (orphanIds.isNotEmpty) {
            await _repository.deleteTransactionsBatch(orphanIds).catchError((
              Object e,
            ) {
              debugPrint(
                '[TransactionProvider] batch delete orphan rows failed: $e',
              );
            });
          }
          final txnsToInsert = <TransactionRecord>[];
          for (final r in remoteList) {
            if (!localIds.contains(r.id)) {
              txnsToInsert.add(r);
            }
          }
          if (txnsToInsert.isNotEmpty) {
            await _repository.insertTransactionsBatch(txnsToInsert).catchError((Object e) {
              debugPrint(
                '[TransactionProvider] batch insert remote rows failed: $e',
              );
            });
          }

          _syncStatus = SyncStatus.synced;
          _lastSyncAt = DateTime.now();
          _syncError = null;
          notifyListeners();
        },
        onError: (Object e) {
          debugPrint('[Firestore] stream error: $e');
          _syncStatus = SyncStatus.error;
          _syncError = e.toString();
          notifyListeners();
        },
      );
    }
  }

  Future<void> addTransaction({
    required double amount,
    required TransactionType type,
    required String categoryId,
    required DateTime date,
    String note = '',
    PaymentMethod paymentMethod = PaymentMethod.upi,
    bool isRecurring = false,
    RecurringFrequency? recurringFrequency,
    String? merchantName,
    String? taxCategory,
    TransactionSource source = TransactionSource.manual,
    String? accountId,
  }) async {
    final transaction = TransactionRecord(
      id: _uuid.v4(),
      amount: amount,
      type: type,
      categoryId: categoryId,
      date: date,
      note: note,
      paymentMethod: paymentMethod,
      isRecurring: isRecurring,
      recurringFrequency: recurringFrequency,
      merchantName: merchantName,
      taxCategory: taxCategory,
      source: source,
      accountId: accountId,
    );

    // Optimistic local update
    _transactions.insert(0, transaction);
    _invalidateAggregates();
    _applyFiltersAndSort();
    notifyListeners();

    // Persist locally (skip on web — SQLite unavailable)
    if (!kIsWeb) {
      await _repository
          .insertTransaction(transaction)
          .catchError((Object e) => debugPrint('SQLite insert failed: $e'));
    }

    // Sync to Firestore
    _setSyncStatus(SyncStatus.syncing);
    _firestoreSync
        .upsertTransaction(transaction)
        .then((_) => _setSyncStatus(SyncStatus.synced))
        .catchError((Object e) {
          debugPrint('[Sync] upsert failed: $e');
          _setSyncStatus(SyncStatus.error, error: e.toString());
        });
  }

  Future<void> updateTransaction(TransactionRecord transaction) async {
    final index = _transactions.indexWhere((t) => t.id == transaction.id);
    if (index != -1) {
      _transactions[index] = transaction;
      _invalidateAggregates();
      _applyFiltersAndSort();
      notifyListeners();
    }

    if (!kIsWeb) {
      await _repository
          .updateTransaction(transaction)
          .catchError((Object e) => debugPrint('SQLite update failed: $e'));
    }

    _setSyncStatus(SyncStatus.syncing);
    _firestoreSync
        .upsertTransaction(transaction)
        .then((_) => _setSyncStatus(SyncStatus.synced))
        .catchError((Object e) {
          debugPrint('[Sync] update failed: $e');
          _setSyncStatus(SyncStatus.error, error: e.toString());
        });
  }

  Future<void> deleteTransaction(String id) async {
    _transactions.removeWhere((t) => t.id == id);
    _invalidateAggregates();
    _applyFiltersAndSort();
    notifyListeners();

    if (!kIsWeb) {
      await _repository
          .deleteTransaction(id)
          .catchError((Object e) => debugPrint('SQLite delete failed: $e'));
    }

    _setSyncStatus(SyncStatus.syncing);
    _firestoreSync
        .deleteTransaction(id)
        .then((_) => _setSyncStatus(SyncStatus.synced))
        .catchError((Object e) {
          debugPrint('[Sync] delete failed: $e');
          _setSyncStatus(SyncStatus.error, error: e.toString());
        });
  }

  void _setSyncStatus(SyncStatus status, {String? error}) {
    _syncStatus = status;
    if (status == SyncStatus.synced) {
      _lastSyncAt = DateTime.now();
      _syncError = null;
    } else if (status == SyncStatus.error) {
      _syncError = error;
    }
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    _applyFiltersAndSort();
    notifyListeners();
  }

  void setFilters({
    String? categoryId,
    DateTime? startDate,
    DateTime? endDate,
    double? minAmount,
    double? maxAmount,
    String? type,
    String? paymentMethod,
  }) {
    _filterCategoryId = categoryId;
    _filterStartDate = startDate;
    _filterEndDate = endDate;
    _filterMinAmount = minAmount;
    _filterMaxAmount = maxAmount;
    _filterType = type != null ? TransactionType.fromJson(type) : null;
    _filterPaymentMethod = paymentMethod != null ? PaymentMethod.fromJson(paymentMethod) : null;
    _applyFiltersAndSort();
    notifyListeners();
  }

  void clearFilters() {
    _filterCategoryId = null;
    _filterStartDate = null;
    _filterEndDate = null;
    _filterMinAmount = null;
    _filterMaxAmount = null;
    _filterType = null;
    _filterPaymentMethod = null;
    _searchQuery = '';
    _applyFiltersAndSort();
    notifyListeners();
  }

  void setSortBy(String sortBy, {bool? ascending}) {
    _sortBy = sortBy;
    if (ascending != null) _sortAscending = ascending;
    _applyFiltersAndSort();
    notifyListeners();
  }

  void setCurrentMonth(int month, int year) {
    _currentMonth = month;
    _currentYear = year;
    _invalidateAggregates();
    notifyListeners();
  }

  void _applyFiltersAndSort() {
    final bool hasSearch = _searchQuery.isNotEmpty;
    final String? query = hasSearch ? _searchQuery.toLowerCase() : null;
    final bool hasAnyFilter =
        hasSearch ||
        _filterCategoryId != null ||
        _filterStartDate != null ||
        _filterEndDate != null ||
        _filterMinAmount != null ||
        _filterMaxAmount != null ||
        _filterType != null ||
        _filterPaymentMethod != null;

    final List<TransactionRecord> filtered;
    if (!hasAnyFilter) {
      filtered = List<TransactionRecord>.from(_transactions);
    } else {
      filtered = <TransactionRecord>[];
      for (final t in _transactions) {
        if (query != null &&
            !t.note.toLowerCase().contains(query) &&
            !t.paymentMethod.displayName.toLowerCase().contains(query) &&
            !t.amount.toString().contains(query)) {
          continue;
        }
        if (_filterCategoryId != null && t.categoryId != _filterCategoryId) {
          continue;
        }
        if (_filterStartDate != null &&
            !t.date.isAfter(
              _filterStartDate!.subtract(const Duration(days: 1)),
            )) {
          continue;
        }
        if (_filterEndDate != null &&
            !t.date.isBefore(_filterEndDate!.add(const Duration(days: 1)))) {
          continue;
        }
        if (_filterMinAmount != null && t.amount < _filterMinAmount!) continue;
        if (_filterMaxAmount != null && t.amount > _filterMaxAmount!) continue;
        if (_filterType != null && t.type != _filterType) continue;
        if (_filterPaymentMethod != null &&
            t.paymentMethod != _filterPaymentMethod) {
          continue;
        }
        filtered.add(t);
      }
    }

    switch (_sortBy) {
      case 'date':
        filtered.sort(
          (a, b) => _sortAscending
              ? a.date.compareTo(b.date)
              : b.date.compareTo(a.date),
        );
        break;
      case 'amount':
        filtered.sort(
          (a, b) => _sortAscending
              ? a.amount.compareTo(b.amount)
              : b.amount.compareTo(a.amount),
        );
        break;
      case 'category':
        filtered.sort(
          (a, b) => _sortAscending
              ? a.categoryId.compareTo(b.categoryId)
              : b.categoryId.compareTo(a.categoryId),
        );
        break;
    }

    _filteredTransactions = filtered;
  }

  /// Pull transactions from Firestore and merge into local SQLite.
  /// Called after sign-in when the local database may be empty (e.g. fresh install).
  ///
  /// Skips silently if the user is not authenticated (avoids ghost errors).
  Future<void> syncFromFirestore() async {
    if (!_firestoreSync.isAuthenticated) {
      debugPrint('[Sync] Skipping — user not authenticated');
      return;
    }
    try {
      debugPrint('[Sync] Starting Firestore sync...');
      _setSyncStatus(SyncStatus.syncing);

      final remoteTransactions = await _firestoreSync.fetchAllTransactions();
      debugPrint(
        '[Sync] Fetched ${remoteTransactions.length} remote transactions',
      );
      if (remoteTransactions.isEmpty) {
        _setSyncStatus(SyncStatus.synced);
        return;
      }

      if (kIsWeb) {
        // On web, just populate in-memory directly from Firestore
        _transactions = remoteTransactions;
        _invalidateAggregates();
        _applyFiltersAndSort();
        _setSyncStatus(SyncStatus.synced);
        notifyListeners();
        return;
      }

      // Mobile/desktop: merge into SQLite
      if (_transactions.isEmpty) {
        _transactions = await _repository.getAllTransactions();
      }

      final localIds = _transactions.map((t) => t.id).toSet();
      final txnsToInsert = <TransactionRecord>[];

      for (final remoteTxn in remoteTransactions) {
        if (!localIds.contains(remoteTxn.id)) {
          txnsToInsert.add(remoteTxn);
        }
      }

      if (txnsToInsert.isNotEmpty) {
        await _repository.insertTransactionsBatch(txnsToInsert);
        debugPrint('[Sync] Restored ${txnsToInsert.length} transactions from Firestore');
        _transactions = await _repository.getAllTransactions();
        _invalidateAggregates();
        _applyFiltersAndSort();
        notifyListeners();
      } else {
        debugPrint('[Sync] All transactions already present locally');
      }
      _setSyncStatus(SyncStatus.synced);
    } catch (e) {
      debugPrint('[Sync] syncFromFirestore error: $e');
      _setSyncStatus(SyncStatus.error, error: e.toString());
    }
  }

  Future<double> getSpentInCategory(
    String categoryId,
    int month,
    int year,
  ) async {
    if (kIsWeb) {
      // Compute directly from in-memory transactions on web
      return _transactions
          .where(
            (t) =>
                t.categoryId == categoryId &&
                t.type == TransactionType.expense &&
                t.date.month == month &&
                t.date.year == year,
          )
          .fold<double>(0.0, (sum, t) => sum + t.amount);
    }
    return _repository.getSpentInCategory(categoryId, month, year);
  }

  /// Clear all in-memory state, cancel Firestore subscriptions,
  /// and wipe the local SQLite transactions table.
  /// Called on sign-out to prevent data leaking between accounts.
  Future<void> clearData() async {
    _firestoreSubscription?.cancel();
    _firestoreSubscription = null;
    _transactions = [];
    _filteredTransactions = [];
    _searchQuery = '';
    _filterCategoryId = null;
    _filterStartDate = null;
    _filterEndDate = null;
    _filterMinAmount = null;
    _filterMaxAmount = null;
    _filterType = null;
    _filterPaymentMethod = null;
    _sortBy = 'date';
    _sortAscending = false;
    _syncStatus = SyncStatus.idle;
    _lastSyncAt = null;
    _syncError = null;
    _invalidateAggregates();
    notifyListeners();

    // Wipe SQLite so the next user doesn't see this user's data.
    if (!kIsWeb) {
      await _repository.deleteAllTransactions().catchError(
        (Object e) => debugPrint('SQLite clear failed: $e'),
      );
    }
  }

  @override
  void dispose() {
    _firestoreSubscription?.cancel();
    super.dispose();
  }
}
