import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:pet/core/utils/app_logger.dart';
import 'package:pet/services/platform_stub.dart'
    if (dart.library.io) 'package:pet/services/platform_native.dart'
    as platform;

import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pet/data/repositories/classification_repository.dart';
import 'package:pet/data/repositories/sms_transaction_repository.dart';
import 'package:pet/services/native_sms_reader.dart';
import 'package:pet/services/financial_ingestion_service.dart';
import 'package:pet/services/account_deletion_service.dart';

/// ─────────────────────────────────────────────────────────────────────
/// ReconciliationService — On-launch sweep that detects missed
/// transactions from the last 7 days.
///
/// ## Strategy
///
/// 1. **Incremental watermark** — Stores the epoch-millis timestamp of
///    the newest SMS that was fully processed. On the next launch, only
///    SMS newer than this watermark are fetched.
///
/// 2. **7-day safety net** — If the watermark is missing, corrupted, or
///    older than 7 days, the sweep falls back to a 7-day window. This
///    guarantees coverage even after app data resets.
///
/// 3. **Multi-layer deduplication** (in priority order):
///    a. SHA-256 hash of (normalized body + timestamp) — fastest, O(1).
///    b. Transaction reference ID + amount + date — cross-source dedup.
///    c. Amount + timestamp proximity (±2 min) + sender — fuzzy dedup
///       for SMS without reference IDs.
///
/// 4. **Isolate-based parsing** — Heavy regex work runs in a background
///    isolate so the UI thread stays smooth during the splash animation.
///
/// 5. **Idempotent** — Running the sweep multiple times never produces
///    duplicate transactions. Safe to call on every app resume.
///
/// ## Failure Handling
///
/// - **Permission denied** → logs warning, returns 0, does not crash.
/// - **Empty query result** → normal on fresh devices or strict OEMs.
/// - **Corrupted watermark** → falls back to 7-day window.
/// - **Isolate failure** → falls back to main-thread processing.
/// - **DB errors** → caught per-transaction to avoid losing the batch.
///
/// SECURITY: All processing is on-device. No SMS data leaves the device.
/// ─────────────────────────────────────────────────────────────────────
class ReconciliationService {
  static final ReconciliationService _instance =
      ReconciliationService._internal();
  factory ReconciliationService({
    NativeSmsReader? nativeReader,
    SmsTransactionRepository? repository,
  }) {
    if (nativeReader != null) _instance._nativeReader = nativeReader;
    if (repository != null) _instance._repository = repository;
    return _instance;
  }
  ReconciliationService._internal();

  /// SharedPreferences key for the reconciliation watermark.
  /// Stored as epoch milliseconds (int).
  static const String _kWatermarkKey = 'pet_reconciliation_watermark';

  /// SharedPreferences key for the last reconciliation run timestamp.
  static const String _kLastRunKey = 'pet_reconciliation_last_run';

  /// Maximum lookback window in days (safety net).
  static const int _kMaxLookbackDays = 30;

  /// Minimum interval between reconciliation runs (minutes).
  /// Prevents redundant work if the user rapidly opens/closes the app.
  static const int _kMinIntervalMinutes = 5;

  NativeSmsReader _nativeReader = NativeSmsReader();
  SmsTransactionRepository _repository = SmsTransactionRepository();

  @visibleForTesting
  static bool? debugOverrideIsSupported;

  @visibleForTesting
  static bool? debugOverridePermissionGranted;

  bool _isRunning = false;

  /// Whether a reconciliation sweep is currently in progress.
  bool get isRunning => _isRunning;

  // ═══════════════════════════════════════════════════════════════════
  //  PUBLIC API
  // ═══════════════════════════════════════════════════════════════════

