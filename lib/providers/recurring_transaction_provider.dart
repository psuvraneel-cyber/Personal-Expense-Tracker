import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:pet/core/utils/app_logger.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/recurring_rule.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/data/repositories/recurring_transaction_repository.dart';
import 'package:pet/services/account_deletion_service.dart';
import 'package:pet/services/firestore_sync_service.dart';
import 'package:pet/services/recurring_transaction_service.dart';

/// Provider for managing recurring transaction rules and occurrences.
class RecurringTransactionProvider extends ChangeNotifier {
  final RecurringTransactionRepository _repository;
  final RecurringTransactionService _service;
  final FirestoreSyncService _firestoreSync;

  RecurringTransactionProvider({
    RecurringTransactionRepository? repository,
    RecurringTransactionService? service,
    FirestoreSyncService? firestoreSync,
  })  : _repository = repository ?? RecurringTransactionRepository(),
        _service = service ?? RecurringTransactionService(),
        _firestoreSync = firestoreSync ?? FirestoreSyncService();

  List<RecurringRule> _rules = [];
  bool _isLoading = false;
  StreamSubscription<List<RecurringRule>>? _firestoreSubscription;

  List<RecurringRule> get allRules => _rules;
  List<RecurringRule> get activeRules => _rules.where((r) => r.isActive).toList();
  bool get isLoading => _isLoading;

  bool _disposed = false;

