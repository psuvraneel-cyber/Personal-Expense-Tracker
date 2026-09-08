import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:pet/core/utils/app_logger.dart';
import 'package:pet/premium/models/notification_category.dart';
import 'package:pet/premium/models/saving_goal.dart';
import 'package:pet/premium/repositories/saving_goal_repository.dart';
import 'package:pet/premium/services/alert_evaluation_coordinator.dart';
import 'package:pet/premium/services/notification_service.dart';
import 'package:pet/services/account_deletion_service.dart';
import 'package:pet/services/firestore_sync_service.dart';
import 'package:uuid/uuid.dart';

class GoalProvider extends ChangeNotifier {
  final SavingGoalRepository _repository;
  final FirestoreSyncService _firestoreSync;
  final Uuid _uuid = const Uuid();

  GoalProvider({
    SavingGoalRepository? repository,
    FirestoreSyncService? firestoreSync,
  })  : _repository = repository ?? SavingGoalRepository(),
        _firestoreSync = firestoreSync ?? FirestoreSyncService();

  List<SavingGoal> _goals = [];
  bool _isLoading = false;
  bool _isLoaded = false;
  bool _disposed = false;
  StreamSubscription<List<SavingGoal>>? _firestoreSubscription;

  List<SavingGoal> get goals => _goals;
  bool get isLoading => _isLoading;
  bool get isLoaded => _isLoaded;

  /// Total amount saved across active (non-paused) goals that must be protected as reserves.
  double get totalActiveGoalReserves => _goals
      .where((g) => !g.isPaused)
      .fold(0.0, (sum, g) => sum + g.currentAmount);

  /// Total amount saved across all goals regardless of pause status.
  double get totalSavedAmount =>
      _goals.fold(0.0, (sum, g) => sum + g.currentAmount);

  Future<void> load({bool force = false}) async {
    if (_disposed) return;
    if (_isLoaded && !force) return;
    _isLoading = true;
    notifyListeners();

    try {
      if (!kIsWeb) {
        _goals = await _repository.getAll();
      }
      _isLoaded = true;
      if (_disposed) return;
      notifyListeners();

      await _subscribeToFirestore();
    } catch (e, st) {
      AppLogger.error('Failed to load goals', error: e, stack: st, label: 'GoalProvider');
    } finally {
      if (!_disposed) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> _subscribeToFirestore() async {
    if (AccountDeletionService.isDeletionInProgress || _disposed) return;
    await _firestoreSubscription?.cancel();
    _firestoreSubscription = null;

    if (!_firestoreSync.isAuthenticated) return;

    final stream = _firestoreSync.savingGoalsStream();
    _firestoreSubscription = stream.listen(
      (remoteGoals) async {
        if (_disposed || AccountDeletionService.isDeletionInProgress) return;
        if (remoteGoals.isEmpty && _goals.isNotEmpty) return;

        final localMap = {for (final g in _goals) g.id: g};
        bool changed = false;

        for (final remote in remoteGoals) {
          final local = localMap[remote.id];
          if (local == null) {
            localMap[remote.id] = remote;
            if (!kIsWeb) await _repository.upsert(remote);
            changed = true;
          } else if (remote.createdAt.isAfter(local.createdAt) ||
                     remote.currentAmount != local.currentAmount ||
                     remote.isPaused != local.isPaused ||
                     remote.name != local.name ||
                     remote.targetAmount != local.targetAmount) {
            localMap[remote.id] = remote;
            if (!kIsWeb) await _repository.upsert(remote);
            changed = true;
          }
        }

        if (changed && !_disposed) {
          _goals = localMap.values.toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          notifyListeners();
        }
      },
      onError: (Object e) {
        AppLogger.debug('[GoalProvider] Firestore stream error: $e');
      },
    );
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
    if (!kIsWeb) {
      await _repository.upsert(goal);
    }
    _goals = [goal, ..._goals];
    notifyListeners();

    if (_firestoreSync.isAuthenticated) {
      unawaited(_firestoreSync.upsertSavingGoal(goal).catchError((e) {
        AppLogger.debug('[GoalProvider] Firestore upsertGoal failed: $e');
      }));
    }
  }

  Future<void> updateProgress(String id, double amount) async {
    final index = _goals.indexWhere((g) => g.id == id);
    if (index == -1) return;

    final wasAchieved =
        _goals[index].currentAmount >= _goals[index].targetAmount;
    final updated = _goals[index].copyWith(currentAmount: amount);
    final isNowAchieved = updated.currentAmount >= updated.targetAmount;

    _goals = List<SavingGoal>.from(_goals)..[index] = updated;
    if (!kIsWeb) {
      await _repository.upsert(updated);
    }
    notifyListeners();

    if (_firestoreSync.isAuthenticated) {
      unawaited(_firestoreSync.upsertSavingGoal(updated).catchError((e) {
        AppLogger.debug('[GoalProvider] Firestore sync updateProgress failed: $e');
      }));
    }

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
    if (!kIsWeb) {
      await _repository.upsert(updated);
    }
    notifyListeners();

    if (_firestoreSync.isAuthenticated) {
      unawaited(_firestoreSync.upsertSavingGoal(updated).catchError((e) {
        AppLogger.debug('[GoalProvider] Firestore sync topUpGoal failed: $e');
      }));
    }

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
    if (!kIsWeb) {
      await _repository.upsert(updated);
    }
    notifyListeners();

    if (_firestoreSync.isAuthenticated) {
      unawaited(_firestoreSync.upsertSavingGoal(updated).catchError((e) {
        AppLogger.debug('[GoalProvider] Firestore sync togglePause failed: $e');
      }));
    }
  }

  Future<void> deleteGoal(String id) async {
    if (!kIsWeb) {
      await _repository.delete(id);
    }
    _goals = _goals.where((g) => g.id != id).toList();
    AlertEvaluationCoordinator().onGoalDeleted(id);
    notifyListeners();

    if (_firestoreSync.isAuthenticated) {
      unawaited(_firestoreSync.deleteSavingGoal(id).catchError((e) {
        AppLogger.debug('[GoalProvider] Firestore sync deleteGoal failed: $e');
      }));
    }
  }

  Future<void> clearData() async {
    _goals = [];
    _isLoading = false;
    _isLoaded = false;
    notifyListeners();

    final sub = _firestoreSubscription;
    _firestoreSubscription = null;
    await sub?.cancel();

    if (!kIsWeb) {
      await _repository.deleteAll().catchError((e) {
        AppLogger.error('SavingGoal clear failed', error: e, label: 'GoalProvider');
      });
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _firestoreSubscription?.cancel();
    super.dispose();
  }
}
