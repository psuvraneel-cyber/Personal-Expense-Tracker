import 'package:pet/core/utils/app_logger.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pet/data/models/sms_transaction.dart';
import 'package:pet/data/repositories/sms_transaction_repository.dart';
import 'package:pet/services/sms_service.dart';
import 'package:pet/services/sms_background_service.dart';
import 'package:pet/services/reconciliation_service.dart';
import 'package:pet/services/sms_parser/user_feedback_store.dart';

/// Provider for managing SMS-parsed transactions and the SMS scanning lifecycle.
class SmsTransactionProvider extends ChangeNotifier {
  final SmsTransactionRepository _repository = SmsTransactionRepository();
  final SmsService _smsService = SmsService();
  final ReconciliationService _reconciliationService = ReconciliationService();

  List<SmsTransaction> _transactions = [];
  List<SmsTransaction> _uncertainTransactions = [];
  bool _isLoading = false;
  bool _isScanning = false;
  bool _isReconciling = false;
  bool _permissionsGranted = false;
  bool _smsFeatureEnabled = false;
  bool _notificationAccessGranted = false;
  int _lastScanCount = 0;
  int _lastReconciliationCount = 0;

  // Cached computed values
  List<SmsTransaction>? _cachedDebits;
  List<SmsTransaction>? _cachedCredits;
  double? _cachedTotalDebits;
  double? _cachedTotalCredits;

  void _invalidateComputedCache() {
    _cachedDebits = null;
    _cachedCredits = null;
    _cachedTotalDebits = null;
    _cachedTotalCredits = null;
  }

  // Public getters
  List<SmsTransaction> get transactions => _transactions;
  List<SmsTransaction> get uncertainTransactions => _uncertainTransactions;
  bool get isLoading => _isLoading;
  bool get isScanning => _isScanning;
  bool get isReconciling => _isReconciling;
  bool get permissionsGranted => _permissionsGranted;
  bool get smsFeatureEnabled => _smsFeatureEnabled;
  bool get notificationAccessGranted => _notificationAccessGranted;
  int get lastScanCount => _lastScanCount;
  int get lastReconciliationCount => _lastReconciliationCount;

  /// Make UI supported on all non-web platforms for testing and visualization
  bool get isSupported => !kIsWeb;

  List<SmsTransaction> get debitTransactions {
    _cachedDebits ??= _transactions
        .where((t) => t.transactionType == 'debit')
        .toList();
    return _cachedDebits!;
  }

  List<SmsTransaction> get creditTransactions {
    _cachedCredits ??= _transactions
        .where((t) => t.transactionType == 'credit')
        .toList();
    return _cachedCredits!;
  }

  double get totalDebits {
    _cachedTotalDebits ??= debitTransactions.fold<double>(
      0.0,
      (sum, t) => sum + t.amount,
    );
    return _cachedTotalDebits!;
  }

  double get totalCredits {
    _cachedTotalCredits ??= creditTransactions.fold<double>(
      0.0,
      (sum, t) => sum + t.amount,
    );
    return _cachedTotalCredits!;
  }

  /// Initialize the provider: load preferences and existing transactions.
  /// Automatically triggers reconciliation sweep if SMS feature is enabled.
  Future<void> initialize() async {
    if (!isSupported) return;

    final prefs = await SharedPreferences.getInstance();
    _smsFeatureEnabled = prefs.getBool('smsFeatureEnabled') ?? false;
    _notificationAccessGranted = await _smsService.checkNotificationAccess();

    // Load user feedback from DB into memory
    await _loadUserFeedback();

    if (_smsFeatureEnabled) {
      await loadTransactions();

      // Fire-and-forget reconciliation sweep on app open.
      // Runs in the background — does not block UI initialization.
      _runReconciliationSweep();

      // Resume live listening + background tasks if SMS service is supported locally (Android).
      if (SmsService.isSupported) {
        final smsPermission = await Permission.sms.status;
        if (smsPermission.isGranted) {
          _smsService.startListening(
            onNewTransaction: (transaction) {
              _transactions.insert(0, transaction);
              _invalidateComputedCache();
              notifyListeners();
            },
          );
          await initSmsBackgroundService();
        }
      }
    }
  }

  /// Load persisted user feedback records into UserFeedbackStore.
  Future<void> _loadUserFeedback() async {
    try {
      final records = await _repository.getAllFeedbackRecords();
      final feedbacks = records.map((r) => UserFeedback.fromMap(r)).toList();
      UserFeedbackStore.loadFromRecords(feedbacks);
    } catch (e) {
      AppLogger.debug('[PET-SMS] Error loading user feedback: $e');
    }
  }

