import 'package:pet/data/models/enums.dart';
import 'package:pet/premium/models/notification_category.dart';
import 'package:pet/premium/models/recurring_payment.dart';
import 'package:pet/premium/services/notification_service.dart';

/// Utility class for scheduling upcoming bill reminders via flutter_local_notifications.
/// Can be invoked from both foreground (RecurringProvider) and background WorkManager isolates.
class BillReminderScheduler {
  BillReminderScheduler._();

  /// Computes and schedules a notification 3 days before the due date at 10:00 AM.
  /// Only schedules for confirmed active commitments if the reminder date is strictly in the future.
  static Future<void> scheduleReminders(
    List<RecurringPayment> recurring, {
    DateTime? now,
  }) async {
    final referenceTime = now ?? DateTime.now();

    for (final item in recurring) {
      // Unconfirmed detections or cancelled bills should not fire scheduled notifications
      if (item.status != RecurringStatus.confirmed) continue;

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
        final title = item.isAutopay
            ? 'Upcoming autopay reminder'
            : 'Upcoming bill reminder';
        final body = item.isAutopay
            ? '${item.merchantName} (₹${item.amount.toStringAsFixed(0)}) autopay expected in 3 days. Check that your balance is sufficient.'
            : '${item.merchantName} (₹${item.amount.toStringAsFixed(0)}) is due in 3 days.';

        await NotificationService.scheduleNotification(
          id: NotificationService.collisionSafeId(idKey),
          title: title,
          body: body,
          scheduledDate: scheduleDate,
          category: NotificationCategory.bill,
          payload: payload,
        );
      }
    }
  }

  /// Cancels any scheduled reminder for a specific recurring payment occurrence.
  static Future<void> cancelReminder(RecurringPayment item) async {
    final idKey = 'sched_${item.id}_${item.nextDueAt.toIso8601String()}';
    await NotificationService.cancelNotification(
      NotificationService.collisionSafeId(idKey),
    );
  }
}
