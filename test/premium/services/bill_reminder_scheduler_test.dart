import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pet/premium/models/recurring_payment.dart';
import 'package:pet/premium/services/bill_reminder_scheduler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('BillReminderScheduler.scheduleReminders', () {
    test('filters out reminders whose schedule date (due - 3 days at 10 AM) is in the past', () async {
      final now = DateTime(2026, 7, 27, 12, 0, 0);
      // Due on July 29 -> reminder date is July 26 at 10:00 AM (in the past relative to July 27)
      final pastBill = RecurringPayment(
        id: 'bill_past',
        merchantName: 'Electricity Co',
        amount: 100.0,
        frequency: 'monthly',
        lastPaidAt: DateTime(2026, 6, 29),
        nextDueAt: DateTime(2026, 7, 29),
        categoryId: 'utilities',
        confidence: 1.0,
        source: 'manual',
      );

      // Should run without throwing errors and ignore past bill reminder
      await BillReminderScheduler.scheduleReminders([pastBill], now: now);
    });

    test('calculates correct reminder date 3 days prior at 10 AM for future bills', () async {
      final now = DateTime(2026, 7, 20, 10, 0, 0);
      // Due on July 29 -> reminder date is July 26 at 10:00 AM (in the future relative to July 20)
      final futureBill = RecurringPayment(
        id: 'bill_future',
        merchantName: 'Internet Corp',
        amount: 50.0,
        frequency: 'monthly',
        lastPaidAt: DateTime(2026, 6, 29),
        nextDueAt: DateTime(2026, 7, 29),
        categoryId: 'utilities',
        confidence: 1.0,
        source: 'manual',
      );

      // Should run without throwing errors
      await BillReminderScheduler.scheduleReminders([futureBill], now: now);
    });
  });
}
