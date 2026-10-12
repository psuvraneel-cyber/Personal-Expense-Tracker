// Golden tests for premium financial outputs (audit remediation R14).
//
// One fixed 90-day data set (the audit's seed) runs through the real
// forecast, bill, alert, tax and Money Wrap code. Expected numbers were
// computed independently (a separate Python re-implementation of the
// documented rules, kept with the audit), so a change in any engine's
// arithmetic shows up here. If a change is intended, recompute the expected
// value by hand and explain it in the commit.
import 'package:flutter_test/flutter_test.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/sms_transaction.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/premium/models/app_alert.dart';
import 'package:pet/premium/models/recurring_payment.dart';
import 'package:pet/premium/providers/tax_provider.dart';
import 'package:pet/premium/services/alert_evaluator.dart';
import 'package:pet/premium/services/anomaly_detection_service.dart';
import 'package:pet/premium/services/balance_anchor_service.dart';
import 'package:pet/premium/services/bill_payment_matcher.dart';
import 'package:pet/premium/services/cashflow_forecast_service.dart';
import 'package:pet/premium/services/premium_teasers.dart';
import 'package:pet/premium/services/recurring_detection_service.dart';
import 'package:pet/services/money_wrap.dart';

final now = DateTime(2026, 10, 12, 12);

/// The seed: 14 Jul – 11 Oct 2026.
/// - Food ₹300 every day (Local Store); Metro ₹100 on weekdays; Myntra ₹800
///   on Saturdays.
/// - Salary ₹60,000 on 1 Aug, 1 Sep, 1 Oct (08:00).
/// - Netflix ₹649 on the 7th (Aug–Oct); Spotify ₹119 on the 15th (Jul–Sep);
///   Cult Fit ₹999 on 20 Jul and 20 Aug (then cancelled); Tata Power ₹1,800
///   on 10 Aug and 10 Oct.
/// - LIC ₹50,000 on 1 Sep (80C); Star Health ₹18,000 on 25 Aug (80D).
/// - Croma ₹2,500 twice on 12 Sep (duplicate); Apple Store ₹25,000 on 2 Oct.
List<TransactionRecord> seed() {
  final out = <TransactionRecord>[];
  void add(String id, double amount, DateTime date, String category,
      {String? merchant,
      TransactionType type = TransactionType.expense,
      String? tax}) {
    out.add(TransactionRecord(
      id: id,
      amount: amount,
      type: type,
      categoryId: category,
      date: date,
      merchantName: merchant,
      taxCategory: tax,
      updatedAt: date,
    ));
  }

  var n = 0;
  for (var d = DateTime(2026, 7, 14, 12);
      !d.isAfter(DateTime(2026, 10, 11, 12));
      d = DateTime(d.year, d.month, d.day + 1, 12)) {
    add('food$n', 300, d, 'food', merchant: 'Local Store');
    if (d.weekday <= DateTime.friday) {
      add('metro$n', 100, d, 'transport', merchant: 'Metro');
    }
    if (d.weekday == DateTime.saturday) {
      add('shop$n', 800, d, 'shopping', merchant: 'Myntra');
    }
    n++;
  }
  for (final m in [8, 9, 10]) {
    add('salary$m', 60000, DateTime(2026, m, 1, 8), 'salary',
        type: TransactionType.income);
    add('netflix$m', 649, DateTime(2026, m, 7, 12), 'subscriptions',
        merchant: 'Netflix');
  }
  for (final m in [7, 8, 9]) {
    add('spotify$m', 119, DateTime(2026, m, 15, 12), 'subscriptions',
        merchant: 'Spotify');
  }
  for (final m in [7, 8]) {
    add('gym$m', 999, DateTime(2026, m, 20, 12), 'fitness',
        merchant: 'Cult Fit');
  }
  for (final m in [8, 10]) {
    add('power$m', 1800, DateTime(2026, m, 10, 12), 'utilities',
        merchant: 'Tata Power');
  }
  add('lic', 50000, DateTime(2026, 9, 1, 12), 'insurance',
      merchant: 'LIC', tax: '80C');
  add('health', 18000, DateTime(2026, 8, 25, 12), 'insurance',
      merchant: 'Star Health', tax: '80D');
  add('croma1', 2500, DateTime(2026, 9, 12, 12), 'electronics',
      merchant: 'Croma');
  add('croma2', 2500, DateTime(2026, 9, 12, 12), 'electronics',
      merchant: 'Croma');
  add('iphone', 25000, DateTime(2026, 10, 2, 12), 'shopping',
      merchant: 'Apple Store');
  return out;
}

