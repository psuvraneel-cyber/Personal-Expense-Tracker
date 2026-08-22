import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/data/repositories/transaction_repository.dart';
import 'package:pet/services/firestore_sync_service.dart';
import 'package:pet/services/account_deletion_service.dart';
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
  }) : _repository = repository ?? TransactionRepository(),
       _firestoreSync = firestoreSync ?? FirestoreSyncService() {
    _loadLastSyncAt();
  }

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
  StreamSubscription<List<Map<String, dynamic>>>? _tombstoneSubscription;

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
        if (_firestoreSync.isAuthenticated) {
          final currentUserId = _firestoreSync.currentUserId;
          await _repository
              .migrateGuestSyncActions('guest_user', currentUserId)
              .catchError((Object e) {
                debugPrint('[Sync] Failed to migrate guest sync actions: $e');
              });
        }
        _transactions = await _repository.getAllTransactions();
        _invalidateAggregates();
        _applyFiltersAndSort();
      } catch (e) {
        debugPrint('Error loading transactions from SQLite: $e');
      }
      // Attach real-time listener in the background (non-blocking).
      _subscribeToFirestoreStream();
      // Process pending queue actions in background
      triggerSyncQueue();
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Subscribe to the Firestore real-time stream.
  /// Idempotent — cancels any existing subscription first.
  Future<void> _subscribeToFirestoreStream() async {
    if (AccountDeletionService.isDeletionInProgress) {
      debugPrint(
        '[Sync] Skip subscribing to Firestore streams: account deletion in progress',
      );
      return;
    }
    await _firestoreSubscription?.cancel();
    _firestoreSubscription = null;
    await _tombstoneSubscription?.cancel();
    _tombstoneSubscription = null;

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
          // Incrementally sync SQLite using safe LWW merge-upsert (no deletions).
          final localAll = await _repository.getAllTransactions().catchError(
            (_) => <TransactionRecord>[],
          );
          final localMap = {for (final t in localAll) t.id: t};

          final txnsToUpsert = <TransactionRecord>[];
          for (final r in remoteList) {
            final l = localMap[r.id];
            if (l == null) {
              txnsToUpsert.add(r);
            } else {
              // Last-Write-Wins (LWW) check: update local if remote is newer
              final rUpdated = r.updatedAt;
              final lUpdated = l.updatedAt;
              if (rUpdated != null &&
                  (lUpdated == null || rUpdated.isAfter(lUpdated))) {
                txnsToUpsert.add(r);
              }
            }
          }

          if (txnsToUpsert.isNotEmpty) {
            await _repository.insertTransactionsBatch(txnsToUpsert).catchError((
              Object e,
            ) {
              debugPrint(
                '[TransactionProvider] batch upsert remote rows failed: $e',
              );
            });
          }

          // Defensive logging for skipped deletes of local records not in bounded snapshot
          final remoteIds = remoteList.map((t) => t.id).toSet();
          final localIds = localAll.map((t) => t.id).toSet();
          final orphanIds = localIds
              .where((id) => !remoteIds.contains(id))
              .toList();
          if (orphanIds.isNotEmpty) {
            debugPrint(
              '[Sync] Bounded remote snapshot missing ${orphanIds.length} local transaction IDs. '
              'Preserving local rows (skipped delete) to prevent data loss of offline or out-of-bounds records.',
            );
          }

          // Load local authoritative merged list to populate UI
          _transactions = await _repository.getAllTransactions().catchError(
            (_) => <TransactionRecord>[],
          );
          _invalidateAggregates();
          _applyFiltersAndSort();

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

      // Subscribe to remote deletion tombstones for cross-device sync
      debugPrint(
        '[Sync] Subscribed to tombstonesStream for ${_firestoreSync.currentUserId}',
      );
      _tombstoneSubscription = _firestoreSync.tombstonesStream().listen(
        (tombstones) async {
          debugPrint(
            '[Sync] Tombstones event received for ${_firestoreSync.currentUserId}: $tombstones',
          );
          if (tombstones.isEmpty) return;

          final localAll = await _repository.getAllTransactions().catchError(
            (_) => <TransactionRecord>[],
          );
          final localMap = {for (final t in localAll) t.id: t};

          bool changed = false;
          for (final tomb in tombstones) {
            final tId = tomb['id'] as String?;
            if (tId == null) continue;

            final localTxn = localMap[tId];
            if (localTxn != null) {
              // Delete wins! Remove local row
              debugPrint(
                '[Sync] Tombstone received for $tId. Deleting local row (Delete-Wins policy).',
              );
              await _repository
                  .deleteTransaction(tId)
                  .catchError(
                    (e) => debugPrint(
                      'Failed to delete local row for tombstone: $e',
                    ),
                  );
              changed = true;
            }
          }

          if (changed) {
            _transactions = await _repository.getAllTransactions().catchError(
              (_) => <TransactionRecord>[],
            );
            _invalidateAggregates();
            _applyFiltersAndSort();
            notifyListeners();
          }
        },
        onError: (Object e) {
          debugPrint('[Firestore] tombstone stream error: $e');
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
    if (AccountDeletionService.isDeletionInProgress) {
      throw StateError('Account deletion in progress');
    }
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
      updatedAt: DateTime.now(),
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
    if (!kIsWeb) {
      final currentUserId = _firestoreSync.isAuthenticated
          ? _firestoreSync.currentUserId
          : 'guest_user';
      await _repository
          .enqueueSyncAction(
            const Uuid().v4(),
            transaction.id,
            'create',
            jsonEncode(transaction.toMap()),
            currentUserId,
          )
          .catchError(
            (Object e) => debugPrint('Sync queue enqueue failed: $e'),
          );

      triggerSyncQueue();
    } else {
      _setSyncStatus(SyncStatus.syncing);
      _firestoreSync
          .upsertTransaction(transaction)
          .then((_) => _setSyncStatus(SyncStatus.synced))
          .catchError((Object e) {
            debugPrint('[Sync] upsert failed: $e');
            _setSyncStatus(SyncStatus.error, error: e.toString());
          });
    }
  }

  Future<void> updateTransaction(TransactionRecord transaction) async {
    if (AccountDeletionService.isDeletionInProgress) {
      throw StateError('Account deletion in progress');
    }
    final updatedTxn = transaction.copyWith(updatedAt: DateTime.now());
    final index = _transactions.indexWhere((t) => t.id == updatedTxn.id);
    if (index != -1) {
      _transactions[index] = updatedTxn;
      _invalidateAggregates();
      _applyFiltersAndSort();
      notifyListeners();
    }

    if (!kIsWeb) {
      await _repository
          .updateTransaction(updatedTxn)
          .catchError((Object e) => debugPrint('SQLite update failed: $e'));
    }

    // Sync to Firestore
    if (!kIsWeb) {
      final currentUserId = _firestoreSync.isAuthenticated
          ? _firestoreSync.currentUserId
          : 'guest_user';
      await _repository
          .enqueueSyncAction(
            const Uuid().v4(),
            updatedTxn.id,
            'update',
            jsonEncode(updatedTxn.toMap()),
            currentUserId,
          )
          .catchError(
            (Object e) => debugPrint('Sync queue enqueue failed: $e'),
          );

      triggerSyncQueue();
    } else {
      _setSyncStatus(SyncStatus.syncing);
      _firestoreSync
          .upsertTransaction(updatedTxn)
          .then((_) => _setSyncStatus(SyncStatus.synced))
          .catchError((Object e) {
            debugPrint('[Sync] update failed: $e');
            _setSyncStatus(SyncStatus.error, error: e.toString());
          });
    }
  }

  Future<void> deleteTransaction(String id) async {
    if (AccountDeletionService.isDeletionInProgress) {
      throw StateError('Account deletion in progress');
    }
    _transactions.removeWhere((t) => t.id == id);
    _invalidateAggregates();
    _applyFiltersAndSort();
    notifyListeners();

    if (!kIsWeb) {
      await _repository
          .deleteTransaction(id)
          .catchError((Object e) => debugPrint('SQLite delete failed: $e'));
    }

    // Sync to Firestore
    if (!kIsWeb) {
      final currentUserId = _firestoreSync.isAuthenticated
          ? _firestoreSync.currentUserId
          : 'guest_user';
      final pending = await _repository.getPendingSyncActions(currentUserId);
      final hasPendingCreate = pending.any(
        (x) => x['transactionId'] == id && x['action'] == 'create',
      );

      if (hasPendingCreate) {
        debugPrint(
          '[SyncQueue] Compacting: removing pending create/update for deleted transaction $id',
        );
        final actionsToRemove = pending.where((x) => x['transactionId'] == id);
        for (final act in actionsToRemove) {
          await _repository.deleteSyncAction(act['id'] as String);
        }
      } else {
        await _repository
            .enqueueSyncAction(
              const Uuid().v4(),
              id,
              'delete',
              null,
              currentUserId,
            )
            .catchError(
              (Object e) => debugPrint('Sync queue enqueue failed: $e'),
            );

        triggerSyncQueue();
      }
    } else {
      _setSyncStatus(SyncStatus.syncing);
      _firestoreSync
          .deleteTransaction(id)
          .then((_) => _setSyncStatus(SyncStatus.synced))
          .catchError((Object e) {
            debugPrint('[Sync] delete failed: $e');
            _setSyncStatus(SyncStatus.error, error: e.toString());
          });
    }
  }

  void _setSyncStatus(SyncStatus status, {String? error}) {
    _syncStatus = status;
    if (status == SyncStatus.synced) {
      _lastSyncAt = DateTime.now();
      _syncError = null;
      SharedPreferences.getInstance()
          .then((prefs) {
            prefs.setString('lastSyncAt', _lastSyncAt!.toIso8601String());
          })
          .catchError((Object e) {
            debugPrint('[Sync] Failed to save lastSyncTime: $e');
          });
    } else if (status == SyncStatus.error) {
      _syncError = error;
    }
    notifyListeners();
  }

  Future<void> _loadLastSyncAt() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timeStr = prefs.getString('lastSyncAt');
      if (timeStr != null) {
        _lastSyncAt = DateTime.parse(timeStr);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[Sync] Failed to load lastSyncTime: $e');
    }
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
    _filterPaymentMethod = paymentMethod != null
        ? PaymentMethod.fromJson(paymentMethod)
        : null;
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
      final localAll = await _repository.getAllTransactions().catchError(
        (_) => <TransactionRecord>[],
      );
      final localMap = {for (final t in localAll) t.id: t};

      final txnsToUpsert = <TransactionRecord>[];
      for (final remoteTxn in remoteTransactions) {
        final l = localMap[remoteTxn.id];
        if (l == null) {
          txnsToUpsert.add(remoteTxn);
        } else {
          // Last-Write-Wins (LWW) check: update local if remote is newer
          final rUpdated = remoteTxn.updatedAt;
          final lUpdated = l.updatedAt;
          if (rUpdated != null &&
              (lUpdated == null || rUpdated.isAfter(lUpdated))) {
            txnsToUpsert.add(remoteTxn);
          }
        }
      }

      if (txnsToUpsert.isNotEmpty) {
        await _repository.insertTransactionsBatch(txnsToUpsert);
        debugPrint(
          '[Sync] Restored/updated ${txnsToUpsert.length} transactions from Firestore',
        );
      } else {
        debugPrint('[Sync] All remote transactions already up-to-date locally');
      }

      // Defensive logging for skipped deletes of local records not in bounded snapshot
      final remoteIds = remoteTransactions.map((t) => t.id).toSet();
      final localIds = localAll.map((t) => t.id).toSet();
      final orphanIds = localIds
          .where((id) => !remoteIds.contains(id))
          .toList();
      if (orphanIds.isNotEmpty) {
        debugPrint(
          '[Sync] Bounded remote snapshot missing ${orphanIds.length} local transaction IDs. '
          'Preserving local rows (skipped delete) to prevent data loss.',
        );
      }

      // Load local authoritative merged list to populate UI
      _transactions = await _repository.getAllTransactions().catchError(
        (_) => <TransactionRecord>[],
      );
      _invalidateAggregates();
      _applyFiltersAndSort();
      notifyListeners();
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
          .fold<double>(0.0, (total, t) => total + t.amount);
    }
    return _repository.getSpentInCategory(categoryId, month, year);
  }

  /// Clear all in-memory state, cancel Firestore subscriptions,
  /// and wipe the local SQLite transactions table.
  /// Called on sign-out to prevent data leaking between accounts.
  Future<void> clearData() async {
    _firestoreSubscription?.cancel();
    _firestoreSubscription = null;
    _tombstoneSubscription?.cancel();
    _tombstoneSubscription = null;
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
    SharedPreferences.getInstance()
        .then((prefs) {
          prefs.remove('lastSyncAt');
        })
        .catchError((Object e) {
          debugPrint('[Sync] Failed to remove lastSyncTime: $e');
        });
    _invalidateAggregates();
    notifyListeners();

    // Wipe SQLite so the next user doesn't see this user's data.
    if (!kIsWeb) {
      await _repository.deleteAllTransactions().catchError(
        (Object e) => debugPrint('SQLite clear failed: $e'),
      );
    }
  }

  bool _isProcessingSyncQueue = false;
  bool _syncQueueNeedsProcessing = false;

  /// Process any pending actions in the SQLite sync queue.
  /// Uses exponential backoff for retries to avoid duplicate processes or retry storms.
  Future<void> triggerSyncQueue({bool force = false}) async {
    if (kIsWeb) return;
    if (AccountDeletionService.isDeletionInProgress) {
      debugPrint('[SyncQueue] Skip trigger — account deletion in progress');
      return;
    }
    if (!_firestoreSync.isAuthenticated) {
      debugPrint('[SyncQueue] Skip trigger — user not authenticated');
      return;
    }
    if (_isProcessingSyncQueue) {
      debugPrint('[SyncQueue] Already processing — scheduling next pass');
      _syncQueueNeedsProcessing = true;
      return;
    }

    _isProcessingSyncQueue = true;
    _syncQueueNeedsProcessing = false;
    _setSyncStatus(SyncStatus.syncing);

    try {
      final currentUserId = _firestoreSync.currentUserId;

      while (true) {
        final pendingActions = await _repository.getPendingSyncActions(
          currentUserId,
        );
        if (pendingActions.isEmpty) {
          _setSyncStatus(SyncStatus.synced);
          break;
        }

        debugPrint(
          '[SyncQueue] Found ${pendingActions.length} pending actions to process',
        );
        bool processedAny = false;

        for (final action in pendingActions) {
          final actionId = action['id'] as String;
          final tId = action['transactionId'] as String;
          final act = action['action'] as String;
          final payloadStr = action['payload'] as String?;
          final retryCount = action['retryCount'] as int? ?? 0;
          final lastAttemptAt = action['lastAttemptAt'] as int? ?? 0;

          // Exponential backoff check: skip if backoff duration has not elapsed yet
          if (!force && retryCount > 0) {
            final now = DateTime.now().millisecondsSinceEpoch;
            final backoffMs =
                (1 << retryCount.clamp(0, 10)) *
                5000; // 5s, 10s, 20s, 40s... capped at ~5120s (~85m)
            if (now - lastAttemptAt < backoffMs) {
              debugPrint(
                '[SyncQueue] Skipping action $actionId due to backoff window',
              );
              continue;
            }
          }

          processedAny = true;

          try {
            if (act == 'create' || act == 'update') {
              if (payloadStr == null) {
                throw StateError(
                  'Payload is null for write sync action $actionId',
                );
              }
              final map = jsonDecode(payloadStr) as Map<String, dynamic>;
              final txn = TransactionRecord.fromMap(map);
              await _firestoreSync.upsertTransaction(txn);
            } else if (act == 'delete') {
              await _firestoreSync.deleteTransaction(tId);
              // Write explicit deletion tombstone
              await _firestoreSync.createTombstone(tId);
            }

            // Success: delete action from queue
            await _repository.deleteSyncAction(actionId);
            debugPrint(
              '[SyncQueue] Action $actionId ($act) synced successfully',
            );
          } catch (e) {
            debugPrint('[SyncQueue] Action $actionId ($act) sync failed: $e');
            await _repository.incrementSyncRetry(actionId, e.toString());
            _setSyncStatus(SyncStatus.error, error: e.toString());
            // Stop processing subsequent actions in the queue to observe order and allow backoff
            processedAny = false;
            break;
          }
        }

        // If no actions could be processed (e.g. all skipped due to backoff or first failed), exit loop
        if (!processedAny) {
          break;
        }
      }
    } catch (e) {
      debugPrint('[SyncQueue] Unexpected error in triggerSyncQueue: $e');
      _setSyncStatus(SyncStatus.error, error: e.toString());
    } finally {
      _isProcessingSyncQueue = false;
      if (_syncQueueNeedsProcessing) {
        _syncQueueNeedsProcessing = false;
        // Schedule next pass
        Future.microtask(() => triggerSyncQueue(force: force));
      }
    }
  }

  @override
  void dispose() {
    _firestoreSubscription?.cancel();
    _tombstoneSubscription?.cancel();
    super.dispose();
  }
}
