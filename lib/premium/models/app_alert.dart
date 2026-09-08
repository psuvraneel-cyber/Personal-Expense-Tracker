import 'package:flutter/foundation.dart';

enum AppAlertType {
  budget('budget'),
  anomaly('anomaly'),
  cashflow('cashflow'),
  bill('bill'),
  goal('goal'),
  largeTransaction('large_transaction'),
  duplicateTransaction('duplicate_transaction'),
  system('system');

  final String value;
  const AppAlertType(this.value);

  static AppAlertType fromString(String? val) {
    return AppAlertType.values.firstWhere(
      (e) => e.value == val || e.name == val,
      orElse: () => AppAlertType.system,
    );
  }
}

enum AlertSeverity {
  info('info'),
  warning('warning'),
  critical('critical');

  final String value;
  const AlertSeverity(this.value);

  static AlertSeverity fromString(String? val) {
    return AlertSeverity.values.firstWhere(
      (e) => e.value == val || e.name == val,
      orElse: () => AlertSeverity.warning,
    );
  }
}

enum AppAlertStage {
  warning('warning'),
  exceeded('exceeded'),
  critical('critical'),
  pacing('pacing'),
  milestone('milestone'),
  info('info');

  final String value;
  const AppAlertStage(this.value);

  static AppAlertStage? fromString(String? val) {
    if (val == null) return null;
    return AppAlertStage.values.firstWhere(
      (e) => e.value == val || e.name == val,
      orElse: () => AppAlertStage.info,
    );
  }
}

enum AlertActionType {
  viewTransactions('view_transactions'),
  adjustBudget('adjust_budget'),
  viewCashflow('view_cashflow'),
  viewBill('view_bill'),
  viewGoal('view_goal'),
  inspectTransaction('inspect_transaction');

  final String value;
  const AlertActionType(this.value);

  static AlertActionType? fromString(String? val) {
    if (val == null) return null;
    return AlertActionType.values.firstWhere(
      (e) => e.value == val || e.name == val,
      orElse: () => AlertActionType.viewTransactions,
    );
  }
}

/// Unified domain model for all alerts across P.E.T.
@immutable
class AppAlert {
  final String id;
  final AppAlertType type;
  final AppAlertStage? stage;
  final AlertSeverity severity;
  final String title;
  final String message;
  final String? alertKey;
  final String? categoryId;
  final double? amount;
  final double? targetAmount;
  final double? ratio;
  final String? transactionId;
  final String? recurringPaymentId;
  final String? goalId;
  final String? period; // Canonical: YYYY-MM
  final bool isRead;
  final bool isDismissed;
  final AlertActionType? actionType;
  final String? actionPayload;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? resolvedAt;
  final DateTime? expiresAt;

  const AppAlert({
    required this.id,
    required this.type,
    this.stage,
    this.severity = AlertSeverity.warning,
    required this.title,
    required this.message,
    this.alertKey,
    this.categoryId,
    this.amount,
    this.targetAmount,
    this.ratio,
    this.transactionId,
    this.recurringPaymentId,
    this.goalId,
    this.period,
    this.isRead = false,
    this.isDismissed = false,
    this.actionType,
    this.actionPayload,
    required this.createdAt,
    this.updatedAt,
    this.resolvedAt,
    this.expiresAt,
  });