  /// Load all stored SMS transactions from the local database.
  Future<void> loadTransactions() async {
    _isLoading = true;
    notifyListeners();

    try {
      // One-time cleanup: remove any duplicates that may have been inserted
      // before the in-batch deduplication fix (idempotent — no-op if clean).
      await _repository.deduplicateExisting();

      final all = await _repository.getAllSmsTransactions();
      _transactions = all
          .where((t) => t.isVerified || t.confidence >= 0.55)
          .toList();
      _uncertainTransactions = all
          .where(
            (t) => !t.isVerified && t.confidence < 0.55 && t.confidence >= 0.35,
          )
          .toList();
      _invalidateComputedCache();
    } catch (e) {
      AppLogger.debug('[PET-SMS] Error loading SMS transactions: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> requestNotificationAccess() async {
    await _smsService.requestNotificationAccess();
    _notificationAccessGranted = await _smsService.checkNotificationAccess();
    notifyListeners();
  }

  /// Request SMS permissions and enable the feature if granted.
  Future<bool> requestAndEnablePermissions() async {
    if (!isSupported) return false;

    // Bypass real permission requests on unsupported platforms (like Desktop) for UI testing
    if (!SmsService.isSupported) {
      _permissionsGranted = true;
    } else {
      _permissionsGranted = await _smsService.requestPermissions();
    }

    if (_permissionsGranted) {
      _smsFeatureEnabled = true;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('smsFeatureEnabled', true);
      notifyListeners();
    }
    return _permissionsGranted;
  }

  // ─── Reconciliation ───────────────────────────────────────────────

  /// Internal: fire-and-forget reconciliation on app open.
  /// Catches all errors to never crash the UI.
  /// On failure, schedules a single retry after 5 minutes.
  void _runReconciliationSweep() {
    // Intentionally not awaited — runs in background
    _executeReconciliation().catchError((e) {
      AppLogger.debug('[PET-SMS] Reconciliation sweep error: $e');
      // Schedule a single retry after 5 minutes
      if (!_reconciliationRetryScheduled) {
        _reconciliationRetryScheduled = true;
        Future.delayed(const Duration(minutes: 5), () {
          _reconciliationRetryScheduled = false;
          AppLogger.debug('[PET-SMS] Retrying reconciliation after failure…');
          _executeReconciliation().catchError((e2) {
            AppLogger.debug('[PET-SMS] Reconciliation retry also failed: $e2');
          });
        });
      }
    });
  }

  bool _reconciliationRetryScheduled = false;

  /// Execute reconciliation and update UI state afterward.
  Future<void> _executeReconciliation() async {
    if (_isReconciling) return;

    _isReconciling = true;
    // Don't call notifyListeners() here — avoid UI churn during splash

    try {
      _lastReconciliationCount = await _reconciliationService.reconcile();

      if (_lastReconciliationCount > 0) {
        AppLogger.debug(
          '[PET-SMS] Reconciliation found $_lastReconciliationCount new transactions',
        );
        // Reload transactions to pick up newly inserted ones
        await loadTransactions();
      }
    } catch (e) {
      AppLogger.debug('[PET-SMS] Error during reconciliation: $e');
    } finally {
      _isReconciling = false;
      notifyListeners();
    }
  }

  /// Public: manually trigger a reconciliation sweep.
  /// Returns the number of newly found transactions.
  Future<int> runReconciliation() async {
    if (!isSupported || !_smsFeatureEnabled) return 0;
    await _executeReconciliation();
    return _lastReconciliationCount;
  }

  /// Force a full 7-day rescan on next reconciliation.
  Future<void> resetReconciliationWatermark() async {
    await _reconciliationService.resetWatermark();
  }

  /// Get reconciliation diagnostics for debugging.
  Future<Map<String, dynamic>> getReconciliationDiagnostics() async {
    return _reconciliationService.getDiagnostics();
  }

  /// Perform a full inbox scan.
  /// [lookbackDays] — How many days back to scan.
  Future<int> scanInbox({int lookbackDays = 90}) async {
    if (!isSupported || _isScanning) return 0;

    _isScanning = true;
    notifyListeners();

    try {
      _lastScanCount = await _smsService.scanInbox(lookbackDays: lookbackDays);

      // Reload transactions after scan
      await loadTransactions();

      // Enable background scanning (listener is already started in initialize)
      await initSmsBackgroundService();
    } catch (e) {
      AppLogger.debug('[PET-SMS] Error during scan: $e');
    }

    _isScanning = false;
    notifyListeners();
    return _lastScanCount;
  }

  /// Update the category of a transaction.
  Future<void> updateCategory(String id, String category) async {
    await _repository.updateCategory(id, category);
    final index = _transactions.indexWhere((t) => t.id == id);
    if (index != -1) {
      _transactions[index] = _transactions[index].copyWith(category: category);
      notifyListeners();
    }
  }

  /// Delete a transaction (false positive).
  Future<void> deleteTransaction(String id) async {
    await _repository.deleteSmsTransaction(id);
    _transactions.removeWhere((t) => t.id == id);
    _uncertainTransactions.removeWhere((t) => t.id == id);
    _invalidateComputedCache();
    notifyListeners();
  }

  /// Accept an uncertain transaction — mark as verified and move to main list.
  Future<void> acceptUncertainTransaction(
    String id, {
    String? overrideType,
  }) async {
    final index = _uncertainTransactions.indexWhere((t) => t.id == id);
    if (index == -1) return;

    final txn = _uncertainTransactions[index];
    final updated = txn.copyWith(
      isVerified: true,
      transactionType: overrideType ?? txn.transactionType,
      confidence: 1.0,
    );

    await _repository.updateVerified(id, true);
    if (overrideType != null) {
      await _repository.updateTransactionType(id, overrideType);
    }

    // Record feedback for future learning
    final feedback = UserFeedbackStore.recordFeedback(
      smsBody: txn.rawSmsBody,
      smsTimestamp: txn.timestamp,
      action: overrideType == 'credit'
          ? UserFeedbackAction.markCredit
          : UserFeedbackAction.markDebit,
      confirmedAmount: txn.amount,
    );
    await _repository.saveFeedback(feedback.toMap());

    _uncertainTransactions.removeAt(index);
    _transactions.insert(0, updated);
    notifyListeners();
  }

  /// Reject an uncertain transaction — mark as not a transaction.
  Future<void> rejectUncertainTransaction(String id) async {
    final index = _uncertainTransactions.indexWhere((t) => t.id == id);
    if (index == -1) return;

    final txn = _uncertainTransactions[index];

    // Record feedback to prevent re-detection
    final feedback = UserFeedbackStore.recordFeedback(
      smsBody: txn.rawSmsBody,
      smsTimestamp: txn.timestamp,
      action: UserFeedbackAction.notTransaction,
    );
    await _repository.saveFeedback(feedback.toMap());

    await _repository.deleteSmsTransaction(id);
    _uncertainTransactions.removeAt(index);
    notifyListeners();
  }

  /// Disable the SMS scanning feature entirely.
  Future<void> disableFeature() async {
    _smsFeatureEnabled = false;
    _smsService.stopListening();
    await cancelSmsBackgroundService();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('smsFeatureEnabled', false);
    notifyListeners();
  }

  /// Enable the SMS scanning feature.
  Future<void> enableFeature() async {
    final granted = await requestAndEnablePermissions();
    if (granted) {
      await scanInbox();
    }
  }

  /// Get transactions grouped by bank.
  Map<String, List<SmsTransaction>> get transactionsByBank {
    final Map<String, List<SmsTransaction>> grouped = {};
    for (final t in _transactions) {
      grouped.putIfAbsent(t.bankName, () => []).add(t);
    }
    return grouped;
  }

  /// Get transactions grouped by category.
  Map<String, List<SmsTransaction>> get transactionsByCategory {
    final Map<String, List<SmsTransaction>> grouped = {};
    for (final t in _transactions) {
      grouped.putIfAbsent(t.category, () => []).add(t);
    }
    return grouped;
  }

  /// Get spending by category (debit only).
  Map<String, double> get spendingByCategory {
    final Map<String, double> spending = {};
    for (final t in debitTransactions) {
      spending[t.category] = (spending[t.category] ?? 0) + t.amount;
    }
    return spending;
  }

  /// Get diagnostic information for troubleshooting SMS issues.
  Future<Map<String, dynamic>> getDiagnostics() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'isSupported': isSupported,
      'smsFeatureEnabled': _smsFeatureEnabled,
      'permissionsGranted': _permissionsGranted,
      'transactionCount': _transactions.length,
      'uncertainCount': _uncertainTransactions.length,
      'lastScanCount': _lastScanCount,
      'lastReconciliationCount': _lastReconciliationCount,
      'smsServiceSupported': SmsService.isSupported,
      'lastProcessedTimestamp': prefs.getInt('pet_last_sms_timestamp'),
      'reconciliationWatermark': prefs.getInt('pet_reconciliation_watermark'),
      'lastFailureTimestamp': prefs.getInt('pet_sms_last_failure'),
    };
  }
}
