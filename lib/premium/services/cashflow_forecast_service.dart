import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/premium/models/cashflow_forecast.dart';

class CashflowForecastService {
  CashflowForecastService._();

  static CashflowForecast forecast(
    List<TransactionRecord> transactions, {
    int days = 30,
  }) {
    final now = DateTime.now();

    // Filter out future-dated transactions — they shouldn't influence
    // historical averages or the starting balance.
    final pastTransactions = transactions
        .where((t) => !t.date.isAfter(now))
        .toList();

    double balance = 0;
    for (final t in pastTransactions) {
      if (t.type == TransactionType.income) {
        balance += t.amount;
      } else if (t.type == TransactionType.expense) {
        balance -= t.amount;
      }
    }

    final avgDailyExpense =
        _avgDailyAmount(pastTransactions, TransactionType.expense);
    final avgDailyIncome =
        _avgDailyAmount(pastTransactions, TransactionType.income);
    final netDaily = avgDailyIncome - avgDailyExpense;

    // Check if we have enough data for a reliable forecast
    final hasInsufficientData = _transactionDaySpan(pastTransactions) < 7;

    if (balance < 0) {
      balance = 0;
    }

    final dailyPoints = <CashflowPoint>[];
    for (var i = 0; i < days; i++) {
      final date = DateTime(now.year, now.month, now.day + i);
      balance += netDaily;
      // Clamp future balance to 0 if we keep spending and drop below 0
      if (balance < 0) balance = 0;
      dailyPoints.add(CashflowPoint(date: date, balance: balance));
    }

    // safeToSpend: balance-aware formula — available balance divided by
    // remaining days in the month, rather than the old misleading
    // `avgDailyExpense * 0.9` which ignored actual balance.
    final daysRemainingInMonth = _daysRemainingInMonth(now);
    final currentBalance =
        dailyPoints.isNotEmpty ? dailyPoints.first.balance : balance;
    final safeToSpend = daysRemainingInMonth > 0
        ? currentBalance / daysRemainingInMonth
        : currentBalance;

    final starting = dailyPoints.isNotEmpty
        ? dailyPoints.first.balance - netDaily
        : balance;
    final ending =
        dailyPoints.isNotEmpty ? dailyPoints.last.balance : balance;

    return CashflowForecast(
      startingBalance: starting < 0 ? 0 : starting,
      projectedEndingBalance: ending < 0 ? 0 : ending,
      safeToSpend: safeToSpend < 0 ? 0 : safeToSpend,
      dailyPoints: dailyPoints,
      hasInsufficientData: hasInsufficientData,
    );
  }

  /// Returns the span in days across all transactions (any type).
  static int _transactionDaySpan(List<TransactionRecord> transactions) {
    if (transactions.length < 2) return transactions.length;
    final dates = transactions.map((t) => t.date).toList()..sort();
    return dates.last.difference(dates.first).inDays + 1;
  }

  /// Days remaining in the current month (including today).
  static int _daysRemainingInMonth(DateTime now) {
    final lastDay = DateTime(now.year, now.month + 1, 0).day;
    return (lastDay - now.day + 1).clamp(1, 31);
  }

  static double _avgDailyAmount(
    List<TransactionRecord> transactions,
    TransactionType type,
  ) {
    if (transactions.isEmpty) return 0;
    final filtered = transactions.where((t) => t.type == type).toList();
    if (filtered.isEmpty) return 0;

    final total = filtered.fold<double>(0, (sum, t) => sum + t.amount);

    final dates = filtered.map((t) => t.date).toList()..sort();
    final daySpan = dates.last.difference(dates.first).inDays + 1;

    return total / daySpan.clamp(1, 365);
  }
}
