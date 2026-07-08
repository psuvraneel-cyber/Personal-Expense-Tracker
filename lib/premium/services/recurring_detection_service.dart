import 'package:pet/data/models/sms_transaction.dart';
import 'package:pet/premium/models/recurring_payment.dart';
import 'package:uuid/uuid.dart';

class RecurringDetectionService {
  RecurringDetectionService._();

  static const Uuid _uuid = Uuid();

  static List<RecurringPayment> detect(List<SmsTransaction> transactions) {
    final byMerchant = <String, List<SmsTransaction>>{};
    for (final t in transactions) {
      if (t.transactionType != 'debit') continue;
      final key =
          '${t.merchantName.toLowerCase()}|${t.amount.toStringAsFixed(0)}';
      byMerchant.putIfAbsent(key, () => []).add(t);
    }

    final results = <RecurringPayment>[];
    for (final entry in byMerchant.entries) {
      final items = entry.value
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      if (items.length < 2) continue;

      final frequency = _inferFrequency(items);
      if (frequency == null) continue;

      final last = items.last;
      final nextDue = _predictNextDue(last.timestamp, frequency);

      results.add(
        RecurringPayment(
          id: _uuid.v4(),
          merchantName: last.merchantName,
          amount: last.amount,
          frequency: frequency,
          lastPaidAt: last.timestamp,
          nextDueAt: nextDue,
          categoryId: 'cat_uncategorized',
          confidence: 0.7,
          source: last.source,
        ),
      );
    }

    return results;
  }

  static String? _inferFrequency(List<SmsTransaction> items) {
    final diffs = <int>[];
    for (var i = 1; i < items.length; i++) {
      diffs.add(items[i].timestamp.difference(items[i - 1].timestamp).inDays);
    }
    final avgDays = diffs.isEmpty
        ? 0
        : diffs.reduce((a, b) => a + b) / diffs.length;

    if (avgDays >= 26 && avgDays <= 35) return 'monthly';
    if (avgDays >= 6 && avgDays <= 9) return 'weekly';
    if (avgDays >= 1 && avgDays <= 2) return 'daily';
    if (avgDays >= 350) return 'yearly';
    return null;
  }

  static DateTime _predictNextDue(DateTime last, String frequency) {
    switch (frequency) {
      case 'daily':
        return last.add(const Duration(days: 1));
      case 'weekly':
        return last.add(const Duration(days: 7));
      case 'monthly':
        final nextMonth = last.month + 1;
        final year = last.year + (nextMonth > 12 ? 1 : 0);
        final month = nextMonth > 12 ? 1 : nextMonth;
        var day = last.day;
        final maxDays = DateTime(year, month + 1, 0).day;
        if (day > maxDays) day = maxDays;
        return DateTime(year, month, day);
      case 'yearly':
        var day = last.day;
        final maxDays = DateTime(last.year + 1, last.month + 1, 0).day;
        if (day > maxDays) day = maxDays;
        return DateTime(last.year + 1, last.month, day);
      default:
        return last.add(const Duration(days: 30));
    }
  }
}
