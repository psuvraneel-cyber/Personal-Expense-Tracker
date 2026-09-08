const Object savingGoalSentinel = Object();

class SavingGoal {
  final String id;
  final String name;
  final double targetAmount;
  final double currentAmount;
  final DateTime? targetDate;
  final DateTime createdAt;
  final bool isPaused;
  final String? emoji;
  final DateTime? updatedAt;

  SavingGoal({
    required this.id,
    required this.name,
    required this.targetAmount,
    required this.currentAmount,
    required this.createdAt,
    this.targetDate,
    this.isPaused = false,
    this.emoji,
    this.updatedAt,
  });

  /// The progress of the goal, clamped between 0.0 and 1.0 (100%).
  double get progressPercent {
    if (targetAmount <= 0) return 0.0;
    return (currentAmount / targetAmount).clamp(0.0, 1.0);
  }

  /// Whether the goal target has been reached.
  bool get isAchieved => targetAmount > 0 && currentAmount >= targetAmount;

  /// Remaining amount needed to reach target (0.0 if already achieved).
  double get remainingAmount =>
      (targetAmount - currentAmount).clamp(0.0, double.infinity);

  /// Protected reserve amount: paused goals reserve 0; active goals reserve
  /// current saved amount clamped to targetAmount to prevent over-saving distortion.
  double get activeReserveAmount =>
      isPaused ? 0.0 : currentAmount.clamp(0.0, targetAmount);

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
      'updatedAt': updatedAt?.toIso8601String(),
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
      updatedAt: map['updatedAt'] != null
          ? DateTime.tryParse(map['updatedAt'] as String)
          : null,
    );
  }

  /// Type-safe copyWith using sentinel to distinguish between omitted arguments
  /// and explicit null values (e.g. clearing [targetDate] or [emoji]).
  SavingGoal copyWith({
    String? id,
    String? name,
    double? targetAmount,
    double? currentAmount,
    Object? targetDate = savingGoalSentinel,
    DateTime? createdAt,
    bool? isPaused,
    Object? emoji = savingGoalSentinel,
    Object? updatedAt = savingGoalSentinel,
  }) {
    return SavingGoal(
      id: id ?? this.id,
      name: name ?? this.name,
      targetAmount: targetAmount ?? this.targetAmount,
      currentAmount: currentAmount ?? this.currentAmount,
      targetDate: identical(targetDate, savingGoalSentinel)
          ? this.targetDate
          : (targetDate as DateTime?),
      createdAt: createdAt ?? this.createdAt,
      isPaused: isPaused ?? this.isPaused,
      emoji: identical(emoji, savingGoalSentinel)
          ? this.emoji
          : (emoji as String?),
      updatedAt: identical(updatedAt, savingGoalSentinel)
          ? this.updatedAt
          : (updatedAt as DateTime?),
    );
  }
}
