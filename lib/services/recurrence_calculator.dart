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
        final currentTotalMonths =
            currentOccurrence.year * 12 + (currentOccurrence.month - 1);
        final targetTotalMonths = currentTotalMonths + interval;
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
