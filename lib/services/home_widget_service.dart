import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pet/core/utils/app_logger.dart';
import 'package:pet/data/database/database_helper.dart';
import 'package:pet/data/repositories/budget_repository.dart';
import 'package:pet/data/repositories/transaction_repository.dart';

/// Numbers shown by the Android home-screen widget (SpendWidgetProvider.kt).
class SpendWidgetValues {
  const SpendWidgetValues({
    required this.date,
    required this.spentToday,
    required this.monthBudgetLeft,
    required this.locked,
  });

  /// Day the numbers were computed for (yyyy-MM-dd); the widget uses it to
  /// reset "today" after midnight on its own.
  final String date;
  final double spentToday;

  /// This month's total budget minus spending in budgeted categories, or
  /// null when no budgets are set.
  final double? monthBudgetLeft;

  /// Biometric lock is on: the widget hides amounts.
  final bool locked;
}

/// Keeps the home-screen widget up to date. Safe to call from background
/// isolates (WorkManager) as well as the UI.
class HomeWidgetService {
  HomeWidgetService._();

  static const androidName = 'SpendWidgetProvider';

  // Keys shared with SpendWidgetProvider.kt.
  static const kDate = 'widget_date';
  static const kSpentToday = 'widget_spent_today';
  static const kMonthBudgetLeft = 'widget_month_budget_left';
  static const kLocked = 'widget_locked';

  static bool get _supported => !kIsWeb && Platform.isAndroid;

  static Future<void> refresh() async {
    if (!_supported) return;
    try {
      final v = await computeValues();
      await HomeWidget.saveWidgetData<String>(kDate, v.date);
      await HomeWidget.saveWidgetData<String>(kLocked, '${v.locked}');
      // Amounts are not stored at all while the app is locked.
      await HomeWidget.saveWidgetData<String>(
          kSpentToday, v.locked ? null : v.spentToday.toStringAsFixed(2));
      await HomeWidget.saveWidgetData<String>(kMonthBudgetLeft,
          v.locked ? null : v.monthBudgetLeft?.toStringAsFixed(2));
      await HomeWidget.updateWidget(androidName: androidName);
    } catch (e) {
      AppLogger.debug('[HomeWidget] refresh failed: $e');
    }
  }

  /// Asks the launcher to add the widget. Returns false when the launcher
  /// can't (the user must add it from the widget picker instead).
  static Future<bool> requestPin() async {
    if (!_supported) return false;
    try {
      if (await HomeWidget.isRequestPinWidgetSupported() != true) return false;
      await refresh();
      await HomeWidget.requestPinWidget(androidName: androidName);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Removes all widget data (sign-out / account deletion).
  static Future<void> clear() async {
    if (!_supported) return;
    try {
      for (final key in [kDate, kSpentToday, kMonthBudgetLeft, kLocked]) {
        await HomeWidget.saveWidgetData<String>(key, null);
      }
      await HomeWidget.updateWidget(androidName: androidName);
    } catch (e) {
      AppLogger.debug('[HomeWidget] clear failed: $e');
    }
  }

  @visibleForTesting
  static Future<SpendWidgetValues> computeValues({
    DateTime? now,
    DatabaseHelper? dbHelper,
  }) async {
    final today = now ?? DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    final end = start.add(const Duration(days: 1));
    final db = await (dbHelper ?? DatabaseHelper()).database;

    final rows = await db.rawQuery(
      'SELECT SUM(amount) AS total FROM transactions '
      "WHERE type = 'expense' AND date >= ? AND date < ?",
      [start.toIso8601String(), end.toIso8601String()],
    );
    final spentToday = (rows.first['total'] as num?)?.toDouble() ?? 0.0;

    final budgets = await BudgetRepository(database: db)
        .getBudgetsByMonth(today.month, today.year);
    double? left;
    if (budgets.isNotEmpty) {
      final txns = TransactionRepository();
      var total = 0.0;
      var spent = 0.0;
      for (final b in budgets) {
        total += b.amount;
        spent += await txns.getSpentInCategory(
            b.categoryId, today.month, today.year);
      }
      left = total - spent;
    }

    final prefs = await SharedPreferences.getInstance();
    return SpendWidgetValues(
      date: DateFormat('yyyy-MM-dd').format(today),
      spentToday: spentToday,
      monthBudgetLeft: left,
      locked: prefs.getBool('biometricEnabled') ?? false,
    );
  }
}
