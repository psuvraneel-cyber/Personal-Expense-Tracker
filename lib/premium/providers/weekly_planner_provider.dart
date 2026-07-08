import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/transaction.dart';

/// A single day's aggregated spend for the weekly planner strip.
class DaySpend {
  final DateTime date;
  final double spent;

  const DaySpend({required this.date, required this.spent});

  String get shortLabel {
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return labels[date.weekday - 1];
  }
}

/// Weekly planner entry for one category.
class WeeklyPlannerEntry {
  final String categoryId;
  final String categoryName;
  final double weeklyLimit;
  double weeklySpent;

  WeeklyPlannerEntry({
    required this.categoryId,
    required this.categoryName,
    required this.weeklyLimit,
    this.weeklySpent = 0,
  });

  double get progress =>
      weeklyLimit > 0 ? (weeklySpent / weeklyLimit).clamp(0.0, 1.0) : 0.0;
  bool get isOverBudget => weeklySpent > weeklyLimit;
  double get remaining => (weeklyLimit - weeklySpent).clamp(0, double.infinity);

  Map<String, dynamic> toJson() => {
    'categoryId': categoryId,
    'categoryName': categoryName,
    'weeklyLimit': weeklyLimit,
  };

  factory WeeklyPlannerEntry.fromJson(Map<String, dynamic> j) =>
      WeeklyPlannerEntry(
        categoryId: j['categoryId'] as String,
        categoryName: j['categoryName'] as String,
        weeklyLimit: (j['weeklyLimit'] as num).toDouble(),
      );
}

class WeeklyPlannerProvider extends ChangeNotifier {
  static const _prefsKey = 'weekly_planner_entries';

  List<WeeklyPlannerEntry> _entries = [];
  List<DaySpend> _weekDays = [];
  double _totalWeekSpent = 0;
  double _totalWeekLimit = 0;
  List<TransactionRecord>? _lastTransactionsForPlanner;

  List<WeeklyPlannerEntry> get entries => _entries;
  List<DaySpend> get weekDays => _weekDays;
  double get totalWeekSpent => _totalWeekSpent;
  double get totalWeekLimit => _totalWeekLimit;
  bool get hasLimits => _entries.isNotEmpty;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      final list = jsonDecode(raw) as List<dynamic>;
      _entries = list
          .map((e) => WeeklyPlannerEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    notifyListeners();
  }

  Future<void> setLimit({
    required String categoryId,
    required String categoryName,
    required double weeklyLimit,
  }) async {
    final idx = _entries.indexWhere((e) => e.categoryId == categoryId);
    if (idx >= 0) {
      _entries[idx] = WeeklyPlannerEntry(
        categoryId: categoryId,
        categoryName: categoryName,
        weeklyLimit: weeklyLimit,
        weeklySpent: _entries[idx].weeklySpent,
      );
    } else {
      _entries.add(
        WeeklyPlannerEntry(
          categoryId: categoryId,
          categoryName: categoryName,
          weeklyLimit: weeklyLimit,
        ),
      );
    }
    await _persist();
    notifyListeners();
  }

  Future<void> removeLimit(String categoryId) async {
    _entries.removeWhere((e) => e.categoryId == categoryId);
    await _persist();
    notifyListeners();
  }

  void refreshFromTransactions(List<TransactionRecord> transactions) {
    if (identical(_lastTransactionsForPlanner, transactions)) return;
    _lastTransactionsForPlanner = transactions;
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final mondayMidnight = DateTime(
      weekStart.year,
      weekStart.month,
      weekStart.day,
    );

    _weekDays = List.generate(7, (i) {
      final day = mondayMidnight.add(Duration(days: i));
      final daySpent = transactions
          .where((t) {
            if (t.type != TransactionType.expense) return false;
            return t.date.year == day.year &&
                t.date.month == day.month &&
                t.date.day == day.day;
          })
          .fold(0.0, (s, t) => s + t.amount);
      return DaySpend(date: day, spent: daySpent);
    });

    final weekTxns = transactions
        .where(
          (t) =>
              t.type == TransactionType.expense &&
              t.date.isAfter(
                mondayMidnight.subtract(const Duration(seconds: 1)),
              ),
        )
        .toList();

    for (final entry in _entries) {
      entry.weeklySpent = weekTxns
          .where(
            (t) => t.categoryId.toLowerCase() == entry.categoryId.toLowerCase(),
          )
          .fold(0.0, (s, t) => s + t.amount);
    }

    _totalWeekSpent = _weekDays.fold(0.0, (s, d) => s + d.spent);
    _totalWeekLimit = _entries.fold(0.0, (s, e) => s + e.weeklyLimit);

    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(_entries.map((e) => e.toJson()).toList()),
    );
  }
}
