import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:pet/core/utils/app_logger.dart';
import 'package:pet/services/platform_stub.dart'
    if (dart.library.io) 'package:pet/services/platform_native.dart'
    as platform;

import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:pet/data/models/sms_transaction.dart';
import 'package:pet/data/repositories/sms_transaction_repository.dart';
import 'package:pet/services/native_sms_reader.dart';
import 'package:pet/services/classification_rule_engine.dart';
import 'package:pet/premium/services/merchant_normalizer.dart';

/// Service for reading, listening to, and parsing bank SMS messages.
///
/// Android only. Uses native `NativeSmsReader` ContentResolver and EventChannel.
/// All SMS parsing is performed entirely on-device.
class SmsService {
  static final SmsService _instance = SmsService._internal();
  factory SmsService() => _instance;
  SmsService._internal();

  final NativeSmsReader _nativeReader = NativeSmsReader();
  final SmsTransactionRepository _repository = SmsTransactionRepository();
  final Uuid _uuid = const Uuid();

  bool _isListening = false;
  bool get isListening => _isListening;
  StreamSubscription<NativeSmsMessage>? _nativeSmsSubscription;
  StreamSubscription<NativeSmsMessage>? _notificationSubscription;

  /// Check if the platform supports SMS reading (Android only).
  static bool get isSupported => !kIsWeb && platform.isAndroid;

  // ─── Permission Handling ──────────────────────────────────────────

  /// Request SMS permissions (READ_SMS and RECEIVE_SMS).
  /// Returns `true` if permissions are granted.
  ///
  /// Uses permission_handler directly for reliability.
  Future<bool> requestPermissions() async {
    if (!isSupported) return false;

    // Request both permissions using permission_handler (independent of
    // default SMS app settings).
    final statuses = await [Permission.sms, Permission.phone].request();

    final smsGranted = statuses[Permission.sms]?.isGranted ?? false;
    final phoneGranted = statuses[Permission.phone]?.isGranted ?? false;

    AppLogger.debug(
      '[PET-SMS] Permissions — SMS: $smsGranted, Phone: $phoneGranted',
    );

    return smsGranted;
  }

  Future<bool> checkNotificationAccess() async {
    return _nativeReader.hasNotificationAccess();
  }

  Future<void> requestNotificationAccess() async {
    await _nativeReader.requestNotificationAccess();
  }

  // ─── Inbox Scan ───────────────────────────────────────────────────

  /// Scan the SMS inbox (and sent box) for bank transaction messages.
  ///
  /// [lookbackDays] — How many days back to scan (default: 90).
  /// Returns the number of new transactions found and stored.
  ///
  /// Uses the native ContentResolver to read SMS directly from the system
  /// content provider. Reads both inbox AND sent SMS for comprehensive
  /// UPI transaction coverage.
  Future<int> scanInbox({int lookbackDays = 90}) async {
    if (!isSupported) {
      AppLogger.debug('[PET-SMS] scanInbox: Not supported on this platform');
      return 0;
    }

    AppLogger.debug(
      '[PET-SMS] Starting inbox scan (lookbackDays=$lookbackDays)',
    );

    try {
      // PRIMARY: Use native ContentResolver for ALL SMS (inbox + sent)
      final allMessages = await _nativeReader.getAllSms(
        lookbackDays: lookbackDays,
      );

      if (allMessages.isNotEmpty) {
        AppLogger.debug(
          '[PET-SMS] Native reader found ${allMessages.length} SMS (inbox+sent)',
        );
        final count = await _processMessages(allMessages);
        AppLogger.debug(
          '[PET-SMS] Processed $count transactions from native reader',
        );
        return count;
      }

      AppLogger.debug(
        '[PET-SMS] Native getAllSms returned empty, trying inbox-only',
      );

      // FALLBACK: Try inbox-only if getAllSms returned empty
      final inboxMessages = await _nativeReader.getInboxSms(
        lookbackDays: lookbackDays,
      );

      if (inboxMessages.isNotEmpty) {
        AppLogger.debug(
          '[PET-SMS] Native reader found ${inboxMessages.length} SMS in inbox',
        );
        final count = await _processMessages(inboxMessages);
        AppLogger.debug('[PET-SMS] Processed $count transactions from inbox');
        return count;
      }

      AppLogger.debug('[PET-SMS] No SMS found in native scan');
      return 0;
    } catch (e, stack) {
      AppLogger.debug('[PET-SMS] Native reader error: $e');
      AppLogger.debug('[PET-SMS] Stack trace: $stack');
      await _persistDetectionFailure();
      return 0;
    }
  }

