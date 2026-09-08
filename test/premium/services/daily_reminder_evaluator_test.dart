import 'package:flutter_test/flutter_test.dart';
import 'package:pet/premium/services/daily_reminder_evaluator.dart';

void main() {
  group('DailyReminderEvaluator', () {
    test('formatDateKey formats DateTime to YYYY-MM-DD', () {
      final dt = DateTime(2026, 7, 29, 20, 15);
      expect(DailyReminderEvaluator.formatDateKey(dt), '2026-07-29');
    });

    test('shouldFireReminder returns false before configured reminder hour', () {
      final now = DateTime(2026, 7, 29, 19, 59); // 7:59 PM
      final result = DailyReminderEvaluator.shouldFireReminder(
        now: now,
        reminderHour: 20,
        lastReminderDate: null,
        todayTransactionCount: 0,
      );
      expect(result, isFalse);
    });

    test('shouldFireReminder returns true at or after reminder hour when no txns and no prior alert today', () {
      final now = DateTime(2026, 7, 29, 20, 0); // 8:00 PM
      final result = DailyReminderEvaluator.shouldFireReminder(
        now: now,
        reminderHour: 20,
        lastReminderDate: null,
        todayTransactionCount: 0,
      );
      expect(result, isTrue);
    });

    test('shouldFireReminder implements smart suppression (returns false if transactions exist today)', () {
      final now = DateTime(2026, 7, 29, 20, 30); // 8:30 PM
      final result = DailyReminderEvaluator.shouldFireReminder(
        now: now,
        reminderHour: 20,
        lastReminderDate: null,
        todayTransactionCount: 2, // 2 expenses already logged today
      );
      expect(result, isFalse);
    });

    test('shouldFireReminder returns false if watermark matches today (already fired today)', () {
      final now = DateTime(2026, 7, 29, 21, 0); // 9:00 PM
      final result = DailyReminderEvaluator.shouldFireReminder(
        now: now,
        reminderHour: 20,
        lastReminderDate: '2026-07-29',
        todayTransactionCount: 0,
      );
      expect(result, isFalse);
    });

    test('shouldFireReminder returns true on new day after midnight crossing', () {
      final nowNewDay = DateTime(2026, 7, 30, 20, 5); // Next day 8:05 PM
      final result = DailyReminderEvaluator.shouldFireReminder(
        now: nowNewDay,
        reminderHour: 20,
        lastReminderDate: '2026-07-29', // Fired yesterday
        todayTransactionCount: 0,
      );
      expect(result, isTrue);
    });
  });
}
