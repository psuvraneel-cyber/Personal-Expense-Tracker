import 'package:flutter_test/flutter_test.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/premium/services/alert_evaluator.dart';

void main() {
  final referenceTime = DateTime(2026, 7, 29, 10, 0);

  group('AlertEvaluator.evaluateCashflowRisk', () {
    test('returns cashflow alert when projected 30-day balance is negative/zero with sufficient data', () {
      // 10 days of heavy expense transactions with 0 income
      final transactions = List.generate(
        10,
        (i) => TransactionRecord(
          id: 't_$i',
          amount: 5000,
          type: TransactionType.expense,
          categoryId: 'food',
          date: referenceTime.subtract(Duration(days: i)),
        ),
      );

      final alert = AlertEvaluator.evaluateCashflowRisk(
        transactions: transactions,
        now: referenceTime,
      );

      expect(alert, isNotNull);
      expect(alert!.type, equals('cashflow'));
      expect(alert.alertKey, equals('cashflow_2026_7'));
      expect(alert.title, contains('Cashflow Risk Warning'));
    });

    test('returns null when projected 30-day balance is positive', () {
      // High income transactions over 10 days
      final transactions = List.generate(
        10,
        (i) => TransactionRecord(
          id: 't_$i',
          amount: 50000,
          type: TransactionType.income,
          categoryId: 'salary',
          date: referenceTime.subtract(Duration(days: i)),
        ),
      );

      final alert = AlertEvaluator.evaluateCashflowRisk(
        transactions: transactions,
        now: referenceTime,
      );

      expect(alert, isNull);
    });

    test('returns null when data is insufficient (span < 7 days)', () {
      // Only 3 days of transactions
      final transactions = List.generate(
        3,
        (i) => TransactionRecord(
          id: 't_$i',
          amount: 5000,
          type: TransactionType.expense,
          categoryId: 'food',
          date: referenceTime.subtract(Duration(days: i)),
        ),
      );

      final alert = AlertEvaluator.evaluateCashflowRisk(
        transactions: transactions,
        now: referenceTime,
      );

      expect(alert, isNull);
    });
  });
}
