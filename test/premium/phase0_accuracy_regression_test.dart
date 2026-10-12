// Regression tests for the premium QA audit's Phase 0 findings (P1–P5).
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pet/data/database/database_helper.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/sms_transaction.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/premium/models/cashflow_forecast.dart';
import 'package:pet/premium/models/recurring_payment.dart';
import 'package:pet/premium/models/spend_pause.dart';
import 'package:pet/premium/repositories/recurring_payment_repository.dart';
import 'package:pet/premium/services/balance_anchor_service.dart';
import 'package:pet/premium/services/bill_payment_matcher.dart';
import 'package:pet/premium/services/cashflow_forecast_service.dart';
import 'package:pet/premium/services/focus_mode_notifier.dart';
import 'package:pet/premium/services/recurring_detection_service.dart';

final now = DateTime(2026, 10, 12, 12);

TransactionRecord txn(String id, double amount, DateTime date,
        {TransactionType type = TransactionType.expense,
        String category = 'food',
        String? merchant,
        TransactionSource source = TransactionSource.manual}) =>
    TransactionRecord(
      id: id,
      amount: amount,
      type: type,
      categoryId: category,
      date: date,
      merchantName: merchant,
      source: source,
      sourceFingerprint: source == TransactionSource.manual ? null : id,
      updatedAt: date,
    );

RecurringPayment netflix({
  DateTime? nextDueAt,
  DateTime? lastPaidAt,
  RecurringStatus status = RecurringStatus.confirmed,
}) =>
    RecurringPayment(
      id: 'netflix',
      merchantName: 'Netflix',
      amount: 649,
      frequency: 'monthly',
      lastPaidAt: lastPaidAt ?? DateTime(2026, 9, 7),
      nextDueAt: nextDueAt ?? DateTime(2026, 10, 7),
      categoryId: 'subs',
      status: status,
    );

SmsTransaction sms(String id, double amount, DateTime d, String merchant) =>
    SmsTransaction(
      id: id,
      amount: amount,
      merchantName: merchant,
      bankName: 'HDFC',
      transactionType: 'debit',
      timestamp: d,
      rawSmsBody: 'x',
      smsSender: 'HDFCBK',
      smsHash: id,
    );

