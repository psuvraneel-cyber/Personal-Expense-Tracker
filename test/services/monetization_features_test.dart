import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pet/data/database/database_helper.dart';
import 'package:pet/data/models/budget.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/data/repositories/budget_repository.dart';
import 'package:pet/data/repositories/transaction_repository.dart';
import 'package:pet/premium/models/recurring_payment.dart';
import 'package:pet/premium/screens/purchase_screen.dart';
import 'package:pet/premium/services/ai_copilot_service.dart';
import 'package:pet/premium/services/premium_teasers.dart';
import 'package:pet/screens/reports/money_wrap_screen.dart';
import 'package:pet/services/home_widget_service.dart';
import 'package:pet/services/money_wrap.dart';
import 'package:pet/services/referral_service.dart';
import 'package:pet/services/report_notifier.dart';

TransactionRecord _txn(
  String id,
  double amount,
  DateTime date, {
  String category = 'food',
  TransactionType type = TransactionType.expense,
  TransactionSource source = TransactionSource.manual,
}) =>
    TransactionRecord(
      id: id,
      amount: amount,
      type: type,
      categoryId: category,
      date: date,
      source: source,
      sourceFingerprint: source == TransactionSource.manual ? null : id,
      updatedAt: date,
    );

RecurringPayment _bill(String id, double amount,
        {RecurringStatus status = RecurringStatus.detected,
        String frequency = 'monthly',
        double confidence = 0.95}) =>
    RecurringPayment(
      id: id,
      merchantName: id,
      amount: amount,
      frequency: frequency,
      lastPaidAt: DateTime(2026, 9, 1),
      nextDueAt: DateTime(2026, 10, 1),
      categoryId: 'subs',
      status: status,
      confidence: confidence,
    );

