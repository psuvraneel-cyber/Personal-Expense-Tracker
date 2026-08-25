import 'package:pet/premium/models/notification_category.dart';
import 'package:pet/premium/models/recurring_payment.dart';
import 'package:pet/premium/services/notification_service.dart';

/// Utility class for scheduling upcoming bill reminders via flutter_local_notifications.
/// Can be invoked from both foreground (RecurringProvider) and background WorkManager isolates.
class BillReminderScheduler {
  BillReminderScheduler._();

  /// Computes and schedules a notification 3 days before the due date at 10:00 AM.
  /// Only schedules if the resulting reminder date is strictly in the future.
  static Future<void> scheduleReminders(
    List<RecurringPayment> recurring, {
    DateTime? now,
  }) async {
    final referenceTime = now ?? DateTime.now();

    for (final item in recurring) {
      final dueDate = item.nextDueAt;
      final scheduleDate = DateTime(
        dueDate.year,
        dueDate.month,
        dueDate.day,
        10,
        0,
        0,
      ).subtract(const Duration(days: 3));

      if (scheduleDate.isAfter(referenceTime)) {
        final idKey = 'sched_${item.id}_${item.nextDueAt.toIso8601String()}';
        final payload = 'bill:${item.id}';
        await NotificationService.scheduleNotification(
          id: NotificationService.collisionSafeId(idKey),
          title: 'Upcoming bill reminder',
          body: '${item.merchantName} is due in 3 days.',
          scheduledDate: scheduleDate,
          category: NotificationCategory.bill,
          payload: payload,
        );
      }
    }
  }
}
