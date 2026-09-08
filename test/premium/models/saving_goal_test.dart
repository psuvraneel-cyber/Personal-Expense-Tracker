import 'package:flutter_test/flutter_test.dart';
import 'package:pet/premium/models/saving_goal.dart';

void main() {
  group('SavingGoal copyWith nullable semantics (B1)', () {
    final original = SavingGoal(
      id: 'goal-1',
      name: 'Emergency Fund',
      targetAmount: 50000,
      currentAmount: 10000,
      targetDate: DateTime(2026, 12, 31),
      emoji: '🏦',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      isPaused: false,
    );

    test('parameter omitted -> preserves existing nullable values', () {
      final copied = original.copyWith(name: 'Updated Name');
      expect(copied.name, 'Updated Name');
      expect(copied.targetDate, DateTime(2026, 12, 31));
      expect(copied.emoji, '🏦');
      expect(copied.id, original.id);
      expect(copied.targetAmount, original.targetAmount);
    });

    test('parameter explicitly null -> clears existing nullable values', () {
      final copied = original.copyWith(
        targetDate: null,
        emoji: null,
      );
      expect(copied.targetDate, isNull, reason: 'Explicit null should clear targetDate');
      expect(copied.emoji, isNull, reason: 'Explicit null should clear emoji');
      expect(copied.name, original.name);
      expect(copied.targetAmount, original.targetAmount);
    });

    test('parameter provided with non-null value -> replaces existing value', () {
      final newDate = DateTime(2027, 6, 30);
      final copied = original.copyWith(
        targetDate: newDate,
        emoji: '🎯',
      );
      expect(copied.targetDate, newDate);
      expect(copied.emoji, '🎯');
    });

    test('null to set date -> sets value from null', () {
      final noDate = original.copyWith(targetDate: null);
      expect(noDate.targetDate, isNull);

      final setDate = noDate.copyWith(targetDate: DateTime(2028, 1, 1));
      expect(setDate.targetDate, DateTime(2028, 1, 1));
    });
  });

  group('SavingGoal.activeReserveAmount invariants (Phase A3 & B2)', () {
    test('paused goal contributes 0.0 to reserve', () {
      final goal = SavingGoal(
        id: 'paused-goal',
        name: 'Paused Goal',
        targetAmount: 10000,
        currentAmount: 5000,
        createdAt: DateTime.now(),
        isPaused: true,
      );
      expect(goal.activeReserveAmount, 0.0);
    });

    test('active goal contributes currentAmount when currentAmount <= targetAmount', () {
      final goal = SavingGoal(
        id: 'active-goal',
        name: 'Active Goal',
        targetAmount: 10000,
        currentAmount: 4500,
        createdAt: DateTime.now(),
        isPaused: false,
      );
      expect(goal.activeReserveAmount, 4500.0);
    });

    test('overfunded goal is capped at targetAmount for reserve calculation', () {
      final goal = SavingGoal(
        id: 'overfunded-goal',
        name: 'Overfunded Goal',
        targetAmount: 10000,
        currentAmount: 25000, // Oversaved
        createdAt: DateTime.now(),
        isPaused: false,
      );
      // Reserves cannot be arbitrarily inflated beyond the target commitment
      expect(goal.activeReserveAmount, 10000.0);
    });

    test('negative currentAmount contributes 0.0 to reserve', () {
      final goal = SavingGoal(
        id: 'negative-goal',
        name: 'Negative Goal',
        targetAmount: 10000,
        currentAmount: -500,
        createdAt: DateTime.now(),
        isPaused: false,
      );
      expect(goal.activeReserveAmount, 0.0);
    });
  });

  group('SavingGoal serialization', () {
    test('toMap and fromMap preserve all fields including updatedAt and status', () {
      final goal = SavingGoal(
        id: 'goal-full',
        name: 'MacBook Pro',
        targetAmount: 200000,
        currentAmount: 75000,
        targetDate: DateTime(2026, 11, 15),
        emoji: '💻',
        createdAt: DateTime(2026, 1, 1, 10, 0),
        updatedAt: DateTime(2026, 3, 1, 15, 30),
        isPaused: false,
      );

      final map = goal.toMap();
      final reconstructed = SavingGoal.fromMap(map);

      expect(reconstructed.id, goal.id);
      expect(reconstructed.name, goal.name);
      expect(reconstructed.targetAmount, goal.targetAmount);
      expect(reconstructed.currentAmount, goal.currentAmount);
      expect(reconstructed.targetDate, goal.targetDate);
      expect(reconstructed.emoji, goal.emoji);
      expect(reconstructed.createdAt, goal.createdAt);
      expect(reconstructed.updatedAt, goal.updatedAt);
      expect(reconstructed.isPaused, goal.isPaused);
    });
  });

  group('SavingGoal mathematical stability and invariants', () {
    test('handles zero, negative, and NaN target amounts gracefully', () {
      final zeroTarget = SavingGoal(
        id: 'g-zero',
        name: 'Zero Target',
        targetAmount: 0,
        currentAmount: 100,
        createdAt: DateTime.now(),
      );
      expect(zeroTarget.progressPercent, 0.0);
      expect(zeroTarget.isAchieved, isFalse);
      expect(zeroTarget.remainingAmount, 0.0);
      expect(zeroTarget.activeReserveAmount, 0.0);

      final negTarget = SavingGoal(
        id: 'g-neg',
        name: 'Negative Target',
        targetAmount: -500,
        currentAmount: 100,
        createdAt: DateTime.now(),
      );
      expect(negTarget.progressPercent, 0.0);
      expect(negTarget.isAchieved, isFalse);
      expect(negTarget.remainingAmount, 0.0);
      expect(negTarget.activeReserveAmount, 0.0);

      final nanGoal = SavingGoal(
        id: 'g-nan',
        name: 'NaN Target',
        targetAmount: double.nan,
        currentAmount: 100,
        createdAt: DateTime.now(),
      );
      expect(nanGoal.progressPercent, 0.0);
      expect(nanGoal.isAchieved, isFalse);
      expect(nanGoal.remainingAmount, 0.0);
      expect(nanGoal.activeReserveAmount, 0.0);
    });

    test('handles NaN and infinite current amounts gracefully', () {
      final nanCurrent = SavingGoal(
        id: 'g-curr-nan',
        name: 'NaN Current',
        targetAmount: 1000,
        currentAmount: double.nan,
        createdAt: DateTime.now(),
      );
      expect(nanCurrent.progressPercent, 0.0);
      expect(nanCurrent.isAchieved, isFalse);
      expect(nanCurrent.remainingAmount, 1000.0);
      expect(nanCurrent.activeReserveAmount, 0.0);

      final infCurrent = SavingGoal(
        id: 'g-curr-inf',
        name: 'Inf Current',
        targetAmount: 1000,
        currentAmount: double.infinity,
        createdAt: DateTime.now(),
      );
      expect(infCurrent.progressPercent, 0.0);
      expect(infCurrent.isAchieved, isFalse);
      expect(infCurrent.remainingAmount, 1000.0);
      expect(infCurrent.activeReserveAmount, 0.0);
    });

    test('clamps progressPercent between 0.0 and 1.0', () {
      final normal = SavingGoal(
        id: 'g-normal',
        name: 'Normal',
        targetAmount: 1000,
        currentAmount: 500,
        createdAt: DateTime.now(),
      );
      expect(normal.progressPercent, 0.5);
      expect(normal.isAchieved, isFalse);
      expect(normal.remainingAmount, 500.0);
      expect(normal.activeReserveAmount, 500.0);

      final over = SavingGoal(
        id: 'g-over',
        name: 'Overfunded',
        targetAmount: 1000,
        currentAmount: 2000,
        createdAt: DateTime.now(),
      );
      expect(over.progressPercent, 1.0);
      expect(over.isAchieved, isTrue);
      expect(over.remainingAmount, 0.0);
      expect(over.activeReserveAmount, 1000.0);
    });
  });
}
