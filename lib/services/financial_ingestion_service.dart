import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show ValueNotifier, visibleForTesting;
import 'package:pet/core/utils/app_logger.dart';
import 'package:pet/data/database/database_helper.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/financial_observation.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/data/models/sms_transaction.dart';
import 'package:pet/premium/models/recurring_payment.dart';
import 'package:pet/premium/repositories/linked_account_repository.dart';
import 'package:pet/premium/repositories/recurring_payment_repository.dart';
import 'package:pet/premium/services/merchant_normalizer.dart';
import 'package:pet/premium/services/notification_service.dart';
import 'package:pet/services/canonical_identity_resolver.dart';
import 'package:pet/services/firestore_sync_service.dart';
import 'package:pet/services/category_mapper.dart';
import 'package:pet/services/classification_rule_engine.dart';
import 'package:pet/services/ingestion_diagnostics.dart';
import 'package:pet/services/merchant_rule_service.dart';
import 'package:pet/services/native_sms_reader.dart';
import 'package:pet/services/sms_service.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

/// Central ingestion engine that transforms raw SMS and push notifications
/// into canonical [FinancialObservation]s and promotes confirmed transactions
/// directly into the primary ledger (`transactions` table).
class FinancialIngestionService {
  static final FinancialIngestionService _instance =
      FinancialIngestionService._internal();
  factory FinancialIngestionService({DatabaseHelper? dbHelper}) {
    if (dbHelper != null) {
      _instance._dbHelper = dbHelper;
    }
    _instance.ensureNotificationCallbackRegistered();
    return _instance;
  }
  FinancialIngestionService._internal() {
    ensureNotificationCallbackRegistered();
  }

  DatabaseHelper _dbHelper = DatabaseHelper();
  final NativeSmsReader _nativeReader = NativeSmsReader();
  final LinkedAccountRepository _accountRepository = LinkedAccountRepository();
  final IngestionDiagnostics _diagnostics = IngestionDiagnostics.instance;
  final MerchantRuleService _merchantRuleService = MerchantRuleService();
  final RecurringPaymentRepository _recurringRepository =
      RecurringPaymentRepository();
  static const Uuid _uuid = Uuid();

  /// Incremented whenever automatic ingestion (or a review decision) changes
  /// the `transactions` ledger, so in-memory UI state can reload.
  static final ValueNotifier<int> ledgerRevision = ValueNotifier<int>(0);

  /// Incremented when the pending-review queue changes.
  static final ValueNotifier<int> reviewRevision = ValueNotifier<int>(0);

  /// Tail of the in-isolate work queue. Every ingestion / review mutation runs
  /// strictly one after another so concurrent events (live SMS + notification
  /// + inbox scan) cannot race past the dedup checks. Cross-isolate races
  /// (background worker) are stopped by the UNIQUE index on
  /// `transactions.sourceFingerprint`.
  Future<void> _tail = Future<void>.value();

