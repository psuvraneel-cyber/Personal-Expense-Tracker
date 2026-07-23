/// User feedback store — provides a "not a transaction / mark as credit /
/// mark as debit" feedback loop that updates local rules.
///
/// ## Design
/// When the user corrects a parser decision, we store two things:
/// 1. A **feedback record** (SMS hash → user's correction) in a local table.
/// 2. Optionally, a **classification rule** derived from the SMS pattern.
///
/// On subsequent parses, the feedback store is checked FIRST:
/// - If the SMS hash matches a "not a transaction" feedback, skip it.
/// - If it matches a "mark as debit/credit" feedback, override the direction.
///
/// ## Telemetry Schema (opt-in, no PII)
/// When the user opts in, uncertain messages are logged with:
/// ```json
/// {
///   "format_hash": "sha256(masked_body)", // digits→'#', names→'X'
///   "sender_prefix": "AD-",               // not full sender
///   "rejection_reason": "low_confidence",
///   "has_amount": true,
///   "has_intent": true,
///   "has_ref": false,
///   "score": 42,
///   "user_action": "marked_debit"         // or "marked_not_txn"
/// }
/// ```
/// No raw SMS body, no amounts, no names, no phone numbers.
///
/// ## Serverless Collection (opt-in)
/// A Firebase Cloud Function or Supabase Edge Function can accept these
/// anonymized records. Batch upload weekly. The function validates the
/// schema and stores in a BigQuery table for offline analysis.
///
/// Consent flow: Settings → "Help improve transaction detection" toggle.
library;

import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:pet/data/repositories/sms_transaction_repository.dart';
import 'package:pet/services/sms_parser/transaction_parse_result.dart';

/// Types of user feedback on a parsed SMS.
enum UserFeedbackAction {
  /// User says this is NOT a transaction (false positive).
  notTransaction,

  /// User says this IS a debit (parser got it wrong or missed it).
  markDebit,

  /// User says this IS a credit (parser got it wrong or missed it).
  markCredit,
}

/// A single user feedback record.
class UserFeedback {
  final String smsHash;
  final UserFeedbackAction action;
  final DateTime createdAt;

  /// Optional: the amount the user confirmed.
  final double? confirmedAmount;

  const UserFeedback({
    required this.smsHash,
    required this.action,
    required this.createdAt,
    this.confirmedAmount,
  });

  Map<String, dynamic> toMap() => {
    'smsHash': smsHash,
    'action': action.name,
    'createdAt': createdAt.toIso8601String(),
    'confirmedAmount': confirmedAmount,
  };

  factory UserFeedback.fromMap(Map<String, dynamic> map) => UserFeedback(
    smsHash: map['smsHash'] as String,
    action: UserFeedbackAction.values.firstWhere(
      (a) => a.name == map['action'],
    ),
    createdAt: DateTime.parse(map['createdAt'] as String),
    confirmedAmount: (map['confirmedAmount'] as num?)?.toDouble(),
  );
}

/// Anonymized telemetry record (no PII).
class TelemetryRecord {
  final String formatHash;
  final String senderPrefix;
  final String rejectionReason;
  final bool hasAmount;
  final bool hasIntent;
  final bool hasRef;
  final int score;
  final String userAction;

  const TelemetryRecord({
    required this.formatHash,
    required this.senderPrefix,
    required this.rejectionReason,
    required this.hasAmount,
    required this.hasIntent,
    required this.hasRef,
    required this.score,
    required this.userAction,
  });

  Map<String, dynamic> toJson() => {
    'format_hash': formatHash,
    'sender_prefix': senderPrefix,
    'rejection_reason': rejectionReason,
    'has_amount': hasAmount,
    'has_intent': hasIntent,
    'has_ref': hasRef,
    'score': score,
    'user_action': userAction,
  };
}

/// In-memory feedback store with persistence hooks.
///
/// In production, [_feedbackCache] should be persisted to SQLite.
/// The [load] and [save] methods are provided for integration.
class UserFeedbackStore {
  UserFeedbackStore._();

  /// Cache: smsHash → feedback action.
  static final Map<String, UserFeedback> _feedbackCache = {};

  /// Optional persistence handler (e.g. for custom DB saving or testing).
  static Future<void> Function(UserFeedback feedback)? onFeedbackRecorded;

  @visibleForTesting
  static void resetForTesting() {
    _feedbackCache.clear();
    onFeedbackRecorded = null;
  }

