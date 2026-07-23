import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Model representing a transaction parsed from a bank SMS message.
///
/// All parsing and storage happens entirely on-device.
/// No raw SMS data is ever sent to an external server.
class SmsTransaction {
  final String id;
  final double amount;
  final String merchantName;
  final String bankName;
  final String transactionType; // 'debit' or 'credit'
  final String
  transactionSubType; // 'payment', 'collect', 'refund', 'cashback', 'transfer', 'reversal'
  final DateTime timestamp;
  final String rawSmsBody;
  final String smsSender;
  final String smsHash; // SHA-256 hash for deduplication
  final String category;
  final bool isVerified;
  final String? referenceId; // UPI Ref / IMPS Ref / Txn ID
  final String? upiId; // VPA (e.g., merchant@ybl)
  final double confidence; // Parser confidence score 0.0 – 1.0
  final String source; // 'sms', 'notification', or 'manual'
  final bool timestampIsApproximate; // true if legacy 12:00 AM record

  SmsTransaction({
    required this.id,
    required this.amount,
    required this.merchantName,
    required this.bankName,
    required this.transactionType,
    this.transactionSubType = 'payment',
    required this.timestamp,
    required this.rawSmsBody,
    required this.smsSender,
    required this.smsHash,
    this.category = 'Uncategorized',
    this.isVerified = false,
    this.referenceId,
    this.upiId,
    this.confidence = 0.5,
    this.source = 'sms',
    this.timestampIsApproximate = false,
  });

  /// Generate a unique SHA-256 hash from SMS body + timestamp for duplicate prevention.
  /// Two SMS messages with the same body and timestamp will produce the same hash,
  /// preventing duplicate entries if the same SMS is processed twice.
  ///
  /// NOTE: OS SMS timestamps are typically second-precision. In rare cases where a carrier
  /// re-delivers the exact same SMS >1s apart, a different hash could theoretically be generated.
  /// This second-precision timestamp limitation is a known and accepted tradeoff.
  static String generateHash(String smsBody, DateTime timestamp) {
    final normalizedBody = smsBody.trim().replaceAll(RegExp(r'\s+'), ' ');
    final input = '$normalizedBody|${timestamp.millisecondsSinceEpoch}';
    return sha256.convert(utf8.encode(input)).toString();
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'amount': amount,
      'merchantName': merchantName,
      'bankName': bankName,
      'transactionType': transactionType,
      'transactionSubType': transactionSubType,
      'timestamp': timestamp.toIso8601String(),
      'rawSmsBody': rawSmsBody,
      'smsSender': smsSender,
      'smsHash': smsHash,
      'category': category,
      'isVerified': isVerified ? 1 : 0,
      'referenceId': referenceId,
      'upiId': upiId,
      'confidence': confidence,
      'source': source,
      'timestamp_is_approximate': timestampIsApproximate ? 1 : 0,
    };
  }

  factory SmsTransaction.fromMap(Map<String, dynamic> map) {
    return SmsTransaction(
      id: map['id'] as String,
      amount: (map['amount'] as num).toDouble(),
      merchantName: map['merchantName'] as String,
      bankName: map['bankName'] as String,
      transactionType: map['transactionType'] as String,
      transactionSubType: map['transactionSubType'] as String? ?? 'payment',
      timestamp: DateTime.parse(map['timestamp'] as String),
      rawSmsBody: map['rawSmsBody'] as String,
      smsSender: map['smsSender'] as String? ?? '',
      smsHash: map['smsHash'] as String,
      category: map['category'] as String? ?? 'Uncategorized',
      isVerified: (map['isVerified'] as int? ?? 0) == 1,
      referenceId: map['referenceId'] as String?,
      upiId: map['upiId'] as String?,
      confidence: (map['confidence'] as num?)?.toDouble() ?? 0.5,
      source: map['source'] as String? ?? 'sms',
      timestampIsApproximate:
          (map['timestamp_is_approximate'] as int? ?? 0) == 1,
    );
  }

  SmsTransaction copyWith({
    String? id,
    double? amount,
    String? merchantName,
    String? bankName,
    String? transactionType,
    String? transactionSubType,
    DateTime? timestamp,
    String? rawSmsBody,
    String? smsSender,
    String? smsHash,
    String? category,
    bool? isVerified,
    String? referenceId,
    String? upiId,
    double? confidence,
    String? source,
    bool? timestampIsApproximate,
  }) {
    return SmsTransaction(
      id: id ?? this.id,
      amount: amount ?? this.amount,
      merchantName: merchantName ?? this.merchantName,
      bankName: bankName ?? this.bankName,
      transactionType: transactionType ?? this.transactionType,
      transactionSubType: transactionSubType ?? this.transactionSubType,
      timestamp: timestamp ?? this.timestamp,
      rawSmsBody: rawSmsBody ?? this.rawSmsBody,
      smsSender: smsSender ?? this.smsSender,
      smsHash: smsHash ?? this.smsHash,
      category: category ?? this.category,
      isVerified: isVerified ?? this.isVerified,
      referenceId: referenceId ?? this.referenceId,
      upiId: upiId ?? this.upiId,
      confidence: confidence ?? this.confidence,
      source: source ?? this.source,
      timestampIsApproximate:
          timestampIsApproximate ?? this.timestampIsApproximate,
    );
  }

  @override
  String toString() {
    return 'SmsTransaction(amount: $amount, merchant: $merchantName, '
        'bank: $bankName, type: $transactionType/$transactionSubType, '
        'ref: $referenceId, upi: $upiId, '
        'confidence: ${(confidence * 100).toStringAsFixed(0)}%, '
        'date: $timestamp)';
  }
}