  /// Persist the timestamp of the last SMS detection failure.
  /// UI can check this to show "Auto-detection paused" banner.
  Future<void> _persistDetectionFailure() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        'pet_sms_last_failure',
        DateTime.now().millisecondsSinceEpoch,
      );
      AppLogger.debug('[PET-SMS] Detection failure persisted');
    } catch (_) {
      // Best-effort — don't crash on prefs failure
    }
  }

  /// Whether the last SMS scan ended in complete failure.
  static Future<DateTime?> getLastFailureTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ms = prefs.getInt('pet_sms_last_failure');
      if (ms == null) return null;
      return DateTime.fromMillisecondsSinceEpoch(ms);
    } catch (_) {
      return null;
    }
  }

  Future<int> _processMessages(List<NativeSmsMessage> messages) async {
    final processedHashes = await _repository.getAllHashes();

    // Pre-filter out messages already in processing state (accepted, ignored, deleted, etc.)
    final unparsedMessages = messages.where((m) {
      if (m.body.isEmpty) return false;
      final hash = SmsTransaction.generateHash(m.body, m.dateTime);
      return !processedHashes.contains(hash);
    }).toList();

    AppLogger.debug(
      '[PET-SMS] Processing ${unparsedMessages.length}/${messages.length} unparsed messages from native reader (dispatching to isolate)',
    );

    if (unparsedMessages.isEmpty) {
      AppLogger.debug('[PET-SMS] All messages already in processing state — skipping isolate');
      return 0;
    }

    // Run the CPU-heavy classification inside an isolate
    final parsed = await compute(_parseMessagesIsolate, _IsolateData(unparsedMessages));

    AppLogger.debug(
      '[PET-SMS] Isolate returned ${parsed.length} parsed transactions',
    );

    final List<SmsTransaction> newTxns = [];
    int duplicateCount = 0;

    for (final txn in parsed) {
      // DB dedup: skip if already persisted/ignored/deleted from a previous scan.
      final exists = await _repository.existsByHash(txn.smsHash);
      if (exists) {
        duplicateCount++;
        continue;
      }

      // Cross-source dedup: check if a notification already captured this
      if (txn.referenceId != null) {
        final refDup = await _repository.existsByReferenceAndAmount(
          txn.referenceId!,
          txn.amount,
          txn.timestamp,
        );
        if (refDup) {
          duplicateCount++;
          continue;
        }
      }

      newTxns.add(txn);
    }

    AppLogger.debug(
      '[PET-SMS] Main Thread: Skipped $duplicateCount duplicates, '
      'new ${newTxns.length}',
    );

    // Calculate latest SMS dateMillis for watermark advancement
    final int? latestMs = messages.isNotEmpty
        ? messages.map((m) => m.dateMillis).reduce((a, b) => a > b ? a : b)
        : null;

    // Atomically insert transaction rows AND update watermark in ONE SQLite transaction
    final insertedCount = await _repository.insertBatchWithWatermark(
      transactions: newTxns,
      watermarkTimestamp: latestMs,
      watermarkKeys: const ['sms_watermark'],
    );

    AppLogger.debug('[PET-SMS] Atomically inserted $insertedCount new transactions and updated watermark ($latestMs)');

    return insertedCount;
  }

  // ─── Live Listener ────────────────────────────────────────────────

  /// Start listening for incoming SMS messages.
  /// Parses and stores transactions in real-time.
  ///
  /// Uses the native EventChannel listener (default-SMS-app independent)
  /// and the notification listener for maximum reliability.
  void startListening({Function(SmsTransaction)? onNewTransaction}) {
    if (!isSupported || _isListening) return;

    // PRIMARY: Native EventChannel listener (default-SMS-app independent)
    _nativeSmsSubscription = _nativeReader.incomingSmsStream.listen(
      (NativeSmsMessage nativeMsg) async {
        final body = nativeMsg.body;
        final sender = nativeMsg.address;
        final timestamp = nativeMsg.dateTime;

        if (body.isEmpty) return;

        // Use two-tier classification engine
        final classified = await ClassificationRuleEngine.classify(
          body,
          sender,
          timestamp,
        );
        if (classified == null) return;

        final hash = SmsTransaction.generateHash(body, timestamp);
        final exists = await _repository.existsByHash(hash);
        if (exists) return;

        // Cross-source dedup: check if a notification already captured this
        if (classified.referenceId != null) {
          final refDup = await _repository.existsByReferenceAndAmount(
            classified.referenceId!,
            classified.amount,
            classified.parsedDate,
          );
          if (refDup) return;
        }

        final category =
            classified.category ?? inferCategoryFromClassified(classified);
        final normalizedMerchant = MerchantNormalizer.normalize(
          classified.merchantName,
        );

        final transaction = SmsTransaction(
          id: _uuid.v4(),
          amount: classified.amount,
          merchantName: normalizedMerchant,
          bankName: classified.bankName,
          transactionType: classified.transactionType,
          transactionSubType: classified.transactionSubType,
          timestamp: classified.parsedDate,
          rawSmsBody: redactSensitiveData(body),
          smsSender: sender,
          smsHash: hash,
          category: category,
          referenceId: classified.referenceId,
          upiId: classified.upiId,
          confidence: classified.confidence,
          source: 'sms',
        );

        final inserted = await _repository.insertSmsTransaction(transaction);
        if (inserted) {
          AppLogger.debug(
            '[PET-SMS] Native listener: new transaction (${classified.classifiedBy.name}): '
            '${transaction.amount} ${transaction.transactionType} at ${transaction.merchantName}',
          );
          onNewTransaction?.call(transaction);
        }
      },
      onError: (error) {
        AppLogger.debug('[PET-SMS] Native listener error: $error');
      },
    );

    // NOTIFICATION LISTENER: Capture UPI app notifications (GPay, PhonePe, Paytm)
    _notificationSubscription = _nativeReader.incomingNotificationStream.listen(
      (NativeSmsMessage notifMsg) async {
        final txn = await processNotificationMessage(notifMsg);
        if (txn != null) {
          onNewTransaction?.call(txn);
        }
      },
      onError: (error) {
        AppLogger.debug('[PET-SMS] Notification listener error: $error');
      },
    );

    _isListening = true;
    AppLogger.debug(
      '[PET-SMS] Started listening for incoming SMS via native reader',
    );
  }

  /// Parses, deduplicates, and inserts a single notification message into SQLite.
  /// Returns the inserted [SmsTransaction] or `null` if the message is non-financial,
  /// unclassifiable, or a duplicate.
  Future<SmsTransaction?> processNotificationMessage(
    NativeSmsMessage notifMsg,
  ) async {
    final body = notifMsg.body;
    final sender = notifMsg.address;
    final timestamp = notifMsg.dateTime;

    if (body.isEmpty) return null;

    final classified = await ClassificationRuleEngine.classify(
      body,
      sender,
      timestamp,
    );
    if (classified == null) return null;

    final hash = SmsTransaction.generateHash(body, timestamp);
    final exists = await _repository.existsByHash(hash);
    if (exists) return null;

    // Cross-source dedup: check if SMS already captured this transaction
    if (classified.referenceId != null) {
      final refDup = await _repository.existsByReferenceAndAmount(
        classified.referenceId!,
        classified.amount,
        classified.parsedDate,
      );
      if (refDup) return null;
    }

    final category =
        classified.category ?? inferCategoryFromClassified(classified);
    final normalizedMerchant = MerchantNormalizer.normalize(
      classified.merchantName,
    );

    final transaction = SmsTransaction(
      id: _uuid.v4(),
      amount: classified.amount,
      merchantName: normalizedMerchant,
      bankName: classified.bankName,
      transactionType: classified.transactionType,
      transactionSubType: classified.transactionSubType,
      timestamp: classified.parsedDate,
      rawSmsBody: redactSensitiveData(body),
      smsSender: sender,
      smsHash: hash,
      category: category,
      referenceId: classified.referenceId,
      upiId: classified.upiId,
      confidence: classified.confidence,
      source: 'notification',
    );

    final inserted = await _repository.insertSmsTransaction(transaction);
    if (inserted) {
      AppLogger.debug(
        '[PET-SMS] Notification listener: new transaction: '
        '${transaction.amount} ${transaction.transactionType} at ${transaction.merchantName}',
      );
      return transaction;
    }
    return null;
  }

  /// Process all pending notifications from the native encrypted cache.
  /// Pops them from native storage and ingests them into the SQLite database.
  /// Returns the list of newly created and stored transactions.
  Future<List<SmsTransaction>> processPendingNotifications() async {
    if (!isSupported) return [];
    try {
      final pendingMessages = await _nativeReader.popPendingNotifications();
      if (pendingMessages.isEmpty) return [];

      final results = <SmsTransaction>[];
      for (final msg in pendingMessages) {
        final txn = await processNotificationMessage(msg);
        if (txn != null) {
          results.add(txn);
        }
      }
      AppLogger.debug(
        '[PET-SMS] Processed ${pendingMessages.length} cached notifications -> ${results.length} new transactions',
      );
      return results;
    } catch (e) {
      AppLogger.debug('[PET-SMS] Error processing pending notifications: $e');
      return [];
    }
  }

  /// Stop listening for incoming SMS messages.
  void stopListening() {
    _nativeSmsSubscription?.cancel();
    _nativeSmsSubscription = null;
    _notificationSubscription?.cancel();
    _notificationSubscription = null;
    _nativeReader.stopListening();
    _isListening = false;
    AppLogger.debug('[PET-SMS] Stopped listening for incoming SMS');
  }

  // ─── Internal Processing ──────────────────────────────────────────

  static bool _matchesAny(String text, List<String> keywords) {
    for (final keyword in keywords) {
      if (text.contains(keyword)) return true;
    }
    return false;
  }

  /// Redact sensitive data from SMS body before DB storage.
  /// Replaces account numbers and phone numbers with XX**** (keeping last 4 digits).
  /// Keeps the redacted version for display; dedup uses hash of original.
  static String redactSensitiveData(String body) {
    var redacted = body;

    // 1. Redact account and card numbers preceded by account/card context keywords.
    final accountContextPattern = RegExp(
      r'(?:\b(?:a/c|account|acct|card|a/c\s+no|account\s+no|card\s+no|a/c\s+ending|card\s+ending)\b\.?\s*:?\s*)(?:[a-zA-Z]*\s*)?(\d{4,})(\d{4})\b',
      caseSensitive: false,
    );
    redacted = redacted.replaceAllMapped(accountContextPattern, (m) {
      final fullMatch = m.group(0)!;
      final prefixDigits = m.group(1)!;
      final last4 = m.group(2)!;
      final totalDigits = prefixDigits.length + 4;
      if (totalDigits >= 8) {
        final firstDigitIdx = fullMatch.indexOf(RegExp(r'\d'));
        final prefixText = fullMatch.substring(0, firstDigitIdx);
        return '${prefixText}XX****$last4';
      }
      return fullMatch;
    });

    // 2. Redact standalone 13-16 digit account/card numbers (not preceded by Ref/Txn/UPI keywords).
    final longAccountPattern = RegExp(r'(?<!\d)(\d{9,12})(\d{4})(?!\d)');
    redacted = redacted.replaceAllMapped(longAccountPattern, (m) {
      final startIdx = m.start;
      final precedingText = redacted.substring(0, startIdx).toLowerCase();
      // Skip if preceded by reference ID keywords
      if (RegExp(r'(?:ref|rrn|utr|txnid|txn|upi|reference)\s*(?:no|num|id)?\.?\s*:?\s*$', caseSensitive: false).hasMatch(precedingText)) {
        return m.group(0)!;
      }
      final last4 = m.group(2)!;
      return 'XX****$last4';
    });

    // 3. Redact 10-digit Indian phone numbers (+91XXXXXXXXXX, 0XXXXXXXXXX, or 10-digit starting with 6-9).
    // Enforces strict digit boundaries (?<!\d) and (?!\d) so 12-digit UPI ref numbers are NEVER matched.
    final phonePattern = RegExp(
      r'(?<!\d)(?:\+91[\s-]?)?([6-9]\d{5})(\d{4})(?!\d)',
    );
    redacted = redacted.replaceAllMapped(phonePattern, (m) {
      final startIdx = m.start;
      final precedingText = redacted.substring(0, startIdx).toLowerCase();
      // Do not redact if preceded by currency or reference ID keywords
      if (RegExp(r'(?:rs\.?|inr\.?|₹)\s*$', caseSensitive: false).hasMatch(precedingText)) {
        return m.group(0)!;
      }
      if (RegExp(r'(?:ref|rrn|utr|txnid|txn|upi|reference)\s*(?:no|num|id)?\.?\s*:?\s*$', caseSensitive: false).hasMatch(precedingText)) {
        return m.group(0)!;
      }
      final last4 = m.group(2)!;
      return 'XX****$last4';
    });

    return redacted;
  }

  /// Infer category from a ClassifiedTransaction (used when no rule-assigned
  /// category is available, i.e., the hardcoded parser handled the SMS).
  static String inferCategoryFromClassified(ClassifiedTransaction classified) {
    final merchant = MerchantNormalizer.normalize(
      classified.merchantName,
    ).toLowerCase();
    final upi = (classified.upiId ?? '').toLowerCase();

    // Food & dining
    if (_matchesAny(merchant, [
      'swiggy',
      'zomato',
      'restaurant',
      'cafe',
      'food',
      'pizza',
      'burger',
      'domino',
      'mcdonald',
      'kfc',
      'starbuck',
    ])) {
      return 'Food & Dining';
    }

    // Transport
    if (_matchesAny(merchant, [
      'uber',
      'ola',
      'rapido',
      'metro',
      'irctc',
      'petrol',
      'fuel',
      'parking',
      'fastag',
      'toll',
    ])) {
      return 'Transport';
    }

    // Shopping
    if (_matchesAny(merchant, [
      'amazon',
      'flipkart',
      'myntra',
      'ajio',
      'meesho',
      'shop',
      'mall',
      'store',
      'mart',
      'retail',
      'nykaa',
    ])) {
      return 'Shopping';
    }

    // Bills & utilities
    if (_matchesAny(merchant, [
      'electricity',
      'water',
      'gas',
      'broadband',
      'wifi',
      'jio',
      'airtel',
      'vi ',
      'vodafone',
      'bsnl',
      'bill',
    ])) {
      return 'Bills & Utilities';
    }

    if (_matchesAny(merchant, ['recharge', 'dth', 'prepaid', 'postpaid'])) {
      return 'Recharge & DTH';
    }

    if (_matchesAny(merchant, [
      'pharmacy',
      'medical',
      'hospital',
      'doctor',
      'health',
      'clinic',
      'apollo',
      'medplus',
      '1mg',
      'pharmeasy',
    ])) {
      return 'Health';
    }

    if (_matchesAny(merchant, [
      'netflix',
      'hotstar',
      'prime video',
      'spotify',
      'youtube',
      'cinema',
      'pvr',
      'inox',
      'movie',
      'game',
    ])) {
      return 'Entertainment';
    }

    if (_matchesAny(merchant, [
      'grocery',
      'grocer',
      'bigbasket',
      'blinkit',
      'zepto',
      'dmart',
      'reliance fresh',
      'instamart',
      'dunzo',
    ])) {
      return 'Groceries';
    }

    if (_matchesAny(merchant, [
      'emi',
      'loan',
      'credit card',
      'bajaj fin',
      'hdfc ltd',
    ])) {
      return 'EMI & Loans';
    }

    if (_matchesAny(merchant, [
      'school',
      'college',
      'university',
      'tuition',
      'course',
      'udemy',
      'coursera',
      'unacademy',
      'byju',
    ])) {
      return 'Education';
    }

    // Check UPI patterns
    if (_matchesAny(upi, ['swiggy', 'zomato'])) return 'Food & Dining';
    if (_matchesAny(upi, ['uber', 'ola', 'rapido'])) return 'Transport';
    if (_matchesAny(upi, ['amazon', 'flipkart'])) return 'Shopping';

    return 'Uncategorized';
  }
}

