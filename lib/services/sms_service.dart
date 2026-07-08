import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:pet/core/utils/app_logger.dart';
import 'package:pet/services/platform_stub.dart'
    if (dart.library.io) 'package:pet/services/platform_native.dart'
    as platform;

import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telephony/telephony.dart';
import 'package:uuid/uuid.dart';
import 'package:pet/data/models/sms_transaction.dart';
import 'package:pet/data/repositories/sms_transaction_repository.dart';
import 'package:pet/services/native_sms_reader.dart';
import 'package:pet/services/classification_rule_engine.dart';
import 'package:pet/premium/services/merchant_normalizer.dart';

/// Top-level background handler for incoming SMS (required by Telephony).
/// This function runs even when the app is terminated.
///
/// SECURITY: All processing is on-device. No SMS data leaves the device.
@pragma('vm:entry-point')
void backgroundMessageHandler(SmsMessage message) async {
  // In background mode we cannot access the full Flutter engine easily,
  // so we log the SMS for processing on next app launch.
  // The WorkManager periodic task will pick it up.
  AppLogger.debug('[PET-SMS] Background SMS from: ${message.address}');
}

/// Service for reading, listening to, and parsing bank SMS messages.
///
/// Android only. Uses the `telephony` package for SMS access.
/// All SMS parsing is performed entirely on-device.
class SmsService {
  static final SmsService _instance = SmsService._internal();
  factory SmsService() => _instance;
  SmsService._internal();

  /// SharedPreferences key for incremental scan watermark.
  static const String _kLastProcessedTimestamp = 'pet_last_sms_timestamp';

  final Telephony _telephony = Telephony.instance;
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
  /// Uses permission_handler directly for reliability — the telephony
  /// package's permission request can fail after default SMS app changes.
  Future<bool> requestPermissions() async {
    if (!isSupported) return false;

    // Request both permissions using permission_handler (independent of
    // the telephony package and default SMS app settings).
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
  /// UPI transaction coverage. Falls back to the telephony package if
  /// the native channel fails.
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

      // LAST RESORT: Use telephony package
      AppLogger.debug(
        '[PET-SMS] Native reader empty, falling back to telephony package',
      );
      final count = await _scanInboxViaTelephony(lookbackDays: lookbackDays);
      AppLogger.debug(
        '[PET-SMS] Telephony fallback processed $count transactions',
      );
      return count;
    } catch (e, stack) {
      AppLogger.debug('[PET-SMS] Native reader error: $e');
      AppLogger.debug('[PET-SMS] Stack trace: $stack');
      try {
        AppLogger.debug('[PET-SMS] Attempting telephony fallback after error');
        return _scanInboxViaTelephony(lookbackDays: lookbackDays);
      } catch (e2) {
        AppLogger.debug('[PET-SMS] Fallback telephony also failed: $e2');
        // Both paths failed — persist failure timestamp for UI feedback
        await _persistDetectionFailure();
        return 0;
      }
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
    AppLogger.debug(
      '[PET-SMS] Processing ${messages.length} messages from native reader (dispatching to isolate)',
    );

    // Run the CPU-heavy classification inside an isolate
    final parsed = await compute(_parseMessagesIsolate, _IsolateData(messages));

    AppLogger.debug(
      '[PET-SMS] Isolate returned ${parsed.length} parsed transactions',
    );

    final List<SmsTransaction> newTxns = [];
    int duplicateCount = 0;

    for (final txn in parsed) {
      // DB dedup: skip if already persisted from a previous scan.
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

    final insertedCount = await _repository.insertBatch(newTxns);
    AppLogger.debug('[PET-SMS] Inserted $insertedCount new transactions');

    // Update the last-processed watermark for incremental scans
    if (messages.isNotEmpty) {
      final latestMs = messages
          .map((m) => m.dateMillis)
          .reduce((a, b) => a > b ? a : b);
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getInt(_kLastProcessedTimestamp) ?? 0;
      if (latestMs > existing) {
        await prefs.setInt(_kLastProcessedTimestamp, latestMs);
      }
    }

    return insertedCount;
  }

  Future<int> _scanInboxViaTelephony({int lookbackDays = 90}) async {
    try {
      AppLogger.debug('[PET-SMS] Telephony: Starting inbox scan');

      final List<SmsMessage> messages = await _telephony.getInboxSms(
        columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
        filter: SmsFilter.where(SmsColumn.DATE).greaterThan(
          DateTime.now()
              .subtract(Duration(days: lookbackDays))
              .millisecondsSinceEpoch
              .toString(),
        ),
        sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
      );

      AppLogger.debug(
        '[PET-SMS] Telephony: Found ${messages.length} SMS in inbox',
      );

      if (messages.isEmpty) {
        AppLogger.debug(
          '[PET-SMS] Telephony: No SMS found in the last $lookbackDays days',
        );
        return 0;
      }

      // Map telephony messages to NativeSmsMessage so we can use the same
      // isolate-backed processing pipeline
      final nativeMessages = messages.map((m) {
        return NativeSmsMessage(
          address: m.address ?? '',
          body: m.body ?? '',
          dateMillis: m.date ?? DateTime.now().millisecondsSinceEpoch,
        );
      }).toList();

      return await _processMessages(nativeMessages);
    } catch (e) {
      AppLogger.debug('[PET-SMS] Error scanning inbox: $e');
      return 0;
    }
  }

  // ─── Live Listener ────────────────────────────────────────────────

  /// Start listening for incoming SMS messages.
  /// Parses and stores transactions in real-time.
  ///
  /// Uses BOTH the native EventChannel listener AND the telephony package
  /// listener for maximum reliability. The native listener uses its own
  /// BroadcastReceiver (independent of default SMS app), while the telephony
  /// listener provides a fallback.
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
        final body = notifMsg.body;
        final sender = notifMsg.address;
        final timestamp = notifMsg.dateTime;

        if (body.isEmpty) return;

        final classified = await ClassificationRuleEngine.classify(
          body,
          sender,
          timestamp,
        );
        if (classified == null) return;

        final hash = SmsTransaction.generateHash(body, timestamp);
        final exists = await _repository.existsByHash(hash);
        if (exists) return;

        // Cross-source dedup: check if SMS already captured this transaction
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
          source: 'notification',
        );