void main() {
  group('Premium teasers', () {
    test('recurring counts active payments and their monthly cost', () {
      final teaser = PremiumTeasers.recurring([
        _bill('Netflix', 649),
        _bill('Spotify', 119, status: RecurringStatus.confirmed),
        _bill('Old gym', 999, status: RecurringStatus.cancelled),
      ]);
      expect(
          teaser, 'We found 2 recurring payments costing about ₹768 a month.');
      expect(PremiumTeasers.recurring([]), isNull);
      expect(PremiumTeasers.recurring([_bill('Gym', 999)]),
          contains('1 recurring payment '));
    });

    test('only confirmed or confident detections count; never daily', () {
      final teaser = PremiumTeasers.recurring([
        _bill('Netflix', 649), // detected, confident
        _bill('Chai Point', 120, confidence: 0.65), // only two payments
        _bill('Metro', 40, frequency: 'daily'), // daily: coincidence-prone
        _bill('Rent', 15000,
            status: RecurringStatus.confirmed, confidence: 0.6),
      ]);
      expect(teaser,
          'We found 2 recurring payments costing about ₹15,649 a month.');
    });

    test('tax total covers the Indian financial year only', () {
      TransactionRecord tax(String id, DateTime d) =>
          _txn(id, 1000, d).copyWith(taxCategory: '80C');
      final total = PremiumTeasers.deductibleThisFinancialYear([
        tax('in', DateTime(2026, 4, 1)),
        tax('in2', DateTime(2027, 3, 31)),
        tax('before', DateTime(2026, 3, 31)),
        _txn('untagged', 5000, DateTime(2026, 6, 1)),
      ], DateTime(2026, 10, 11));
      expect(total, 2000);
    });

    test('teasers stay quiet when there is nothing to say', () {
      expect(PremiumTeasers.alerts(0), isNull);
      expect(PremiumTeasers.tax(0), isNull);
      expect(PremiumTeasers.cashflow(5), isNull);
      expect(PremiumTeasers.alerts(1), startsWith('1 alert '));
    });
  });

  group('Paywall helpers', () {
    test('free-trial labels', () {
      expect(freeTrialLabel(const Period(PeriodUnit.day, 7, 'P7D')),
          '7-day free trial');
      expect(freeTrialLabel(const Period(PeriodUnit.week, 1, 'P1W')),
          '7-day free trial');
      expect(freeTrialLabel(const Period(PeriodUnit.month, 1, 'P1M')),
          '1-month free trial');
      expect(freeTrialLabel(null), isNull);
    });

    test('lapsed subscribers see the win-back offering when it exists', () {
      expect(offeringIdToShow(lapsed: true, available: ['default', 'winback']),
          kWinBackOfferingId);
      expect(offeringIdToShow(lapsed: false, available: ['winback']), isNull);
      expect(offeringIdToShow(lapsed: true, available: ['default']), isNull);
    });

    test('yearly savings only when meaningful', () {
      expect(annualSavingsPercent(annual: 450, monthly: 50), 25);
      expect(annualSavingsPercent(annual: 590, monthly: 50), isNull);
      expect(annualSavingsPercent(annual: 0, monthly: 50), isNull);
    });
  });

  group('AI free allowance client', () {
    test('parses the quota the server reports', () {
      final free = AiQuota.fromJson({
        'plan': 'free',
        'limit': 3,
        'remaining': 1,
        'resetsAt': '2026-11-01T00:00:00.000Z',
      })!;
      expect([free.isPremium, free.limit, free.remaining, free.canAsk],
          [false, 3, 1, true]);
      expect(AiQuota.fromJson({'plan': 'premium'})!.canAsk, isTrue);
      expect(AiQuota.fromJson(null), isNull);
    });

    test('maps 403 allowance errors to AiAccessException', () {
      final e = AiCopilotService.parseAccessError(
          '{"errorCode":"FREE_QUOTA_EXHAUSTED","error":"used up",'
          '"quota":{"plan":"free","limit":3,"remaining":0}}')!;
      expect(e.quotaExhausted, isTrue);
      expect(e.quota!.canAsk, isFalse);
      expect(
          AiCopilotService.parseAccessError('{"errorCode":"SIGN_IN_REQUIRED"}')!
              .signInRequired,
          isTrue);
      expect(AiCopilotService.parseAccessError('{"error":"other"}'), isNull);
      expect(AiCopilotService.parseAccessError('not json'), isNull);
    });
  });

  group('Referral results', () {
    test('every server error has a friendly message', () {
      expect(ReferralService.resultFor(200, '{}').ok, isTrue);
      final generic = ReferralService.resultFor(502, 'oops');
      expect(generic.message, contains('try again'));
      for (final code in [
        'INVALID_CODE',
        'OWN_CODE',
        'ALREADY_REDEEMED',
        'NOT_NEW_USER',
        'SIGN_IN_REQUIRED',
      ]) {
        final r = ReferralService.resultFor(400, '{"errorCode":"$code"}');
        expect(r.ok, isFalse);
        expect(r.message, isNot(generic.message), reason: code);
      }
    });

    test('share text includes the code and store link', () {
      final text = ReferralService.shareText('ABCD2345', 'https://x');
      expect(text, contains('ABCD2345'));
      expect(text, contains('https://x'));
    });
  });

  group('Money Wrap', () {
    final sept = DateTime(2026, 9);
    String name(String id) => {'food': 'Food', 'shop': 'Shopping'}[id] ?? id;

    MoneyWrap wrap() => MoneyWrap.compute(
          month: sept,
          categoryName: name,
          recurring: [_bill('Netflix', 649)],
          transactions: [
            _txn('a', 3000, DateTime(2026, 9, 3)),
            _txn('b', 1000, DateTime(2026, 9, 4),
                category: 'shop', source: TransactionSource.sms),
            _txn('c', 50000, DateTime(2026, 9, 1),
                type: TransactionType.income),
            // August
            _txn('d', 3000, DateTime(2026, 8, 3)),
            _txn('e', 3000, DateTime(2026, 8, 9), category: 'shop'),
            // October (ignored)
            _txn('f', 9999, DateTime(2026, 10, 1)),
          ],
        );

    test('summarises the month against the month before', () {
      final w = wrap();
      expect([w.spent, w.income, w.transactionCount, w.autoImportedCount],
          [4000, 50000, 3, 1]);
      expect(w.topCategory, 'Food');
      expect(w.topCategoryShare, 0.75);
      expect(w.spentChangePercent!.round(), -33);
      expect(w.biggestDropCategory, 'Shopping');
      expect(w.biggestDropAmount, 2000);
      expect(w.biggestDropPercent.round(), 67);
      expect(w.subscriptionsFound, 1);
    });

    test('the shared card hides amounts unless asked', () {
      final hidden =
          MoneyWrapCard.linesFor(wrap(), false).map((l) => l.$2).join('\n');
      expect(hidden, isNot(contains('₹')));
      expect(hidden, contains('Top category: Food (75% of spending)'));
      expect(hidden, contains('Spent 33% less than August'));
      expect(hidden, contains('Biggest saving: Shopping, down 67%'));

      final shown =
          MoneyWrapCard.linesFor(wrap(), true).map((l) => l.$2).join('\n');
      expect(shown, contains('₹4,000 spent'));
    });

    test('notification text', () {
      expect(
          ReportNotifier.wrapMessage(wrap()),
          'Top category: Food. You spent 33% less than the month before. '
          'Tap to see your month and share it.');
    });
  });

  group('Report timing', () {
    test('weekly recap is due on Monday from 9am', () {
      expect(ReportNotifier.weeklyDue(DateTime(2026, 10, 12, 8)), isNull);
      expect(ReportNotifier.weeklyDue(DateTime(2026, 10, 12, 9)),
          DateTime(2026, 10, 12));
      expect(ReportNotifier.weeklyDue(DateTime(2026, 10, 13, 9)), isNull);
    });

    test('Money Wrap is due on the 1st (from 10am) to the 3rd', () {
      expect(ReportNotifier.wrapDue(DateTime(2026, 10, 1, 9)), isNull);
      expect(
          ReportNotifier.wrapDue(DateTime(2026, 10, 1, 10)), DateTime(2026, 9));
      expect(
          ReportNotifier.wrapDue(DateTime(2026, 10, 3, 23)), DateTime(2026, 9));
      expect(ReportNotifier.wrapDue(DateTime(2026, 10, 4)), isNull);
      expect(ReportNotifier.wrapDue(DateTime(2027, 1, 2)), DateTime(2026, 12));
    });

    test('weekly message compares with the week before', () {
      expect(ReportNotifier.weeklyMessage(0, 0), isNull);
      expect(ReportNotifier.weeklyMessage(1500, 2000),
          'You spent ₹1,500 last week — ₹500 less than the week before. Nice!');
      expect(ReportNotifier.weeklyMessage(2500, 2000), contains('₹500 more'));
      expect(ReportNotifier.weeklyMessage(800, 0),
          'You spent ₹800 last week. Tap to see where it went.');
    });
  });

  group('Home-screen widget values', () {
    late Database db;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = await openDatabase(
        inMemoryDatabasePath,
        version: kDatabaseVersion,
        onCreate: (db, v) => DatabaseHelper().onCreateForTesting(db, v),
      );
      DatabaseHelper.setTestDatabase(db);
    });

    tearDown(() async {
      await db.close();
      DatabaseHelper.setTestDatabase(null);
    });

    test('today\'s spend and budget left this month', () async {
      final repo = TransactionRepository();
      await repo.insertTransaction(_txn('t1', 200, DateTime(2026, 10, 11, 9)));
      await repo.insertTransaction(_txn('t2', 300, DateTime(2026, 10, 11, 20)));
      await repo.insertTransaction(_txn('y', 1000, DateTime(2026, 10, 10, 9)));
      await repo.insertTransaction(_txn('inc', 900, DateTime(2026, 10, 11),
          type: TransactionType.income));
      await BudgetRepository(database: db).insertOrUpdateBudget(Budget(
          id: 'b', categoryId: 'food', amount: 5000, month: 10, year: 2026));

      final v = await HomeWidgetService.computeValues(
          now: DateTime(2026, 10, 11, 21));
      expect(v.date, '2026-10-11');
      expect(v.spentToday, 500);
      expect(v.monthBudgetLeft, 3500);
      expect(v.locked, isFalse);
    });

    test('no budget → no budget figure; biometric lock → locked', () async {
      SharedPreferences.setMockInitialValues({'biometricEnabled': true});
      final v =
          await HomeWidgetService.computeValues(now: DateTime(2026, 10, 11));
      expect(v.monthBudgetLeft, isNull);
      expect(v.locked, isTrue);
    });
  });
}
