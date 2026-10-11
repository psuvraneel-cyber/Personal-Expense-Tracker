import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pet/core/utils/app_logger.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/repositories/category_repository.dart';
import 'package:pet/data/repositories/transaction_repository.dart';
import 'package:pet/premium/models/notification_category.dart';
import 'package:pet/premium/repositories/recurring_payment_repository.dart';
import 'package:pet/premium/services/notification_service.dart';
import 'package:pet/services/money_wrap.dart';

/// Sends the Monday weekly recap and the monthly "Money Wrap" notification.
///
/// Content depends on data at the time, so instead of pre-scheduling, this
/// runs from the 30-minute background task (and at app start) and sends
/// each report once, at or after its time: Mondays from 9:00, and on the
/// 1st–3rd of the month from 10:00. Both use the "Weekly & Monthly
/// Reports" notification setting.
class ReportNotifier {
  ReportNotifier._();

  static const kLastWeekly = 'reportLastWeeklySent';
  static const kLastWrap = 'reportLastWrapSent';
  static const weeklyNotificationId = 910001;
  static const wrapNotificationId = 910002;

  static final _inr =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  static Future<void> maybeNotify({DateTime? now}) async {
    if (kIsWeb) return;
    final at = now ?? DateTime.now();
    try {
      await _maybeWeekly(at);
      await _maybeWrap(at);
    } catch (e) {
      AppLogger.debug('[Reports] failed: $e');
    }
  }

  /// Monday this week (midnight) when it's time for the weekly recap.
  @visibleForTesting
  static DateTime? weeklyDue(DateTime now) {
    if (now.weekday != DateTime.monday || now.hour < 9) return null;
    return DateTime(now.year, now.month, now.day);
  }

  /// First day of the month to wrap up, when it's time for the wrap.
  @visibleForTesting
  static DateTime? wrapDue(DateTime now) {
    if (now.day > 3 || (now.day == 1 && now.hour < 10)) return null;
    return DateTime(now.year, now.month - 1);
  }

  @visibleForTesting
  static String? weeklyMessage(double lastWeek, double weekBefore) {
    if (lastWeek <= 0 && weekBefore <= 0) return null;
    final spent = 'You spent ${_inr.format(lastWeek)} last week';
    if (weekBefore <= 0) return '$spent. Tap to see where it went.';
    final diff = lastWeek - weekBefore;
    if (diff.abs() < 1) return '$spent — the same as the week before.';
    return diff < 0
        ? '$spent — ${_inr.format(-diff)} less than the week before. Nice!'
        : '$spent — ${_inr.format(diff)} more than the week before.';
  }

  @visibleForTesting
  static String wrapMessage(MoneyWrap wrap) {
    final parts = <String>[
      if (wrap.topCategory != null) 'Top category: ${wrap.topCategory}.',
      if ((wrap.spentChangePercent ?? 0) <= -1)
        'You spent ${(-wrap.spentChangePercent!).round()}% less than the '
            'month before.',
      'Tap to see your month and share it.',
    ];
    return parts.join(' ');
  }

  static Future<void> _maybeWeekly(DateTime now) async {
    final monday = weeklyDue(now);
    if (monday == null) return;
    final key = DateFormat('yyyy-MM-dd').format(monday);
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(kLastWeekly) == key) return;

    final txns = await TransactionRepository().getTransactionsByDateRange(
      monday.subtract(const Duration(days: 14)),
      monday.subtract(const Duration(microseconds: 1)),
    );
    final weekStart = monday.subtract(const Duration(days: 7));
    var lastWeek = 0.0, weekBefore = 0.0;
    for (final t in txns.where((t) => t.type == TransactionType.expense)) {
      if (t.date.isBefore(weekStart)) {
        weekBefore += t.amount;
      } else {
        lastWeek += t.amount;
      }
    }
    final body = weeklyMessage(lastWeek, weekBefore);
    await prefs.setString(kLastWeekly, key);
    if (body == null) return;
    await NotificationService.showInstant(
      id: weeklyNotificationId,
      title: 'Your week in money',
      body: body,
      category: NotificationCategory.weeklyReport,
      payload: 'weekly',
    );
  }

  static Future<void> _maybeWrap(DateTime now) async {
    final month = wrapDue(now);
    if (month == null) return;
    final key = DateFormat('yyyy-MM').format(month);
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(kLastWrap) == key) return;

    final wrap = await loadWrap(month);
    await prefs.setString(kLastWrap, key);
    if (wrap.isEmpty) return;
    await NotificationService.showInstant(
      id: wrapNotificationId,
      title: 'Your ${DateFormat('MMMM').format(month)} Money Wrap is ready',
      body: wrapMessage(wrap),
      category: NotificationCategory.weeklyReport,
      payload: 'wrap:$key',
    );
  }

  /// Reads everything the wrap for [month] needs from the database.
  static Future<MoneyWrap> loadWrap(DateTime month) async {
    final txns = await TransactionRepository().getTransactionsByDateRange(
      DateTime(month.year, month.month - 1),
      DateTime(month.year, month.month + 1)
          .subtract(const Duration(microseconds: 1)),
    );
    final names = {
      for (final c in await CategoryRepository().getAllCategories())
        c.id: c.name,
    };
    final recurring = await RecurringPaymentRepository().getAll();
    return MoneyWrap.compute(
      month: month,
      transactions: txns,
      categoryName: (id) => names[id] ?? 'Other',
      recurring: recurring,
    );
  }
}