  Future<T> _serialized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await action());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  /// Owner for queued cloud-sync actions. Rows queued as `guest_user` are
  /// re-assigned to the signed-in account by
  /// `TransactionRepository.migrateGuestSyncActions` on the next load.
  static String _syncUserId() {
    try {
      final sync = FirestoreSyncService();
      if (sync.isAuthenticated) return sync.currentUserId;
    } catch (_) {}
    return 'guest_user';
  }

  static Map<String, Object?> _syncQueueRow(
    String transactionId,
    String action, {
    TransactionRecord? record,
  }) {
    return {
      'id': _uuid.v4(),
      'transactionId': transactionId,
      'action': action,
      'payload': record == null ? null : jsonEncode(record.toMap()),
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'userId': _syncUserId(),
      'retryCount': 0,
      'lastAttemptAt': 0,
      'lastError': null,
    };
  }

  /// Kept for API compatibility. Notification actions are now handled by
  /// `handleTransactionNotificationAction` (works in background isolates too).
  void ensureNotificationCallbackRegistered() {}

  /// Minimum confidence threshold for automatic promotion to the core ledger.
  static const double autoAcceptConfidenceThreshold = 0.80;

  /// Minimum confidence threshold to place into the Pending Review queue.
  static const double reviewConfidenceThreshold = 0.35;

  // ─── Single Message Ingestion ──────────────────────────────────────

  /// Ingests a raw [NativeSmsMessage] from SMS or push notification.
  /// Returns the promoted [TransactionRecord] if auto-promoted, or `null`
  /// if rejected, uncertain (placed in review), or duplicate.
  Future<TransactionRecord?> ingestMessage(NativeSmsMessage msg) =>
      _serialized(() => _ingestMessageUnlocked(msg));

  Future<TransactionRecord?> _ingestMessageUnlocked(
    NativeSmsMessage msg,
  ) async {
    final body = msg.body;
    final sender = msg.address;
    final timestamp = msg.dateTime;

    if (body.trim().isEmpty && (msg.title?.trim().isEmpty ?? true)) {
      return null;
    }

    final db = await _dbHelper.database;
    final observationId = _uuid.v4();
    final source = msg.source == 'notification'
        ? FinancialObservationSource.notification
        : FinancialObservationSource.sms;

    _diagnostics.recordReceived();

    final normalizedText = FinancialObservation.buildNormalizedText(
      title: msg.title,
      body: body,
    );

    final observationHash = FinancialObservation.generateHash(
      normalizedText,
      timestamp,
    );

    // 1. Raw Dedup Check: Check if observationHash was already processed
    final existingObs = await db.query(
      'financial_observations',
      where: 'observationHash = ?',
      whereArgs: [observationHash],
      limit: 1,
    );
    if (existingObs.isNotEmpty) {
      _diagnostics.recordDuplicate();
      AppLogger.debug(
          '[IngestionService] Observation already recorded (hash=$observationHash)');
      return null;
    }

    // Also check sms_processing_state for tombstones/deleted/rejected
    final stateRows = await db.query(
      'sms_processing_state',
      where: 'smsHash = ?',
      whereArgs: [observationHash],
      limit: 1,
    );
    if (stateRows.isNotEmpty) {
      final status = stateRows.first['status'] as String?;
      if (status == 'rejected' || status == 'deleted' || status == 'ignored') {
        AppLogger.debug(
            '[IngestionService] Message tombstoned as $status. Skipping resurrection.');
        return null;
      }
    }

    // 2. Classify via Two-Tier Consensus Parser
    _diagnostics.recordParsed();
    final classified = await ClassificationRuleEngine.classify(
      normalizedText,
      sender,
      timestamp,
    );

    if (classified == null) {
      // Definitively non-financial or rejected
      _diagnostics.recordRejection();
      _diagnostics.recordEvent(
        source: source.name,
        state: 'rejected',
        confidence: 0.0,
        reason: 'non_financial_content',
      );

      await _recordObservation(
        db,
        FinancialObservation(
          observationId: observationId,
          source: source,
          sourceIdentifier: sender,
          sender: sender,
          packageName: msg.packageName,
          title: msg.title,
          body: body,
          normalizedText: normalizedText,
          receivedAt: DateTime.now(),
          sourceTimestamp: timestamp,
          observationHash: observationHash,
          state: FinancialObservationState.rejected,
          stateReason: 'non_financial_content',
          confidence: 0.0,
        ),
      );
      return null;
    }

    // 2b. Handle Bill Statements (P7.1 - P7.3)
    if (classified.isBill) {
      _diagnostics.recordBillEvent();
      _diagnostics.recordEvent(
        source: source.name,
        state: 'accepted',
        confidence: classified.confidence,
        bank: classified.bankName,
        merchant: classified.merchantName,
        decision: 'bill_detected',
        reason: 'bill_statement_notice',
      );

      if (classified.billAmountDue != null && classified.billAmountDue! > 0) {
        final dueDate =
            classified.billDueDate ?? timestamp.add(const Duration(days: 15));
        final billItem = RecurringPayment(
          id: 'bill_$observationId',
          merchantName: classified.merchantName,
          amount: classified.billAmountDue!,
          frequency: 'monthly',
          lastPaidAt: timestamp,
          nextDueAt: dueDate,
          categoryId: CategoryMapper.mapToCategoryId(
            parserCategory: 'Bills',
            merchantName: classified.merchantName,
            isIncome: false,
          ),
          confidence: classified.confidence,
          source: source.name,
          status: RecurringStatus.detected,
          detectionReason: 'Parsed from statement notice ($sender)',
        );
        await _recurringRepository.upsert(billItem);
      }

      await _recordObservation(
        db,
        FinancialObservation(
          observationId: observationId,
          source: source,
          sourceIdentifier: sender,
          sender: sender,
          packageName: msg.packageName,
          title: msg.title,
          body: body,
          normalizedText: normalizedText,
          receivedAt: DateTime.now(),
          sourceTimestamp: timestamp,
          accountHint: classified.bankName,
          observationHash: observationHash,
          state: FinancialObservationState.accepted,
          stateReason: 'bill_statement_detected',
          confidence: classified.confidence,
        ),
      );
      return null;
    }

    // 2c. Handle Balance-Only Notifications (P6.1 - P6.4)
    if (classified.amount <= 0 && classified.balanceAfter != null) {
      _diagnostics.recordBalanceObservation();
      _diagnostics.recordEvent(
        source: source.name,
        state: 'accepted',
        confidence: classified.confidence,
        bank: classified.bankName,
        decision: 'balance_observed',
        reason: 'balance_only_notice',
      );

      final matchedAcct = await _accountRepository.findByBankAndTail(
        classified.bankName,
        classified.accountTail,
      );
      if (matchedAcct != null) {
        await _accountRepository.updateObservedBalance(
          matchedAcct.id,
          classified.balanceAfter!,
          timestamp,
        );
      }

      await _recordObservation(
        db,
        FinancialObservation(
          observationId: observationId,
          source: source,
          sourceIdentifier: sender,
          sender: sender,
          packageName: msg.packageName,
          title: msg.title,
          body: body,
          normalizedText: normalizedText,
          receivedAt: DateTime.now(),
          sourceTimestamp: timestamp,
          accountHint: classified.bankName,
          observationHash: observationHash,
          state: FinancialObservationState.accepted,
          stateReason: 'balance_observation_recorded',
          confidence: classified.confidence,
        ),
      );
      return null;
    }

    // 3. User Learned Rules Check (P7.5) & Entity Normalization
    final learnedRule = await _merchantRuleService.matchRule(
      upiId: classified.upiId,
      rawMerchant: classified.merchantName,
    );
    final amount = classified.amount;
    final merchant = learnedRule?.learnedMerchantName ??
        MerchantNormalizer.normalize(classified.merchantName);
    final bank = classified.bankName;
    final refId = classified.referenceId;
    final upiId = classified.upiId;
    final confidence = classified.confidence;

    final fingerprint = CanonicalIdentityResolver.generateFingerprint(
      referenceId: refId,
      merchantName: merchant,
      upiId: upiId,
      amount: amount,
      timestamp: timestamp,
    );

    // 4. Cross-Source Dedup Check against Core Ledger & Observations
    final existingTxnByFingerprint = await db.query(
      'transactions',
      where: 'sourceFingerprint = ?',
      whereArgs: [fingerprint],
      limit: 1,
    );

    if (existingTxnByFingerprint.isNotEmpty) {
      final matchedTxnId = existingTxnByFingerprint.first['id'] as String;
      _diagnostics.recordCrossSourceMerge();
      _diagnostics.recordEvent(
        source: source.name,
        state: 'linked',
        confidence: confidence,
        bank: bank,
        merchant: merchant,
        decision: 'collapsed_cross_source_duplicate',
        reason: 'matched_$matchedTxnId',
        transactionId: matchedTxnId,
      );

      AppLogger.debug(
          '[IngestionService] Duplicate event collapsed (matched txnId=$matchedTxnId)');

      await _recordObservation(
        db,
        FinancialObservation(
          observationId: observationId,
          source: source,
          sourceIdentifier: sender,
          sender: sender,
          packageName: msg.packageName,
          title: msg.title,
          body: body,
          normalizedText: normalizedText,
          receivedAt: DateTime.now(),
          sourceTimestamp: timestamp,
          accountHint: bank,
          observationHash: observationHash,
          sourceFingerprint: fingerprint,
          state: FinancialObservationState.linked,
          stateReason: 'cross_source_duplicate_of_$matchedTxnId',
          confidence: confidence,
          canonicalTransactionId: matchedTxnId,
        ),
      );
      return null;
    }

    // 4b. Observational Balance Update if balanceAfter exists
    if (classified.balanceAfter != null) {
      _diagnostics.recordBalanceObservation();
      final matchedAcct = await _accountRepository.findByBankAndTail(
        bank,
        classified.accountTail,
      );
      if (matchedAcct != null) {
        await _accountRepository.updateObservedBalance(
          matchedAcct.id,
          classified.balanceAfter!,
          timestamp,
        );
      }
    }

    // 5. Ingestion Decision
    final isIncome = classified.transactionType == 'credit';
    final mappedCategoryId = learnedRule?.learnedCategoryId ??
        CategoryMapper.mapToCategoryId(
          parserCategory: classified.category,
          merchantName: merchant,
          isIncome: isIncome,
        );

    // Evidence-based high-confidence determination (P2.2)
    final hasHighEvidence = (amount > 0) &&
        (classified.transactionType == 'debit' ||
            classified.transactionType == 'credit') &&
        (merchant != 'Unknown') &&
        (bank != 'Unknown Bank') &&
        (confidence >= 0.40);

    final isAutoAccept =
        (confidence >= autoAcceptConfidenceThreshold) || hasHighEvidence;

    if (confidence < reviewConfidenceThreshold) {
      // Low confidence -> Reject
      _diagnostics.recordRejection();
      _diagnostics.recordEvent(
        source: source.name,
        state: 'rejected',
        confidence: confidence,
        bank: bank,
        merchant: merchant,
        decision: 'reject',
        reason: 'confidence_below_threshold ($confidence)',
      );

      await _recordObservation(
        db,
        FinancialObservation(
          observationId: observationId,
          source: source,
          sourceIdentifier: sender,
          sender: sender,
          packageName: msg.packageName,
          title: msg.title,
          body: body,
          normalizedText: normalizedText,
          receivedAt: DateTime.now(),
          sourceTimestamp: timestamp,
          accountHint: bank,
          observationHash: observationHash,
          sourceFingerprint: fingerprint,
          state: FinancialObservationState.rejected,
          stateReason: 'confidence_below_threshold ($confidence)',
          confidence: confidence,
        ),
      );
      return null;
    } else if (!isAutoAccept) {
      // Moderate confidence or missing required counterparty evidence -> Route to Pending Review
      _diagnostics.recordReviewRequired();
      _diagnostics.recordEvent(
        source: source.name,
        state: 'uncertain',
        confidence: confidence,
        bank: bank,
        merchant: merchant,
        decision: 'review_required',
        reason: 'moderate_confidence',
      );

      AppLogger.debug(
          '[IngestionService] Holding observation in review queue (confidence=$confidence)');
      await _recordObservation(
        db,
        FinancialObservation(
          observationId: observationId,
          source: source,
          sourceIdentifier: sender,
          sender: sender,
          packageName: msg.packageName,
          title: msg.title,
          body: body,
          normalizedText: normalizedText,
          receivedAt: DateTime.now(),
          sourceTimestamp: timestamp,
          accountHint: bank,
          observationHash: observationHash,
          sourceFingerprint: fingerprint,
          state: FinancialObservationState.uncertain,
          stateReason: 'review_required',
          confidence: confidence,
        ),
      );

      reviewRevision.value++;

      // Interactive notification for review (Confirm, Edit, Ignore)
      await NotificationService.showTransactionDetectedNotification(
        observationId: observationId,
        merchant: merchant,
        amount: amount,
        bankOrChannel: bank,
        isUncertain: true,
      );

      return null;
    }

    // 6. High Confidence (>= 0.80) -> Atomic Ledger Promotion
    final txnId = 'txn_$observationId';
    final nowIso = DateTime.now().toIso8601String();

    final promotedTxn = TransactionRecord(
      id: txnId,
      amount: amount,
      type: isIncome ? TransactionType.income : TransactionType.expense,
      categoryId: mappedCategoryId,
      date: classified.parsedDate,
      note: '$merchant ($bank)',
      paymentMethod: PaymentMethod.upi,
      isRecurring: false,
      merchantName: merchant,
      source: source == FinancialObservationSource.notification
          ? TransactionSource.notification
          : TransactionSource.sms,
      updatedAt: DateTime.now(),
      sourceObservationId: observationId,
      sourceFingerprint: fingerprint,
    );

    final observation = FinancialObservation(
      observationId: observationId,
      source: source,
      sourceIdentifier: sender,
      sender: sender,
      packageName: msg.packageName,
      title: msg.title,
      body: body,
      normalizedText: normalizedText,
      receivedAt: DateTime.now(),
      sourceTimestamp: timestamp,
      accountHint: bank,
      observationHash: observationHash,
      sourceFingerprint: fingerprint,
      state: FinancialObservationState.promoted,
      stateReason: 'high_confidence_auto_promotion',
      confidence: confidence,
      canonicalTransactionId: txnId,
    );

    String? duplicateOfTxnId;
    await db.transaction((txn) async {
      // 1. Insert canonical transaction into core ledger. Re-check the
      //    fingerprint inside the transaction and verify the row afterwards:
      //    a concurrent writer (e.g. the background isolate) may have won the
      //    race, in which case the UNIQUE index silently ignores this insert.
      final existing = await txn.query(
        'transactions',
        columns: ['id'],
        where: 'sourceFingerprint = ?',
        whereArgs: [fingerprint],
        limit: 1,
      );
      if (existing.isEmpty) {
        await txn.insert(
          'transactions',
          promotedTxn.toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      final mine = await txn.query(
        'transactions',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [txnId],
        limit: 1,
      );
      if (mine.isEmpty) {
        duplicateOfTxnId = existing.isNotEmpty
            ? existing.first['id'] as String
            : (await txn.query(
                'transactions',
                columns: ['id'],
                where: 'sourceFingerprint = ?',
                whereArgs: [fingerprint],
                limit: 1,
              ))
                .map((r) => r['id'] as String)
                .firstOrNull;
        await txn.insert(
          'financial_observations',
          _minimise(
            observation.copyWith(
              state: FinancialObservationState.linked,
              stateReason: 'cross_source_duplicate_of_$duplicateOfTxnId',
              canonicalTransactionId: duplicateOfTxnId,
            ),
          ).toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        return;
      }

      // 1b. Queue the new ledger row for cloud sync in the same transaction.
      await txn.insert(
        'transaction_sync_queue',
        _syncQueueRow(txnId, 'create', record: promotedTxn),
      );

      // 2. Insert observation record (minimised — see [_minimise])
      await txn.insert(
        'financial_observations',
        _minimise(observation).toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // 3. Mark processing state to prevent inbox rescan duplicates
      await txn.insert(
        'sms_processing_state',
        {
          'id': observationId,
          'smsHash': observationHash,
          'status': 'accepted',
          'processedAt': nowIso,
          'reason': 'auto_promoted_to_ledger',
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // 4. Also insert into legacy sms_transactions table for backward compatibility
      final smsTxn = SmsTransaction(
        id: observationId,
        amount: amount,
        merchantName: merchant,
        bankName: bank,
        transactionType: classified.transactionType,
        transactionSubType: classified.transactionSubType,
        timestamp: classified.parsedDate,
        rawSmsBody: SmsService.redactSensitiveData(body),
        smsSender: sender,
        smsHash: observationHash,
        category: classified.category ?? 'Uncategorized',
        referenceId: refId,
        upiId: upiId,
        confidence: confidence,
        source: source == FinancialObservationSource.notification
            ? 'notification'
            : 'sms',
      );
      await txn.insert(
        'sms_transactions',
        smsTxn.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    });

    if (duplicateOfTxnId != null) {
      _diagnostics.recordCrossSourceMerge();
      AppLogger.debug(
        '[IngestionService] Concurrent duplicate collapsed into $duplicateOfTxnId',
      );
      return null;
    }

    ledgerRevision.value++;
    AppLogger.info(
      '[IngestionService] Promoted ₹$amount at $merchant to Core Ledger ($txnId)',
    );

    // Interactive notification for auto-promoted transaction
    await NotificationService.showTransactionDetectedNotification(
      observationId: observationId,
      merchant: merchant,
      amount: amount,
      bankOrChannel: bank,
      isUncertain: false,
      categoryName: classified.category,
    );

    return promotedTxn;
  }

  // ─── Batch Notification & SMS Ingestion ────────────────────────────

  /// Processes all pending notifications from the native encrypted cache using
  /// the non-destructive peek-and-acknowledge protocol.
  Future<List<TransactionRecord>> processPendingNotifications() async {
    if (!NativeSmsReader.isSupported) return [];

    try {
      final pendingMessages = await _nativeReader.peekPendingNotifications();
      if (pendingMessages.isEmpty) return [];

      AppLogger.info(
        '[IngestionService] Peeked ${pendingMessages.length} cached notifications for ingestion',
      );

      final promotedTransactions = <TransactionRecord>[];
      final processedIds = <String>[];
      var legacyCount = 0;

      for (final msg in pendingMessages) {
        try {
          final txn = await ingestMessage(msg);
          if (txn != null) {
            promotedTransactions.add(txn);
          }
        } catch (e) {
          // A poison-pill item is still acknowledged so it cannot loop forever.
          AppLogger.error(
              '[IngestionService] Error ingesting single notification',
              error: e);
        }
        if (msg.cacheId != null) {
          processedIds.add(msg.cacheId!);
        } else {
          legacyCount++;
        }
      }

      // Acknowledge exactly what was processed, only after it was stored.
      if (processedIds.isNotEmpty) {
        await _nativeReader.acknowledgeNotificationIds(processedIds);
      }
      // Items cached by older builds have no id; they sit at the head.
      if (legacyCount > 0 && processedIds.isEmpty) {
        await _nativeReader.acknowledgeNotifications(legacyCount);
      }

      return promotedTransactions;
    } catch (e) {
      AppLogger.error(
          '[IngestionService] Error processing pending notifications',
          error: e);
      return [];
    }
  }

  /// Ingests a batch of messages from ContentResolver inbox scan with atomic watermark update.
  Future<int> ingestBatch({
    required List<NativeSmsMessage> messages,
    int? watermarkTimestamp,
    List<String> watermarkKeys = const ['sms_watermark'],
  }) async {
    int promotedCount = 0;
    final db = await _dbHelper.database;

    for (final msg in messages) {
      final txn = await ingestMessage(msg);
      if (txn != null) {
        promotedCount++;
      }
    }

    if (watermarkTimestamp != null && watermarkTimestamp > 0) {
      final nowIso = DateTime.now().toIso8601String();
      for (final key in watermarkKeys) {
        final existing = await db.query(
          'system_watermarks',
          columns: ['value'],
          where: 'key = ?',
          whereArgs: [key],
          limit: 1,
        );
        final currentVal =
            existing.isNotEmpty ? (existing.first['value'] as int) : 0;
        if (watermarkTimestamp > currentVal) {
          await db.insert(
            'system_watermarks',
            {
              'key': key,
              'value': watermarkTimestamp,
              'updatedAt': nowIso,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    }

    return promotedCount;
  }

  // ─── Pending Review & User Decision Actions ────────────────────────

  /// Fetch all observations awaiting user review.
  Future<List<FinancialObservation>> getPendingReviewObservations() async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'financial_observations',
      where: 'state = ?',
      whereArgs: [FinancialObservationState.uncertain.name],
      orderBy: 'sourceTimestamp DESC',
    );
    return maps.map((m) => FinancialObservation.fromMap(m)).toList();
  }

  /// Explicitly confirms and promotes an uncertain observation to the core ledger.
  Future<TransactionRecord?> confirmObservation({
    required String observationId,
    double? overrideAmount,
    String? overrideCategoryId,
    String? overrideMerchant,
    TransactionType? overrideType,
  }) =>
      _serialized(
        () => _confirmObservationUnlocked(
          observationId: observationId,
          overrideAmount: overrideAmount,
          overrideCategoryId: overrideCategoryId,
          overrideMerchant: overrideMerchant,
          overrideType: overrideType,
        ),
      );

  Future<TransactionRecord?> _confirmObservationUnlocked({
    required String observationId,
    double? overrideAmount,
    String? overrideCategoryId,
    String? overrideMerchant,
    TransactionType? overrideType,
  }) async {
    final db = await _dbHelper.database;
    final obsRows = await db.query(
      'financial_observations',
      where: 'observationId = ?',
      whereArgs: [observationId],
      limit: 1,
    );
    if (obsRows.isEmpty) return null;

    final observation = FinancialObservation.fromMap(obsRows.first);
    final classified = await ClassificationRuleEngine.classify(
      observation.normalizedText,
      observation.sender ?? observation.sourceIdentifier,
      observation.sourceTimestamp,
    );

    final finalAmount = overrideAmount ?? classified?.amount ?? 0.0;
    final finalMerchant =
        overrideMerchant ?? classified?.merchantName ?? 'Unknown';
    final finalType = overrideType ??
        (classified?.transactionType == 'credit'
            ? TransactionType.income
            : TransactionType.expense);
    final finalCategoryId = overrideCategoryId ??
        CategoryMapper.mapToCategoryId(
          parserCategory: classified?.category,
          merchantName: finalMerchant,
          isIncome: finalType == TransactionType.income,
        );

    final txnId = 'txn_$observationId';
    final nowIso = DateTime.now().toIso8601String();

    final fingerprint = CanonicalIdentityResolver.generateFingerprint(
      referenceId: classified?.referenceId,
      merchantName: finalMerchant,
      amount: finalAmount,
      timestamp: observation.sourceTimestamp,
    );

    final txnRecord = TransactionRecord(
      id: txnId,
      amount: finalAmount,
      type: finalType,
      categoryId: finalCategoryId,
      date: observation.sourceTimestamp,
      note: '$finalMerchant (${classified?.bankName ?? 'Confirmed'})',
      paymentMethod: PaymentMethod.upi,
      merchantName: finalMerchant,
      source: observation.source == FinancialObservationSource.notification
          ? TransactionSource.notification
          : TransactionSource.sms,
      updatedAt: DateTime.now(),
      sourceObservationId: observationId,
      sourceFingerprint: fingerprint,
    );

    if (!finalAmount.isFinite || finalAmount <= 0) {
      AppLogger.debug(
        '[IngestionService] confirmObservation: no valid amount for $observationId',
      );
      return null;
    }

    var linkedTo = txnId;
    await db.transaction((txn) async {
      // If another source already recorded this event, link instead of
      // creating a duplicate ledger row.
      final dup = await txn.query(
        'transactions',
        columns: ['id'],
        where: 'sourceFingerprint = ? AND id != ?',
        whereArgs: [fingerprint, txnId],
        limit: 1,
      );
      if (dup.isNotEmpty) {
        linkedTo = dup.first['id'] as String;
      } else {
        await txn.insert(
          'transactions',
          txnRecord.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await txn.insert(
          'transaction_sync_queue',
          _syncQueueRow(txnId, 'create', record: txnRecord),
        );
        // Keep the legacy SMS list in sync with the ledger.
        await txn.insert(
          'sms_transactions',
          SmsTransaction(
            id: observationId,
            amount: finalAmount,
            merchantName: finalMerchant,
            bankName: classified?.bankName ?? 'Unknown Bank',
            transactionType:
                finalType == TransactionType.income ? 'credit' : 'debit',
            timestamp: observation.sourceTimestamp,
            rawSmsBody: SmsService.redactSensitiveData(observation.body),
            smsSender: observation.sender ?? observation.sourceIdentifier,
            smsHash: observation.observationHash,
            category: classified?.category ?? 'Uncategorized',
            referenceId: classified?.referenceId,
            upiId: classified?.upiId,
            confidence: 1.0,
            isVerified: true,
            source:
                observation.source == FinancialObservationSource.notification
                    ? 'notification'
                    : 'sms',
          ).toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }

      await txn.update(
        'financial_observations',
        {
          'state': dup.isNotEmpty
              ? FinancialObservationState.linked.name
              : FinancialObservationState.promoted.name,
          'stateReason': 'user_confirmed',
          'confidence': 1.0,
          'canonicalTransactionId': linkedTo,
        },
        where: 'observationId = ?',
        whereArgs: [observationId],
      );

      await txn.insert(
        'sms_processing_state',
        {
          'id': observationId,
          'smsHash': observation.observationHash,
          'status': 'accepted',
          'processedAt': nowIso,
          'reason': 'user_confirmed_promotion',
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });

    // Learn merchant rule for future occurrences
    try {
      final upi = classified?.upiId;
      final merch = classified?.merchantName;
      final identifier = (upi != null && upi.isNotEmpty)
          ? upi
          : (merch != null && merch.isNotEmpty
              ? merch
              : (finalMerchant != 'Unknown' ? finalMerchant : null));

      if (identifier != null && identifier.trim().isNotEmpty) {
        await _merchantRuleService.learnRule(
          identifier: identifier,
          learnedMerchantName: finalMerchant,
          categoryId: finalCategoryId,
        );
      }
    } catch (e) {
      AppLogger.debug('[IngestionService] Error learning merchant rule: $e');
    }

    ledgerRevision.value++;
    reviewRevision.value++;
    return linkedTo == txnId ? txnRecord : null;
  }

  /// Re-categorises the ledger transaction created from an SMS/notification
  /// (category picked on the SMS screen), queues the change for cloud sync,
  /// and remembers the choice for this merchant.
  Future<void> recategorizeFromSms({
    required String observationId,
    required String parserCategory,
  }) =>
      _serialized(() async {
        final db = await _dbHelper.database;
        final rows = await db.query(
          'transactions',
          where: 'sourceObservationId = ?',
          whereArgs: [observationId],
        );
        if (rows.isEmpty) return;
        for (final row in rows) {
          final current = TransactionRecord.fromMap(row);
          final categoryId = CategoryMapper.mapToCategoryId(
            parserCategory: parserCategory,
            merchantName: current.merchantName ?? '',
            isIncome: current.type == TransactionType.income,
          );
          final updated = current.copyWith(
            categoryId: categoryId,
            updatedAt: DateTime.now(),
          );
          await db.transaction((txn) async {
            await txn.update(
              'transactions',
              updated.toMap(),
              where: 'id = ?',
              whereArgs: [updated.id],
            );
            await txn.insert(
              'transaction_sync_queue',
              _syncQueueRow(updated.id, 'update', record: updated),
            );
          });
          final merchant = current.merchantName;
          if (merchant != null &&
              merchant.isNotEmpty &&
              merchant != 'Unknown') {
            try {
              await _merchantRuleService.learnRule(
                identifier: merchant,
                learnedMerchantName: merchant,
                categoryId: categoryId,
              );
            } catch (_) {}
          }
        }
        ledgerRevision.value++;
      });

  /// User rejects an observation (false positive, "Ignore" action, or
  /// deleting an auto-detected transaction). Records a persistent tombstone so
  /// the message is never re-imported, **and removes any ledger transaction
  /// created from it** (queuing a cloud delete).
  Future<void> rejectObservation({
    required String observationId,
    String? reason,
  }) =>
      _serialized(
        () => _rejectObservationUnlocked(
          observationId: observationId,
          reason: reason,
        ),
      );

  Future<void> _rejectObservationUnlocked({
    required String observationId,
    String? reason,
  }) async {
    final db = await _dbHelper.database;
    final obsRows = await db.query(
      'financial_observations',
      where: 'observationId = ?',
      whereArgs: [observationId],
      limit: 1,
    );
    final obs =
        obsRows.isEmpty ? null : FinancialObservation.fromMap(obsRows.first);
    final nowIso = DateTime.now().toIso8601String();
    var ledgerChanged = false;

    await db.transaction((txn) async {
      if (obs != null) {
        await txn.update(
          'financial_observations',
          {
            'state': FinancialObservationState.rejected.name,
            'stateReason': reason ?? 'user_rejected',
            'canonicalTransactionId': null,
            // Rejected messages keep only their hash (see _minimise).
            'title': null,
            'body': '',
            'normalizedText': '',
          },
          where: 'observationId = ?',
          whereArgs: [observationId],
        );

        await txn.insert(
          'sms_processing_state',
          {
            'id': observationId,
            'smsHash': obs.observationHash,
            'status': 'rejected',
            'processedAt': nowIso,
            'reason': reason ?? 'user_rejected',
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      // Remove ledger rows created from this message (auto-promoted,
      // user-confirmed, or migrated by the v18 backfill).
      final ids = <String>{
        if (obs?.canonicalTransactionId != null) obs!.canonicalTransactionId!,
        ...(await txn.query(
          'transactions',
          columns: ['id'],
          where: 'sourceObservationId = ?',
          whereArgs: [observationId],
        ))
            .map((r) => r['id'] as String),
      };
      for (final id in ids) {
        final deleted =
            await txn.delete('transactions', where: 'id = ?', whereArgs: [id]);
        if (deleted > 0) {
          ledgerChanged = true;
          await txn.insert(
              'transaction_sync_queue', _syncQueueRow(id, 'delete'));
        }
      }
      await txn.delete(
        'sms_transactions',
        where: 'id = ?',
        whereArgs: [observationId],
      );
    });

    if (ledgerChanged) ledgerRevision.value++;
    reviewRevision.value++;
  }

  // ─── Internal Helpers ──────────────────────────────────────────────

  Future<void> _recordObservation(Database db, FinancialObservation obs) async {
    await db.insert(
      'financial_observations',
      _minimise(obs).toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Data minimisation applied before any observation is persisted.
  ///
  /// - Rejected (non-financial / low-confidence) messages keep **only** their
  ///   hash (for dedup and "never resurrect" tombstones) — the message text is
  ///   never stored, because it may be a personal message.
  /// - Everything else is stored with account, card and phone numbers redacted.
  /// - Raw text of resolved observations is purged after
  ///   [DatabaseHelper.observationTextRetention] by
  ///   [DatabaseHelper.purgeExpiredSensitiveData].
  static FinancialObservation _minimise(FinancialObservation obs) {
    if (obs.state == FinancialObservationState.rejected) {
      return FinancialObservation(
        observationId: obs.observationId,
        source: obs.source,
        sourceIdentifier: obs.sourceIdentifier,
        sender: obs.sender,
        packageName: obs.packageName,
        title: null,
        body: '',
        normalizedText: '',
        receivedAt: obs.receivedAt,
        sourceTimestamp: obs.sourceTimestamp,
        observationHash: obs.observationHash,
        sourceFingerprint: obs.sourceFingerprint,
        state: obs.state,
        stateReason: obs.stateReason,
        confidence: obs.confidence,
      );
    }
    return obs.copyWith(
      title:
          obs.title == null ? null : SmsService.redactSensitiveData(obs.title!),
      body: SmsService.redactSensitiveData(obs.body),
      normalizedText: SmsService.redactSensitiveData(obs.normalizedText),
    );
  }

  @visibleForTesting
  static FinancialObservation minimiseForTesting(FinancialObservation obs) =>
      _minimise(obs);
}
