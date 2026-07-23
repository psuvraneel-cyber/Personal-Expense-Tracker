/// Log entry for an SMS message that the parser could not classify.
///
/// When the TransactionParser fails to extract a transaction from an SMS
/// that looks potentially financial (contains amount indicators), the SMS
/// is logged here for user review. Users can then create custom
/// [ClassificationRule]s from these entries to handle similar messages.
///
/// ## Lifecycle
/// 1. SMS arrives → parser returns `null` → logged as unknown format.
/// 2. User reviews unknown formats in the Rule Management screen.
/// 3. User creates a rule from the log entry → log marked as resolved.
/// 4. Future SMS matching the new rule are parsed automatically.
///
/// SECURITY: All data is stored and processed entirely on-device.
class UnknownFormatLog {
  final String id;

  /// The full SMS body text.
  final String smsBody;

  /// The SMS sender ID (e.g., "AD-HDFCBK").
  final String smsSender;

  /// When the SMS was received.
  final DateTime timestamp;

  /// Why the parser rejected this SMS.
  /// Values: 'no_amount', 'no_type', 'rejected_filter', 'parse_failed',
  ///         'low_confidence', 'unknown'
  final String rejectionReason;

  /// Whether the user has reviewed this entry.
  final bool isReviewed;

  /// Whether a rule was created from this entry.
  final bool isResolved;

  /// The ID of the rule created from this entry (if any).
  final String? resolvedRuleId;

  /// How many times this exact SMS pattern has been seen.
  /// Incremented via SMS body hash matching.
  final int occurrenceCount;

  /// SHA-256 hash of normalized SMS body for dedup/counting.
  final String bodyHash;

  /// User-provided note (optional).
  final String? userNote;

  const UnknownFormatLog({
    required this.id,
    required this.smsBody,
    required this.smsSender,
    required this.timestamp,
    this.rejectionReason = 'unknown',
    this.isReviewed = false,
    this.isResolved = false,
    this.resolvedRuleId,
    this.occurrenceCount = 1,
    required this.bodyHash,
    this.userNote,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'smsBody': smsBody,
      'smsSender': smsSender,
      'timestamp': timestamp.toIso8601String(),
      'created_at': timestamp.millisecondsSinceEpoch,
      'rejectionReason': rejectionReason,
      'isReviewed': isReviewed ? 1 : 0,
      'isResolved': isResolved ? 1 : 0,
      'resolvedRuleId': resolvedRuleId,
      'occurrenceCount': occurrenceCount,
      'bodyHash': bodyHash,
      'userNote': userNote,
    };
  }

  factory UnknownFormatLog.fromMap(Map<String, dynamic> map) {
    final timestampStr = map['timestamp'] as String?;
    final createdAtMillis = map['created_at'] as int?;
    final DateTime parsedTime;
    if (timestampStr != null && timestampStr.isNotEmpty) {
      parsedTime = DateTime.tryParse(timestampStr) ??
          (createdAtMillis != null
              ? DateTime.fromMillisecondsSinceEpoch(createdAtMillis)
              : DateTime.now());
    } else if (createdAtMillis != null) {
      parsedTime = DateTime.fromMillisecondsSinceEpoch(createdAtMillis);
    } else {
      parsedTime = DateTime.now();
    }

    return UnknownFormatLog(
      id: map['id'] as String,
      smsBody: map['smsBody'] as String,
      smsSender: map['smsSender'] as String,
      timestamp: parsedTime,
      rejectionReason: map['rejectionReason'] as String? ?? 'unknown',
      isReviewed: (map['isReviewed'] as int? ?? 0) == 1,
      isResolved: (map['isResolved'] as int? ?? 0) == 1,
      resolvedRuleId: map['resolvedRuleId'] as String?,
      occurrenceCount: map['occurrenceCount'] as int? ?? 1,
      bodyHash: map['bodyHash'] as String,
      userNote: map['userNote'] as String?,
    );
  }

  UnknownFormatLog copyWith({
    String? id,
    String? smsBody,
    String? smsSender,
    DateTime? timestamp,
    String? rejectionReason,
    bool? isReviewed,
    bool? isResolved,
    String? resolvedRuleId,
    int? occurrenceCount,
    String? bodyHash,
    String? userNote,
  }) {
    return UnknownFormatLog(
      id: id ?? this.id,
      smsBody: smsBody ?? this.smsBody,
      smsSender: smsSender ?? this.smsSender,
      timestamp: timestamp ?? this.timestamp,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      isReviewed: isReviewed ?? this.isReviewed,
      isResolved: isResolved ?? this.isResolved,
      resolvedRuleId: resolvedRuleId ?? this.resolvedRuleId,
      occurrenceCount: occurrenceCount ?? this.occurrenceCount,
      bodyHash: bodyHash ?? this.bodyHash,
      userNote: userNote ?? this.userNote,
    );
  }

  @override
  String toString() {
    return 'UnknownFormatLog(sender: $smsSender, reason: $rejectionReason, '
        'occurrences: $occurrenceCount, resolved: $isResolved)';
  }
}
