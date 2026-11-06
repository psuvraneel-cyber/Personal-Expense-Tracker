import 'package:pet/premium/models/invoice.dart';
import 'package:pet/premium/models/notification_category.dart';
import 'package:pet/premium/services/notification_service.dart';

/// Local reminders for invoices clients haven't paid: one on the due date,
/// one [overdueAfterDays] later. They go to the user, never to the client.
class InvoiceReminderScheduler {
  InvoiceReminderScheduler._();

  static const int reminderHour = 10;
  static const int overdueAfterDays = 3;

  /// When the two reminders for [invoice] should fire.
  static ({DateTime due, DateTime overdue}) timesFor(Invoice invoice) {
    final d = invoice.dueDate;
    return (
      due: DateTime(d.year, d.month, d.day, reminderHour),
      overdue:
          DateTime(d.year, d.month, d.day + overdueAfterDays, reminderHour),
    );
  }

  static int _dueId(Invoice i) =>
      NotificationService.collisionSafeId('inv_due_${i.id}');
  static int _overdueId(Invoice i) =>
      NotificationService.collisionSafeId('inv_overdue_${i.id}');

  /// Brings [invoice]'s reminders up to date: scheduled while it's sent and
  /// unpaid, cancelled otherwise. The same ids are reused, so calling this
  /// after every change replaces rather than duplicates.
  static Future<void> sync(
    Invoice invoice, {
    required double balance,
    DateTime? now,
  }) async {
    await NotificationService.cancelNotification(_dueId(invoice));
    await NotificationService.cancelNotification(_overdueId(invoice));
    if (invoice.status != InvoiceStatus.sent || balance <= 0) return;

    final reference = now ?? DateTime.now();
    final times = timesFor(invoice);
    final amount = '₹${balance.toStringAsFixed(0)}';
    final who = invoice.billTo.name;
    if (times.due.isAfter(reference)) {
      await NotificationService.scheduleNotification(
        id: _dueId(invoice),
        title: 'Invoice due today',
        body: '${invoice.number} for $who: $amount unpaid.',
        scheduledDate: times.due,
        category: NotificationCategory.invoice,
        payload: 'invoice:${invoice.id}',
      );
    }
    if (times.overdue.isAfter(reference)) {
      await NotificationService.scheduleNotification(
        id: _overdueId(invoice),
        title: 'Invoice overdue',
        body: '${invoice.number} for $who: $amount still unpaid. '
            'Tap to remind them.',
        scheduledDate: times.overdue,
        category: NotificationCategory.invoice,
        payload: 'invoice:${invoice.id}',
      );
    }
  }
}
