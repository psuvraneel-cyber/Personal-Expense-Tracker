import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:pet/core/utils/app_logger.dart';
import 'package:pet/premium/models/goal_history_item.dart';
import 'package:pet/premium/models/saving_goal.dart';
import 'package:pet/premium/repositories/saving_goal_repository.dart';
import 'package:pet/premium/services/alert_evaluation_coordinator.dart';
import 'package:pet/services/account_deletion_service.dart';
import 'package:pet/services/firestore_sync_service.dart';
import 'package:uuid/uuid.dart';

enum TopUpStatus {
  success,
  alreadyAchieved,
  exceedsTarget,
  invalidAmount,
  goalNotFound,
  goalPaused,
}

class TopUpResult {
  final TopUpStatus status;
  final double allowedAmount;
  final double overage;
  final SavingGoal? updatedGoal;

  const TopUpResult({
    required this.status,
    this.allowedAmount = 0.0,
    this.overage = 0.0,
    this.updatedGoal,
  });

  bool get isSuccess => status == TopUpStatus.success;
}

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

  /// Authoritative single source of truth for total protected goal reserves.
  /// Uses [SavingGoal.activeReserveAmount] which returns 0.0 for paused goals
  /// and clamps currentAmount to targetAmount to prevent over-saving distortion.
  double get totalActiveGoalReserves =>
      _goals.fold(0.0, (sum, g) => sum + g.activeReserveAmount);

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
      AppLogger.error(
        'Failed to load goals',
        error: e,
        stack: st,
        label: 'GoalProvider',
      );
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

    final expectedSession = _firestoreSync.currentSession;

    final stream = _firestoreSync.savingGoalsStream();
    _firestoreSubscription = stream.listen(
      (remoteGoals) async {
        if (_disposed || AccountDeletionService.isDeletionInProgress) return;
        // Invalidate stale in-flight snapshot if session generation or user has changed
        if (!_firestoreSync.currentSession.matches(expectedSession)) {
          AppLogger.warn(
            '[GoalProvider] Dropping stale Firestore snapshot from superseded session: $expectedSession vs ${_firestoreSync.currentSession}',
            label: 'GoalProvider',
          );
          return;
        }
        await reconcileRemoteGoals(remoteGoals);
      },
      onError: (Object e) {
        AppLogger.debug('[GoalProvider] Firestore stream error: $e');
      },
    );
  }

  /// Reconciles local SQLite state with remote Firestore snapshot.
  /// Detects remote deletions and cleans up local ghosts.
  @visibleForTesting
  Future<void> reconcileRemoteGoals(List<SavingGoal> remoteGoals) async {
    if (_disposed || AccountDeletionService.isDeletionInProgress) return;

    final remoteIds = remoteGoals.map((g) => g.id).toSet();
    final localMap = {for (final g in _goals) g.id: g};
    bool changed = false;

    // 1. Reconcile remote creations and updates with strict LWW
    for (final remote in remoteGoals) {
      final local = localMap[remote.id];
      if (local == null) {
        localMap[remote.id] = remote;
        if (!kIsWeb) await _repository.upsert(remote);
        changed = true;
      } else {
        final remoteUpdated = remote.updatedAt ?? remote.createdAt;
        final localUpdated = local.updatedAt ?? local.createdAt;

        if (remoteUpdated.isAfter(localUpdated)) {
          // Remote is strictly newer: overwrite local
          localMap[remote.id] = remote;
          if (!kIsWeb) await _repository.upsert(remote);
          changed = true;
        } else if (localUpdated.isAfter(remoteUpdated)) {
          // Local is strictly newer: preserve local and upload to Firestore
          if (_firestoreSync.isAuthenticated) {
            unawaited(_firestoreSync.upsertSavingGoal(local).catchError((e) {
              AppLogger.debug(
                  '[GoalProvider] Uploading newer local goal to remote: $e');
            }));
          }
        } else {
          // Identical timestamps: deterministic tie-breaker if fields differ
          final localMapStr = local.toMap().toString();
          final remoteMapStr = remote.toMap().toString();
          if (localMapStr != remoteMapStr) {
            if (remoteMapStr.compareTo(localMapStr) > 0) {
              localMap[remote.id] = remote;
              if (!kIsWeb) await _repository.upsert(remote);
              changed = true;
            } else {
              if (_firestoreSync.isAuthenticated) {
                unawaited(
                    _firestoreSync.upsertSavingGoal(local).catchError((e) {
                  AppLogger.debug(
                      '[GoalProvider] Uploading tied local goal to remote: $e');
                }));
              }
            }
          }
        }
      }
    }

    // 2. Goals that exist locally but NOT in remote snapshot:
    // Preserve local goals (never delete on snapshot absence) and upload offline-created goals.
    for (final local in _goals) {
      if (!remoteIds.contains(local.id)) {
        if (_firestoreSync.isAuthenticated) {
          unawaited(_firestoreSync.upsertSavingGoal(local).catchError((e) {
            AppLogger.debug(
                '[GoalProvider] Syncing offline-created goal to remote: $e');
          }));
        }
      }
    }

    if (changed && !_disposed) {
      _goals = localMap.values.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      notifyListeners();
    }
  }

  Future<void> addGoal({
    required String name,
    required double targetAmount,
    DateTime? targetDate,
    String? emoji,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('Goal name cannot be empty');
    }
    if (targetAmount <= 0) {
      throw ArgumentError('Target amount must be greater than zero');
    }

    final now = DateTime.now();
    final goal = SavingGoal(
      id: _uuid.v4(),
      name: trimmedName,
      targetAmount: targetAmount,
      currentAmount: 0,
      createdAt: now,
      targetDate: targetDate,
      emoji: emoji,
      updatedAt: now,
    );
    if (!kIsWeb) {
      await _repository.mutateGoalWithHistory(
        goal: goal,
        history: GoalHistoryItem(
          id: _uuid.v4(),
          goalId: goal.id,
          amount: 0,
          actionType: 'created',
          createdAt: now,
          note: 'Goal created',
          previousAmount: 0.0,
          resultingAmount: 0.0,
          source: 'manual',
        ),
      );
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
    if (amount < 0) {
      throw ArgumentError('Progress amount cannot be negative');
    }
    final index = _goals.indexWhere((g) => g.id == id);
    if (index == -1) return;

    final goal = _goals[index];
    final wasAchieved = goal.isAchieved;
    final now = DateTime.now();
    final updated = goal.copyWith(
      currentAmount: amount,
      updatedAt: now,
    );
    final isNowAchieved = updated.isAchieved;

    _goals = List<SavingGoal>.from(_goals)..[index] = updated;
    if (!kIsWeb) {
      await _repository.mutateGoalWithHistory(
        goal: updated,
        history: GoalHistoryItem(
          id: _uuid.v4(),
          goalId: id,
          amount: amount - goal.currentAmount,
          actionType: 'progressUpdate',
          createdAt: now,
          note: 'Progress update',
          previousAmount: goal.currentAmount,
          resultingAmount: amount,
          source: 'manual',
        ),
      );
    }
    notifyListeners();

    if (_firestoreSync.isAuthenticated) {
      unawaited(_firestoreSync.upsertSavingGoal(updated).catchError((e) {
        AppLogger.debug(
          '[GoalProvider] Firestore sync updateProgress failed: $e',
        );
      }));
    }

    if (!wasAchieved && isNowAchieved) {
      await _checkAndSendAchievementNotification(updated);
    }
  }

  /// Financially coherent top-up adhering to product invariants.
  ///
  /// Prevents unbounded over-saving by default. If [amount] exceeds remaining headroom,
  /// returns [TopUpStatus.exceedsTarget] unless [allowOverfunding] is explicitly set.
  Future<TopUpResult> topUpGoal(
    String id,
    double amount, {
    bool allowOverfunding = false,
  }) async {
    if (amount <= 0) {
      return const TopUpResult(status: TopUpStatus.invalidAmount);
    }
    final index = _goals.indexWhere((g) => g.id == id);
    if (index == -1) {
      return const TopUpResult(status: TopUpStatus.goalNotFound);
    }

    final goal = _goals[index];
    if (goal.isPaused) {
      return TopUpResult(
        status: TopUpStatus.goalPaused,
        allowedAmount: 0.0,
        overage: amount,
        updatedGoal: goal,
      );
    }
    final remaining = goal.remainingAmount;

    if (goal.isAchieved && !allowOverfunding) {
      return TopUpResult(
        status: TopUpStatus.alreadyAchieved,
        allowedAmount: 0.0,
        overage: amount,
        updatedGoal: goal,
      );
    }

    if (amount > remaining && !allowOverfunding) {
      return TopUpResult(
        status: TopUpStatus.exceedsTarget,
        allowedAmount: remaining,
        overage: amount - remaining,
        updatedGoal: goal,
      );
    }

    final now = DateTime.now();
    final wasAchieved = goal.isAchieved;
    final updated = goal.copyWith(
      currentAmount: goal.currentAmount + amount,
      updatedAt: now,
    );
    final isNowAchieved = updated.isAchieved;

    _goals = List<SavingGoal>.from(_goals)..[index] = updated;
    if (!kIsWeb) {
      await _repository.mutateGoalWithHistory(
        goal: updated,
        history: GoalHistoryItem(
          id: _uuid.v4(),
          goalId: id,
          amount: amount,
          actionType: 'topUp',
          createdAt: now,
          note: 'Top up',
          previousAmount: goal.currentAmount,
          resultingAmount: updated.currentAmount,
          source: 'manual',
        ),
      );
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

    return TopUpResult(
      status: TopUpStatus.success,
      allowedAmount: amount,
      updatedGoal: updated,
    );
  }

  /// Withdraw funds from an active goal.
  ///
  /// Strictly enforces domain invariants: withdrawal amount must be > 0
  /// and cannot exceed current saved amount.
  Future<void> withdrawFromGoal(
    String id,
    double amount, {
    String? note,
  }) async {
    if (amount <= 0) {
      throw ArgumentError('Withdrawal amount must be greater than zero');
    }
    final index = _goals.indexWhere((g) => g.id == id);
    if (index == -1) {
      throw ArgumentError('Goal with ID $id not found');
    }

    final goal = _goals[index];
    if (amount > goal.currentAmount) {
      throw ArgumentError(
        'Withdrawal amount ($amount) exceeds current saved amount (${goal.currentAmount})',
      );
    }

    final now = DateTime.now();
    final newAmount = (goal.currentAmount - amount).clamp(0.0, double.infinity);
    final updated = goal.copyWith(
      currentAmount: newAmount,
      updatedAt: now,
    );

    _goals = List<SavingGoal>.from(_goals)..[index] = updated;
    if (!kIsWeb) {
      await _repository.mutateGoalWithHistory(
        goal: updated,
        history: GoalHistoryItem(
          id: _uuid.v4(),
          goalId: id,
          amount: -amount,
          actionType: 'withdrawal',
          createdAt: now,
          note: note ?? 'Withdrawal',
          previousAmount: goal.currentAmount,
          resultingAmount: newAmount,
          source: 'manual',
        ),
      );
    }
    notifyListeners();

    if (_firestoreSync.isAuthenticated) {
      unawaited(_firestoreSync.upsertSavingGoal(updated).catchError((e) {
        AppLogger.debug(
            '[GoalProvider] Firestore sync withdrawFromGoal failed: $e');
      }));
    }
  }

  /// Edit existing goal attributes (name, target amount, target date, emoji).
  ///
  /// Distinguishes between omitted parameters and explicit null values
  /// using [savingGoalSentinel].
  Future<void> editGoal({
    required String id,
    String? name,
    double? targetAmount,
    Object? targetDate = savingGoalSentinel,
    Object? emoji = savingGoalSentinel,
  }) async {
    final index = _goals.indexWhere((g) => g.id == id);
    if (index == -1) {
      throw ArgumentError('Goal with ID $id not found');
    }

    final goal = _goals[index];
    final wasAchieved = goal.isAchieved;
    final now = DateTime.now();

    final newName = name != null ? name.trim() : goal.name;
    if (newName.isEmpty) {
      throw ArgumentError('Goal name cannot be empty');
    }
    final newTarget = targetAmount ?? goal.targetAmount;
    if (newTarget <= 0) {
      throw ArgumentError('Target amount must be greater than zero');
    }
    if (newTarget < goal.currentAmount) {
      throw ArgumentError(
        'Target amount cannot be reduced below currently saved amount (${goal.currentAmount})',
      );
    }

    final updated = goal.copyWith(
      name: newName,
      targetAmount: newTarget,
      targetDate: targetDate,
      emoji: emoji,
      updatedAt: now,
    );
    final isNowAchieved = updated.isAchieved;

    _goals = List<SavingGoal>.from(_goals)..[index] = updated;
    if (!kIsWeb) {
      await _repository.mutateGoalWithHistory(
        goal: updated,
        history: GoalHistoryItem(
          id: _uuid.v4(),
          goalId: id,
          amount: 0,
          actionType: 'goalEdited',
          createdAt: now,
          note: 'Goal edited: $newName',
          previousAmount: goal.currentAmount,
          resultingAmount: goal.currentAmount,
          source: 'manual',
        ),
      );
    }
    notifyListeners();

    if (_firestoreSync.isAuthenticated) {
      unawaited(_firestoreSync.upsertSavingGoal(updated).catchError((e) {
        AppLogger.debug('[GoalProvider] Firestore sync editGoal failed: $e');
      }));
    }

    if (!wasAchieved && isNowAchieved) {
      await _checkAndSendAchievementNotification(updated);
    }
  }

  /// Single authoritative path for goal achievement notification.
  /// Delegated solely to [AlertEvaluationCoordinator] to prevent double notifications.
  Future<void> _checkAndSendAchievementNotification(SavingGoal goal) async {
    try {
      await AlertEvaluationCoordinator().onGoalsChanged([goal]);
    } catch (e) {
      AppLogger.debug(
          '[GoalProvider] Alert coordinator notification failed: $e');
    }
  }

  /// Toggle pause state on a goal.
  Future<void> togglePause(String id) async {
    final index = _goals.indexWhere((g) => g.id == id);
    if (index == -1) return;
    final goal = _goals[index];
    final now = DateTime.now();
    final updated = goal.copyWith(
      isPaused: !goal.isPaused,
      updatedAt: now,
    );
    _goals = List<SavingGoal>.from(_goals)..[index] = updated;
    if (!kIsWeb) {
      await _repository.upsert(updated);
      await _repository.addHistory(GoalHistoryItem(
        id: _uuid.v4(),
        goalId: id,
        amount: 0,
        actionType: updated.isPaused ? 'goalPaused' : 'goalResumed',
        createdAt: now,
        note: updated.isPaused ? 'Goal paused' : 'Goal resumed',
        previousAmount: goal.currentAmount,
        resultingAmount: goal.currentAmount,
        source: 'manual',
      ));
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

  /// Retrieve goal contribution audit history.
  Future<List<GoalHistoryItem>> getHistory(String goalId) async {
    if (kIsWeb) return [];
    return _repository.getHistory(goalId);
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
        AppLogger.error(
          'SavingGoal clear failed',
          error: e,
          label: 'GoalProvider',
        );
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