  /// Load feedback from database (call at startup).
  /// Provide a list of feedback records loaded from your DB.
  static void loadFromRecords(List<UserFeedback> records) {
    _feedbackCache.clear();
    for (final r in records) {
      _feedbackCache[r.smsHash] = r;
    }
  }

  /// Record user feedback.
  ///
  /// Returns a [UserFeedback] object to persist in the database.
  static UserFeedback recordFeedback({
    required String smsBody,
    required DateTime smsTimestamp,
    required UserFeedbackAction action,
    double? confirmedAmount,
  }) {
    final hash = _generateHash(smsBody, smsTimestamp);
    final feedback = UserFeedback(
      smsHash: hash,
      action: action,
      createdAt: DateTime.now(),
      confirmedAmount: confirmedAmount,
    );
    _feedbackCache[hash] = feedback;

    bool hasBinding = false;
    try {
      final _ = WidgetsBinding.instance;
      hasBinding = true;
    } catch (_) {}

    // Immediately persist write-through to SQLite (async, non-blocking)
    if (onFeedbackRecorded != null) {
      onFeedbackRecorded!(feedback).catchError((_) {});
    } else if (hasBinding) {
      Future.microtask(() async {
        try {
          await SmsTransactionRepository().saveFeedback(feedback.toMap());
        } catch (_) {}
      });
    }

    return feedback;
  }

  /// Check if there's user feedback for a given SMS.
  /// Returns null if no feedback exists.
  static UserFeedback? getFeedback(String smsBody, DateTime smsTimestamp) {
    final hash = _generateHash(smsBody, smsTimestamp);
    return _feedbackCache[hash];
  }

  /// Apply user feedback to a parse result.
  ///
  /// If the user previously corrected this SMS, override the result.
  static TransactionParseResult? applyFeedback(
    TransactionParseResult result,
    String smsBody,
    DateTime smsTimestamp,
  ) {
    final feedback = getFeedback(smsBody, smsTimestamp);
    if (feedback == null) return null;

    switch (feedback.action) {
      case UserFeedbackAction.notTransaction:
        return TransactionParseResult.rejected(
          reasons: [
            ...result.reasons,
            'USER OVERRIDE: Marked as not a transaction',
          ],
        );

      case UserFeedbackAction.markDebit:
        return result.copyWith(
          isTransaction: true,
          isUncertain: false,
          direction: TransactionDirection.debit,
          amount: feedback.confirmedAmount ?? result.amount,
          confidence: 100,
          reasons: [...result.reasons, 'USER OVERRIDE: Marked as debit'],
        );

      case UserFeedbackAction.markCredit:
        return result.copyWith(
          isTransaction: true,
          isUncertain: false,
          direction: TransactionDirection.credit,
          amount: feedback.confirmedAmount ?? result.amount,
          confidence: 100,
          reasons: [...result.reasons, 'USER OVERRIDE: Marked as credit'],
        );
    }
  }

  /// Generate anonymized telemetry record (no PII).
  ///
  /// Call this when a user provides feedback on an uncertain message,
  /// to collect data for offline rule improvement.
  static TelemetryRecord buildTelemetry({
    required String smsBody,
    required String sender,
    required TransactionParseResult result,
    required UserFeedbackAction action,
  }) {
    // Mask all digits to create a format template
    final maskedBody = smsBody
        .replaceAll(RegExp(r'\d'), '#')
        .replaceAll(RegExp(r'[A-Z]{4,}'), 'X'); // Mask proper nouns

    final formatHash = sha256
        .convert(utf8.encode(maskedBody))
        .toString()
        .substring(0, 16); // Truncate for brevity

    // Extract just the prefix (e.g., "AD-" from "AD-HDFCBK")
    final senderPrefix = sender.length >= 3 ? sender.substring(0, 3) : sender;

    return TelemetryRecord(
      formatHash: formatHash,
      senderPrefix: senderPrefix,
      rejectionReason: result.isUncertain
          ? 'low_confidence'
          : (result.isTransaction ? 'false_positive' : 'false_negative'),
      hasAmount: result.amount != null,
      hasIntent: result.direction != null,
      hasRef: result.reference != null,
      score: result.confidence,
      userAction: action.name,
    );
  }

  static String _generateHash(String smsBody, DateTime timestamp) {
    final normalized = smsBody.trim().replaceAll(RegExp(r'\s+'), ' ');
    final input = '$normalized|${timestamp.millisecondsSinceEpoch}';
    return sha256.convert(utf8.encode(input)).toString();
  }

  /// Clear all cached feedback (for testing).
  static void clearCache() => _feedbackCache.clear();
}
