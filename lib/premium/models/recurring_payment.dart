import 'package:pet/data/models/enums.dart';
import 'package:pet/services/recurrence_calculator.dart';

class RecurringPayment {
  final String id;
  final String merchantName;
  final double amount;
  final String frequency; // daily, weekly, monthly, quarterly, semiannual, yearly
  final DateTime lastPaidAt;
  final DateTime nextDueAt;
  final String categoryId;
  final double confidence;
  final String source; // sms, notification, manual
  final RecurringStatus status;
  final bool isAutopay;
  final double? previousAmount;
  final DateTime? priceChangeDetectedAt;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? detectionReason;

  RecurringPayment({
    required this.id,
    required this.merchantName,
    required this.amount,
    required this.frequency,
    required this.lastPaidAt,
    required this.nextDueAt,
    required this.categoryId,
    this.confidence = 0.6,
    this.source = 'sms',
    this.status = RecurringStatus.confirmed,
    this.isAutopay = false,
    this.previousAmount,
    this.priceChangeDetectedAt,
    this.notes,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.detectionReason,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  RecurringFrequency get frequencyEnum =>
      RecurringFrequency.fromJson(frequency) ?? RecurringFrequency.monthly;

  /// Whether a price change was detected for this recurring commitment.
  bool get isPriceChanged =>
      previousAmount != null &&
      previousAmount! > 0 &&
      (amount - previousAmount!).abs() > 0.01;

  /// The difference in amount if a price change was detected (new - old).
  double get priceDifference =>
      previousAmount != null ? amount - previousAmount! : 0.0;

  /// Annual commitment calculated using calendar-correct frequency multiplier.
  double get annualAmount =>
      amount * RecurrenceCalculator.annualMultiplier(frequencyEnum);

  /// Monthly equivalent spend for budgeting and summary comparison.
  double get monthlyEquivalentAmount =>
      amount * RecurrenceCalculator.monthlyMultiplier(frequencyEnum);

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'merchantName': merchantName,
      'amount': amount,
      'frequency': frequency,
      'lastPaidAt': lastPaidAt.toIso8601String(),
      'nextDueAt': nextDueAt.toIso8601String(),
      'categoryId': categoryId,
      'confidence': confidence,
      'source': source,
      'status': status.toJson(),
      'isAutopay': isAutopay ? 1 : 0,
      'previousAmount': previousAmount,
      'priceChangeDetectedAt': priceChangeDetectedAt?.toIso8601String(),
      'notes': notes,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'detectionReason': detectionReason,
    };
  }

  factory RecurringPayment.fromMap(Map<String, dynamic> map) {
    final statusStr = map['status'] as String?;
    final isAutopayVal = map['isAutopay'];
    final isAutopayBool = isAutopayVal == 1 || isAutopayVal == true;

    return RecurringPayment(
      id: map['id'] as String,
      merchantName: map['merchantName'] as String,
      amount: (map['amount'] as num).toDouble(),
      frequency: map['frequency'] as String,
      lastPaidAt: DateTime.parse(map['lastPaidAt'] as String),
      nextDueAt: DateTime.parse(map['nextDueAt'] as String),
      categoryId: map['categoryId'] as String? ?? 'other',
      confidence: (map['confidence'] as num?)?.toDouble() ?? 0.6,
      source: map['source'] as String? ?? 'sms',
      status: RecurringStatus.fromJson(statusStr),
      isAutopay: isAutopayBool,
      previousAmount: (map['previousAmount'] as num?)?.toDouble(),
      priceChangeDetectedAt: map['priceChangeDetectedAt'] != null
          ? DateTime.parse(map['priceChangeDetectedAt'] as String)
          : null,
      notes: map['notes'] as String?,
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'] as String)
          : DateTime.parse(map['lastPaidAt'] as String),
      updatedAt: map['updatedAt'] != null
          ? DateTime.parse(map['updatedAt'] as String)
          : DateTime.parse(map['lastPaidAt'] as String),
      detectionReason: map['detectionReason'] as String?,
    );
  }

  RecurringPayment copyWith({
    String? id,
    String? merchantName,
    double? amount,
    String? frequency,
    DateTime? lastPaidAt,
    DateTime? nextDueAt,
    String? categoryId,
    double? confidence,
    String? source,
    RecurringStatus? status,
    bool? isAutopay,
    double? previousAmount,
    DateTime? priceChangeDetectedAt,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? detectionReason,
  }) {
    return RecurringPayment(
      id: id ?? this.id,
      merchantName: merchantName ?? this.merchantName,
      amount: amount ?? this.amount,
      frequency: frequency ?? this.frequency,
      lastPaidAt: lastPaidAt ?? this.lastPaidAt,
      nextDueAt: nextDueAt ?? this.nextDueAt,
      categoryId: categoryId ?? this.categoryId,
      confidence: confidence ?? this.confidence,
      source: source ?? this.source,
      status: status ?? this.status,
      isAutopay: isAutopay ?? this.isAutopay,
      previousAmount: previousAmount ?? this.previousAmount,
      priceChangeDetectedAt: priceChangeDetectedAt ?? this.priceChangeDetectedAt,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      detectionReason: detectionReason ?? this.detectionReason,
    );
  }
}
