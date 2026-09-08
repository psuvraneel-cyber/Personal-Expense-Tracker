import 'package:flutter_test/flutter_test.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/recurring_rule.dart';
import 'package:pet/services/recurrence_calculator.dart';

void main() {
  group('RecurrenceCalculator Tests', () {
    group('Daily Recurrence', () {
      test('Normal day progression', () {
        final anchor = DateTime(2026, 8, 20, 10, 2, 30);
        final next = RecurrenceCalculator.computeNextOccurrence(
          anchorDate: anchor,
          currentOccurrence: anchor,
          frequency: RecurringFrequency.daily,
        );
        expect(next, DateTime(2026, 8, 21, 10, 2, 30));
      });

      test('Month boundary transition (31 Aug -> 1 Sep)', () {
        final anchor = DateTime(2026, 8, 31, 14, 0);
        final next = RecurrenceCalculator.computeNextOccurrence(
          anchorDate: anchor,
          currentOccurrence: anchor,
          frequency: RecurringFrequency.daily,
        );
        expect(next, DateTime(2026, 9, 1, 14, 0));
      });

      test('Year boundary transition (31 Dec -> 1 Jan)', () {
        final anchor = DateTime(2026, 12, 31, 23, 59, 59);
        final next = RecurrenceCalculator.computeNextOccurrence(
          anchorDate: anchor,
          currentOccurrence: anchor,
          frequency: RecurringFrequency.daily,
        );
        expect(next, DateTime(2027, 1, 1, 23, 59, 59));
      });

      test('Leap year transition (28 Feb 2028 -> 29 Feb 2028 -> 1 Mar 2028)', () {
        final anchor = DateTime(2028, 2, 28, 8, 30);
        final feb29 = RecurrenceCalculator.computeNextOccurrence(
          anchorDate: anchor,
          currentOccurrence: anchor,
          frequency: RecurringFrequency.daily,
        );
        expect(feb29, DateTime(2028, 2, 29, 8, 30));

        final mar1 = RecurrenceCalculator.computeNextOccurrence(
          anchorDate: anchor,
          currentOccurrence: feb29,
          frequency: RecurringFrequency.daily,
        );
        expect(mar1, DateTime(2028, 3, 1, 8, 30));
      });
    });

    group('Weekly Recurrence', () {
      test('Preserves weekday and scheduled time', () {
        // Thursday 10:02 AM
        final anchor = DateTime(2026, 8, 20, 10, 2);
        expect(anchor.weekday, DateTime.thursday);

        final next = RecurrenceCalculator.computeNextOccurrence(
          anchorDate: anchor,
          currentOccurrence: anchor,
          frequency: RecurringFrequency.weekly,
        );
        expect(next, DateTime(2026, 8, 27, 10, 2));
        expect(next.weekday, DateTime.thursday);
      });

      test('Crosses month boundary maintaining weekday', () {
        final anchor = DateTime(2026, 8, 27, 10, 2);
        final next = RecurrenceCalculator.computeNextOccurrence(
          anchorDate: anchor,
          currentOccurrence: anchor,
          frequency: RecurringFrequency.weekly,
        );
        expect(next, DateTime(2026, 9, 3, 10, 2));
        expect(next.weekday, DateTime.thursday);
      });

      test('Crosses year boundary maintaining weekday', () {
        final anchor = DateTime(2026, 12, 31, 10, 2); // Thursday
        final next = RecurrenceCalculator.computeNextOccurrence(
          anchorDate: anchor,
          currentOccurrence: anchor,
          frequency: RecurringFrequency.weekly,
        );
        expect(next, DateTime(2027, 1, 7, 10, 2));
        expect(next.weekday, DateTime.thursday);
      });
    });

    group('Monthly Recurrence & Calendar Math', () {
      test('Normal 15th of month progression', () {
        final anchor = DateTime(2026, 1, 15, 9, 0);
        final feb = RecurrenceCalculator.computeNextOccurrence(
          anchorDate: anchor,
          currentOccurrence: anchor,
          frequency: RecurringFrequency.monthly,
        );
        expect(feb, DateTime(2026, 2, 15, 9, 0));
      });

      test('31st of month clamping: Jan 31 -> Feb 28 -> Mar 31 -> Apr 30 -> May 31 (Zero degradation)', () {
        final anchor = DateTime(2026, 1, 31, 10, 30);

        final feb = RecurrenceCalculator.computeNextOccurrence(
          anchorDate: anchor,
          currentOccurrence: anchor,
          frequency: RecurringFrequency.monthly,
        );
        expect(feb, DateTime(2026, 2, 28, 10, 30));

        final mar = RecurrenceCalculator.computeNextOccurrence(
          anchorDate: anchor,
          currentOccurrence: feb,
          frequency: RecurringFrequency.monthly,
        );
        // Crucial: Must return to 31st in March!
        expect(mar, DateTime(2026, 3, 31, 10, 30));

        final apr = RecurrenceCalculator.computeNextOccurrence(
          anchorDate: anchor,
          currentOccurrence: mar,
          frequency: RecurringFrequency.monthly,
        );
        expect(apr, DateTime(2026, 4, 30, 10, 30));

        final may = RecurrenceCalculator.computeNextOccurrence(
          anchorDate: anchor,
          currentOccurrence: apr,
          frequency: RecurringFrequency.monthly,
        );
        expect(may, DateTime(2026, 5, 31, 10, 30));
      });

      test('31st in leap year: Jan 31 2028 -> Feb 29 2028 -> Mar 31 2028', () {
        final anchor = DateTime(2028, 1, 31, 12, 0);

        final feb = RecurrenceCalculator.computeNextOccurrence(
          anchorDate: anchor,
          currentOccurrence: anchor,
          frequency: RecurringFrequency.monthly,
        );
        expect(feb, DateTime(2028, 2, 29, 12, 0));

        final mar = RecurrenceCalculator.computeNextOccurrence(
          anchorDate: anchor,
          currentOccurrence: feb,
          frequency: RecurringFrequency.monthly,
        );
        expect(mar, DateTime(2028, 3, 31, 12, 0));
      });

      test('Year rollover: Dec 2026 -> Jan 2027', () {
        final anchor = DateTime(2026, 12, 15, 18, 45);
        final next = RecurrenceCalculator.computeNextOccurrence(
          anchorDate: anchor,
          currentOccurrence: anchor,
          frequency: RecurringFrequency.monthly,
        );
        expect(next, DateTime(2027, 1, 15, 18, 45));
      });
    });

    group('Yearly Recurrence', () {
      test('Normal year progression', () {
        final anchor = DateTime(2026, 8, 20, 10, 0);
        final next = RecurrenceCalculator.computeNextOccurrence(
          anchorDate: anchor,
          currentOccurrence: anchor,
          frequency: RecurringFrequency.yearly,
        );
        expect(next, DateTime(2027, 8, 20, 10, 0));
      });

      test('Leap day yearly recurrence: 29 Feb 2028 -> 28 Feb 2029 -> ... -> 29 Feb 2032', () {
        final anchor = DateTime(2028, 2, 29, 11, 15);

        final y2029 = RecurrenceCalculator.computeNextOccurrence(
          anchorDate: anchor,
          currentOccurrence: anchor,
          frequency: RecurringFrequency.yearly,
        );
        expect(y2029, DateTime(2029, 2, 28, 11, 15));

        final y2030 = RecurrenceCalculator.computeNextOccurrence(
          anchorDate: anchor,
          currentOccurrence: y2029,
          frequency: RecurringFrequency.yearly,
        );
        expect(y2030, DateTime(2030, 2, 28, 11, 15));

        final y2031 = RecurrenceCalculator.computeNextOccurrence(
          anchorDate: anchor,
          currentOccurrence: y2030,
          frequency: RecurringFrequency.yearly,
        );
        expect(y2031, DateTime(2031, 2, 28, 11, 15));

        final y2032 = RecurrenceCalculator.computeNextOccurrence(
          anchorDate: anchor,
          currentOccurrence: y2031,
          frequency: RecurringFrequency.yearly,
        );
        // Returns to 29 Feb in leap year!
        expect(y2032, DateTime(2032, 2, 29, 11, 15));
      });
    });

    group('Time and Precision Invariants', () {
      test('Midnight scheduled time is preserved', () {
        final anchor = DateTime(2026, 1, 1, 0, 0, 0, 0);
        final next = RecurrenceCalculator.computeNextOccurrence(
          anchorDate: anchor,
          currentOccurrence: anchor,
          frequency: RecurringFrequency.monthly,
        );
        expect(next, DateTime(2026, 2, 1, 0, 0, 0, 0));
      });

      test('Late night 23:59:59 time is preserved', () {
        final anchor = DateTime(2026, 1, 1, 23, 59, 59, 500);
        final next = RecurrenceCalculator.computeNextOccurrence(
          anchorDate: anchor,
          currentOccurrence: anchor,
          frequency: RecurringFrequency.monthly,
        );
        expect(next, DateTime(2026, 2, 1, 23, 59, 59, 500));
      });

      test('Zero schedule drift over 12 cycles', () {
        final anchor = DateTime(2026, 1, 31, 10, 2, 15);
        var current = anchor;

        for (int i = 1; i <= 12; i++) {
          current = RecurrenceCalculator.computeNextOccurrence(
            anchorDate: anchor,
            currentOccurrence: current,
            frequency: RecurringFrequency.monthly,
          );
          expect(current.hour, 10);
          expect(current.minute, 2);
          expect(current.second, 15);
        }
        // At cycle 12 (Jan 2027), must be exactly Jan 31 2027 10:02:15
        expect(current, DateTime(2027, 1, 31, 10, 2, 15));
      });
    });

    group('Missed Occurrences / Catch-up', () {
      test('Returns empty when next occurrence is in the future', () {
        final rule = RecurringRule(
          id: 'rule_1',
          amount: 50000,
          type: TransactionType.income,
          categoryId: 'salary',
          frequency: RecurringFrequency.monthly,
          startDate: DateTime(2026, 8, 20, 10, 0),
          nextOccurrenceDate: DateTime(2026, 9, 20, 10, 0),
          createdAt: DateTime(2026, 8, 20),
          updatedAt: DateTime(2026, 8, 20),
        );

        final missed = RecurrenceCalculator.computeMissedOccurrences(
          rule: rule,
          now: DateTime(2026, 8, 25),
        );
        expect(missed, isEmpty);
      });

      test('Returns single due occurrence when now is at or after nextOccurrenceDate', () {
        final rule = RecurringRule(
          id: 'rule_1',
          amount: 50000,
          type: TransactionType.income,
          categoryId: 'salary',
          frequency: RecurringFrequency.monthly,
          startDate: DateTime(2026, 8, 20, 10, 0),
          nextOccurrenceDate: DateTime(2026, 9, 20, 10, 0),
          createdAt: DateTime(2026, 8, 20),
          updatedAt: DateTime(2026, 8, 20),
        );

        final missed = RecurrenceCalculator.computeMissedOccurrences(
          rule: rule,
          now: DateTime(2026, 9, 20, 10, 5),
        );
        expect(missed, [DateTime(2026, 9, 20, 10, 0)]);
      });

      test('Returns multiple missed occurrences when device was off for 3 months', () {
        final rule = RecurringRule(
          id: 'rule_salary',
          amount: 50000,
          type: TransactionType.income,
          categoryId: 'salary',
          frequency: RecurringFrequency.monthly,
          startDate: DateTime(2026, 8, 31, 10, 0),
          nextOccurrenceDate: DateTime(2026, 9, 30, 10, 0),
          createdAt: DateTime(2026, 8, 31),
          updatedAt: DateTime(2026, 8, 31),
        );

        // App opened on Dec 5, 2026
        final missed = RecurrenceCalculator.computeMissedOccurrences(
          rule: rule,
          now: DateTime(2026, 12, 5, 12, 0),
        );

        expect(missed, [
          DateTime(2026, 9, 30, 10, 0),
          DateTime(2026, 10, 31, 10, 0),
          DateTime(2026, 11, 30, 10, 0),
        ]);
      });

      test('Respects rule.endDate', () {
        final rule = RecurringRule(
          id: 'rule_temp',
          amount: 1000,
          type: TransactionType.expense,
          categoryId: 'subs',
          frequency: RecurringFrequency.monthly,
          startDate: DateTime(2026, 1, 1, 10, 0),
          nextOccurrenceDate: DateTime(2026, 2, 1, 10, 0),
          endDate: DateTime(2026, 3, 15, 23, 59),
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        );

        // App opened on Dec 2026
        final missed = RecurrenceCalculator.computeMissedOccurrences(
          rule: rule,
          now: DateTime(2026, 12, 1),
        );

        expect(missed, [
          DateTime(2026, 2, 1, 10, 0),
          DateTime(2026, 3, 1, 10, 0),
        ]);
      });

      test('Respects maxOccurrences cap', () {
        final rule = RecurringRule(
          id: 'rule_daily',
          amount: 50,
          type: TransactionType.expense,
          categoryId: 'food',
          frequency: RecurringFrequency.daily,
          startDate: DateTime(2025, 1, 1, 10, 0),
          nextOccurrenceDate: DateTime(2025, 1, 2, 10, 0),
          createdAt: DateTime(2025, 1, 1),
          updatedAt: DateTime(2025, 1, 1),
        );

        final missed = RecurrenceCalculator.computeMissedOccurrences(
          rule: rule,
          now: DateTime(2026, 1, 1),
          maxOccurrences: 10,
        );

        expect(missed.length, 10);
      });

      test('Returns empty for inactive rule', () {
        final rule = RecurringRule(
          id: 'rule_inactive',
          amount: 100,
          type: TransactionType.expense,
          categoryId: 'food',
          frequency: RecurringFrequency.daily,
          startDate: DateTime(2026, 8, 1, 10, 0),
          nextOccurrenceDate: DateTime(2026, 8, 2, 10, 0),
          isActive: false,
          createdAt: DateTime(2026, 8, 1),
          updatedAt: DateTime(2026, 8, 1),
        );

        final missed = RecurrenceCalculator.computeMissedOccurrences(
          rule: rule,
          now: DateTime(2026, 8, 20),
        );

        expect(missed, isEmpty);
      });
    });
  });
}