RecurringPayment bill(String id, String merchant, double amount,
        DateTime lastPaid, DateTime nextDue) =>
    RecurringPayment(
      id: id,
      merchantName: merchant,
      amount: amount,
      frequency: 'monthly',
      lastPaidAt: lastPaid,
      nextDueAt: nextDue,
      categoryId: 'subscriptions',
      status: RecurringStatus.confirmed,
    );

void main() {
  final txns = seed();

  test('seed has the expected 185 transactions', () {
    expect(txns, hasLength(185));
  });

  group('Cash-flow forecast, 30 days', () {
    // Balance ₹1,00,000 entered on 1 Oct at 09:00 (after that day's salary).
    final anchor =
        BalanceAnchor(amount: 100000, asOf: DateTime(2026, 10, 1, 9));
    // Netflix still says due 7 Oct (paid that day); Spotify due 15 Oct.
    final bills = [
      bill('nf', 'Netflix', 649, DateTime(2026, 9, 7, 12),
          DateTime(2026, 10, 7, 12)),
      bill('sp', 'Spotify', 119, DateTime(2026, 9, 15, 12),
          DateTime(2026, 10, 15, 12)),
    ];
    late final f = (() {
      CashflowForecastService.clearCache();
      return CashflowForecastService.forecast(
        txns,
        confirmedBills: bills,
        referenceDate: now,
        openingBalanceOverride:
            BalanceAnchorService.openingBalance(anchor, txns, now),
      );
    })();

    test('starting balance', () {
      // 1,00,000 − spending after 1 Oct 09:00 (Food 11×300, Metro 7×100,
      // Myntra 2×800, Netflix 649, Tata Power 1,800, Apple 25,000).
      expect(f.startingBalance, 66951);
    });

    test('income and spending rates', () {
      // Last 60 days: 2 salaries = ₹1,20,000 → ₹2,000/day.
      expect(f.expectedIncome, closeTo(60000, 0.01));
      // Non-bill spending in the window ₹1,30,199 ÷ 60 × 30.
      expect(f.expectedVariableExpenses, closeTo(65099.5, 0.01));
      // Netflix 7 Nov (7 Oct was paid) + Spotify 15 Oct.
      expect(f.expectedBills, 768);
      expect(f.majorEvents.map((e) => e.title), ['Spotify', 'Netflix']);
    });

    test('ending, lowest point and safe-to-spend', () {
      expect(f.projectedEndingBalance, closeTo(61083.5, 0.01));
      expect(f.lowestProjectedBalance, closeTo(61083.5, 0.01));
      expect(f.lowestProjectedDate, DateTime(2026, 11, 10));
      // (61,083.50 − ₹5,000 buffer) ÷ 30 days.
      expect(f.safeToSpend, closeTo(1869.45, 0.01));
    });
  });

  group('Bills', () {
    final debits = [
      for (final t in txns.where((t) => t.type == TransactionType.expense))
        SmsTransaction(
          id: t.id,
          amount: t.amount,
          merchantName: t.merchantName ?? '',
          bankName: 'HDFC',
          transactionType: 'debit',
          timestamp: t.date,
          rawSmsBody: 'x',
          smsSender: 'HDFCBK',
          smsHash: t.id,
        ),
    ];
    final found = {
      for (final r in RecurringDetectionService.detect(debits))
        r.merchantName: r,
    };

    test('detection', () {
      // Metro (weekday gaps of 1 and 3 days) is too irregular; Tata Power
      // (61 days) fits no cycle; Croma (same day) has no gap.
      expect(found.keys.toSet(),
          {'Local Store', 'Myntra', 'Netflix', 'Spotify', 'Cult Fit'});
      expect(found['Netflix']!.frequency, 'monthly');
      expect(found['Netflix']!.confidence, 0.85); // 3 payments
      expect(found['Cult Fit']!.confidence, 0.65); // 2 payments
      expect(found['Myntra']!.frequency, 'weekly');
      expect(found['Local Store']!.frequency, 'daily');
      expect(found['Netflix']!.nextDueAt, DateTime(2026, 11, 7, 12));
    });

    test('upgrade hook counts confident, non-daily bills only', () {
      // Myntra ₹800 × 52 / 12 + Netflix ₹649 + Spotify ₹119 = ₹4,234.67.
      expect(PremiumTeasers.recurring(found.values.toList()),
          'We found 3 recurring payments costing about ₹4,235 a month.');
    });

    test('the 7 Oct Netflix payment pays the 7 Oct bill', () {
      final netflix = bill('nf', 'Netflix', 649, DateTime(2026, 9, 7, 12),
          DateTime(2026, 10, 7, 12));
      final payment = txns.firstWhere((t) => t.id == 'netflix10');
      expect(
          BillPaymentMatcher.matches(netflix,
              merchant: payment.merchantName,
              amount: payment.amount,
              date: payment.date),
          isTrue);
      expect(
          BillPaymentMatcher.matches(netflix,
              merchant: 'Spotify', amount: 119, date: DateTime(2026, 10, 7)),
          isFalse);
    });
  });

  group('Alerts on 12 Oct', () {
    test('baselines use only fully tracked months (Aug, Sep)', () {
      final base = AlertEvaluator.computeBaseline(txns, now: now);
      expect(base['food'], 9150);
      expect(base['shopping'], 3600);
      expect(base['transport'], 2150);
    });

    test('only shopping spikes (₹26,600 vs ₹3,600 usual)', () {
      final spikes = AnomalyDetectionService.detectSpikes(
          txns, AlertEvaluator.computeBaseline(txns, now: now),
          now: now);
      expect(spikes.map((s) => s.categoryId), ['shopping']);
      expect(spikes.single.ratio, closeTo(7.3889, 0.0001));
    });

    test('budgets: shopping critical, food fine, no pacing noise', () {
      const budgets = {'food': 9000.0, 'shopping': 3000.0};
      const spent = {'food': 3300.0, 'shopping': 26600.0};
      final alerts = AlertEvaluator.evaluateBudgetAlerts(
          budgets: budgets, spent: spent, now: now);
      expect(alerts.map((a) => (a.categoryId, a.stage)),
          [('shopping', AppAlertStage.critical)]);
      // Food: ₹275/day × 31 = ₹8,525, under 115% of ₹9,000.
      expect(
          AlertEvaluator.evaluateBudgetPacing(
            budgets: budgets,
            spent: spent,
            now: now,
            largestExpense:
                AlertEvaluator.largestExpenseThisMonth(txns, now: now),
          ),
          isEmpty);
    });
  });

  test('Tax buckets FY 2026-27, old regime, 30% slab', () {
    final totals = <String, double>{};
    for (final t in txns.where((t) => t.taxCategory != null)) {
      totals[t.taxCategory!] = (totals[t.taxCategory!] ?? 0) + t.amount;
    }
    final claimable = TaxProvider.claimable(totals, TaxProvider.defaultLimits);
    expect(claimable, 68000);
    expect(
        TaxProvider.estimatedSaving(
            claimable: claimable, regime: TaxRegime.oldRegime, slabRate: 0.30),
        closeTo(21216, 0.01));
  });

  test('Money Wrap for September', () {
    final wrap = MoneyWrap.compute(
      month: DateTime(2026, 9),
      transactions: txns,
      categoryName: (id) => id,
      recurring: const [],
    );
    expect(wrap.spent, 70168);
    expect(wrap.income, 60000);
    expect(wrap.transactionCount, 62);
    expect(wrap.topCategory, 'insurance');
    expect(wrap.spentChangePercent, closeTo(89.8125, 0.0001));
    expect(wrap.biggestDropCategory, 'utilities');
    expect(wrap.biggestDropPercent, 100);
  });
}