  /// Factory helper to build an alert with backwards compatibility for legacy string types.
  factory AppAlert.fromLegacy({
    required String id,
    required String type,
    required String title,
    required String message,
    required DateTime createdAt,
    String? categoryId,
    bool isRead = false,
    String? alertKey,
    AlertSeverity severity = AlertSeverity.warning,
    AppAlertStage? stage,
    double? amount,
    double? targetAmount,
    double? ratio,
  }) {
    return AppAlert(
      id: id,
      type: AppAlertType.fromString(type),
      stage: stage,
      severity: severity,
      title: title,
      message: message,
      categoryId: categoryId,
      createdAt: createdAt,
      isRead: isRead,
      alertKey: alertKey,
      amount: amount,
      targetAmount: targetAmount,
      ratio: ratio,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type.value,
      'stage': stage?.value,
      'severity': severity.value,
      'title': title,
      'message': message,
      'alertKey': alertKey,
      'categoryId': categoryId,
      'amount': amount,
      'targetAmount': targetAmount,
      'ratio': ratio,
      'transactionId': transactionId,
      'recurringPaymentId': recurringPaymentId,
      'goalId': goalId,
      'period': period,
      'isRead': isRead ? 1 : 0,
      'isDismissed': isDismissed ? 1 : 0,
      'actionType': actionType?.value,
      'actionPayload': actionPayload,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'resolvedAt': resolvedAt?.toIso8601String(),
      'expiresAt': expiresAt?.toIso8601String(),
    };
  }

  factory AppAlert.fromMap(Map<String, dynamic> map) {
    return AppAlert(
      id: map['id'] as String,
      type: AppAlertType.fromString(map['type'] as String?),
      stage: AppAlertStage.fromString(map['stage'] as String?),
      severity: AlertSeverity.fromString(map['severity'] as String?),
      title: map['title'] as String,
      message: map['message'] as String,
      alertKey: map['alertKey'] as String?,
      categoryId: map['categoryId'] as String?,
      amount: (map['amount'] as num?)?.toDouble(),
      targetAmount: (map['targetAmount'] as num?)?.toDouble(),
      ratio: (map['ratio'] as num?)?.toDouble(),
      transactionId: map['transactionId'] as String?,
      recurringPaymentId: map['recurringPaymentId'] as String?,
      goalId: map['goalId'] as String?,
      period: map['period'] as String?,
      isRead: (map['isRead'] as int? ?? 0) == 1,
      isDismissed: (map['isDismissed'] as int? ?? 0) == 1,
      actionType: AlertActionType.fromString(map['actionType'] as String?),
      actionPayload: map['actionPayload'] as String?,
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: map['updatedAt'] != null
          ? DateTime.tryParse(map['updatedAt'] as String)
          : null,
      resolvedAt: map['resolvedAt'] != null
          ? DateTime.tryParse(map['resolvedAt'] as String)
          : null,
      expiresAt: map['expiresAt'] != null
          ? DateTime.tryParse(map['expiresAt'] as String)
          : null,
    );
  }

  AppAlert copyWith({
    String? id,
    AppAlertType? type,
    AppAlertStage? stage,
    AlertSeverity? severity,
    String? title,
    String? message,
    String? alertKey,
    String? categoryId,
    double? amount,
    double? targetAmount,
    double? ratio,
    String? transactionId,
    String? recurringPaymentId,
    String? goalId,
    String? period,
    bool? isRead,
    bool? isDismissed,
    AlertActionType? actionType,
    String? actionPayload,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? resolvedAt,
    DateTime? expiresAt,
  }) {
    return AppAlert(
      id: id ?? this.id,
      type: type ?? this.type,
      stage: stage ?? this.stage,
      severity: severity ?? this.severity,
      title: title ?? this.title,
      message: message ?? this.message,
      alertKey: alertKey ?? this.alertKey,
      categoryId: categoryId ?? this.categoryId,
      amount: amount ?? this.amount,
      targetAmount: targetAmount ?? this.targetAmount,
      ratio: ratio ?? this.ratio,
      transactionId: transactionId ?? this.transactionId,
      recurringPaymentId: recurringPaymentId ?? this.recurringPaymentId,
      goalId: goalId ?? this.goalId,
      period: period ?? this.period,
      isRead: isRead ?? this.isRead,
      isDismissed: isDismissed ?? this.isDismissed,
      actionType: actionType ?? this.actionType,
      actionPayload: actionPayload ?? this.actionPayload,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }
}
