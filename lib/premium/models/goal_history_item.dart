/// Represents an immutable audit trail event for a savings goal
/// (created, topUp, progressUpdate, withdrawal, goalEdited, goalPaused, goalResumed, goalAchieved).
class GoalHistoryItem {
  final String id;
  final String goalId;
  final double amount;
  final String actionType;
  final DateTime createdAt;
  final String? note;
  final double? previousAmount;
  final double? resultingAmount;
  final String source;
  final String? transactionId;

  const GoalHistoryItem({
    required this.id,
    required this.goalId,
    required this.amount,
    required this.actionType,
    required this.createdAt,
    this.note,
    this.previousAmount,
    this.resultingAmount,
    this.source = 'manual',
    this.transactionId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'goalId': goalId,
      'amount': amount,
      'actionType': actionType,
      'createdAt': createdAt.toIso8601String(),
      'note': note,
      'previousAmount': previousAmount,
      'resultingAmount': resultingAmount,
      'source': source,
      'transactionId': transactionId,
    };
  }

  factory GoalHistoryItem.fromMap(Map<String, dynamic> map) {
    return GoalHistoryItem(
      id: map['id'] as String,
      goalId: map['goalId'] as String,
      amount: (map['amount'] as num).toDouble(),
      actionType: map['actionType'] as String? ?? 'topUp',
      createdAt: DateTime.parse(map['createdAt'] as String),
      note: map['note'] as String?,
      previousAmount: (map['previousAmount'] as num?)?.toDouble(),
      resultingAmount: (map['resultingAmount'] as num?)?.toDouble(),
      source: map['source'] as String? ?? 'manual',
      transactionId: map['transactionId'] as String?,
    );
  }
}
