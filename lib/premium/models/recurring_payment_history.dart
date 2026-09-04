class RecurringPaymentHistory {
  final String id;
  final String recurringPaymentId;
  final double amount;
  final DateTime paidAt;
  final String source; // 'manual', 'detected_transaction', 'sms'
  final String? transactionId;
  final String? notes;
  final DateTime createdAt;

  RecurringPaymentHistory({
    required this.id,
    required this.recurringPaymentId,
    required this.amount,
    required this.paidAt,
    this.source = 'manual',
    this.transactionId,
    this.notes,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'recurringPaymentId': recurringPaymentId,
      'amount': amount,
      'paidAt': paidAt.toIso8601String(),
      'source': source,
      'transactionId': transactionId,
      'notes': notes,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory RecurringPaymentHistory.fromMap(Map<String, dynamic> map) {
    return RecurringPaymentHistory(
      id: map['id'] as String,
      recurringPaymentId: map['recurringPaymentId'] as String,
      amount: (map['amount'] as num).toDouble(),
      paidAt: DateTime.parse(map['paidAt'] as String),
      source: map['source'] as String? ?? 'manual',
      transactionId: map['transactionId'] as String?,
      notes: map['notes'] as String?,
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'] as String)
          : DateTime.now(),
    );
  }
}