  /// Load all recurring rules from local DB and subscribe to Firestore sync.
  Future<void> loadRules() async {
    if (_disposed) return;
    _isLoading = true;
    notifyListeners();

    try {
      if (!kIsWeb) {
        _rules = await _repository.getAllRules();
        if (_disposed) return;
        notifyListeners();
      }
      await _subscribeToFirestore();
    } catch (e) {
      AppLogger.error('Failed to load recurring rules', error: e, label: 'RecurringProvider');
    } finally {
      if (!_disposed) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Subscribe to Firestore real-time stream of recurring rules.
  Future<void> _subscribeToFirestore() async {
    if (AccountDeletionService.isDeletionInProgress || _disposed) return;
    await _firestoreSubscription?.cancel();
    _firestoreSubscription = null;

    if (!_firestoreSync.isAuthenticated) return;

    final stream = _firestoreSync.recurringRulesStream();
    _firestoreSubscription = stream.listen(
      (remoteRules) async {
        if (_disposed) return;
        try {
          if (remoteRules.isNotEmpty && !kIsWeb) {
            for (final rule in remoteRules) {
              await _repository.insertRule(rule);
            }
            if (_disposed) return;
            _rules = await _repository.getAllRules();
          } else if (kIsWeb) {
            _rules = remoteRules;
          }
          if (!_disposed) {
            notifyListeners();
          }
        } catch (e) {
          AppLogger.error('Failed to sync remote rules into SQLite', error: e, label: 'RecurringProvider');
        }
      },
      onError: (Object e) {
        AppLogger.error('Recurring rules Firestore stream error', error: e, label: 'RecurringProvider');
      },
    );
  }

  /// Evaluates and generates any due or missed recurring occurrences.
  /// Returns the list of generated [TransactionRecord]s.
  Future<List<TransactionRecord>> checkAndGenerateDue({DateTime? now}) async {
    try {
      final generated = await _service.generateDueOccurrences(now: now);
      if (generated.isNotEmpty) {
        _rules = await _repository.getAllRules();
        notifyListeners();
      }
      return generated;
    } catch (e) {
      AppLogger.error('Error during checkAndGenerateDue', error: e, label: 'RecurringProvider');
      return [];
    }
  }

  /// Creates a new recurring rule and optionally its first transaction occurrence.
  Future<({RecurringRule rule, TransactionRecord? firstTransaction})> createRule({
    required double amount,
    required TransactionType type,
    required String categoryId,
    required RecurringFrequency frequency,
    required DateTime startDate,
    DateTime? endDate,
    int interval = 1,
    String note = '',
    PaymentMethod paymentMethod = PaymentMethod.upi,
    String? merchantName,
    String? taxCategory,
    TransactionSource source = TransactionSource.manual,
    String? accountId,
    bool generateFirstOccurrenceImmediately = true,
  }) async {
    final userId = _firestoreSync.isAuthenticated ? _firestoreSync.currentUserId : null;
    final result = await _service.createRule(
      amount: amount,
      type: type,
      categoryId: categoryId,
      frequency: frequency,
      startDate: startDate,
      endDate: endDate,
      interval: interval,
      note: note,
      paymentMethod: paymentMethod,
      merchantName: merchantName,
      taxCategory: taxCategory,
      source: source,
      accountId: accountId,
      userId: userId,
      generateFirstOccurrenceImmediately: generateFirstOccurrenceImmediately,
    );

    if (_firestoreSync.isAuthenticated) {
      _firestoreSync.upsertRecurringRule(result.rule).catchError((Object e) {
        AppLogger.error('Failed to sync new recurring rule to Firestore', error: e, label: 'RecurringProvider');
      });
    }

    _rules = await _repository.getAllRules();
    notifyListeners();
    return result;
  }

  /// Stops / deactivates a recurring rule.
  Future<void> stopRule(String ruleId) async {
    await _service.stopRule(ruleId);
    final updated = await _repository.getRuleById(ruleId);
    if (updated != null && _firestoreSync.isAuthenticated) {
      _firestoreSync.upsertRecurringRule(updated).catchError((Object e) {
        AppLogger.error('Failed to sync stopped rule to Firestore', error: e, label: 'RecurringProvider');
      });
    }
    _rules = await _repository.getAllRules();
    notifyListeners();
  }

  /// Updates an existing recurring rule.
  Future<void> updateRule(RecurringRule rule) async {
    await _service.updateRule(rule);
    if (_firestoreSync.isAuthenticated) {
      _firestoreSync.upsertRecurringRule(rule).catchError((Object e) {
        AppLogger.error('Failed to sync updated rule to Firestore', error: e, label: 'RecurringProvider');
      });
    }
    _rules = await _repository.getAllRules();
    notifyListeners();
  }

  /// Deletes a rule and all associated transactions.
  Future<void> deleteRuleAndAllOccurrences(String ruleId) async {
    final userId = _firestoreSync.isAuthenticated ? _firestoreSync.currentUserId : null;
    await _service.deleteRuleAndAllOccurrences(ruleId, userId: userId);
    if (_firestoreSync.isAuthenticated) {
      _firestoreSync.deleteRecurringRule(ruleId).catchError((Object e) {
        AppLogger.error('Failed to delete rule from Firestore', error: e, label: 'RecurringProvider');
      });
    }
    _rules = await _repository.getAllRules();
    notifyListeners();
  }

  /// Skips the next occurrence of a rule.
  Future<void> skipOccurrence({
    required String ruleId,
    required DateTime scheduledDate,
  }) async {
    await _service.skipOccurrence(ruleId: ruleId, scheduledDate: scheduledDate);
    final updated = await _repository.getRuleById(ruleId);
    if (updated != null && _firestoreSync.isAuthenticated) {
      _firestoreSync.upsertRecurringRule(updated).catchError((Object e) {
        AppLogger.error('Failed to sync rule after skip to Firestore', error: e, label: 'RecurringProvider');
      });
    }
    _rules = await _repository.getAllRules();
    notifyListeners();
  }

  /// Deletes a single occurrence transaction and skips that occurrence.
  Future<void> deleteOccurrenceTransaction({
    required String transactionId,
    required String ruleId,
    required DateTime scheduledDate,
  }) async {
    final userId = _firestoreSync.isAuthenticated ? _firestoreSync.currentUserId : null;
    await _service.deleteOccurrenceTransaction(
      transactionId: transactionId,
      ruleId: ruleId,
      scheduledDate: scheduledDate,
      userId: userId,
    );
    _rules = await _repository.getAllRules();
    notifyListeners();
  }

  /// Clears local provider data on user logout.
  void clearData() {
    _firestoreSubscription?.cancel();
    _firestoreSubscription = null;
    _rules = [];
    _isLoading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _firestoreSubscription?.cancel();
    super.dispose();
  }
}
