import 'dart:async';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:pet/core/utils/app_logger.dart';
import 'package:pet/services/platform_stub.dart'
    if (dart.library.io) 'package:pet/services/platform_native.dart'
    as platform;

import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:pet/data/models/sms_transaction.dart';
import 'package:pet/data/repositories/classification_repository.dart';
import 'package:pet/data/repositories/sms_transaction_repository.dart';
import 'package:pet/services/classification_rule_engine.dart';
import 'package:pet/services/native_sms_reader.dart';
import 'package:pet/services/sms_service.dart';
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
  factory ReconciliationService() => _instance;
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

  final NativeSmsReader _nativeReader = NativeSmsReader();
  final SmsTransactionRepository _repository = SmsTransactionRepository();
  final Uuid _uuid = const Uuid();

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
  ///   - Last sweep was < [_kMinIntervalMinutes] ago
  ///
  /// This method never throws. All exceptions are caught and logged.
  Future<int> reconcile() async {
    if (kIsWeb || !platform.isAndroid) return 0;
    if (AccountDeletionService.isDeletionInProgress) {
      AppLogger.debug('[Reconciliation] Account deletion in progress — skipping');
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
      final smsStatus = await Permission.sms.status;
      if (!smsStatus.isGranted) {
        AppLogger.debug(
          '[Reconciliation] SMS permission not granted — skipping',
        );
        return 0;
      }

      // ── 2. Throttle: skip if last run was too recent ────────────
      final prefs = await SharedPreferences.getInstance();
      final lastRunMs = prefs.getInt(_kLastRunKey) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - lastRunMs < _kMinIntervalMinutes * 60 * 1000) {
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

      final latestMs = messages
          .map((m) => m.dateMillis)
          .reduce((a, b) => a > b ? a : b);

      // ── 5. Pre-load existing hashes for fast dedup ──────────────
      final lookbackStart = DateTime.now().subtract(
        const Duration(days: _kMaxLookbackDays + 1),
      );
      final existingHashes = await _repository.getHashesSince(lookbackStart);

      AppLogger.debug(
        '[Reconciliation] Loaded ${existingHashes.length} existing hashes',
      );

      // ── 6. Run parsing in background isolate ────────────────────
      List<_ParsedCandidate> candidates;
      try {
        candidates = await _parseInIsolate(messages, existingHashes);
      } catch (e) {
        AppLogger.debug(
          '[Reconciliation] Isolate failed ($e) — falling back to main thread',
        );
        candidates = await _parseOnMainThread(messages, existingHashes);
      }

      AppLogger.debug(
        '[Reconciliation] Parsed ${candidates.length} potential transactions',
      );

      // ── 7. Multi-layer deduplication & ATOMIC insert + watermark commit ─
      final insertedCount = await _deduplicateAndInsert(candidates, latestMs);

      await prefs.setInt(_kLastRunKey, now);

      stopwatch.stop();
      AppLogger.debug(
        '[Reconciliation] Complete — $insertedCount new transactions '
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
    final stored = await _repository.getWatermark(_kWatermarkKey);

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
  Future<int?> validateWatermarkForTest(SharedPreferences prefs, int nowMs) async {
    return _getValidatedWatermark(nowMs);
  }

  /// Returns the last sync timestamp (watermark or last run).
  Future<DateTime?> getLastSyncTimestamp() async {
    final watermark = await _repository.getWatermark(_kWatermarkKey);
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

  /// Advance the watermark to the newest SMS timestamp in the batch.
  void _advanceWatermark(
    SharedPreferences prefs,
    List<NativeSmsMessage> messages,
    int nowMs,
  ) {
    if (messages.isEmpty) {
      prefs.setInt(_kLastRunKey, nowMs);
      return;
    }

    final latestMs = messages
        .map((m) => m.dateMillis)
        .reduce((a, b) => a > b ? a : b);

    // Only advance forward, never backward
    final currentWatermark = prefs.getInt(_kWatermarkKey) ?? 0;
    if (latestMs > currentWatermark) {
      prefs.setInt(_kWatermarkKey, latestMs);
    }

    // Also update SmsService's watermark for consistency
    final smsServiceKey = 'pet_last_sms_timestamp';
    final smsServiceWatermark = prefs.getInt(smsServiceKey) ?? 0;
    if (latestMs > smsServiceWatermark) {
      prefs.setInt(smsServiceKey, latestMs);
    }

    prefs.setInt(_kLastRunKey, nowMs);
  }

  // ═══════════════════════════════════════════════════════════════════
  //  ISOLATE-BASED PARSING
  // ═══════════════════════════════════════════════════════════════════

  /// Run the classification engine in a background isolate.
  ///
  /// Since ClassificationRuleEngine logs unknown formats to the database,
  /// we serialize the messages and use the main-thread classification
  /// instead, but we do the hash computation and pre-filtering in the
  /// isolate for CPU savings.
  ///
  /// For the actual classification, we use compute() which runs on a
  /// separate isolate but with a simpler serialization model.
  Future<List<_ParsedCandidate>> _parseInIsolate(
    List<NativeSmsMessage> messages,
    Set<String> existingHashes,
  ) async {
    // Step 1: Pre-filter and hash in isolate (pure computation)
    final preFiltered = await Isolate.run(() {
      return _preFilterAndHash(messages, existingHashes);
    });

    if (preFiltered.isEmpty) return [];

    AppLogger.debug(
      '[Reconciliation] Pre-filter: ${messages.length} → ${preFiltered.length} candidates',
    );

    // Step 2: Classify on main thread (needs DB access for rules)
    return _classifyCandidates(preFiltered);
  }

  /// Fallback: run everything on the main thread.
  Future<List<_ParsedCandidate>> _parseOnMainThread(
    List<NativeSmsMessage> messages,
    Set<String> existingHashes,
  ) async {
    final preFiltered = _preFilterAndHash(messages, existingHashes);
    if (preFiltered.isEmpty) return [];
    return _classifyCandidates(preFiltered);
  }

  /// Pure function: compute hashes and filter out known messages.
  /// Safe to run in any isolate (no DB access, no Flutter bindings).
  static List<_PreFilteredMessage> _preFilterAndHash(
    List<NativeSmsMessage> messages,
    Set<String> existingHashes,
  ) {
    final results = <_PreFilteredMessage>[];
    final seenHashes = <String>{};

    for (final msg in messages) {
      if (msg.body.isEmpty) continue;

      final hash = SmsTransaction.generateHash(msg.body, msg.dateTime);

      // Skip if already in DB
      if (existingHashes.contains(hash)) continue;

      // Skip if duplicate within this batch (inbox/sent overlap)
      if (seenHashes.contains(hash)) continue;
      seenHashes.add(hash);

      results.add(
        _PreFilteredMessage(
          address: msg.address,
          body: msg.body,
          dateMillis: msg.dateMillis,
          type: msg.type,
          hash: hash,
        ),
      );
    }

    return results;
  }

  /// Classify pre-filtered messages using the hardcoded parser.
  /// Must run on main thread (needs DB access for unknown format logging).
  Future<List<_ParsedCandidate>> _classifyCandidates(
    List<_PreFilteredMessage> messages,
  ) async {
    final results = <_ParsedCandidate>[];

    for (final msg in messages) {
      try {
        final timestamp = DateTime.fromMillisecondsSinceEpoch(msg.dateMillis);

        final classified = await ClassificationRuleEngine.classify(
          msg.body,
          msg.address,
          timestamp,
        );
        if (classified == null) continue;

        results.add(
          _ParsedCandidate(
            hash: msg.hash,
            body: msg.body,
            sender: msg.address,
            dateMillis: msg.dateMillis,
            amount: classified.amount,
            merchantName: classified.merchantName,
            bankName: classified.bankName,
            transactionType: classified.transactionType,
            transactionSubType: classified.transactionSubType,
            parsedDate: classified.parsedDate,
            referenceId: classified.referenceId,
            upiId: classified.upiId,
            confidence: classified.confidence,
            category: classified.category,
          ),
        );
      } catch (e) {
        AppLogger.debug(
          '[Reconciliation] Error classifying SMS from ${msg.address}: $e',
        );
        // Continue with remaining messages — don't lose the batch
      }
    }

    return results;
  }

  // ═══════════════════════════════════════════════════════════════════
  //  MULTI-LAYER DEDUPLICATION & INSERT
  // ═══════════════════════════════════════════════════════════════════

  /// Apply three-tier deduplication and insert new transactions ATOMICALLY with watermark update.
  ///
  /// For each candidate:
  /// 1. Hash check (already done in pre-filter, but double-check at insert)
  /// 2. Reference ID + amount + date check (cross-source dedup)
  /// 3. Amount + timestamp proximity + sender check (fuzzy dedup)
  ///
  /// All passed candidates + watermark timestamp commit in ONE ATOMIC SQLite TRANSACTION.
  Future<int> _deduplicateAndInsert(
    List<_ParsedCandidate> candidates,
    int? latestMs,
  ) async {
    final newTxns = <SmsTransaction>[];

    for (final candidate in candidates) {
      try {
        // ── Layer 1: Hash dedup ──────────────────────────────────
        final hashExists = await _repository.existsByHash(candidate.hash);
        if (hashExists) continue;

        // ── Layer 2: Reference ID dedup ─────────────────────────
        if (candidate.referenceId != null &&
            candidate.referenceId!.isNotEmpty) {
          final refExists = await _repository.existsByReferenceAndAmount(
            candidate.referenceId!,
            candidate.amount,
            candidate.parsedDate,
          );
          if (refExists) continue;
        }

        // ── Layer 3: Proximity dedup ────────────────────────────
        final proximityExists = await _repository
            .existsByAmountTimestampProximity(
              amount: candidate.amount,
              timestamp: candidate.parsedDate,
              sender: candidate.sender,
              windowSeconds: 30,
              merchantName: candidate.merchantName,
            );
        if (proximityExists) continue;

        // ── All layers passed ────────────────────────────────────
        newTxns.add(
          SmsTransaction(
            id: _uuid.v4(),
            amount: candidate.amount,
            merchantName: candidate.merchantName,
            bankName: candidate.bankName,
            transactionType: candidate.transactionType,
            transactionSubType: candidate.transactionSubType,
            timestamp: candidate.parsedDate,
            rawSmsBody: SmsService.redactSensitiveData(candidate.body),
            smsSender: candidate.sender,
            smsHash: candidate.hash,
            category: candidate.category ?? 'Uncategorized',
            referenceId: candidate.referenceId,
            upiId: candidate.upiId,
            confidence: candidate.confidence,
            source: 'reconciliation',
          ),
        );
      } catch (e) {
        AppLogger.debug(
          '[Reconciliation] Error filtering candidate (${candidate.hash}): $e',
        );
      }
    }

    // Atomically insert all new transactions AND advance watermarks in ONE SQLite transaction
    final insertedCount = await _repository.insertBatchWithWatermark(
      transactions: newTxns,
      watermarkTimestamp: latestMs,
      watermarkKeys: const ['reconciliation_watermark', 'sms_watermark'],
    );

    return insertedCount;
  }

  // ═══════════════════════════════════════════════════════════════════
  //  DIAGNOSTICS
  // ═══════════════════════════════════════════════════════════════════

  /// Get diagnostic info for debugging.
  Future<Map<String, dynamic>> getDiagnostics() async {
    final watermark = await _repository.getWatermark(_kWatermarkKey);
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

// ═════════════════════════════════════════════════════════════════════
//  INTERNAL DATA CLASSES
// ═════════════════════════════════════════════════════════════════════

/// Intermediate result after pre-filtering (hash computed, not yet classified).
class _PreFilteredMessage {
  final String address;
  final String body;
  final int dateMillis;
  final int type;
  final String hash;

  const _PreFilteredMessage({
    required this.address,
    required this.body,
    required this.dateMillis,
    required this.type,
    required this.hash,
  });
}

/// Fully parsed candidate ready for deduplication and insertion.
class _ParsedCandidate {
  final String hash;
  final String body;
  final String sender;
  final int dateMillis;
  final double amount;
  final String merchantName;
  final String bankName;
  final String transactionType;
  final String transactionSubType;
  final DateTime parsedDate;
  final String? referenceId;
  final String? upiId;
  final double confidence;
  final String? category;

  const _ParsedCandidate({
    required this.hash,
    required this.body,
    required this.sender,
    required this.dateMillis,
    required this.amount,
    required this.merchantName,
    required this.bankName,
    required this.transactionType,
    required this.transactionSubType,
    required this.parsedDate,
    this.referenceId,
    this.upiId,
    required this.confidence,
    this.category,
  });
}
