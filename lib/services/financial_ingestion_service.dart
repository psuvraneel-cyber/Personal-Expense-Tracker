import 'dart:async';
import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;
import 'package:pet/premium/services/focus_mode_notifier.dart';
import 'package:pet/premium/services/bill_payment_matcher.dart';
import 'package:pet/premium/services/invoice_payment_matcher.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart' show sha256;
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
import 'package:pet/core/constants/categories.dart'
    show defaultCategories, kFromPeopleCategoryId, kTransferCategoryId;
import 'package:pet/services/canonical_identity_resolver.dart';
import 'package:pet/services/counterparty_classifier.dart';
import 'package:pet/services/firestore_sync_service.dart';
import 'package:pet/services/category_mapper.dart';
import 'package:pet/services/classification_rule_engine.dart';
import 'package:pet/services/ingestion_diagnostics.dart';
import 'package:pet/services/merchant_rule_service.dart';
import 'package:pet/services/native_sms_reader.dart';
import 'package:pet/services/sms_parser/sender_identity.dart';
import 'package:pet/services/sms_parser/transaction_evidence.dart';
import 'package:pet/services/sms_service.dart';
import 'package:pet/services/trusted_template_service.dart';
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
  TrustedTemplateService get _trustedTemplates =>
      TrustedTemplateService(dbHelper: _dbHelper);
  final RecurringPaymentRepository _recurringRepository =
      RecurringPaymentRepository();
  static const Uuid _uuid = Uuid();

  /// Incremented whenever automatic ingestion (or a review decision) changes
  /// the `transactions` ledger, so in-memory UI state can reload.
  static final ValueNotifier<int> ledgerRevision = ValueNotifier<int>(0);

  /// Incremented when the pending-review queue changes.
  static final ValueNotifier<int> reviewRevision = ValueNotifier<int>(0);

  /// Name the UI isolate registers [_revisionPort] under.
  static const String revisionPortName = 'pet.ingestion.revisions';
  static const String _ledgerMessage = 'ledger';
  static const String _reviewMessage = 'review';
  static ReceivePort? _revisionPort;

  /// Called once from the UI isolate's `main()`. WorkManager tasks (an SMS
  /// that arrives before the live listener attaches, periodic scans) and
  /// notification actions ingest in their own isolates, whose copies of
  /// [ledgerRevision] / [reviewRevision] nobody listens to; they forward
  /// each bump here so the UI reloads without a restart.
  static void listenForOtherIsolates() {
    if (_revisionPort != null) return;
    final port = ReceivePort();
    // A hot restart or a crashed UI isolate can leave a stale mapping.
    IsolateNameServer.removePortNameMapping(revisionPortName);
    IsolateNameServer.registerPortWithName(port.sendPort, revisionPortName);
    port.listen((message) {
      if (message == _ledgerMessage) ledgerRevision.value++;
      if (message == _reviewMessage) reviewRevision.value++;
    });
    _revisionPort = port;
  }

  @visibleForTesting
  static void stopListeningForOtherIsolates() {
    _revisionPort?.close();
    _revisionPort = null;
    IsolateNameServer.removePortNameMapping(revisionPortName);
  }

  static void _ledgerChanged() {
    ledgerRevision.value++;
    _forwardToUiIsolate(_ledgerMessage);
  }

  static void _reviewChanged() {
    reviewRevision.value++;
    _forwardToUiIsolate(_reviewMessage);
  }

  static void _forwardToUiIsolate(String message) {
    // In the UI isolate the listeners are already local.
    if (_revisionPort != null) return;
    IsolateNameServer.lookupPortByName(revisionPortName)?.send(message);
  }

  @visibleForTesting
  static void ledgerChangedForTesting() => _ledgerChanged();

  @visibleForTesting
  static void reviewChangedForTesting() => _reviewChanged();

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
        await _recurringRepository.upsertStatementBill(billItem);
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

    var fingerprint = CanonicalIdentityResolver.generateFingerprint(
      referenceId: refId,
      merchantName: merchant,
      upiId: upiId,
      amount: amount,
      timestamp: timestamp,
    );
    final isRefIdentity = CanonicalIdentityResolver.generateIdentityKey(
      referenceId: refId,
      merchantName: merchant,
      upiId: upiId,
      amount: amount,
      timestamp: timestamp,
    ).startsWith('ref:');

    // 4. Cross-Source Dedup Check against Core Ledger & Observations
    final existingTxnByFingerprint = await db.query(
      'transactions',
      where: 'sourceFingerprint = ?',
      whereArgs: [fingerprint],
      limit: 1,
    );

    String? matchedTxnId;
    if (existingTxnByFingerprint.isNotEmpty) {
      final candidateId = existingTxnByFingerprint.first['id'] as String;
      if (isRefIdentity ||
          await _isSameEventAs(db, candidateId, source, normalizedText)) {
        matchedTxnId = candidateId;
      } else {
        // Same merchant and amount in the same 15-minute bucket, from the
        // same source but a different message: a second, real payment
        // (two ₹20 teas). Keep it, under its own identity.
        fingerprint = sha256
            .convert(utf8.encode('$fingerprint|$observationHash'))
            .toString();
      }
    } else {
      // The bucketed fingerprint misses the same payment when the two
      // sources carry different evidence (UPI ref only in the SMS) or fall
      // either side of a 15-minute bucket edge. Look for it directly.
      matchedTxnId = await _findCrossSourceTwin(
        db,
        source: source,
        amount: amount,
        isIncome: classified.transactionType == 'credit',
        merchant: merchant,
        timestamp: timestamp,
      );
    }

    if (matchedTxnId != null) {
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
    final mappedCategoryId = learnedCategoryFits(learnedRule?.learnedCategoryId,
            isIncome: isIncome) ??
        importCategoryId(
          classified: classified,
          merchant: merchant,
          isIncome: isIncome,
          text: normalizedText,
        );

    // Evidence-based high-confidence determination (P2.2)
    final hasHighEvidence = (amount > 0) &&
        (classified.transactionType == 'debit' ||
            classified.transactionType == 'credit') &&
        (merchant != 'Unknown') &&
        (bank != 'Unknown Bank') &&
        (confidence >= 0.40);

    // A bank's own service SMS with a reference number is as reliable as
    // anything the app can see, even when it does not name the other party
    // (e.g. "credited with INR 75.00 … by UPI Ref No …").
    final isVerifiedBankAlert = isVerifiedBankAlertFor(
      source: source,
      sender: sender,
      classified: classified,
    );

    // Paying a credit-card bill or moving money between your own accounts
    // isn't spending or income: auto-importing it would count card
    // purchases twice, or a self-transfer as both income and expense. The
    // ledger has no "transfer" type, so let the user decide in Review.
    final possibleTransfer = isPossibleTransfer(normalizedText);
    // Offer wording ("get ₹500 cashback…") without the hard evidence a real
    // bank alert carries (account ending, reference, balance): an ad.
    final offerVerdict = TransactionEvidence.assess(
      normalizedText,
      accountTail: classified.accountTail,
      referenceId: refId,
      balanceAfter: classified.balanceAfter,
    );
    final looksLikeOffer = offerVerdict == OfferVerdict.review;
    // The user accepted a message of this exact shape from this sender
    // before and asked to always add them. Never overrides the transfer or
    // offer checks, and a credit template never accepts a debit.
    final trustedTemplate = (possibleTransfer ||
            offerVerdict != OfferVerdict.clean ||
            !(isIncome || classified.transactionType == 'debit'))
        ? null
        : await _trustedTemplates.match(
            sender: sender,
            isIncome: isIncome,
            text: normalizedText,
            payee: classified.merchantName,
          );
    final isAutoAccept = !possibleTransfer &&
        !looksLikeOffer &&
        ((confidence >= autoAcceptConfidenceThreshold) ||
            hasHighEvidence ||
            isVerifiedBankAlert ||
            trustedTemplate != null);
    final reviewReason = possibleTransfer
        ? 'possible_transfer'
        : looksLikeOffer
            ? 'looks_like_offer'
            : 'review_required';

    // Shown instead of "Unknown" when the bank does not name the payee.
    final displayMerchant = merchant == 'Unknown' && isVerifiedBankAlert
        ? unnamedPayeeLabel(classified)
        : merchant;

    final rejectReason = offerVerdict == OfferVerdict.reject
        ? 'looks_like_offer'
        : confidence < reviewConfidenceThreshold
            ? 'confidence_below_threshold ($confidence)'
            : null;

    if (rejectReason != null) {
      // Low confidence, or an offer rather than a transaction -> Reject
      _diagnostics.recordRejection();
      _diagnostics.recordEvent(
        source: source.name,
        state: 'rejected',
        confidence: confidence,
        bank: bank,
        merchant: merchant,
        decision: 'reject',
        reason: rejectReason,
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
          stateReason: rejectReason,
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
        reason: reviewReason == 'review_required'
            ? 'moderate_confidence'
            : reviewReason,
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
          stateReason: reviewReason,
          confidence: confidence,
        ),
      );

      _reviewChanged();

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
      type: mappedCategoryId == kTransferCategoryId
          ? TransactionType.transfer
          : (isIncome ? TransactionType.income : TransactionType.expense),
      categoryId: mappedCategoryId,
      date: classified.parsedDate,
      note: '$displayMerchant ($bank)',
      paymentMethod: PaymentMethod.upi,
      isRecurring: false,
      merchantName: displayMerchant,
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
      stateReason: trustedTemplate != null
          ? 'trusted_template_auto_promotion'
          : 'high_confidence_auto_promotion',
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
        merchantName: displayMerchant,
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

    _ledgerChanged();
    AppLogger.info(
      '[IngestionService] Promoted ₹$amount at $displayMerchant to Core Ledger ($txnId)',
    );
    await _afterLedgerInsert(promotedTxn);

    // Interactive notification for auto-promoted transaction
    await NotificationService.showTransactionDetectedNotification(
      observationId: observationId,
      merchant: displayMerchant,
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

  /// "Always add messages like this": trusts the shape of an observation
  /// the user just accepted, so the next one from the same sender is added
  /// without review. Returns the template hash (for undo), or null when the
  /// message can't be read any more.
  Future<String?> trustObservation(String observationId,
      {TransactionType? type}) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'financial_observations',
      where: 'observationId = ?',
      whereArgs: [observationId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final observation = FinancialObservation.fromMap(rows.first);
    if (observation.normalizedText.isEmpty) return null;
    final sender = observation.sender ?? observation.sourceIdentifier;
    final classified = await ClassificationRuleEngine.classify(
      observation.normalizedText,
      sender,
      observation.sourceTimestamp,
    );
    final isIncome = type != null
        ? type == TransactionType.income
        : classified?.transactionType == 'credit';
    return _trustedTemplates.trust(
      sender: sender,
      isIncome: isIncome,
      text: observation.normalizedText,
      payee: classified?.merchantName,
    );
  }

  /// Stops trusting a message shape (undo, or removed in Settings).
  Future<void> untrustTemplate(String templateHash) =>
      _trustedTemplates.remove(templateHash);

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
    final isCredit = classified?.transactionType == 'credit';
    final requestedType = overrideType ??
        (isCredit ? TransactionType.income : TransactionType.expense);
    final finalCategoryId = overrideCategoryId ??
        (requestedType == TransactionType.transfer
            ? kTransferCategoryId
            : importCategoryId(
                classified: classified,
                merchant: finalMerchant,
                isIncome: requestedType == TransactionType.income,
                text: observation.normalizedText,
              ));
    // The Transfer category and the transfer type always go together.
    final finalType = finalCategoryId == kTransferCategoryId
        ? TransactionType.transfer
        : requestedType;

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
            // A transfer keeps the direction the message shows.
            transactionType: switch (finalType) {
              TransactionType.income => 'credit',
              TransactionType.expense => 'debit',
              TransactionType.transfer => isCredit ? 'credit' : 'debit',
            },
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

    _ledgerChanged();
    _reviewChanged();
    if (linkedTo == txnId) await _afterLedgerInsert(txnRecord);
    return linkedTo == txnId ? txnRecord : null;
  }

  /// Follow-ups for a newly recorded transaction. Best effort: never blocks
  /// or fails the import.
  Future<void> _afterLedgerInsert(TransactionRecord txn) async {
    // Autopaid bills: mark the matching confirmed bill as paid.
    await BillPaymentMatcher.recordIfBillPayment(txn);
    // Money in: settle the open invoice it pays, or ask about it.
    final invoiceMatch = await InvoicePaymentMatcher.recordIfInvoicePayment(
      txn,
      userId: _syncUserId(),
    );
    if (invoiceMatch == InvoiceMatchOutcome.paid) {
      await _fileAsClientIncomeUnlocked(txn.id);
    }
    // Screens were told about the ledger before the invoice changed.
    if (invoiceMatch != null) _ledgerChanged();
    // Focus Mode: tell the user a paused category was spent in.
    await FocusModeNotifier.notifyIfPaused(txn, userId: _syncUserId());
  }

  /// Files a client's payment as Freelance income, even when the client is a
  /// person ("From people" keeps money out of income). Categories the user
  /// or the importer chose on purpose, like Salary, are left alone.
  Future<void> fileAsClientIncome(String transactionId) =>
      _serialized(() async {
        await _fileAsClientIncomeUnlocked(transactionId);
        _ledgerChanged();
      });

  Future<void> _fileAsClientIncomeUnlocked(String transactionId) async {
    try {
      final db = await _dbHelper.database;
      final rows = await db.query(
        'transactions',
        where: 'id = ?',
        whereArgs: [transactionId],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final current = TransactionRecord.fromMap(rows.first);
      const generic = {kFromPeopleCategoryId, 'cat_other_income'};
      if (!generic.contains(current.categoryId)) return;
      final updated = current.copyWith(
        categoryId: 'cat_freelance',
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
    } catch (e) {
      AppLogger.debug('[IngestionService] Client income filing failed: $e');
    }
  }

  /// Remembers the user's "Count as income" choice for the payee of [txn],
  /// so future credits from them land in the same category. Keyed on the
  /// payee name the import matched against (the stored observation text has
  /// phone numbers masked, so re-reading it would give a different UPI ID).
  Future<void> rememberIncomeChoice(TransactionRecord txn) async {
    if (txn.type != TransactionType.income) return;
    final merchant = txn.merchantName;
    if (merchant == null || merchant.isEmpty || merchant == 'Unknown') return;
    await _merchantRuleService.learnRule(
      identifier: merchant,
      learnedMerchantName: merchant,
      categoryId: txn.categoryId,
    );
  }

  /// A learned category is only reused for money moving the same way: a
  /// "From people" rule for a friend must not label what you pay them.
  /// Custom categories (not in the defaults) are trusted as learned.
  @visibleForTesting
  static String? learnedCategoryFits(String? categoryId,
      {required bool isIncome}) {
    if (categoryId == null) return null;
    final known = defaultCategories.where((c) => c.id == categoryId);
    if (known.isEmpty) return categoryId;
    // A transfer (card bill, own account) can move either way.
    if (known.first.type == 'transfer') return categoryId;
    return (known.first.type == 'income') == isIncome ? categoryId : null;
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
        _ledgerChanged();
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

    if (ledgerChanged) _ledgerChanged();
    _reviewChanged();
  }

  /// Whether an SMS is a bank's own service alert with enough evidence to
  /// import without review: a bank service/transactional sender ID, a
  /// reference number, a detected direction and a positive amount.
  /// Merchant confirmations (e.g. Swiggy) and promotions never qualify.
  @visibleForTesting
  static bool isVerifiedBankAlertFor({
    required FinancialObservationSource source,
    required String sender,
    required ClassifiedTransaction classified,
  }) {
    final ref = classified.referenceId?.trim() ?? '';
    return source == FinancialObservationSource.sms &&
        SenderIdentity.isBankServiceSender(sender) &&
        classified.bankName != 'Unknown Bank' &&
        classified.hasDirection &&
        ref.length >= 6 &&
        classified.amount > 0 &&
        classified.confidence >= reviewConfidenceThreshold;
  }

  /// Payee shown when a bank alert does not name the other party.
  @visibleForTesting
  static String unnamedPayeeLabel(ClassifiedTransaction classified) {
    final channel = switch (classified.channel) {
      'imps' => 'IMPS',
      'neft' => 'NEFT',
      'rtgs' => 'RTGS',
      'upi' => 'UPI',
      _ => 'Bank',
    };
    return classified.transactionType == 'credit'
        ? '$channel credit'
        : '$channel payment';
  }

  /// Sub-types that are plain money movements (not refunds, cashback or
  /// reversals, which keep their own categories).
  static const Set<String> _plainTransferSubTypes = {
    'payment',
    'transfer',
    'collect',
    'unknown',
    '',
  };

  /// Category for an imported transaction (when the user hasn't taught one
  /// for this payee): money a *person* sent you is "From people" — tracked,
  /// but not counted as income; everything else uses the usual mapping.
  @visibleForTesting
  static String importCategoryId({
    required ClassifiedTransaction? classified,
    required String merchant,
    required bool isIncome,
    required String text,
  }) {
    // The payee is usually just the employer ("ACME TECHNOLOGIES"), so the
    // salary cue is only in the message.
    if (isIncome && looksLikeSalary(text)) return 'cat_salary';
    if (isIncome &&
        classified != null &&
        _plainTransferSubTypes.contains(classified.transactionSubType) &&
        CounterpartyClassifier.classify(
              payeeName: classified.merchantName,
              upiId: classified.upiId,
              channel: classified.channel,
              text: text,
            ) ==
            CounterpartyType.person) {
      return kFromPeopleCategoryId;
    }
    return CategoryMapper.mapToCategoryId(
      parserCategory: classified?.category,
      merchantName: merchant,
      isIncome: isIncome,
    );
  }

  static final RegExp _salaryAccount =
      RegExp(r'\bsal(?:ary)?\s*(?:a/?c|acc(?:oun)?t)\b', caseSensitive: false);
  static final RegExp _salaryCue = RegExp(
    r'\b(?:salary|payroll|sal\s+cr(?:edit(?:ed)?)?|sal\s+for\s+\w+)\b',
    caseSensitive: false,
  );

  /// A credit that says it is salary. "Credited to your Salary A/c" only
  /// names the account type, so it doesn't count.
  @visibleForTesting
  static bool looksLikeSalary(String text) =>
      _salaryCue.hasMatch(text.replaceAll(_salaryAccount, ' '));

  /// Messages about paying a credit-card bill or moving money between the
  /// user's own accounts. Card *purchases* ("spent on your credit card at
  /// Amazon") deliberately don't match.
  static final List<RegExp> _transferPatterns = [
    RegExp(r'\b(?:credit\s*card|cc)\s*(?:bill|dues?|outstanding)\b'),
    RegExp(r'towards\s+(?:your\s+)?(?:\w+\s+){0,3}(?:credit\s*)?card'),
    RegExp(r'payment\s+(?:of\s+\S+\s+\S*\s*)?(?:has\s+been\s+)?received\b'
        r'.{0,60}\bcard\b'),
    RegExp(r'\breceived\s+(?:a\s+)?payment\b.{0,60}\bcard\b'),
    RegExp(r'\bself[\s-]?transfer\b'),
    RegExp(r'\b(?:to|into)\s+(?:your\s+)?own\s+(?:a/?c|account)\b'),
    RegExp(r'\btransfer(?:red)?\s+to\s+self\b'),
  ];

  @visibleForTesting
  static bool isPossibleTransfer(String text) {
    final t = text.toLowerCase();
    return _transferPatterns.any((p) => p.hasMatch(t));
  }

  // ─── Internal Helpers ──────────────────────────────────────────────

  /// Whether a new message whose fingerprint matches ledger row [txnId] is
  /// the same payment: either it came from a different source (SMS vs app
  /// notification), or it is the same message text delivered again (e.g.
  /// broadcast and inbox scan with slightly different timestamps).
  Future<bool> _isSameEventAs(
    Database db,
    String txnId,
    FinancialObservationSource source,
    String normalizedText,
  ) async {
    final rows = await db.query(
      'financial_observations',
      columns: ['source', 'normalizedText'],
      where: 'canonicalTransactionId = ?',
      whereArgs: [txnId],
    );
    // No provenance to compare with: keep the conservative merge.
    if (rows.isEmpty) return true;
    final redacted = SmsService.redactSensitiveData(normalizedText);
    for (final row in rows) {
      if (row['source'] != source.name) return true;
      final stored = row['normalizedText'] as String? ?? '';
      // Text already purged (older than the retention window): can't tell.
      if (stored.isEmpty || stored == redacted) return true;
    }
    return false;
  }

  /// A ledger transaction imported from the *other* source (SMS vs app
  /// notification) for the same amount and direction within
  /// [CanonicalIdentityResolver.windowDuration], whose merchant doesn't
  /// contradict [merchant]. Returns its id, or null.
  Future<String?> _findCrossSourceTwin(
    Database db, {
    required FinancialObservationSource source,
    required double amount,
    required bool isIncome,
    required String merchant,
    required DateTime timestamp,
  }) async {
    const window = CanonicalIdentityResolver.windowDuration;
    final rows = await db.rawQuery('''
      SELECT t.id, t.merchantName
      FROM financial_observations o
      JOIN transactions t ON t.id = o.canonicalTransactionId
      WHERE o.source != ?
        AND o.state IN ('promoted', 'linked')
        AND o.sourceTimestamp >= ? AND o.sourceTimestamp <= ?
        AND ABS(t.amount - ?) < 0.01
        AND t.type = ?
      ORDER BY ABS(julianday(o.sourceTimestamp) - julianday(?))
    ''', [
      source.name,
      timestamp.subtract(window).toIso8601String(),
      timestamp.add(window).toIso8601String(),
      amount,
      isIncome ? 'income' : 'expense',
      timestamp.toIso8601String(),
    ]);
    for (final row in rows) {
      if (_merchantsCompatible(merchant, row['merchantName'] as String?)) {
        return row['id'] as String;
      }
    }
    return null;
  }

  /// Two merchant names that could describe the same payee: equal after
  /// normalisation, one containing the other, or either one unknown.
  static bool _merchantsCompatible(String a, String? b) {
    String clean(String? s) =>
        (s ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final x = clean(a);
    final y = clean(b);
    const unknown = {'', 'unknown'};
    if (unknown.contains(x) || unknown.contains(y)) return true;
    return x == y || x.contains(y) || y.contains(x);
  }

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
