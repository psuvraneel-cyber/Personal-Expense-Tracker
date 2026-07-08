class SavingGoal {
  final String id;
  final String name;
  final double targetAmount;
  final double currentAmount;
  final DateTime? targetDate;
  final DateTime createdAt;
  final bool isPaused;
  final String? emoji;

  SavingGoal({
    required this.id,
    required this.name,
    required this.targetAmount,
    required this.currentAmount,
    required this.createdAt,
    this.targetDate,
    this.isPaused = false,
    this.emoji,
  });

  /// The progress of the goal, clamped between 0.0 and 1.0 (100%).
  double get progressPercent {
    if (targetAmount <= 0) return 0.0;
    return (currentAmount / targetAmount).clamp(0.0, 1.0);
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'targetAmount': targetAmount,
      'currentAmount': currentAmount,
      'targetDate': targetDate?.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'isPaused': isPaused ? 1 : 0,
      'emoji': emoji,
    };
  }

  factory SavingGoal.fromMap(Map<String, dynamic> map) {
    return SavingGoal(
      id: map['id'] as String,
      name: map['name'] as String,
      targetAmount: (map['targetAmount'] as num).toDouble(),
      currentAmount: (map['currentAmount'] as num).toDouble(),
      targetDate: map['targetDate'] != null
          ? DateTime.parse(map['targetDate'] as String)
          : null,
      createdAt: DateTime.parse(map['createdAt'] as String),
      isPaused: (map['isPaused'] as int? ?? 0) == 1,
      emoji: map['emoji'] as String?,
    );
  }

  SavingGoal copyWith({
    String? id,
    String? name,
    double? targetAmount,
    double? currentAmount,
    DateTime? targetDate,
    DateTime? createdAt,
    bool? isPaused,
    String? emoji,
  }) {
    return SavingGoal(
      id: id ?? this.id,
      name: name ?? this.name,
      targetAmount: targetAmount ?? this.targetAmount,
      currentAmount: currentAmount ?? this.currentAmount,
      targetDate: targetDate ?? this.targetDate,
      createdAt: createdAt ?? this.createdAt,
      isPaused: isPaused ?? this.isPaused,
      emoji: emoji ?? this.emoji,
    );
  }
}
