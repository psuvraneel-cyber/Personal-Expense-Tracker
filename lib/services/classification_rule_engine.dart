import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:pet/core/utils/app_logger.dart';
import 'package:pet/data/models/unknown_format_log.dart';
import 'package:pet/data/repositories/classification_repository.dart';
import 'package:pet/services/sms_parser/self_consistency_checker.dart';
import 'package:pet/services/sms_service.dart';
import 'package:uuid/uuid.dart';

/// SMS classification engine that wraps the [SelfConsistencyChecker].
///
/// Pipeline:
/// 1. Run both parsers via [SelfConsistencyChecker.check()].
/// 2. If the consensus result is a transaction, return a [ClassifiedTransaction].
/// 3. If parsing fails and the SMS looks financial, log it for diagnostics.
///
/// SECURITY: All processing is on-device. No SMS data leaves the device.
class ClassificationRuleEngine {
  ClassificationRuleEngine._();

  static final ClassificationRepository _repository =
      ClassificationRepository();
  static const Uuid _uuid = Uuid();

  // ═══════════════════════════════════════════════════════════════════
  //  PARSING PIPELINE
  // ═══════════════════════════════════════════════════════════════════

  /// Parse an SMS using the self-consistency checker (dual-parser consensus).
  ///
  /// Returns a [ClassifiedTransaction] with the parsed result, or null
  /// if the SMS is not a financial transaction.
  static Future<ClassifiedTransaction?> classify(
    String smsBody,
    String sender,
    DateTime smsTimestamp, {
    bool logUnknown = true,
  }) async {
    // Run both parsers and get consensus result
    final consensus = SelfConsistencyChecker.check(
      body: smsBody,
      sender: sender,
      timestamp: smsTimestamp,
    );

    final result = consensus.result;

    if (result.isTransaction || result.isUncertain) {
      AppLogger.debug(
        '[PET-Rules] ${consensus.source.name} → '
        '${result.direction?.name ?? "?"} ₹${result.amount} '
        '(confidence=${result.confidence}, '
        'agreement=${consensus.agreement.name})',
      );

      return ClassifiedTransaction(
        amount: result.amount ?? 0,
        merchantName: result.merchant ?? 'Unknown',
        bankName: result.bank ?? 'Unknown Bank',
        transactionType: result.direction?.name ?? 'debit',
        transactionSubType: result.subType.name,
        parsedDate: result.date ?? smsTimestamp,
        upiId: result.upiId,
        referenceId: result.reference,
        accountTail: result.accountTail,
        channel: result.channel.name,
        confidence: result.confidence / 100.0,
        category: null, // Will be inferred by SmsService._inferCategory
        classifiedBy: _mapSource(consensus.source),
      );
    }

    // Log unknown format for diagnostics
    if (logUnknown) {
      await _logUnknownFormat(smsBody, sender, smsTimestamp);
    }
    return null;
  }

  /// Map [ConsistencySource] to [ClassificationSource].
  static ClassificationSource _mapSource(ConsistencySource source) {
    return switch (source) {
      ConsistencySource.consensus => ClassificationSource.consensus,
      ConsistencySource.modularOnly => ClassificationSource.modularPipeline,
      ConsistencySource.legacyOnly => ClassificationSource.hardcodedParser,
      ConsistencySource.modularPreferred =>
        ClassificationSource.modularPipeline,
      ConsistencySource.noneDetected => ClassificationSource.hardcodedParser,
    };
  }

  // ═══════════════════════════════════════════════════════════════════
  //  UNKNOWN FORMAT LOGGING
  // ═══════════════════════════════════════════════════════════════════

  /// Minimum SMS indicators to consider logging as unknown format.
  static final RegExp _financialIndicator = RegExp(
    r'(?:Rs\.?\s*|INR\.?\s*|₹\s?)\d|(?:debited|credited|paid|received|sent|deducted)',
    caseSensitive: false,
  );

  /// Log an unclassified SMS that looks potentially financial.
  static Future<void> _logUnknownFormat(
    String smsBody,
    String sender,
    DateTime timestamp,
  ) async {
    // Only log SMS that look potentially financial
    if (!_financialIndicator.hasMatch(smsBody)) return;

    // Determine rejection reason
    String reason;
    if (smsBody.length < 30) {
      reason = 'too_short';
    } else if (!RegExp(
      r'(?:Rs\.?\s*|INR\.?\s*|₹\s?)\d',
      caseSensitive: false,
    ).hasMatch(smsBody)) {
      reason = 'no_amount';
    } else if (!RegExp(
      r'debited|credited|paid|received|sent|deducted|spent|deposited',
      caseSensitive: false,
    ).hasMatch(smsBody)) {
      reason = 'no_type';
    } else {
      reason = 'parse_failed';
    }

    // Generate body hash for dedup
    final normalizedBody = smsBody.trim().replaceAll(RegExp(r'\s+'), ' ');
    // Mask numbers to group similar formats
    final maskedBody = normalizedBody.replaceAll(RegExp(r'\d'), '#');
    final bodyHash = sha256.convert(utf8.encode(maskedBody)).toString();

    final log = UnknownFormatLog(
      id: _uuid.v4(),
      smsBody: SmsService.redactSensitiveData(smsBody),
      smsSender: sender,
      timestamp: timestamp,
      rejectionReason: reason,
      bodyHash: bodyHash,
    );

    try {
      await _repository.upsertUnknownLog(log);
      AppLogger.debug(
        '[PET-Rules] Logged unknown format: sender=$sender, reason=$reason',
      );
    } catch (e) {
      AppLogger.debug('[PET-Rules] Error logging unknown format: $e');
    }
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  DATA MODELS
// ═════════════════════════════════════════════════════════════════════════════

/// How the transaction was classified.
enum ClassificationSource {
  /// Parsed by the hardcoded TransactionParser (legacy).
  hardcodedParser,

  /// Parsed by the modular SmsTransactionParser pipeline.
  modularPipeline,

  /// Both parsers agreed (consensus via SelfConsistencyChecker).
  consensus,
}

/// Result of the classification pipeline.
class ClassifiedTransaction {
  final double amount;
  final String merchantName;
  final String bankName;
  final String transactionType;
  final String transactionSubType;
  final DateTime parsedDate;
  final String? upiId;
  final String? referenceId;
  final String? accountTail;
  final String channel;
  final double confidence;

  /// Category inferred from merchant/transaction data.
  final String? category;

  /// Which classification method handled this SMS.
  final ClassificationSource classifiedBy;

  const ClassifiedTransaction({
    required this.amount,
    required this.merchantName,
    required this.bankName,
    required this.transactionType,
    this.transactionSubType = 'payment',
    required this.parsedDate,
    this.upiId,
    this.referenceId,
    this.accountTail,
    this.channel = 'unknown',
    this.confidence = 0.5,
    this.category,
    required this.classifiedBy,
    // Kept for API compatibility — unused after rule removal
    String? matchedRuleId,
    String? matchedRuleName,
  });

  @override
  String toString() {
    return 'ClassifiedTransaction(₹$amount, $transactionType, '
        'merchant: $merchantName, channel: $channel, category: $category)';
  }
}
