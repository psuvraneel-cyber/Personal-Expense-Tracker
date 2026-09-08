enum WeeklyRecurrencePolicy {
  recurring,
  oneOff;

  String toJson() => name;
  static WeeklyRecurrencePolicy fromJson(String? value) {
    if (value == 'oneOff') return WeeklyRecurrencePolicy.oneOff;
    return WeeklyRecurrencePolicy.recurring;
  }
}

class WeeklyLimit {
  final String id;
  final String categoryId;
  final String categoryName;
  final double weeklyLimit;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isActive;
  final DateTime? periodStart;
  final WeeklyRecurrencePolicy recurrencePolicy;

  WeeklyLimit({
    required this.id,
    required this.categoryId,
    required this.categoryName,
    required this.weeklyLimit,
    required this.createdAt,
    required this.updatedAt,
    this.isActive = true,
    this.periodStart,
    this.recurrencePolicy = WeeklyRecurrencePolicy.recurring,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'categoryId': categoryId,
      'categoryName': categoryName,
      'weeklyLimit': weeklyLimit,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'isActive': isActive ? 1 : 0,
      'periodStart': periodStart?.toIso8601String(),
      'recurrencePolicy': recurrencePolicy.toJson(),
    };
  }

  factory WeeklyLimit.fromMap(Map<String, dynamic> map) {
    return WeeklyLimit(
      id: map['id'] as String,
      categoryId: map['categoryId'] as String,
      categoryName: map['categoryName'] as String,
      weeklyLimit: (map['weeklyLimit'] as num).toDouble(),
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
      isActive: (map['isActive'] as int? ?? 1) == 1,
      periodStart: map['periodStart'] != null
          ? DateTime.tryParse(map['periodStart'] as String)
          : null,
      recurrencePolicy: WeeklyRecurrencePolicy.fromJson(
        map['recurrencePolicy'] as String?,
      ),
    );
  }

  WeeklyLimit copyWith({
    String? id,
    String? categoryId,
    String? categoryName,
    double? weeklyLimit,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isActive,
    DateTime? periodStart,
    WeeklyRecurrencePolicy? recurrencePolicy,
  }) {
    return WeeklyLimit(
      id: id ?? this.id,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      weeklyLimit: weeklyLimit ?? this.weeklyLimit,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isActive: isActive ?? this.isActive,
      periodStart: periodStart ?? this.periodStart,
      recurrencePolicy: recurrencePolicy ?? this.recurrencePolicy,
    );
  }
}