        final inserted = await _repository.insertSmsTransaction(transaction);
        if (inserted) {
          AppLogger.debug(
            '[PET-SMS] Notification listener: new transaction: '
            '${transaction.amount} ${transaction.transactionType} at ${transaction.merchantName}',
          );
          onNewTransaction?.call(transaction);
        }
      },
      onError: (error) {
        AppLogger.debug('[PET-SMS] Notification listener error: $error');
      },
    );

    // FALLBACK: Also keep the telephony listener as backup
    try {
      _telephony.listenIncomingSms(
        onNewMessage: (SmsMessage message) async {
          await _processIncomingMessage(message, onNewTransaction);
        },
        onBackgroundMessage: backgroundMessageHandler,
        listenInBackground: true,
      );
    } catch (e) {
      AppLogger.debug(
        '[PET-SMS] Telephony listener setup failed (non-fatal): $e',
      );
    }

    _isListening = true;
    AppLogger.debug(
      '[PET-SMS] Started listening for incoming SMS (native + fallback)',
    );
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

  Future<void> _processIncomingMessage(
    SmsMessage message,
    Function(SmsTransaction)? callback,
  ) async {
    final body = message.body;
    final sender = message.address ?? '';
    final timestamp = message.date != null
        ? DateTime.fromMillisecondsSinceEpoch(message.date!)
        : DateTime.now();

    if (body == null || body.isEmpty) return;

    // Use two-tier classification engine
    final classified = await ClassificationRuleEngine.classify(
      body,
      sender,
      timestamp,
    );
    if (classified == null) return;

    final hash = SmsTransaction.generateHash(body, timestamp);

    // Duplicate check
    final exists = await _repository.existsByHash(hash);
    if (exists) return;

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
        '[PET-SMS] New transaction (${classified.classifiedBy.name}): '
        '${transaction.amount} ${transaction.transactionType} at ${transaction.merchantName}',
      );
      callback?.call(transaction);
    }
  }

  static bool _matchesAny(String text, List<String> keywords) {
    for (final keyword in keywords) {
      if (text.contains(keyword)) return true;
    }
    return false;
  }

  /// Redact sensitive data from SMS body before DB storage.
  /// Replaces account numbers with XX**** and phone numbers with ***.
  /// Keeps the redacted version for display; dedup uses hash of original.
  static String redactSensitiveData(String body) {
    var redacted = body;
    // Redact full account numbers (keep last 4 digits)
    redacted = redacted.replaceAllMapped(RegExp(r'\b(\d{4,})\d{4}\b'), (m) {
      final full = m.group(0)!;
      if (full.length >= 8) {
        return 'XX****${full.substring(full.length - 4)}';
      }
      return full;
    });
    // Redact phone numbers (+91XXXXXXXXXX or 10-digit)
    redacted = redacted.replaceAllMapped(RegExp(r'(?:\+91|0)?(\d{10})\b'), (m) {
      final digits = m.group(1)!;
      // Don't redact if it looks like a UPI ref (usually 12+ digits)
      // or an amount — only phone numbers
      return '***${digits.substring(7)}';
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
