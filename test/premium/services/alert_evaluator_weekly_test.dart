import 'package:flutter_test/flutter_test.dart';
import 'package:pet/premium/models/app_alert.dart';
import 'package:pet/premium/models/saving_goal.dart';
import 'package:pet/premium/providers/weekly_planner_provider.dart';
import 'package:pet/premium/services/alert_evaluator.dart';

void main() {
  final now = DateTime(2026, 3, 9, 14, 0); // Monday

  group('AlertEvaluator.evaluateWeeklyLimits (Phase G)', () {
    test('spending under 80% produces no alert', () {
      final entries = [
        WeeklyPlannerEntry(
          categoryId: 'cat-groceries',
          categoryName: 'Groceries',
          weeklyLimit: 2000,
          weeklySpent: 1500, // 75%
        ),
      ];

      final alerts = AlertEvaluator.evaluateWeeklyLimits(entries: entries, now: now);
      expect(alerts, isEmpty);
    });

    test('spending between 80% and 89% produces warning stage alert', () {
      final entries = [
        WeeklyPlannerEntry(
          categoryId: 'cat-groceries',
          categoryName: 'Groceries',
          weeklyLimit: 2000,
          weeklySpent: 1650, // 82.5%
        ),
      ];

      final alerts = AlertEvaluator.evaluateWeeklyLimits(entries: entries, now: now);
      expect(alerts.length, 1);
      final a = alerts.first;
      expect(a.stage, AppAlertStage.warning);
      expect(a.severity, AlertSeverity.warning);
      expect(a.alertKey, contains(':80'));
      expect(a.title, 'Weekly limit warning');
    });

    test('spending between 90% and 99% produces critical warning stage alert', () {
      final entries = [
        WeeklyPlannerEntry(
          categoryId: 'cat-dining',
          categoryName: 'Dining',
          weeklyLimit: 1000,
          weeklySpent: 950, // 95%
        ),
      ];

      final alerts = AlertEvaluator.evaluateWeeklyLimits(entries: entries, now: now);
      expect(alerts.length, 1);
      final a = alerts.first;
      expect(a.stage, AppAlertStage.critical);
      expect(a.severity, AlertSeverity.warning);
      expect(a.alertKey, contains(':90'));
      expect(a.title, 'Weekly limit almost reached');
    });

    test('spending >= 100% produces exceeded critical alert', () {
      final entries = [
        WeeklyPlannerEntry(
          categoryId: 'cat-shopping',
          categoryName: 'Shopping',
          weeklyLimit: 3000,
          weeklySpent: 3500, // 116.6%
        ),
      ];

      final alerts = AlertEvaluator.evaluateWeeklyLimits(entries: entries, now: now);
      expect(alerts.length, 1);
      final a = alerts.first;
      expect(a.stage, AppAlertStage.exceeded);
      expect(a.severity, AlertSeverity.critical);
      expect(a.alertKey, contains(':100'));
      expect(a.title, 'Weekly limit exceeded');
    });

    test('deterministic alertKey enables idempotent deduplication', () {
      final entries = [
        WeeklyPlannerEntry(
          categoryId: 'cat-travel',
          categoryName: 'Travel',
          weeklyLimit: 1000,
          weeklySpent: 850,
        ),
      ];

      final run1 = AlertEvaluator.evaluateWeeklyLimits(entries: entries, now: now);
      final run2 = AlertEvaluator.evaluateWeeklyLimits(entries: entries, now: now);

      expect(run1.first.alertKey, run2.first.alertKey);
    });
  });

  group('AlertEvaluator.evaluateGoals milestones (Phase M)', () {
    test('evaluates 25%, 50%, 75% and 100% milestone thresholds', () {
      final goals = [
        SavingGoal(
          id: 'g-25',
          name: 'Watch',
          targetAmount: 10000,
          currentAmount: 3000, // 30% -> >= 25%
          createdAt: now,
        ),
        SavingGoal(
          id: 'g-50',
          name: 'Bike',
          targetAmount: 50000,
          currentAmount: 26000, // 52% -> >= 50%
          createdAt: now,
        ),
        SavingGoal(
          id: 'g-75',
          name: 'Laptop',
          targetAmount: 100000,
          currentAmount: 80000, // 80% -> >= 75%
          createdAt: now,
        ),
        SavingGoal(
          id: 'g-100',
          name: 'Vacation',
          targetAmount: 20000,
          currentAmount: 20000, // 100% -> achieved
          createdAt: now,
        ),
        SavingGoal(
          id: 'g-under',
          name: 'New Car',
          targetAmount: 500000,
          currentAmount: 50000, // 10% -> under 25%
          createdAt: now,
        ),
      ];

      final alerts = AlertEvaluator.evaluateGoals(goals: goals, now: now);
      expect(alerts.length, 4);

      final a25 = alerts.firstWhere((a) => a.goalId == 'g-25');
      expect(a25.alertKey, 'goal_milestone:g-25:25');

      final a50 = alerts.firstWhere((a) => a.goalId == 'g-50');
      expect(a50.alertKey, 'goal_milestone:g-50:50');

      final a75 = alerts.firstWhere((a) => a.goalId == 'g-75');
      expect(a75.alertKey, 'goal_milestone:g-75:75');

      final a100 = alerts.firstWhere((a) => a.goalId == 'g-100');
      expect(a100.alertKey, 'goal_achieved:g-100');
      expect(a100.title, contains('Goal Achieved!'));
    });
  });
}