  /// Run the reconciliation sweep. Safe to call on every app open.
  ///
  /// Returns the number of newly inserted transactions.
  /// Returns 0 immediately if:
  ///   - Platform is not Android
  ///   - SMS permission is not granted
  ///   - A sweep is already in progress
  ///   - Last sweep was < [_kMinIntervalMinutes] ago (unless [force] is true)
  ///
  /// This method never throws. All exceptions are caught and logged.
  Future<int> reconcile({bool force = false}) async {
    if (kIsWeb || !(debugOverrideIsSupported ?? platform.isAndroid)) return 0;
    if (AccountDeletionService.isDeletionInProgress) {
      AppLogger.debug(
        '[Reconciliation] Account deletion in progress — skipping',
      );
      return 0;
    }
    if (_isRunning) {
      AppLogger.debug('[Reconciliation] Already running — skipping');
      return 0;
    }

    final stopwatch = Stopwatch()..start();

    try {
      _isRunning = true;

      // ── 1. Check permissions ────────────────────────────────────
      if (!force && !(debugOverridePermissionGranted ?? false)) {
        final smsStatus = await Permission.sms.status;
        if (!smsStatus.isGranted) {
          AppLogger.debug(
            '[Reconciliation] SMS permission not granted — skipping',
          );
          return 0;
        }
      }

      // ── 2. Throttle: skip if last run was too recent ────────────
      final prefs = await SharedPreferences.getInstance();
      final lastRunMs = prefs.getInt(_kLastRunKey) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (!force && (now - lastRunMs < _kMinIntervalMinutes * 60 * 1000)) {
        AppLogger.debug(
          '[Reconciliation] Last run was <${_kMinIntervalMinutes}min ago — skipping',
        );
        return 0;
      }

      // ── 3. Read watermark with validation ───────────────────────
      final watermark = await _getValidatedWatermark(now);

      // Perform maintenance cleanup on unknown format logs (30-day TTL & 500-row cap)
      try {
        await ClassificationRepository().cleanUpUnknownLogs();
      } catch (e) {
        AppLogger.debug('[Reconciliation] Error cleaning up unknown logs: $e');
      }

      AppLogger.debug(
        '[Reconciliation] Starting sweep — watermark: '
        '${watermark != null ? DateTime.fromMillisecondsSinceEpoch(watermark) : "null (using ${_kMaxLookbackDays}d fallback)"}',
      );

      // ── 4. Query SMS from native reader ─────────────────────────
      final messages = await _nativeReader.getSmsSinceTimestamp(
        sinceTimestamp: watermark,
        fallbackDays: _kMaxLookbackDays,
      );

      if (messages.isEmpty) {
        AppLogger.debug('[Reconciliation] No new SMS found');
        await prefs.setInt(_kLastRunKey, now);
        return 0;
      }

      AppLogger.debug(
        '[Reconciliation] Fetched ${messages.length} candidate SMS',
      );

      final latestMs =
          messages.map((m) => m.dateMillis).reduce((a, b) => a > b ? a : b);

      // ── 5. Route through canonical FinancialIngestionService (DEF-02 Fix) ─
      // Ensures full consensus classification, FinancialObservation recording,
      // learned merchant rules, cross-source deduplication, bill/balance routing,
      // and atomic promotion to canonical ledger (transactions table).
      final insertedCount = await FinancialIngestionService().ingestBatch(
        messages: messages,
        watermarkTimestamp: latestMs,
        watermarkKeys: const ['reconciliation_watermark', 'sms_watermark'],
      );

      await prefs.setInt(_kLastRunKey, now);
      await prefs.setInt(_kWatermarkKey, latestMs);

      stopwatch.stop();
      AppLogger.debug(
        '[Reconciliation] Complete — $insertedCount new transactions promoted '
        'in ${stopwatch.elapsedMilliseconds}ms',
      );

      return insertedCount;
    } catch (e, stack) {
      AppLogger.debug('[Reconciliation] Unexpected error: $e');
      AppLogger.debug('[Reconciliation] Stack: $stack');
      return 0;
    } finally {
      _isRunning = false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  //  WATERMARK MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════

  /// Validate and return the stored watermark.
  ///
  /// Returns null (triggering the 7-day fallback on the native side) if:
  /// - No watermark is stored
  /// - Watermark is zero or negative
  /// - Watermark is in the future (clock skew or corruption)
  /// - Watermark is older than 7 days (gap too large, use full window)
  Future<int?> _getValidatedWatermark(int nowMs) async {
    final stored = await _repository.getWatermark('reconciliation_watermark') ??
        await _repository.getWatermark(_kWatermarkKey);

    if (stored == null || stored <= 0) return null;
    if (stored > nowMs) {
      AppLogger.debug(
        '[Reconciliation] Watermark is in the future — resetting',
      );
      return null;
    }

    final age = nowMs - stored;
    final maxAgeMs = _kMaxLookbackDays * 24 * 60 * 60 * 1000;
    if (age > maxAgeMs) {
      AppLogger.debug(
        '[Reconciliation] Watermark is >${_kMaxLookbackDays}d old — using full window',
      );
      return null;
    }

    return stored;
  }

  @visibleForTesting
  Future<int?> validateWatermarkForTest(
      SharedPreferences prefs, int nowMs) async {
    return _getValidatedWatermark(nowMs);
  }

  /// Returns the last sync timestamp (watermark or last run).
  Future<DateTime?> getLastSyncTimestamp() async {
    final watermark =
        await _repository.getWatermark('reconciliation_watermark') ??
            await _repository.getWatermark(_kWatermarkKey);
    final smsServiceWatermark = await _repository.getWatermark('sms_watermark');
    final prefs = await SharedPreferences.getInstance();
    final lastRun = prefs.getInt(_kLastRunKey);

    int? latestMs;
    for (final ts in [watermark, lastRun, smsServiceWatermark]) {
      if (ts != null && ts > 0) {
        if (latestMs == null || ts > latestMs) {
          latestMs = ts;
        }
      }
    }
    if (latestMs == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(latestMs);
  }

  // ═══════════════════════════════════════════════════════════════════
  //  DIAGNOSTICS
  // ═══════════════════════════════════════════════════════════════════

  /// Get diagnostic info for debugging.
  Future<Map<String, dynamic>> getDiagnostics() async {
    final watermark =
        await _repository.getWatermark('reconciliation_watermark') ??
            await _repository.getWatermark(_kWatermarkKey);
    final prefs = await SharedPreferences.getInstance();
    final lastRun = prefs.getInt(_kLastRunKey);

    return {
      'watermark': watermark,
      'watermarkDate': watermark != null
          ? DateTime.fromMillisecondsSinceEpoch(watermark).toIso8601String()
          : null,
      'lastRun': lastRun,
      'lastRunDate': lastRun != null
          ? DateTime.fromMillisecondsSinceEpoch(lastRun).toIso8601String()
          : null,
      'isRunning': _isRunning,
      'totalStoredTransactions': await _repository.getCount(),
    };
  }

  /// Reset the watermark (force full 7-day rescan on next launch).
  Future<void> resetWatermark() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kWatermarkKey);
    await prefs.remove(_kLastRunKey);
    await _repository.clearWatermarks();
    AppLogger.debug(
      '[Reconciliation] Watermark reset — next run will do full scan',
    );
  }
}
