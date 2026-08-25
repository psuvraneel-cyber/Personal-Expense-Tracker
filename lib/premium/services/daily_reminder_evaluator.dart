/// Pure static evaluator for daily expense reminders.
/// Encapsulates time checks, watermark date comparison, and smart suppression.
class DailyReminderEvaluator {
  DailyReminderEvaluator._();

  /// Returns ISO date string 'YYYY-MM-DD' for a given [DateTime].
  static String formatDateKey(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Returns true if a daily expense reminder should fire.
  ///
  /// Criteria:
  /// 1. Current hour >= [reminderHour] (default 20 / 8 PM).
  /// 2. [lastReminderDate] is null or not equal to today's date key ('YYYY-MM-DD').
  /// 3. [todayTransactionCount] is 0 (smart suppression: if user already logged expenses today, don't remind).
  static bool shouldFireReminder({
    required DateTime now,
    required int reminderHour,
    required String? lastReminderDate,
    required int todayTransactionCount,
  }) {
    if (now.hour < reminderHour) return false;
    final todayKey = formatDateKey(now);
    if (lastReminderDate == todayKey) return false;
    if (todayTransactionCount > 0) return false;
    return true;
  }
}
