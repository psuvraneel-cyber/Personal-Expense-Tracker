import 'package:cloud_firestore/cloud_firestore.dart';

/// Status of an individual scheduled occurrence.
enum RecurringOccurrenceStatus {
  generated,
  skipped,
  cancelled;

  String toJson() => name;

  static RecurringOccurrenceStatus fromJson(String? value) {
    if (value == 'skipped') return RecurringOccurrenceStatus.skipped;
    if (value == 'cancelled') return RecurringOccurrenceStatus.cancelled;
    return RecurringOccurrenceStatus.generated;
  }
}

/// First-class model representing an individual occurrence state of a recurrence rule.
/// Provides deterministic identity and idempotency for generated or skipped transactions.
class RecurringOccurrence {
  final String id;
  final String ruleId;
  final DateTime scheduledDate;
  final RecurringOccurrenceStatus status;
  final String? transactionId;
  final DateTime? generatedAt;
  final DateTime updatedAt;

  RecurringOccurrence({
    required this.id,
    required this.ruleId,
    required this.scheduledDate,
    this.status = RecurringOccurrenceStatus.generated,
    this.transactionId,
    this.generatedAt,
    required this.updatedAt,
  });

  /// Helper to create a deterministic ID from ruleId and scheduledDate
  static String generateId(String ruleId, DateTime scheduledDate) {
    return '${ruleId}_${scheduledDate.toIso8601String()}';
  }

  /// Serialize to SQLite row
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'ruleId': ruleId,
      'scheduledDate': scheduledDate.toIso8601String(),
      'status': status.toJson(),
      'transactionId': transactionId,
      'generatedAt': generatedAt?.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  /// Deserialize from SQLite row
  factory RecurringOccurrence.fromMap(Map<String, dynamic> map) {
    return RecurringOccurrence(
      id: map['id'] as String,
      ruleId: map['ruleId'] as String,
      scheduledDate: DateTime.parse(map['scheduledDate'] as String),
      status: RecurringOccurrenceStatus.fromJson(map['status'] as String?),
      transactionId: map['transactionId'] as String?,
      generatedAt: map['generatedAt'] != null
          ? DateTime.parse(map['generatedAt'] as String)
          : null,
      updatedAt: map['updatedAt'] != null
          ? DateTime.parse(map['updatedAt'] as String)
          : DateTime.now(),
    );
  }

  /// Serialize to Firestore document map
  Map<String, dynamic> toFirestore() {
    return {
      'ruleId': ruleId,
      'scheduledDate': Timestamp.fromDate(scheduledDate),
      'status': status.toJson(),
      'transactionId': transactionId,
      'generatedAt': generatedAt != null ? Timestamp.fromDate(generatedAt!) : null,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  /// Deserialize from a Firestore document
  factory RecurringOccurrence.fromFirestore(
    String docId,
    Map<String, dynamic> data,
  ) {
    return RecurringOccurrence(
      id: docId,
      ruleId: data['ruleId'] as String? ?? '',
      scheduledDate:
          (data['scheduledDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      status: RecurringOccurrenceStatus.fromJson(data['status'] as String?),
      transactionId: data['transactionId'] as String?,
      generatedAt: (data['generatedAt'] as Timestamp?)?.toDate(),
      updatedAt:
          (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  RecurringOccurrence copyWith({
    String? id,
    String? ruleId,
    DateTime? scheduledDate,
    RecurringOccurrenceStatus? status,
    String? transactionId,
    DateTime? generatedAt,
    DateTime? updatedAt,
  }) {
    return RecurringOccurrence(
      id: id ?? this.id,
      ruleId: ruleId ?? this.ruleId,
      scheduledDate: scheduledDate ?? this.scheduledDate,
      status: status ?? this.status,
      transactionId: transactionId ?? this.transactionId,
      generatedAt: generatedAt ?? this.generatedAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
