import 'package:pet/data/models/enums.dart';
import 'package:pet/premium/services/premium_teasers.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/premium/models/recurring_payment.dart';

/// A month in review: the "Money Wrap" shown on the 1st of each month and
/// shareable as a card.
class MoneyWrap {
  const MoneyWrap({
    required this.month,
    required this.spent,
    required this.income,
    required this.transactionCount,
    required this.autoImportedCount,
    required this.topCategory,
    required this.topCategoryAmount,
    required this.previousMonthSpent,
    required this.biggestDropCategory,
    required this.biggestDropAmount,
    required this.biggestDropBefore,
    required this.subscriptionsFound,
    required this.subscriptionsMonthly,
  });

  /// First day of the month this wrap covers.
  final DateTime month;
  final double spent;
  final double income;
  final int transactionCount;

  /// Transactions P.E.T recorded automatically from SMS/notifications.
  final int autoImportedCount;

  final String? topCategory;
  final double topCategoryAmount;

  /// Spending in the month before, for the month-on-month comparison
  /// (0 when there was no spending to compare with).
  final double previousMonthSpent;

  /// Category with the largest drop in spending vs. the month before.
  final String? biggestDropCategory;
  final double biggestDropAmount;

  /// That category's spending in the month before.
  final double biggestDropBefore;

  final int subscriptionsFound;
  final double subscriptionsMonthly;

  bool get isEmpty => transactionCount == 0;

  double get topCategoryShare => spent > 0 ? topCategoryAmount / spent : 0;

  /// Percent change in spending vs. the month before (negative = spent
  /// less), or null when there's nothing to compare with.
  double? get spentChangePercent => previousMonthSpent > 0
      ? (spent - previousMonthSpent) / previousMonthSpent * 100
      : null;

  double get biggestDropPercent =>
      biggestDropBefore > 0 ? biggestDropAmount / biggestDropBefore * 100 : 0;

  /// Builds the wrap for [month] from transactions covering that month and
  /// the one before. [categoryName] maps category ids to display names.
  static MoneyWrap compute({
    required DateTime month,
    required List<TransactionRecord> transactions,
    required String Function(String categoryId) categoryName,
    required List<RecurringPayment> recurring,
  }) {
    final start = DateTime(month.year, month.month);
    final end = DateTime(month.year, month.month + 1);
    final prevStart = DateTime(month.year, month.month - 1);

    bool inRange(DateTime d, DateTime a, DateTime b) =>
        !d.isBefore(a) && d.isBefore(b);

    var spent = 0.0, income = 0.0, prevSpent = 0.0;
    var count = 0, auto = 0;
    final byCategory = <String, double>{};
    final prevByCategory = <String, double>{};

    for (final t in transactions) {
      if (inRange(t.date, start, end)) {
        count++;
        if (t.source != TransactionSource.manual) auto++;
        if (t.type == TransactionType.expense) {
          spent += t.amount;
          final name = categoryName(t.categoryId);
          byCategory[name] = (byCategory[name] ?? 0) + t.amount;
        } else if (t.type == TransactionType.income) {
          income += t.amount;
        }
      } else if (inRange(t.date, prevStart, start) &&
          t.type == TransactionType.expense) {
        prevSpent += t.amount;
        final name = categoryName(t.categoryId);
        prevByCategory[name] = (prevByCategory[name] ?? 0) + t.amount;
      }
    }

    String? top;
    var topAmount = 0.0;
    byCategory.forEach((name, amount) {
      if (amount > topAmount) {
        top = name;
        topAmount = amount;
      }
    });

    String? drop;
    var dropAmount = 0.0;
    prevByCategory.forEach((name, before) {
      final saved = before - (byCategory[name] ?? 0);
      if (saved > dropAmount) {
        drop = name;
        dropAmount = saved;
      }
    });

    final active = PremiumTeasers.activeRecurring(recurring);

    return MoneyWrap(
      month: start,
      spent: spent,
      income: income,
      transactionCount: count,
      autoImportedCount: auto,
      topCategory: top,
      topCategoryAmount: topAmount,
      previousMonthSpent: prevSpent,
      biggestDropCategory: drop,
      biggestDropAmount: dropAmount,
      biggestDropBefore: drop == null ? 0 : prevByCategory[drop]!,
      subscriptionsFound: active.length,
      subscriptionsMonthly:
          active.fold(0.0, (sum, r) => sum + r.monthlyEquivalentAmount),
    );
  }
}
