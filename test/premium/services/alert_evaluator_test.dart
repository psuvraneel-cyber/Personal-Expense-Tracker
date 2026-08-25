import 'package:flutter_test/flutter_test.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/premium/services/alert_evaluator.dart';

void main() {
  final now = DateTime(2026, 7, 29);

  group('AlertEvaluator.evaluateBudgetAlerts', () {
    test('returns no alert when spent ratio is below 0.9 (0.89 boundary)', () {
      final budgets = {'cat_food': 100.0};
      final spent = {'cat_food': 89.0};

      final alerts = AlertEvaluator.evaluateBudgetAlerts(
        budgets: budgets,
        spent: spent,
        now: now,
      );

      expect(alerts, isEmpty);
    });

    test('returns warning alert when spent ratio is exactly 0.9 (0.90 boundary)',
        () {
      final budgets = {'cat_food': 100.0};
      final spent = {'cat_food': 90.0};

      final alerts = AlertEvaluator.evaluateBudgetAlerts(
        budgets: budgets,
        spent: spent,
        now: now,
      );

      expect(alerts.length, equals(1));
      final alert = alerts.first;
      expect(alert.type, equals('budget'));
      expect(alert.title, equals('Budget warning'));
      expect(alert.message, equals('You are close to your budget limit.'));
      expect(alert.categoryId, equals('cat_food'));
      expect(alert.alertKey, equals('budget_cat_food_7'));
    });

    test(
        'returns exceeded alert when spent ratio is 1.0 or higher (1.00 boundary)',
        () {
      final budgets = {'cat_food': 100.0};
      final spent = {'cat_food': 100.0};

      final alerts = AlertEvaluator.evaluateBudgetAlerts(
        budgets: budgets,
        spent: spent,
        now: now,
      );

      expect(alerts.length, equals(1));
      final alert = alerts.first;
      expect(alert.type, equals('budget'));
      expect(alert.title, equals('Budget exceeded'));
      expect(
        alert.message,
        equals('You have crossed your budget in this category.'),
      );
      expect(alert.categoryId, equals('cat_food'));
      expect(alert.alertKey, equals('budget_cat_food_7'));
    });

    test('returns exceeded alert when spent ratio exceeds 1.0 (e.g. 1.20)', () {
      final budgets = {'cat_food': 100.0};
      final spent = {'cat_food': 120.0};

      final alerts = AlertEvaluator.evaluateBudgetAlerts(
        budgets: budgets,
        spent: spent,
        now: now,
      );

      expect(alerts.length, equals(1));
      expect(alerts.first.title, equals('Budget exceeded'));
    });

    test('ignores categories with invalid or zero/negative budget amount', () {
      final budgets = {'cat_food': 0.0, 'cat_rent': -50.0};
      final spent = {'cat_food': 10.0, 'cat_rent': 10.0};

      final alerts = AlertEvaluator.evaluateBudgetAlerts(
        budgets: budgets,
        spent: spent,
        now: now,
      );

      expect(alerts, isEmpty);
    });
  });

  group('AlertEvaluator.computeBaseline', () {
    test('correctly computes category average over past 3 months of expenses',
        () {
      final txns = [
        TransactionRecord(
          id: 't1',
          amount: 100,
          date: DateTime(2026, 5, 10),
          categoryId: 'cat_dining',
          type: TransactionType.expense,
        ),
        TransactionRecord(
          id: 't2',
          amount: 200,
          date: DateTime(2026, 6, 15),
          categoryId: 'cat_dining',
          type: TransactionType.expense,
        ),
        TransactionRecord(
          id: 't3',
          amount: 150,
          date: DateTime(2026, 4, 1),
          categoryId: 'cat_dining',
          type: TransactionType.expense,
        ),
        // Income should be ignored
        TransactionRecord(
          id: 't4',
          amount: 1000,
          date: DateTime(2026, 5, 1),
          categoryId: 'cat_dining',
          type: TransactionType.income,
        ),
        // Transaction older than 3 months should be ignored
        TransactionRecord(
          id: 't5',
          amount: 500,
          date: DateTime(2026, 3, 31),
          categoryId: 'cat_dining',
          type: TransactionType.expense,
        ),
      ];

      final baseline = AlertEvaluator.computeBaseline(txns, now: now);

      // Dining expense total: 100 (May) + 200 (June) + 150 (April) = 450 across 3 distinct months -> avg = 150.0
      expect(baseline['cat_dining'], equals(150.0));
    });
  });

  group('AlertEvaluator.evaluateAnomalies', () {
    test('detects spending spikes exceeding 1.8x baseline', () {
      final currentTxns = [
        TransactionRecord(
          id: 't4',
          amount: 250,
          date: DateTime(2026, 7, 15),
          categoryId: 'cat_shopping',
          type: TransactionType.expense,
        ),
      ];
      final baseline = {'cat_shopping': 100.0};

      final alerts = AlertEvaluator.evaluateAnomalies(
        transactions: currentTxns,
        baseline: baseline,
        now: now,
      );

      expect(alerts.length, equals(1));
      final alert = alerts.first;
      expect(alert.type, equals('anomaly'));
      expect(alert.title, equals('Spending spike detected'));
      expect(
        alert.message,
        equals('This category is 2.5x higher than usual.'),
      );
      expect(alert.categoryId, equals('cat_shopping'));
      expect(alert.alertKey, equals('anomaly_cat_shopping_7'));
    });

    test('returns no anomaly alert when spending is normal', () {
      final currentTxns = [
        TransactionRecord(
          id: 't1',
          amount: 100,
          date: DateTime(2026, 7, 10),
          categoryId: 'cat_shopping',
          type: TransactionType.expense,
        ),
      ];
      final baseline = {'cat_shopping': 100.0};

      final alerts = AlertEvaluator.evaluateAnomalies(
        transactions: currentTxns,
        baseline: baseline,
        now: now,
      );

      expect(alerts, isEmpty);
    });
  });
}
