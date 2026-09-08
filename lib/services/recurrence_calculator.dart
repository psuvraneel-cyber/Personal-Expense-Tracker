import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/recurring_rule.dart';

/// Pure calendar-correct recurrence engine.
///
/// Designed to prevent schedule drift, handle leap years, month-end clamping
/// (e.g. 31 Jan -> 28 Feb -> 31 Mar -> 30 Apr), and compute bounded catch-up
/// occurrences for offline / missed intervals.
class RecurrenceCalculator {
  RecurrenceCalculator._();

  /// Returns the number of days in the given [month] of [year].
  static int daysInMonth(int year, int month) {
    return DateTime(year, month + 1, 0).day;
  }

  /// Whether the given [year] is a leap year.
  static bool isLeapYear(int year) {
    return (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0);
  }

  /// Computes the next occurrence date after [currentOccurrence], anchored to [anchorDate].
  ///
  /// [anchorDate] is the original starting date/time of the recurrence rule.
  /// Preserving [anchorDate] ensures that month-end dates (e.g. 31st) or leap days (Feb 29)
  /// do not permanently degrade after passing through shorter months.
  static DateTime computeNextOccurrence({
    required DateTime anchorDate,
    required DateTime currentOccurrence,
    required RecurringFrequency frequency,
    int interval = 1,
  }) {
    if (interval < 1) interval = 1;

    switch (frequency) {
      case RecurringFrequency.daily:
        return DateTime(
          currentOccurrence.year,
          currentOccurrence.month,
          currentOccurrence.day + interval,
          anchorDate.hour,
          anchorDate.minute,
          anchorDate.second,
          anchorDate.millisecond,
          anchorDate.microsecond,
        );

      case RecurringFrequency.weekly:
        return DateTime(
          currentOccurrence.year,
          currentOccurrence.month,
          currentOccurrence.day + (interval * 7),
          anchorDate.hour,
          anchorDate.minute,
          anchorDate.second,
          anchorDate.millisecond,
          anchorDate.microsecond,
        );

      case RecurringFrequency.monthly:
      case RecurringFrequency.quarterly:
      case RecurringFrequency.semiannual:
        final monthMultiplier = frequency == RecurringFrequency.quarterly
            ? 3
            : frequency == RecurringFrequency.semiannual
                ? 6
                : 1;
        final currentTotalMonths =
            currentOccurrence.year * 12 + (currentOccurrence.month - 1);
        final targetTotalMonths = currentTotalMonths + (interval * monthMultiplier);
        final targetYear = targetTotalMonths ~/ 12;
        final targetMonth = (targetTotalMonths % 12) + 1;
        final maxDays = daysInMonth(targetYear, targetMonth);
        final targetDay = anchorDate.day.clamp(1, maxDays);

        return DateTime(
          targetYear,
          targetMonth,
          targetDay,
          anchorDate.hour,
          anchorDate.minute,
          anchorDate.second,
          anchorDate.millisecond,
          anchorDate.microsecond,
        );

      case RecurringFrequency.yearly:
        final targetYear = currentOccurrence.year + interval;
        final targetMonth = anchorDate.month;
        final maxDays = daysInMonth(targetYear, targetMonth);
        final targetDay = anchorDate.day.clamp(1, maxDays);

        return DateTime(
          targetYear,
          targetMonth,
          targetDay,
          anchorDate.hour,
          anchorDate.minute,
          anchorDate.second,
          anchorDate.millisecond,
          anchorDate.microsecond,
        );
    }
  }

  /// Calculates the next due date when marking a bill or recurring payment as paid.
  ///
  /// Correctly handles on-time, early, and heavily overdue/late payments.
  /// If [paidDate] is after [currentDue], advances cycles until the next due date
  /// is strictly in the future relative to [paidDate], preserving calendar anchor days.
  static DateTime advanceNextDueDate({
    required DateTime currentDue,
    required RecurringFrequency frequency,
    DateTime? paidDate,
  }) {
    final paymentTime = paidDate ?? DateTime.now();
    var next = computeNextOccurrence(
      anchorDate: currentDue,
      currentOccurrence: currentDue,
      frequency: frequency,
    );

    // If the payment was made late (e.g. Due Aug 1, Paid Sep 5), advance until
    // the next due date is strictly in the future relative to the payment date.
    var safetyLimit = 0;
    while (!next.isAfter(paymentTime) && safetyLimit < 100) {
      safetyLimit++;
      next = computeNextOccurrence(
        anchorDate: currentDue,
        currentOccurrence: next,
        frequency: frequency,
      );
    }

    return next;
  }

  /// Returns the annualization multiplier for a given frequency.
  static double annualMultiplier(RecurringFrequency frequency) {
    return switch (frequency) {
      RecurringFrequency.daily => 365,
      RecurringFrequency.weekly => 52,
      RecurringFrequency.monthly => 12,
      RecurringFrequency.quarterly => 4,
      RecurringFrequency.semiannual => 2,
      RecurringFrequency.yearly => 1,
    };
  }

  /// Returns the monthly equivalent multiplier for a given frequency.
  static double monthlyMultiplier(RecurringFrequency frequency) {
    return switch (frequency) {
      RecurringFrequency.daily => 30,
      RecurringFrequency.weekly => 52 / 12,
      RecurringFrequency.monthly => 1,
      RecurringFrequency.quarterly => 1 / 3,
      RecurringFrequency.semiannual => 1 / 6,
      RecurringFrequency.yearly => 1 / 12,
    };
  }

  /// Computes all missed or due occurrence dates for [rule] up to [now].
  ///
  /// Starts from [rule.nextOccurrenceDate].
  /// Caps results at [maxOccurrences] to prevent unbounded loops on malformed/ancient rules.
  static List<DateTime> computeMissedOccurrences({
    required RecurringRule rule,
    required DateTime now,
    int maxOccurrences = 100,
  }) {
    if (!rule.isActive) return [];

    final occurrences = <DateTime>[];
    var candidate = rule.nextOccurrenceDate;

    while (!candidate.isAfter(now)) {
      if (rule.endDate != null && candidate.isAfter(rule.endDate!)) {
        break;
      }

      occurrences.add(candidate);
      if (occurrences.length >= maxOccurrences) {
        break;
      }

      candidate = computeNextOccurrence(
        anchorDate: rule.startDate,
        currentOccurrence: candidate,
        frequency: rule.frequency,
        interval: rule.interval,
      );
    }

    return occurrences;
  }
}
