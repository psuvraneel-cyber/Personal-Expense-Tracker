import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pet/data/models/enums.dart';

/// First-class model representing a recurring rule that generates transaction occurrences.
class RecurringRule {
  final String id;
  final double amount;
  final TransactionType type;
  final String categoryId;
  final String note;
  final PaymentMethod paymentMethod;
  final RecurringFrequency frequency;
  final int interval;
  final DateTime startDate;
  final DateTime? endDate;
  final DateTime nextOccurrenceDate;
  final DateTime? lastGeneratedDate;
  final bool isActive;
  final String? merchantName;
  final String? taxCategory;
  final TransactionSource source;
  final String? accountId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? userId;

  RecurringRule({
    required this.id,
    required this.amount,
    required this.type,
    required this.categoryId,
    this.note = '',
    this.paymentMethod = PaymentMethod.upi,
    required this.frequency,
    this.interval = 1,
    required this.startDate,
    this.endDate,
    required this.nextOccurrenceDate,
    this.lastGeneratedDate,
    this.isActive = true,
    this.merchantName,
    this.taxCategory,
    this.source = TransactionSource.manual,
    this.accountId,
    required this.createdAt,
    required this.updatedAt,
    this.userId,
  });

  /// Serialize to SQLite row
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'amount': amount,
      'type': type.toJson(),
      'categoryId': categoryId,
      'note': note,
      'paymentMethod': paymentMethod.toJson(),
      'frequency': frequency.toJson(),
      'interval': interval,
      'startDate': startDate.toIso8601String(),
      'endDate': endDate?.toIso8601String(),
      'nextOccurrenceDate': nextOccurrenceDate.toIso8601String(),
      'lastGeneratedDate': lastGeneratedDate?.toIso8601String(),
      'isActive': isActive ? 1 : 0,
      'merchantName': merchantName,
      'taxCategory': taxCategory,
      'source': source.toJson(),
      'accountId': accountId,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'userId': userId,
    };
  }

  /// Deserialize from SQLite row
  factory RecurringRule.fromMap(Map<String, dynamic> map) {
    return RecurringRule(
      id: map['id'] as String,
      amount: (map['amount'] as num).toDouble(),
      type: TransactionType.fromJson(map['type'] as String?),
      categoryId: map['categoryId'] as String? ?? 'other',
      note: map['note'] as String? ?? '',
      paymentMethod: PaymentMethod.fromJson(map['paymentMethod'] as String?),
      frequency: RecurringFrequency.fromJson(map['frequency'] as String?) ??
          RecurringFrequency.monthly,
      interval: (map['interval'] as int?) ?? 1,
      startDate: DateTime.parse(map['startDate'] as String),
      endDate: map['endDate'] != null
          ? DateTime.parse(map['endDate'] as String)
          : null,
      nextOccurrenceDate: DateTime.parse(map['nextOccurrenceDate'] as String),
      lastGeneratedDate: map['lastGeneratedDate'] != null
          ? DateTime.parse(map['lastGeneratedDate'] as String)
          : null,
      isActive: (map['isActive'] as int? ?? 1) == 1,
      merchantName: map['merchantName'] as String?,
      taxCategory: map['taxCategory'] as String?,
      source: TransactionSource.fromJson(map['source'] as String?),
      accountId: map['accountId'] as String?,
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'] as String)
          : DateTime.now(),
      updatedAt: map['updatedAt'] != null
          ? DateTime.parse(map['updatedAt'] as String)
          : DateTime.now(),
      userId: map['userId'] as String?,
    );
  }

  /// Serialize to Firestore document map
  Map<String, dynamic> toFirestore() {
    return {
      'amount': amount,
      'type': type.toJson(),
      'categoryId': categoryId,
      'note': note,
      'paymentMethod': paymentMethod.toJson(),
      'frequency': frequency.toJson(),
      'interval': interval,
      'startDate': Timestamp.fromDate(startDate),
      'endDate': endDate != null ? Timestamp.fromDate(endDate!) : null,
      'nextOccurrenceDate': Timestamp.fromDate(nextOccurrenceDate),
      'lastGeneratedDate': lastGeneratedDate != null
          ? Timestamp.fromDate(lastGeneratedDate!)
          : null,
      'isActive': isActive,
      'merchantName': merchantName,
      'taxCategory': taxCategory,
      'source': source.toJson(),
      'accountId': accountId,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': FieldValue.serverTimestamp(),
      'userId': userId,
    };
  }

  /// Deserialize from a Firestore document
  factory RecurringRule.fromFirestore(
    String docId,
    Map<String, dynamic> data,
  ) {
    return RecurringRule(
      id: docId,
      amount: (data['amount'] as num).toDouble(),
      type: TransactionType.fromJson(data['type'] as String?),
      categoryId: data['categoryId'] as String? ?? 'other',
      note: data['note'] as String? ?? '',
      paymentMethod: PaymentMethod.fromJson(data['paymentMethod'] as String?),
      frequency: RecurringFrequency.fromJson(data['frequency'] as String?) ??
          RecurringFrequency.monthly,
      interval: (data['interval'] as int?) ?? 1,
      startDate: (data['startDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      endDate: (data['endDate'] as Timestamp?)?.toDate(),
      nextOccurrenceDate:
          (data['nextOccurrenceDate'] as Timestamp?)?.toDate() ??
              DateTime.now(),
      lastGeneratedDate:
          (data['lastGeneratedDate'] as Timestamp?)?.toDate(),
      isActive: data['isActive'] as bool? ?? true,
      merchantName: data['merchantName'] as String?,
      taxCategory: data['taxCategory'] as String?,
      source: TransactionSource.fromJson(data['source'] as String?),
      accountId: data['accountId'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      userId: data['userId'] as String?,
    );
  }

  RecurringRule copyWith({
    String? id,
    double? amount,
    TransactionType? type,
    String? categoryId,
    String? note,
    PaymentMethod? paymentMethod,
    RecurringFrequency? frequency,
    int? interval,
    DateTime? startDate,
    DateTime? endDate,
    DateTime? nextOccurrenceDate,
    DateTime? lastGeneratedDate,
    bool? isActive,
    String? merchantName,
    String? taxCategory,
    TransactionSource? source,
    String? accountId,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? userId,
  }) {
    return RecurringRule(
      id: id ?? this.id,
      amount: amount ?? this.amount,
      type: type ?? this.type,
      categoryId: categoryId ?? this.categoryId,
      note: note ?? this.note,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      frequency: frequency ?? this.frequency,
      interval: interval ?? this.interval,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      nextOccurrenceDate: nextOccurrenceDate ?? this.nextOccurrenceDate,
      lastGeneratedDate: lastGeneratedDate ?? this.lastGeneratedDate,
      isActive: isActive ?? this.isActive,
      merchantName: merchantName ?? this.merchantName,
      taxCategory: taxCategory ?? this.taxCategory,
      source: source ?? this.source,
      accountId: accountId ?? this.accountId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      userId: userId ?? this.userId,
    );
  }
}