void main() {
  setUp(CashflowForecastService.clearCache);

  group('P1: forecasts start from an entered balance', () {
    test('opening balance = entered amount + tracked activity since', () {
      final anchor =
          BalanceAnchor(amount: 50000, asOf: DateTime(2026, 10, 1, 10));
      final balance = BalanceAnchorService.openingBalance(
          anchor,
          [
            txn('before', 9999,
                DateTime(2026, 9, 30)), // already in the balance
            txn('sameDayEarlier', 500, DateTime(2026, 10, 1, 9)),
            txn('food', 1200, DateTime(2026, 10, 5)),
            txn('refund', 300, DateTime(2026, 10, 6),
                type: TransactionType.income),
            txn('future', 7000, DateTime(2026, 10, 20)), // not happened yet
          ],
          now);
      expect(balance, 50000 - 1200 + 300);
    });

    test('an expenses-only user no longer gets a phantom deficit', () {
      final txns = [
        for (var i = 1; i <= 40; i++)
          txn('e$i', 300, now.subtract(Duration(days: i))),
      ];
      final f = CashflowForecastService.forecast(
        txns,
        referenceDate: now,
        openingBalanceOverride: BalanceAnchorService.openingBalance(
          BalanceAnchor(amount: 80000, asOf: DateTime(2026, 8, 1)),
          txns,
          now,
        ),
      );
      expect(f.startingBalance, 80000 - 12000);
      expect(f.riskLevel, isNot(CashflowRiskLevel.deficitExpected));
      expect(f.safeToSpend, greaterThan(0));
    });
  });

  group('P2: paid bills are not deducted again', () {
    test('forecast skips an "overdue" bill that a payment already covers', () {
      final txns = [
        txn('salary', 60000, DateTime(2026, 10, 1),
            type: TransactionType.income),
        txn('nf', 649, DateTime(2026, 10, 7), merchant: 'NETFLIX.COM'),
        for (var i = 1; i <= 40; i++)
          txn('e$i', 500, now.subtract(Duration(days: i))),
      ];
      final f = CashflowForecastService.forecast(txns,
          confirmedBills: [netflix()], referenceDate: now);
      expect(f.expectedBills, 649);
      expect(f.majorEvents.map((e) => e.title),
          isNot(contains('Netflix (Overdue)')));
      expect(f.majorEvents.single.date, DateTime(2026, 11, 7));
    });

    test('a genuinely unpaid overdue bill is still deducted today', () {
      final f = CashflowForecastService.forecast(
        [
          for (var i = 1; i <= 40; i++)
            txn('e$i', 500, now.subtract(Duration(days: i)))
        ],
        confirmedBills: [netflix()],
        referenceDate: now,
      );
      expect(f.majorEvents.first.title, 'Netflix (Overdue)');
      expect(f.expectedBills, 1298);
    });

    test('payment matching rules', () {
      final bill = netflix();
      bool m(String? merchant, double amount, DateTime date) =>
          BillPaymentMatcher.matches(bill,
              merchant: merchant, amount: amount, date: date);

      expect(m('NETFLIX INDIA PVT LTD', 649, DateTime(2026, 10, 7)), isTrue);
      expect(m('Netflix Subscription', 690, DateTime(2026, 10, 3)), isTrue,
          reason: 'within 10% and 5 days early');
      expect(m('Netflix', 649, DateTime(2026, 10, 17)), isTrue,
          reason: '10 days late');
      expect(m('Netflix', 649, DateTime(2026, 10, 18)), isFalse,
          reason: 'too late for this cycle');
      expect(m('Netflix', 800, DateTime(2026, 10, 7)), isFalse,
          reason: 'amount differs by more than 10%');
      expect(m('Swiggy', 649, DateTime(2026, 10, 7)), isFalse);
      expect(m(null, 649, DateTime(2026, 10, 7)), isFalse);
      expect(
          BillPaymentMatcher.matches(netflix(status: RecurringStatus.detected),
              merchant: 'Netflix', amount: 649, date: DateTime(2026, 10, 7)),
          isFalse,
          reason: 'only confirmed bills are auto-paid');
      expect(
          BillPaymentMatcher.matches(netflix(lastPaidAt: DateTime(2026, 10, 8)),
              merchant: 'Netflix', amount: 649, date: DateTime(2026, 10, 7)),
          isFalse,
          reason: 'a payment already recorded cannot pay the next cycle');
    });
  });

  group('database', () {
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

    test('P2: an imported autopay payment marks the bill paid and advances it',
        () async {
      final repo = RecurringPaymentRepository();
      await repo.upsert(netflix());

      final updated = await BillPaymentMatcher.recordIfBillPayment(
        txn('nf', 649, DateTime(2026, 10, 7, 6),
            merchant: 'NETFLIX.COM', source: TransactionSource.sms),
        repository: repo,
        sideEffects: false,
      );

      expect(updated?.nextDueAt, DateTime(2026, 11, 7));
      final saved = (await repo.getAll()).single;
      expect(saved.nextDueAt, DateTime(2026, 11, 7));
      expect(saved.lastPaidAt, DateTime(2026, 10, 7, 6));
      final history = await db.query('recurring_payment_history');
      expect(history.single['source'], 'auto_match');

      // The same payment can't pay the next cycle too.
      expect(
          await BillPaymentMatcher.recordIfBillPayment(
            txn('nf', 649, DateTime(2026, 10, 7, 6), merchant: 'Netflix'),
            repository: repo,
            sideEffects: false,
          ),
          isNull);
    });

    test('P2: unrelated spending leaves bills alone', () async {
      final repo = RecurringPaymentRepository();
      await repo.upsert(netflix());
      expect(
          await BillPaymentMatcher.recordIfBillPayment(
            txn('food', 649, DateTime(2026, 10, 7), merchant: 'Swiggy'),
            repository: repo,
            sideEffects: false,
          ),
          isNull);
      expect((await repo.getAll()).single.nextDueAt, DateTime(2026, 10, 7));
    });

    RecurringPayment statementBill(String id, DateTime due) => RecurringPayment(
          id: id,
          merchantName: 'HDFC Credit Card',
          amount: 18450,
          frequency: 'monthly',
          lastPaidAt: due.subtract(const Duration(days: 15)),
          nextDueAt: due,
          categoryId: 'bills',
          status: RecurringStatus.detected,
        );

    test('P5: statement bills survive a detection run', () async {
      final repo = RecurringPaymentRepository();
      await repo.upsertStatementBill(statementBill(
          'bill_obs1', DateTime.now().add(const Duration(days: 12))));
      await repo.syncDetectedPayments(const []);
      expect((await repo.getAll()).map((b) => b.id), ['bill_obs1']);
    });

    test('P5: a newer statement replaces the older one; stale ones expire',
        () async {
      final repo = RecurringPaymentRepository();
      await repo.upsertStatementBill(statementBill(
          'bill_sep', DateTime.now().subtract(const Duration(days: 10))));
      await repo.upsertStatementBill(statementBill(
          'bill_oct', DateTime.now().add(const Duration(days: 20))));
      expect((await repo.getAll()).map((b) => b.id), ['bill_oct']);

      await repo.upsert(statementBill(
          'bill_old', DateTime.now().subtract(const Duration(days: 45))));
      await repo.syncDetectedPayments(const []);
      expect((await repo.getAll()).map((b) => b.id), ['bill_oct']);
    });
  });

  group('P3: detection is stricter for short cycles and small amounts', () {
    test('two equal payments a day apart are not a bill', () {
      expect(
          RecurringDetectionService.detect([
            sms('a', 40, DateTime(2026, 10, 1, 9), 'Metro Card Recharge'),
            sms('b', 40, DateTime(2026, 10, 2, 9), 'Metro Card Recharge'),
          ]),
          isEmpty);
    });

    test('weekly needs three payments', () {
      final two = [
        sms('a', 299, DateTime(2026, 9, 1), 'Yoga Class'),
        sms('b', 299, DateTime(2026, 9, 8), 'Yoga Class'),
      ];
      expect(RecurringDetectionService.detect(two), isEmpty);
      expect(
          RecurringDetectionService.detect([
            ...two,
            sms('c', 299, DateTime(2026, 9, 15), 'Yoga Class'),
          ]).single.frequency,
          'weekly');
    });

    test('tiny repeat amounts are ignored; monthly bills still detected', () {
      final found = RecurringDetectionService.detect([
        sms('t1', 20, DateTime(2026, 8, 3), 'Tea Stall'),
        sms('t2', 20, DateTime(2026, 9, 3), 'Tea Stall'),
        sms('n1', 649, DateTime(2026, 8, 7), 'NETFLIX INDIA PVT LTD'),
        sms('n2', 649, DateTime(2026, 9, 7), 'NETFLIX INDIA PVT LTD'),
      ]);
      expect(found.map((r) => r.merchantName), ['Netflix']);
    });
  });

  group('Focus Mode on imported payments', () {
    final pause = SpendPause(
      enabled: true,
      until: DateTime.now().add(const Duration(days: 3)),
      blockedCategoryIds: const ['shopping'],
    );

    test('a payment in a paused category gets a notice', () {
      expect(
        FocusModeNotifier.messageFor(
          txn('m', 1499, now, category: 'shopping', merchant: 'Myntra'),
          pause,
          categoryName: 'Shopping',
        ),
        '₹1,499 at Myntra was recorded in Shopping, which you paused.',
      );
    });

    test('other categories, income and expired pauses are ignored', () {
      expect(
          FocusModeNotifier.messageFor(txn('f', 200, now), pause,
              categoryName: 'Food'),
          isNull);
      expect(
          FocusModeNotifier.messageFor(
              txn('r', 200, now,
                  category: 'shopping', type: TransactionType.income),
              pause,
              categoryName: 'Shopping'),
          isNull);
      final expired = SpendPause(
        enabled: true,
        until: DateTime.now().subtract(const Duration(minutes: 1)),
        blockedCategoryIds: const ['shopping'],
      );
      expect(
          FocusModeNotifier.messageFor(
              txn('m', 100, now, category: 'shopping'), expired,
              categoryName: 'Shopping'),
          isNull);
    });
  });
}
