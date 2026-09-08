import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pet/premium/models/spend_pause.dart';
import 'package:pet/premium/services/alert_evaluation_coordinator.dart';
import 'package:pet/premium/services/spend_pause_service.dart';

class SpendPauseProvider extends ChangeNotifier {
  SpendPause _pause = SpendPause(enabled: false);
  Timer? _timer;
  bool _disposed = false;
  int _sessionOverrideCount = 0;
  final Map<String, int> _categoryOverrides = {};

  SpendPause get pause => _pause;
  bool get isActive => _pause.isActive;
  DateTime? get until => _pause.until;
  Duration get remainingTime => _pause.remainingDuration;
  List<String> get blockedCategoryIds => _pause.blockedCategoryIds;
  int get sessionOverrideCount => _sessionOverrideCount;
  Map<String, int> get categoryOverrides => Map.unmodifiable(_categoryOverrides);

  bool isCategoryBlocked(String categoryId) =>
      _pause.isCategoryBlocked(categoryId);

  /// Records a "Spend Anyway" override during active Focus Mode.
  /// Dispatches an aggregated behavioral alert when repeated overrides occur
  /// (>= 3) rather than spamming individual notifications.
  Future<void> recordOverride({
    required String categoryId,
    required double amount,
    String? categoryName,
    DateTime? now,
  }) async {
    _sessionOverrideCount++;
    _categoryOverrides[categoryId] = (_categoryOverrides[categoryId] ?? 0) + 1;
    final catCount = _categoryOverrides[categoryId]!;

    if (catCount >= 3 || _sessionOverrideCount >= 3) {
      await AlertEvaluationCoordinator().onFocusModeRepeatedOverrides(
        overrideCount: catCount >= 3 ? catCount : _sessionOverrideCount,
        categoryId: categoryId,
        categoryName: categoryName,
        now: now,
      );
    }
    notifyListeners();
  }

  Future<void> load() async {
    _pause = await SpendPauseService.getState();
    _startTimerIfNeeded();
    notifyListeners();
  }

  Future<void> activate({
    required DateTime? until,
    required List<String> categoryIds,
  }) async {
    if (categoryIds.isEmpty) {
      throw ArgumentError('Cannot activate Focus Mode with zero blocked categories');
    }

    _pause = SpendPause(
      enabled: true,
      until: until,
      blockedCategoryIds: categoryIds,
    );

    await SpendPauseService.setState(_pause);
    _startTimerIfNeeded();

    try {
      await HapticFeedback.mediumImpact();
    } catch (_) {}

    notifyListeners();
  }

  Future<void> deactivate() async {
    _stopTimer();
    _sessionOverrideCount = 0;
    _categoryOverrides.clear();
    _pause = SpendPause(enabled: false);
    await SpendPauseService.setState(_pause);

    try {
      await HapticFeedback.lightImpact();
    } catch (_) {}

    notifyListeners();
  }

  /// Automatically prunes blocked category IDs that no longer exist in the system.
  void pruneDeletedCategories(Set<String> validCategoryIds) {
    if (_pause.blockedCategoryIds.isEmpty) return;

    final filtered = _pause.blockedCategoryIds
        .where((id) => validCategoryIds.contains(id))
        .toList();

    if (filtered.length != _pause.blockedCategoryIds.length) {
      _pause = SpendPause(
        enabled: filtered.isNotEmpty && _pause.enabled,
        until: _pause.until,
        blockedCategoryIds: filtered,
      );
      SpendPauseService.setState(_pause);
      if (!_pause.isActive) _stopTimer();
      notifyListeners();
    }
  }

  void _startTimerIfNeeded() {
    _stopTimer();
    if (_pause.isActive && _pause.until != null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_disposed) return;
        if (!_pause.isActive) {
          deactivate();
        } else {
          notifyListeners();
        }
      });
    }
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// Account logout wipe: cancels timers, clears in-memory state,
  /// and wipes persisted SharedPreferences keys completely.
  Future<void> clearData() async {
    _stopTimer();
    _sessionOverrideCount = 0;
    _categoryOverrides.clear();
    _pause = SpendPause(enabled: false);
    await SpendPauseService.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopTimer();
    super.dispose();
  }
}
