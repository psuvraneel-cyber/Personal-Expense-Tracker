import 'package:flutter/material.dart';
import 'package:pet/premium/models/saving_goal.dart';
import 'package:pet/premium/repositories/saving_goal_repository.dart';
import 'package:uuid/uuid.dart';

class GoalProvider extends ChangeNotifier {
  final SavingGoalRepository _repository = SavingGoalRepository();
  final Uuid _uuid = const Uuid();

  List<SavingGoal> _goals = [];
  bool _isLoading = false;

  List<SavingGoal> get goals => _goals;
  bool get isLoading => _isLoading;

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();

    _goals = await _repository.getAll();

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
    _goals.insert(0, goal);
    notifyListeners();
  }

  Future<void> updateProgress(String id, double amount) async {
    final index = _goals.indexWhere((g) => g.id == id);
    if (index == -1) return;
    final updated = _goals[index].copyWith(currentAmount: amount);
    _goals[index] = updated;
    await _repository.upsert(updated);
    notifyListeners();
  }

  /// Add [amount] to a goal's current progress (e.g. from a "Top Up" action).
  Future<void> topUpGoal(String id, double amount) async {
    final index = _goals.indexWhere((g) => g.id == id);
    if (index == -1) return;
    final updated = _goals[index].copyWith(
      currentAmount: _goals[index].currentAmount + amount,
    );
    _goals[index] = updated;
    await _repository.upsert(updated);
    notifyListeners();
  }

  /// Toggle pause state on a goal.
  Future<void> togglePause(String id) async {
    final index = _goals.indexWhere((g) => g.id == id);
    if (index == -1) return;
    final updated = _goals[index].copyWith(isPaused: !_goals[index].isPaused);
    _goals[index] = updated;
    await _repository.upsert(updated);
    notifyListeners();
  }

  Future<void> deleteGoal(String id) async {
    await _repository.delete(id);
    _goals.removeWhere((g) => g.id == id);
    notifyListeners();
  }

  void clearData() {
    _goals = [];
    _isLoading = false;
    notifyListeners();
  }
}
