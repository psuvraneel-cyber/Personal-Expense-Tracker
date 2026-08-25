import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pet/data/models/enums.dart';

class TransactionRecord {
  final String id;
  final double amount;
  final TransactionType type;
  final String categoryId;
  final DateTime date;
  final String note;
  final PaymentMethod paymentMethod;
  final bool isRecurring;
  final RecurringFrequency? recurringFrequency;
  final String? merchantName;
  final String? taxCategory;
  final TransactionSource source;
  final String? accountId;
  final DateTime? updatedAt;
  final String? recurringRuleId;
  final DateTime? occurrenceDate;

  TransactionRecord({
    required this.id,
    required this.amount,
    required this.type,
    required this.categoryId,
    required this.date,
    this.note = '',
    this.paymentMethod = PaymentMethod.upi,
    this.isRecurring = false,
    this.recurringFrequency,
    this.merchantName,
    this.taxCategory,
    this.source = TransactionSource.manual,
    this.accountId,
    this.updatedAt,
    this.recurringRuleId,
    this.occurrenceDate,
  });

  /// Serialize to SQLite row — enums are stored as their string representation
  /// for backward compatibility with existing databases.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'amount': amount,
      'type': type.toJson(),
      'categoryId': categoryId,
      'date': date.toIso8601String(),
      'note': note,
      'paymentMethod': paymentMethod.toJson(),
      'isRecurring': isRecurring ? 1 : 0,
      'recurringFrequency': recurringFrequency?.toJson(),
      'merchantName': merchantName,
      'taxCategory': taxCategory,
      'source': source.toJson(),
      'accountId': accountId,
      'updatedAt': updatedAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
      'recurringRuleId': recurringRuleId,
      'occurrenceDate': occurrenceDate?.toIso8601String(),
    };
  }

  /// Deserialize from SQLite row — strings are converted to enums, with
  /// safe fallbacks for legacy data that may have unexpected values.
  factory TransactionRecord.fromMap(Map<String, dynamic> map) {
    return TransactionRecord(
      id: map['id'] as String,
      amount: (map['amount'] as num).toDouble(),
      type: TransactionType.fromJson(map['type'] as String?),
      categoryId: map['categoryId'] as String,
      date: DateTime.parse(map['date'] as String),
      note: map['note'] as String? ?? '',
      paymentMethod: PaymentMethod.fromJson(map['paymentMethod'] as String?),
      isRecurring: (map['isRecurring'] as int? ?? 0) == 1,
      recurringFrequency: RecurringFrequency.fromJson(
        map['recurringFrequency'] as String?,
      ),
      merchantName: map['merchantName'] as String?,
      taxCategory: map['taxCategory'] as String?,
      source: TransactionSource.fromJson(map['source'] as String?),
      accountId: map['accountId'] as String?,
      updatedAt: map['updatedAt'] != null ? DateTime.parse(map['updatedAt'] as String) : null,
      recurringRuleId: map['recurringRuleId'] as String?,
      occurrenceDate: map['occurrenceDate'] != null
          ? DateTime.parse(map['occurrenceDate'] as String)
          : null,
    );
  }

  TransactionRecord copyWith({
    String? id,
    double? amount,
    TransactionType? type,
    String? categoryId,
    DateTime? date,
    String? note,
    PaymentMethod? paymentMethod,
    bool? isRecurring,
    RecurringFrequency? recurringFrequency,
    String? merchantName,
    String? taxCategory,
    TransactionSource? source,
    String? accountId,
    DateTime? updatedAt,
    String? recurringRuleId,
    DateTime? occurrenceDate,
  }) {
    return TransactionRecord(
      id: id ?? this.id,
      amount: amount ?? this.amount,
      type: type ?? this.type,
      categoryId: categoryId ?? this.categoryId,
      date: date ?? this.date,
      note: note ?? this.note,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      isRecurring: isRecurring ?? this.isRecurring,
      recurringFrequency: recurringFrequency ?? this.recurringFrequency,
      merchantName: merchantName ?? this.merchantName,
      taxCategory: taxCategory ?? this.taxCategory,
      source: source ?? this.source,
      accountId: accountId ?? this.accountId,
      updatedAt: updatedAt ?? this.updatedAt,
      recurringRuleId: recurringRuleId ?? this.recurringRuleId,
      occurrenceDate: occurrenceDate ?? this.occurrenceDate,
    );
  }

  /// Serialize to Firestore document map.
  Map<String, dynamic> toFirestore() {
    return {
      'amount': amount,
      'type': type.toJson(),
      'categoryId': categoryId,
      'date': Timestamp.fromDate(date),
      'note': note,
      'paymentMethod': paymentMethod.toJson(),
      'isRecurring': isRecurring,
      'recurringFrequency': recurringFrequency?.toJson(),
      'merchantName': merchantName,
      'taxCategory': taxCategory,
      'source': source.toJson(),
      'accountId': accountId,
      'updatedAt': FieldValue.serverTimestamp(),
      'recurringRuleId': recurringRuleId,
      'occurrenceDate': occurrenceDate != null
          ? Timestamp.fromDate(occurrenceDate!)
          : null,
    };
  }

  /// Deserialize from a Firestore document.
  factory TransactionRecord.fromFirestore(
    String docId,
    Map<String, dynamic> data,
  ) {
    return TransactionRecord(
      id: docId,
      amount: (data['amount'] as num).toDouble(),
      type: TransactionType.fromJson(data['type'] as String?),
      categoryId: data['categoryId'] as String? ?? '',
      date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      note: data['note'] as String? ?? '',
      paymentMethod: PaymentMethod.fromJson(data['paymentMethod'] as String?),
      isRecurring: data['isRecurring'] as bool? ?? false,
      recurringFrequency: RecurringFrequency.fromJson(
        data['recurringFrequency'] as String?,
      ),
      merchantName: data['merchantName'] as String?,
      taxCategory: data['taxCategory'] as String?,
      source: TransactionSource.fromJson(data['source'] as String?),
      accountId: data['accountId'] as String?,
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      recurringRuleId: data['recurringRuleId'] as String?,
      occurrenceDate: (data['occurrenceDate'] as Timestamp?)?.toDate(),
    );
  }
}