// ─── Isolate Workers ────────────────────────────────────────────────────────

/// Data payload for the isolate.
class _IsolateData {
  final List<NativeSmsMessage> messages;
  const _IsolateData(this.messages);
}

/// Top-level isolate function for parsing a batch of SMS messages.
Future<List<SmsTransaction>> _parseMessagesIsolate(_IsolateData data) async {
  final parsed = <SmsTransaction>[];
  final seenHashes = <String>{};
  final uuid = const Uuid();

  for (final msg in data.messages) {
    final body = msg.body;
    final sender = msg.address;
    final timestamp = msg.dateTime;

    if (body.isEmpty) continue;

    final classified = await ClassificationRuleEngine.classify(
      body,
      sender,
      timestamp,
      logUnknown: false, // Don't hit sqflite inside the isolate
    );

    if (classified == null) continue;

    final hash = SmsTransaction.generateHash(body, timestamp);

    // In-batch dedup
    if (seenHashes.contains(hash)) {
      continue;
    }
    seenHashes.add(hash);

    final category = classified.category ?? SmsService.inferCategoryFromClassified(classified);
    final normalizedMerchant = MerchantNormalizer.normalize(classified.merchantName);

    parsed.add(
      SmsTransaction(
        id: uuid.v4(),
        amount: classified.amount,
        merchantName: normalizedMerchant,
        bankName: classified.bankName,
        transactionType: classified.transactionType,
        transactionSubType: classified.transactionSubType,
        timestamp: classified.parsedDate,
        rawSmsBody: SmsService.redactSensitiveData(body),
        smsSender: sender,
        smsHash: hash,
        category: category,
        referenceId: classified.referenceId,
        upiId: classified.upiId,
        confidence: classified.confidence,
        source: 'sms',
      ),
    );
  }

  return parsed;
}
