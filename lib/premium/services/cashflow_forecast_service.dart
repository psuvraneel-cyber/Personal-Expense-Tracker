import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/premium/models/cashflow_forecast.dart';
import 'package:pet/premium/models/recurring_payment.dart';
import 'package:pet/services/recurrence_calculator.dart';

class CashflowForecastService {
  CashflowForecastService._();

  static CashflowForecast forecast(
    List<TransactionRecord> transactions, {
    List<RecurringPayment>? confirmedBills,
    int days = 30,
    DateTime? referenceDate,
  }) {
    final now = referenceDate ?? DateTime.now();

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

    final hasNegativeStartingBalance = balance < 0;

    // Check if we have enough data for a reliable forecast
    final hasInsufficientData = _transactionDaySpan(pastTransactions) < 7;

    final activeBills = (confirmedBills ?? [])
        .where((b) => b.status == RecurringStatus.confirmed)
        .toList();

    // Prevent double-counting: isolate variable daily expense by subtracting
    // the daily equivalent of known recurring commitments from historical expense average.
    final recurringMonthlyBurn = activeBills.fold(
      0.0,
      (sum, b) => sum + b.monthlyEquivalentAmount,
    );
    final recurringDailyBurn = recurringMonthlyBurn / 30.0;
    final variableDailyExpense =
        (avgDailyExpense - recurringDailyBurn).clamp(0.0, double.infinity);

    // Pre-calculate all occurrences of active bills across the forecast window (days)
    final billDeductionsByDate = <String, double>{};
    final todayFloor = DateTime(now.year, now.month, now.day);
    final windowEnd = DateTime(now.year, now.month, now.day + days);

    for (final bill in activeBills) {
      var occ = bill.nextDueAt;
      var safety = 0;
      while (!occ.isAfter(windowEnd) && safety < 100) {
        safety++;
        if (!occ.isBefore(todayFloor)) {
          final key = '${occ.year}-${occ.month}-${occ.day}';
          billDeductionsByDate[key] = (billDeductionsByDate[key] ?? 0.0) + bill.amount;
        }
        occ = RecurrenceCalculator.computeNextOccurrence(
          anchorDate: bill.nextDueAt,
          currentOccurrence: occ,
          frequency: bill.frequencyEnum,
        );
      }
    }

    final starting = balance;
    final dailyPoints = <CashflowPoint>[];
    double rollingBalance = balance;

    for (var i = 0; i < days; i++) {
      final date = DateTime(now.year, now.month, now.day + i);
      final dateKey = '${date.year}-${date.month}-${date.day}';

      if (activeBills.isNotEmpty) {
        final billsDueToday = billDeductionsByDate[dateKey] ?? 0.0;
        rollingBalance += (avgDailyIncome - variableDailyExpense) - billsDueToday;
      } else {
        final netDaily = avgDailyIncome - avgDailyExpense;
        rollingBalance += netDaily;
      }

      dailyPoints.add(CashflowPoint(date: date, balance: rollingBalance));
    }

    // safeToSpend: balance-aware formula — available balance minus committed bills
    // in current month, divided by remaining days. Clamped to 0 on deficit.
    final daysRemainingInMonth = _daysRemainingInMonth(now);
    final monthEnd = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
    double billsDueRemainingThisMonth = 0.0;

    for (final bill in activeBills) {
      var occ = bill.nextDueAt;
      var safety = 0;
      while (!occ.isAfter(monthEnd) && safety < 50) {
        safety++;
        if (!occ.isBefore(todayFloor)) {
          billsDueRemainingThisMonth += bill.amount;
        }
        occ = RecurrenceCalculator.computeNextOccurrence(
          anchorDate: bill.nextDueAt,
          currentOccurrence: occ,
          frequency: bill.frequencyEnum,
        );
      }
    }

    final effectiveAvailable = (balance - billsDueRemainingThisMonth).clamp(0.0, double.infinity);
    final safeToSpend = (effectiveAvailable > 0 && daysRemainingInMonth > 0)
        ? effectiveAvailable / daysRemainingInMonth
        : 0.0;

    final ending =
        dailyPoints.isNotEmpty ? dailyPoints.last.balance : balance;

    return CashflowForecast(
      startingBalance: starting,
      projectedEndingBalance: ending,
      safeToSpend: safeToSpend,
      dailyPoints: dailyPoints,
      hasInsufficientData: hasInsufficientData,
      hasNegativeStartingBalance: hasNegativeStartingBalance,
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
