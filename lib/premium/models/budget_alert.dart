import 'package:pet/premium/models/app_alert.dart';

export 'package:pet/premium/models/app_alert.dart';

/// Backward-compatibility adapter for legacy code and tests referencing [BudgetAlert].
class BudgetAlert extends AppAlert {
  BudgetAlert({
    required super.id,
    required dynamic type,
    required super.title,
    required super.message,
    required super.createdAt,
    super.categoryId,
    super.isRead = false,
    super.alertKey,
    super.stage,
    super.severity = AlertSeverity.warning,
    super.amount,
    super.targetAmount,
    super.ratio,
    super.transactionId,
    super.recurringPaymentId,
    super.goalId,
    super.period,
    super.isDismissed = false,
    super.actionType,
    super.actionPayload,
    super.updatedAt,
    super.resolvedAt,
    super.expiresAt,
  }) : super(
          type: type is AppAlertType
              ? type
              : AppAlertType.fromString(type as String?),
        );

  factory BudgetAlert.fromMap(Map<String, dynamic> map) {
    final a = AppAlert.fromMap(map);
    return BudgetAlert(
      id: a.id,
      type: a.type,
      title: a.title,
      message: a.message,
      categoryId: a.categoryId,
      createdAt: a.createdAt,
      isRead: a.isRead,
      alertKey: a.alertKey,
      stage: a.stage,
      severity: a.severity,
      amount: a.amount,
      targetAmount: a.targetAmount,
      ratio: a.ratio,
      transactionId: a.transactionId,
      recurringPaymentId: a.recurringPaymentId,
      goalId: a.goalId,
      period: a.period,
      isDismissed: a.isDismissed,
      actionType: a.actionType,
      actionPayload: a.actionPayload,
      updatedAt: a.updatedAt,
      resolvedAt: a.resolvedAt,
      expiresAt: a.expiresAt,
    );
  }
}
