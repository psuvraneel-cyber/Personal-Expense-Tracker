import 'package:flutter/material.dart';
import 'package:pet/premium/models/notification_category.dart';
import 'package:pet/premium/models/saving_goal.dart';
import 'package:pet/premium/repositories/saving_goal_repository.dart';
import 'package:pet/premium/services/alert_evaluation_coordinator.dart';
import 'package:pet/premium/services/notification_service.dart';
import 'package:uuid/uuid.dart';

class GoalProvider extends ChangeNotifier {
  final SavingGoalRepository _repository = SavingGoalRepository();
  final Uuid _uuid = const Uuid();

  List<SavingGoal> _goals = [];
  bool _isLoading = false;
  bool _isLoaded = false;

  List<SavingGoal> get goals => _goals;
  bool get isLoading => _isLoading;
  bool get isLoaded => _isLoaded;

  Future<void> load({bool force = false}) async {
    if (_isLoaded && !force) return;
    _isLoading = true;
    notifyListeners();

    _goals = await _repository.getAll();
    _isLoaded = true;

    _isLoading = false;
    notifyListeners();
  }

  Future<void> addGoal({
    required String name,
    required double targetAmount,
    DateTime? targetDate,
    String? emoji,
  }) async {
    final goal = SavingGoal(
      id: _uuid.v4(),
      name: name,
      targetAmount: targetAmount,
      currentAmount: 0,
      createdAt: DateTime.now(),
      targetDate: targetDate,
      emoji: emoji,
    );
    await _repository.upsert(goal);
    _goals = [goal, ..._goals];
    notifyListeners();
  }

  Future<void> updateProgress(String id, double amount) async {
    final index = _goals.indexWhere((g) => g.id == id);
    if (index == -1) return;

    final wasAchieved =
        _goals[index].currentAmount >= _goals[index].targetAmount;
    final updated = _goals[index].copyWith(currentAmount: amount);
    final isNowAchieved = updated.currentAmount >= updated.targetAmount;

    _goals = List<SavingGoal>.from(_goals)..[index] = updated;
    await _repository.upsert(updated);
    notifyListeners();

    if (!wasAchieved && isNowAchieved) {
      await _checkAndSendAchievementNotification(updated);
    }
  }

  /// Add [amount] to a goal's current progress (e.g. from a "Top Up" action).
  Future<void> topUpGoal(String id, double amount) async {
    final index = _goals.indexWhere((g) => g.id == id);
    if (index == -1) return;

    final wasAchieved =
        _goals[index].currentAmount >= _goals[index].targetAmount;
    final updated = _goals[index].copyWith(
      currentAmount: _goals[index].currentAmount + amount,
    );
    final isNowAchieved = updated.currentAmount >= updated.targetAmount;

    _goals = List<SavingGoal>.from(_goals)..[index] = updated;
    await _repository.upsert(updated);
    notifyListeners();

    if (!wasAchieved && isNowAchieved) {
      await _checkAndSendAchievementNotification(updated);
    }
  }

  Future<void> _checkAndSendAchievementNotification(SavingGoal goal) async {
    await NotificationService.showInstant(
      id: NotificationService.collisionSafeId('goal_${goal.id}'),
      title: '🎉 Goal Achieved!',
      body: 'Congratulations! You reached your saving goal: ${goal.name}',
      category: NotificationCategory.goalProgress,
      payload: 'goal:${goal.id}',
    );
    try {
      await AlertEvaluationCoordinator().onGoalsChanged([goal]);
    } catch (_) {}
  }

  /// Toggle pause state on a goal.
  Future<void> togglePause(String id) async {
    final index = _goals.indexWhere((g) => g.id == id);
    if (index == -1) return;
    final updated = _goals[index].copyWith(isPaused: !_goals[index].isPaused);
    _goals = List<SavingGoal>.from(_goals)..[index] = updated;
    await _repository.upsert(updated);
    notifyListeners();
  }

  Future<void> deleteGoal(String id) async {
    await _repository.delete(id);
    _goals = _goals.where((g) => g.id != id).toList();
    AlertEvaluationCoordinator().onGoalDeleted(id);
    notifyListeners();
  }

  void clearData() {
    _goals = [];
    _isLoading = false;
    _isLoaded = false;
    notifyListeners();
  }
}
