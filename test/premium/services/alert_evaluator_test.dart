import 'package:flutter_test/flutter_test.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/premium/models/app_alert.dart';
import 'package:pet/premium/models/recurring_payment.dart';
import 'package:pet/premium/models/saving_goal.dart';
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

    test(
        'returns warning alert when spent ratio is exactly 0.9 (0.90 boundary)',
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
      expect(alert.type, equals(AppAlertType.budget));
      expect(alert.stage, equals(AppAlertStage.warning));
      expect(alert.severity, equals(AlertSeverity.warning));
      expect(alert.title, equals('Budget warning'));
      expect(alert.message, contains('90% used'));
      expect(alert.categoryId, equals('cat_food'));
      expect(alert.alertKey, equals('budget:cat_food:2026-07:warning'));
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
      expect(alert.type, equals(AppAlertType.budget));
      expect(alert.stage, equals(AppAlertStage.exceeded));
      expect(alert.severity, equals(AlertSeverity.critical));
      expect(alert.title, equals('Budget exceeded'));
      expect(alert.alertKey, equals('budget:cat_food:2026-07:exceeded'));
    });

    test('returns critical stage alert when progress reaches 1.25 or higher',
        () {
      final budgets = {'cat_food': 100.0};
      final spent = {'cat_food': 130.0};

      final alerts = AlertEvaluator.evaluateBudgetAlerts(
        budgets: budgets,
        spent: spent,
        now: now,
      );

      expect(alerts.length, equals(1));
      final alert = alerts.first;
      expect(alert.stage, equals(AppAlertStage.critical));
      expect(alert.severity, equals(AlertSeverity.critical));
      expect(alert.title, equals('Critical budget overrun'));
      expect(alert.alertKey, equals('budget:cat_food:2026-07:critical'));
    });

    test('warning and exceeded stages have distinct alert keys', () {
      final warningAlerts = AlertEvaluator.evaluateBudgetAlerts(
        budgets: {'cat_food': 100.0},
        spent: {'cat_food': 95.0},
        now: now,
      );
      final exceededAlerts = AlertEvaluator.evaluateBudgetAlerts(
        budgets: {'cat_food': 100.0},
        spent: {'cat_food': 105.0},
        now: now,
      );

      expect(warningAlerts.first.alertKey,
          isNot(equals(exceededAlerts.first.alertKey)));
      expect(warningAlerts.first.alertKey,
          equals('budget:cat_food:2026-07:warning'));
      expect(exceededAlerts.first.alertKey,
          equals('budget:cat_food:2026-07:exceeded'));
    });

    test('next year same month generates distinct alert key', () {
      final now2026 = DateTime(2026, 7, 29);
      final now2027 = DateTime(2027, 7, 29);

      final alert2026 = AlertEvaluator.evaluateBudgetAlerts(
        budgets: {'cat_food': 100.0},
        spent: {'cat_food': 95.0},
        now: now2026,
      ).first;

      final alert2027 = AlertEvaluator.evaluateBudgetAlerts(
        budgets: {'cat_food': 100.0},
        spent: {'cat_food': 95.0},
        now: now2027,
      ).first;

      expect(alert2026.alertKey, equals('budget:cat_food:2026-07:warning'));
      expect(alert2027.alertKey, equals('budget:cat_food:2027-07:warning'));
      expect(alert2026.alertKey, isNot(equals(alert2027.alertKey)));
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

  group('AlertEvaluator.computeBaseline & Historical Mathematics Fix', () {
    test(
        'correctly computes category average over past 3 months excluding current month',
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
        // Current month (July) transaction must NOT contaminate baseline
        TransactionRecord(
          id: 't6',
          amount: 9999,
          date: DateTime(2026, 7, 10),
          categoryId: 'cat_dining',
          type: TransactionType.expense,
        ),
      ];

      final baseline = AlertEvaluator.computeBaseline(txns, now: now);

      // Dining expense total: 100 (May) + 200 (June) + 150 (April) = 450 across 3 distinct months -> avg = 150.0
      expect(baseline['cat_dining'], equals(150.0));
    });

    test(
        'CRITICAL FIX: 3 normal months + 1 normal current month does NOT trigger anomaly simply from cumulative lifetime spend',
        () {
      // User spent 10,000 in April, 10,000 in May, 10,000 in June, and 10,000 in July (now).
      // Total historical lifetime = 40,000.
      // Under the old bug: lifetime 40,000 / baseline 10,000 = 4.0x -> FALSE SPIKE ALERT!
      // Under the fixed implementation: July spend (10,000) / baseline (10,000) = 1.0x -> NO ANOMALY!
      final txns = [
        TransactionRecord(
          id: 'm1',
          amount: 10000,
          date: DateTime(2026, 4, 15),
          categoryId: 'cat_groceries',
          type: TransactionType.expense,
        ),
        TransactionRecord(
          id: 'm2',
          amount: 10000,
          date: DateTime(2026, 5, 15),
          categoryId: 'cat_groceries',
          type: TransactionType.expense,
        ),
        TransactionRecord(
          id: 'm3',
          amount: 10000,
          date: DateTime(2026, 6, 15),
          categoryId: 'cat_groceries',
          type: TransactionType.expense,
        ),
        TransactionRecord(
          id: 'm4',
          amount: 10000,
          date: DateTime(2026, 7, 15),
          categoryId: 'cat_groceries',
          type: TransactionType.expense,
        ),
      ];

      final baseline = AlertEvaluator.computeBaseline(txns, now: now);
      expect(baseline['cat_groceries'], equals(10000.0));

      final alerts = AlertEvaluator.evaluateAnomalies(
        transactions: txns,
        baseline: baseline,
        now: now,
      );

      // Must be empty!
      expect(alerts, isEmpty);
    });
  });

  group('AlertEvaluator.evaluateAnomalies', () {
    test('detects genuine spending spikes exceeding 1.8x baseline', () {
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
      expect(alert.type, equals(AppAlertType.anomaly));
      expect(alert.title, equals('Spending spike detected'));
      expect(
        alert.message,
        equals('This category is 2.5x higher than usual.'),
      );
      expect(alert.categoryId, equals('cat_shopping'));
      expect(alert.alertKey, equals('anomaly:cat_shopping:2026-07'));
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

  group('AlertEvaluator.evaluateBudgetPacing', () {
    test('suppresses pacing alerts early in the month (day < 5)', () {
      final day2 = DateTime(2026, 7, 2);
      final alerts = AlertEvaluator.evaluateBudgetPacing(
        budgets: {'cat_food': 10000.0},
        spent: {'cat_food': 2000.0},
        now: day2,
      );
      expect(alerts, isEmpty);
    });

    test(
        'triggers pacing warning when spending run-rate exceeds budget by 15%+',
        () {
      // Day 10 of 31-day month: spent 6,000 of 10,000 budget.
      // Daily rate: 600/day -> Projected: 18,600 (186% of budget)
      // Exhaustion day: 10,000 / 600 = 16 (in 6 days)
      final day10 = DateTime(2026, 7, 10);
      final alerts = AlertEvaluator.evaluateBudgetPacing(
        budgets: {'cat_food': 10000.0},
        spent: {'cat_food': 6000.0},
        now: day10,
      );

      expect(alerts.length, equals(1));
      final alert = alerts.first;
      expect(alert.type, equals(AppAlertType.budget));
      expect(alert.stage, equals(AppAlertStage.pacing));
      expect(alert.title, equals('Budget pacing warning'));
      expect(alert.message, contains('may run out in 6 days'));
      expect(alert.alertKey, equals('budget_pacing:cat_food:2026-07'));
    });

    test('does not trigger pacing warning when spending is on track', () {
      // Day 10 of 31-day month: spent 2,000 of 10,000 budget -> Projected 6,200 (well within budget)
      final day10 = DateTime(2026, 7, 10);
      final alerts = AlertEvaluator.evaluateBudgetPacing(
        budgets: {'cat_food': 10000.0},
        spent: {'cat_food': 2000.0},
        now: day10,
      );

      expect(alerts, isEmpty);
    });
  });

  group('AlertEvaluator.evaluateLargeTransactions', () {
    test('detects transactions exceeding 70% of category budget', () {
      final txns = [
        TransactionRecord(
          id: 'txn_large_1',
          amount: 8000,
          date: DateTime(2026, 7, 10),
          categoryId: 'cat_dining',
          merchantName: 'Fancy Bistro',
          type: TransactionType.expense,
        ),
      ];

      final alerts = AlertEvaluator.evaluateLargeTransactions(
        transactions: txns,
        categoryBudgets: {'cat_dining': 10000.0},
        now: now,
      );

      expect(alerts.length, equals(1));
      final alert = alerts.first;
      expect(alert.type, equals(AppAlertType.largeTransaction));
      expect(alert.alertKey, equals('large_txn:txn_large_1'));
      expect(alert.title, equals('Large transaction detected'));
      expect(alert.message, contains('₹8000 at Fancy Bistro'));
    });
  });

  group('AlertEvaluator.evaluateDuplicateTransactions', () {
    test('detects two payments of same amount to same merchant within 15 mins',
        () {
      final t1 = TransactionRecord(
        id: 'dup_1',
        amount: 500,
        date: DateTime(2026, 7, 10, 14, 0),
        categoryId: 'cat_coffee',
        merchantName: 'Cafe Coffee Day',
        type: TransactionType.expense,
      );
      final t2 = TransactionRecord(
        id: 'dup_2',
        amount: 500,
        date: DateTime(2026, 7, 10, 14, 8), // 8 mins later
        categoryId: 'cat_coffee',
        merchantName: 'Cafe Coffee Day',
        type: TransactionType.expense,
      );

      final alerts = AlertEvaluator.evaluateDuplicateTransactions(
        transactions: [t1, t2],
        now: now,
      );

      expect(alerts.length, equals(1));
      final alert = alerts.first;
      expect(alert.type, equals(AppAlertType.duplicateTransaction));
      expect(alert.alertKey, equals('dup_txn:dup_1_dup_2'));
      expect(alert.message, contains('Two payments of ₹500 were recorded within 8 minutes'));
    });

    test('ignores duplicate amounts if separated by more than 15 mins', () {
      final t1 = TransactionRecord(
        id: 'dup_1',
        amount: 500,
        date: DateTime(2026, 7, 10, 10, 0),
        categoryId: 'cat_coffee',
        merchantName: 'Cafe Coffee Day',
        type: TransactionType.expense,
      );
      final t2 = TransactionRecord(
        id: 'dup_2',
        amount: 500,
        date: DateTime(2026, 7, 10, 16, 0), // 6 hours later
        categoryId: 'cat_coffee',
        merchantName: 'Cafe Coffee Day',
        type: TransactionType.expense,
      );

      final alerts = AlertEvaluator.evaluateDuplicateTransactions(
        transactions: [t1, t2],
        now: now,
      );

      expect(alerts, isEmpty);
    });
  });

  group('AlertEvaluator.evaluateBills & evaluateGoals', () {
    test('evaluates upcoming bill due in 2 days', () {
      final bill = RecurringPayment(
        id: 'rec_netflix',
        merchantName: 'Netflix',
        amount: 649,
        frequency: 'monthly',
        lastPaidAt: DateTime(2026, 6, 30),
        nextDueAt: DateTime(2026, 7, 31), // 2 days from now (July 29)
        categoryId: 'cat_entertainment',
      );

      final alerts = AlertEvaluator.evaluateBills(
        recurring: [bill],
        now: now,
      );

      expect(alerts.length, equals(1));
      final alert = alerts.first;
      expect(alert.type, equals(AppAlertType.bill));
      expect(alert.alertKey, equals('bill:rec_netflix:2026-07-31'));
      expect(alert.message, contains('due in 2 days'));
    });

    test('evaluates goal achieved milestone', () {
      final goal = SavingGoal(
        id: 'goal_macbook',
        name: 'New Laptop',
        targetAmount: 100000,
        currentAmount: 100000,
        createdAt: DateTime(2026, 1, 1),
      );

      final alerts = AlertEvaluator.evaluateGoals(
        goals: [goal],
        now: now,
      );

      expect(alerts.length, equals(1));
      final alert = alerts.first;
      expect(alert.type, equals(AppAlertType.goal));
      expect(alert.title, equals('🎉 Goal Achieved!'));
      expect(alert.alertKey, equals('goal_achieved:goal_macbook'));
    });
  });
}
