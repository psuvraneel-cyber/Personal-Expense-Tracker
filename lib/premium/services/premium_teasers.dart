import 'package:intl/intl.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/premium/models/recurring_payment.dart';

/// Personalised one-liners shown to free users on locked screens ("lock the
/// details, not the discovery"). Each returns null when there is nothing
/// worth saying, so the gate falls back to its generic subtitle.
class PremiumTeasers {
  PremiumTeasers._();

  static final _inr =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  static String _plural(int n, String one, String many) =>
      '$n ${n == 1 ? one : many}';

  /// Bills and subscriptions found from SMS, whether or not confirmed yet.
  static List<RecurringPayment> activeRecurring(List<RecurringPayment> all) =>
      all.where((r) => r.status != RecurringStatus.cancelled).toList();

  static String? recurring(List<RecurringPayment> all) {
    final active = activeRecurring(all);
    if (active.isEmpty) return null;
    final monthly =
        active.fold(0.0, (sum, r) => sum + r.monthlyEquivalentAmount);
    return 'We found ${_plural(active.length, 'recurring payment', 'recurring payments')} '
        'costing about ${_inr.format(monthly)} a month.';
  }

  static String? alerts(int activeCount) => activeCount <= 0
      ? null
      : '${_plural(activeCount, 'alert', 'alerts')} about your spending '
          '${activeCount == 1 ? 'is' : 'are'} waiting for you.';

  static String? tax(double deductibleThisYear) => deductibleThisYear <= 0
      ? null
      : '${_inr.format(deductibleThisYear)} of your spending this financial '
          'year may count towards tax deductions.';

  /// Tax-tagged expenses in the Indian financial year (April–March)
  /// containing [now].
  static double deductibleThisFinancialYear(
      List<TransactionRecord> transactions, DateTime now) {
    final startYear = now.month < 4 ? now.year - 1 : now.year;
    final start = DateTime(startYear, 4, 1);
    final end = DateTime(startYear + 1, 4, 1);
    return transactions
        .where((t) =>
            t.taxCategory != null &&
            t.type == TransactionType.expense &&
            !t.date.isBefore(start) &&
            t.date.isBefore(end))
        .fold(0.0, (sum, t) => sum + t.amount);
  }

  static String? cashflow(int transactionCount) => transactionCount < 10
      ? null
      : 'Your 30-day forecast is ready, based on '
          '${_plural(transactionCount, 'transaction', 'transactions')}.';
}
