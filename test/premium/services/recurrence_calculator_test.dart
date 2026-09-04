import 'package:flutter_test/flutter_test.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/services/recurrence_calculator.dart';

void main() {
  group('RecurrenceCalculator Calendar-Accurate Calculations', () {
    test('computes quarterly (every 3 months) accurately across year boundaries and month lengths', () {
      // 31 Aug + 3 months -> 30 Nov (Nov has 30 days, clamped correctly)
      final aug31 = DateTime(2026, 8, 31, 10, 0);
      final nextNov = RecurrenceCalculator.computeNextOccurrence(
        anchorDate: aug31,
        currentOccurrence: aug31,
        frequency: RecurringFrequency.quarterly,
      );
      expect(nextNov.year, 2026);
      expect(nextNov.month, 11);
      expect(nextNov.day, 30);

      // 30 Nov + 3 months -> 28 Feb 2027 (Feb non-leap year has 28 days)
      final nextFeb = RecurrenceCalculator.computeNextOccurrence(
        anchorDate: aug31,
        currentOccurrence: nextNov,
        frequency: RecurringFrequency.quarterly,
      );
      expect(nextFeb.year, 2027);
      expect(nextFeb.month, 2);
      expect(nextFeb.day, 28);

      // 28 Feb + 3 months -> 31 May 2027 (recovers anchor 31st day!)
      final nextMay = RecurrenceCalculator.computeNextOccurrence(
        anchorDate: aug31,
        currentOccurrence: nextFeb,
        frequency: RecurringFrequency.quarterly,
      );
      expect(nextMay.year, 2027);
      expect(nextMay.month, 5);
      expect(nextMay.day, 31);
    });

    test('computes semiannual (every 6 months) correctly across year boundary', () {
      // 15 Oct 2026 + 6 months -> 15 Apr 2027
      final oct15 = DateTime(2026, 10, 15, 9, 0);
      final next = RecurrenceCalculator.computeNextOccurrence(
        anchorDate: oct15,
        currentOccurrence: oct15,
        frequency: RecurringFrequency.semiannual,
      );
      expect(next.year, 2027);
      expect(next.month, 4);
      expect(next.day, 15);
    });

    test('computes yearly December -> January correctly without integer overflow', () {
      final dec15 = DateTime(2026, 12, 15, 12, 0);
      final next = RecurrenceCalculator.computeNextOccurrence(
        anchorDate: dec15,
        currentOccurrence: dec15,
        frequency: RecurringFrequency.yearly,
      );
      expect(next.year, 2027);
      expect(next.month, 12);
      expect(next.day, 15);
    });

    test('handles leap year Feb 29 recurrence gracefully', () {
      // 2028 is a leap year (Feb 29 exists)
      final leapFeb29 = DateTime(2028, 2, 29);
      // Next year 2029 (non-leap) -> Feb 28
      final year2029 = RecurrenceCalculator.computeNextOccurrence(
        anchorDate: leapFeb29,
        currentOccurrence: leapFeb29,
        frequency: RecurringFrequency.yearly,
      );
      expect(year2029.year, 2029);
      expect(year2029.month, 2);
      expect(year2029.day, 28);

      // Next 4 years 2032 (leap year) -> Feb 29 (recovers leap anchor)
      final year2032 = RecurrenceCalculator.computeNextOccurrence(
        anchorDate: leapFeb29,
        currentOccurrence: DateTime(2031, 2, 28),
        frequency: RecurringFrequency.yearly,
      );
      expect(year2032.year, 2032);
      expect(year2032.month, 2);
      expect(year2032.day, 29);
    });

    test('advanceNextDueDate correctly advances on-time, early, and late payments', () {
      final due = DateTime(2026, 8, 1);

      // On-time payment on Aug 1 -> Next due is Sep 1
      final onTimeNext = RecurrenceCalculator.advanceNextDueDate(
        currentDue: due,
        frequency: RecurringFrequency.monthly,
        paidDate: DateTime(2026, 8, 1),
      );
      expect(onTimeNext, equals(DateTime(2026, 9, 1)));

      // Early payment on July 25 for Aug 1 bill -> Next due is Sep 1
      final earlyNext = RecurrenceCalculator.advanceNextDueDate(
        currentDue: due,
        frequency: RecurringFrequency.monthly,
        paidDate: DateTime(2026, 7, 25),
      );
      expect(earlyNext, equals(DateTime(2026, 9, 1)));

      // Heavily late payment: Due Aug 1, but paid on Oct 10
      // Next due date must NOT report Aug 1 or Sep 1 or Oct 1! Must be Nov 1 (strictly future)
      final lateNext = RecurrenceCalculator.advanceNextDueDate(
        currentDue: due,
        frequency: RecurringFrequency.monthly,
        paidDate: DateTime(2026, 10, 10),
      );
      expect(lateNext.year, 2026);
      expect(lateNext.month, 11);
      expect(lateNext.day, 1);
    });
  });
}
