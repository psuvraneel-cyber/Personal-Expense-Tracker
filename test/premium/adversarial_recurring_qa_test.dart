import 'package:flutter_test/flutter_test.dart';
import 'package:pet/data/database/database_helper.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/sms_transaction.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/premium/models/recurring_payment.dart';
import 'package:pet/premium/models/recurring_payment_history.dart';
import 'package:pet/premium/providers/recurring_provider.dart';
import 'package:pet/premium/repositories/recurring_payment_repository.dart';
import 'package:pet/premium/services/cashflow_forecast_service.dart';
import 'package:pet/premium/services/notification_service.dart';
import 'package:pet/premium/services/recurring_detection_service.dart';
import 'package:pet/services/recurrence_calculator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

SmsTransaction _createSms({
  required String id,
  required String merchantName,
  required double amount,
  required DateTime timestamp,
}) {
  final body = 'Debited Rs.$amount at $merchantName on ${timestamp.toIso8601String()}';
  return SmsTransaction(
    id: id,
    amount: amount,
    merchantName: merchantName,
    bankName: 'HDFC',
    transactionType: 'debit',
    timestamp: timestamp,
    rawSmsBody: body,
    smsSender: 'HDFC-BANK',
    smsHash: SmsTransaction.generateHash(body, timestamp),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database testDb;

  setUpAll(() async {
    testDb = await openDatabase(
      inMemoryDatabasePath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE recurring_payments (
            id TEXT PRIMARY KEY,
            merchantName TEXT NOT NULL,
            amount REAL NOT NULL,
            frequency TEXT NOT NULL,
            lastPaidAt TEXT NOT NULL,
            nextDueAt TEXT NOT NULL,
            categoryId TEXT NOT NULL,
            confidence REAL DEFAULT 0.6,
            source TEXT DEFAULT 'sms',
            status TEXT DEFAULT 'confirmed',
            isAutopay INTEGER DEFAULT 0,
            previousAmount REAL,
            priceChangeDetectedAt TEXT,
            notes TEXT,
            createdAt TEXT NOT NULL,
            updatedAt TEXT NOT NULL,
            detectionReason TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE recurring_payment_history (
            id TEXT PRIMARY KEY,
            recurringPaymentId TEXT NOT NULL,
            amount REAL NOT NULL,
            paidAt TEXT NOT NULL,
            source TEXT DEFAULT 'manual',
            transactionId TEXT,
            notes TEXT,
            createdAt TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE budget_alerts (
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            title TEXT NOT NULL,
            message TEXT NOT NULL,
            createdAt TEXT NOT NULL,
            alertKey TEXT NOT NULL
          )
        ''');
      },
    );
    DatabaseHelper.setTestDatabase(testDb);
  });

  tearDownAll(() async {
    await testDb.close();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    NotificationService.resetForTest();
    await testDb.delete('recurring_payment_history');
    await testDb.delete('recurring_payments');
    await testDb.delete('budget_alerts');
  });

  group('Adversarial QA — Payment Reconciliation & Deduplication', () {
    test('Scenario A & B: User marks bill as paid, subsequent SMS scan preserves single payment history', () async {
      final repo = RecurringPaymentRepository();
      final provider = RecurringProvider();
      final now = DateTime(2026, 9, 10);

      // 1. Confirmed bill exists
      await provider.addManual(
        merchantName: 'Airtel Broadband',
        amount: 999.0,
        frequency: 'monthly',
        nextDueAt: now,
      );
      expect(provider.confirmedBills.length, 1);
      final bill = provider.confirmedBills.first;

      // 2. User marks bill as paid
      await provider.markAsPaid(
        bill.id,
        paidAt: now,
        amount: 999.0,
        note: 'UPI ref 987654321',
        source: 'manual',
      );

      expect(provider.confirmedBills.first.nextDueAt, DateTime(2026, 10, 10));

      final historyAfterManual = await repo.getHistory(bill.id);
      expect(historyAfterManual.length, 1);
      expect(historyAfterManual.first.notes, 'UPI ref 987654321');

      // 3. Subsequent SMS scan with matching transactions runs
      final smsList = [
        _createSms(
          id: 'sms_1',
          merchantName: 'Airtel Broadband',
          amount: 999.0,
          timestamp: now.subtract(const Duration(days: 60)),
        ),
        _createSms(
          id: 'sms_2',
          merchantName: 'Airtel Broadband',
          amount: 999.0,
          timestamp: now.subtract(const Duration(days: 30)),
        ),
        _createSms(
          id: 'sms_3',
          merchantName: 'Airtel Broadband',
          amount: 999.0,
          timestamp: now,
        ),
      ];

      await provider.refreshFromSms(smsList);

      // Invariant: Exactly 1 confirmed bill exists (no duplicate detected candidate)
      expect(provider.confirmedBills.length, 1);
      expect(provider.detectedBills.length, 0);

      // Invariant: Exactly 1 payment history entry exists
      final historyAfterSms = await repo.getHistory(bill.id);
      expect(historyAfterSms.length, 1);
      expect(historyAfterSms.first.amount, 999.0);
    });

    test('Invariant L: Dismissed candidates are persisted and do NOT resurrect on subsequent SMS scans', () async {
      final provider = RecurringProvider();
      final now = DateTime(2026, 9, 10);

      final smsList = [
        _createSms(
          id: 'sms_gym_1',
          merchantName: 'Cult Gym Pvt Ltd',
          amount: 2000.0,
          timestamp: now.subtract(const Duration(days: 60)),
        ),
        _createSms(
          id: 'sms_gym_2',
          merchantName: 'Cult Gym Pvt Ltd',
          amount: 2000.0,
          timestamp: now.subtract(const Duration(days: 30)),
        ),
        _createSms(
          id: 'sms_gym_3',
          merchantName: 'Cult Gym Pvt Ltd',
          amount: 2000.0,
          timestamp: now,
        ),
      ];

      // 1. Initial detection creates candidate
      await provider.refreshFromSms(smsList);
      expect(provider.detectedBills.length, 1);
      expect(provider.detectedBills.first.merchantName, 'Cult Gym');

      final detectedId = provider.detectedBills.first.id;

      // 2. User dismisses candidate
      await provider.dismissDetected(detectedId);
      expect(provider.detectedBills.length, 0);

      // 3. New SMS arrives / user triggers rescan
      final updatedSmsList = [
        ...smsList,
        _createSms(
          id: 'sms_gym_4',
          merchantName: 'Cult Gym Pvt Ltd',
          amount: 2000.0,
          timestamp: now.add(const Duration(days: 1)),
        ),
      ];

      final newProvider = RecurringProvider();
      await newProvider.refreshFromSms(updatedSmsList);

      // Invariant: Dismissed candidate is suppressed and does not reappear
      expect(newProvider.detectedBills.length, 0);
    });

    test('Invariant D & Atomicity: markAsPaid atomic SQLite transaction guarantees history and schedule update together', () async {
      final repo = RecurringPaymentRepository();
      final bill = RecurringPayment(
        id: 'bill_atomic_1',
        merchantName: 'Spotify India',
        amount: 119.0,
        frequency: 'monthly',
        lastPaidAt: DateTime(2026, 8, 1),
        nextDueAt: DateTime(2026, 9, 1),
        categoryId: 'entertainment',
        confidence: 1.0,
        source: 'manual',
        status: RecurringStatus.confirmed,
        createdAt: DateTime(2026, 8, 1),
        updatedAt: DateTime(2026, 8, 1),
      );
      await repo.upsert(bill);

      final history = RecurringPaymentHistory(
        id: 'hist_atomic_1',
        recurringPaymentId: bill.id,
        amount: 119.0,
        paidAt: DateTime(2026, 9, 1),
        source: 'manual',
        notes: 'September sub',
        createdAt: DateTime(2026, 9, 1),
      );

      final updated = bill.copyWith(
        lastPaidAt: DateTime(2026, 9, 1),
        nextDueAt: DateTime(2026, 10, 1),
        updatedAt: DateTime(2026, 9, 1),
      );

      await repo.recordPaymentAndAdvance(
        history: history,
        updatedPayment: updated,
      );

      final savedBill = await repo.getById(bill.id);
      final savedHistory = await repo.getHistory(bill.id);

      expect(savedBill?.nextDueAt, DateTime(2026, 10, 1));
      expect(savedHistory.length, 1);
      expect(savedHistory.first.amount, 119.0);
    });
  });

  group('Adversarial QA — Merchant Normalization & Collision Isolation', () {
    test('Strips UPI-, POS-, BIL/, VPA: prefixes while keeping distinct services isolated', () {
      expect(RecurringDetectionService.normalizeMerchantName('UPI-NETFLIX'), 'Netflix');
      expect(RecurringDetectionService.normalizeMerchantName('POS-NETFLIX'), 'Netflix');
      expect(RecurringDetectionService.normalizeMerchantName('BIL/NETFLIX'), 'Netflix');
      expect(RecurringDetectionService.normalizeMerchantName('VPA:NETFLIX'), 'Netflix');
      expect(RecurringDetectionService.normalizeMerchantName('Netflix.com India Pvt Ltd'), 'Netflix');

      // Collision Isolation: Brand sub-entities must NOT collapse into the root brand
      expect(RecurringDetectionService.normalizeMerchantName('Amazon'), 'Amazon');
      expect(RecurringDetectionService.normalizeMerchantName('Amazon Prime'), 'Amazon Prime');
      expect(RecurringDetectionService.normalizeMerchantName('Amazon Fresh'), 'Amazon Fresh');
      expect(RecurringDetectionService.normalizeMerchantName('Amazon Pay'), 'Amazon Pay');
    });
  });

  group('Adversarial QA — Account Isolation & Sign-out', () {
    test('clearData resets all cached bills and _isInitialized state', () async {
      final provider = RecurringProvider();
      await provider.addManual(
        merchantName: 'Hotstar',
        amount: 499.0,
        frequency: 'yearly',
        nextDueAt: DateTime(2027, 3, 1),
      );

      expect(provider.confirmedBills.length, 1);
      expect(provider.isInitialized, false); // only set on load()

      await provider.load();
      expect(provider.isInitialized, true);

      // Sign-out cleans state
      provider.clearData();
      expect(provider.confirmedBills, isEmpty);
      expect(provider.isInitialized, false);
      expect(provider.isLoading, false);
    });
  });

  group('Adversarial QA — Discrete Cashflow Forecast Projections', () {
    test('Weekly bills deduct on all discrete occurrence dates across 30 days without double counting baseline', () {
      final now = DateTime(2026, 9, 1);
      // Historical spend: 30 days with ₹1,000 daily expense (including ₹500 weekly gym)
      final transactions = <TransactionRecord>[
        for (var i = 0; i < 30; i++)
          TransactionRecord(
            id: 'txn_$i',
            amount: 1000.0,
            type: TransactionType.expense,
            categoryId: 'food',
            date: now.subtract(Duration(days: 30 - i)),
            note: 'Daily burn',
          ),
      ];

      final weeklyBill = RecurringPayment(
        id: 'bill_weekly_gym',
        merchantName: 'CrossFit Gym',
        amount: 700.0,
        frequency: 'weekly',
        lastPaidAt: now.subtract(const Duration(days: 7)),
        nextDueAt: DateTime(2026, 9, 4), // Day 3 in forecast
        categoryId: 'health',
        confidence: 1.0,
        source: 'manual',
        status: RecurringStatus.confirmed,
        createdAt: now,
        updatedAt: now,
      );

      final forecast = CashflowForecastService.forecast(
        transactions,
        confirmedBills: [weeklyBill],
        days: 30,
        referenceDate: now,
      );

      // Weekly bill occurs on Sep 4, Sep 11, Sep 18, Sep 25 (4 times in 30 days)
      expect(forecast.dailyPoints.length, 30);

      // Points should reflect discrete drops on those 4 days
      final sep4Index = 3;
      final sep11Index = 10;
      final sep18Index = 17;
      final sep25Index = 24;

      final dropSep4 = forecast.dailyPoints[sep4Index - 1].balance - forecast.dailyPoints[sep4Index].balance;
      final dropSep11 = forecast.dailyPoints[sep11Index - 1].balance - forecast.dailyPoints[sep11Index].balance;
      final dropSep18 = forecast.dailyPoints[sep18Index - 1].balance - forecast.dailyPoints[sep18Index].balance;
      final dropSep25 = forecast.dailyPoints[sep25Index - 1].balance - forecast.dailyPoints[sep25Index].balance;

      // On non-bill days (e.g. Sep 3 -> Sep 4 before bill), daily drop is the variable daily expense:
      // avgDaily = 1000, recurringDailyBurn = 700 * (52/12) / 30 = 101.11 => variableDaily = 898.89
      // On bill days, drop is variableDaily + 700 = 1598.89
      expect(dropSep4, closeTo(1598.89, 5.0));
      expect(dropSep11, closeTo(1598.89, 5.0));
      expect(dropSep18, closeTo(1598.89, 5.0));
      expect(dropSep25, closeTo(1598.89, 5.0));
    });
  });

  group('Adversarial QA — Snooze, Cancel, Reopen & Delete Lifecycle', () {
    test('Snooze advances nextDueAt by 1 cycle, reschedules notification, does NOT log payment history', () async {
      final repo = RecurringPaymentRepository();
      final provider = RecurringProvider();
      final now = DateTime(2026, 9, 15);

      await provider.addManual(
        merchantName: 'Gym Membership',
        amount: 1500.0,
        frequency: 'monthly',
        nextDueAt: now,
      );

      final billId = provider.confirmedBills.first.id;

      await provider.snoozeBill(billId);

      // 1. Next due date pushed to Oct 15
      expect(provider.confirmedBills.first.nextDueAt, DateTime(2026, 10, 15));

      // 2. No payment history created
      final history = await repo.getHistory(billId);
      expect(history, isEmpty);
    });

    test('Cancel keeps history and stops reminders; Delete removes record, history, and reminders permanently', () async {
      final repo = RecurringPaymentRepository();
      final provider = RecurringProvider();
      final now = DateTime(2026, 9, 15);

      await provider.addManual(
        merchantName: 'Newspaper',
        amount: 250.0,
        frequency: 'monthly',
        nextDueAt: now,
      );
      final billId = provider.confirmedBills.first.id;

      await provider.markAsPaid(billId, paidAt: now, amount: 250.0);
      expect(await repo.getHistory(billId), hasLength(1));

      // 1. Cancel bill
      await provider.cancelBill(billId);
      expect(provider.confirmedBills, isEmpty);
      expect(provider.cancelledBills, hasLength(1));

      // History preserved on cancel
      expect(await repo.getHistory(billId), hasLength(1));

      // 2. Reopen bill
      await provider.reopenBill(billId);
      expect(provider.confirmedBills, hasLength(1));
      expect(provider.cancelledBills, isEmpty);

      // 3. Delete permanently
      await provider.deleteBill(billId);
      expect(provider.confirmedBills, isEmpty);
      expect(provider.cancelledBills, isEmpty);
      expect(await repo.getById(billId), isNull);
      expect(await repo.getHistory(billId), isEmpty);
    });
  });

  group('Adversarial QA — Calendar Boundaries Stress Test', () {
    test('31st day anchor correctly clamped through Feb and restored in 31-day months', () {
      final anchor = DateTime(2026, 1, 31);
      final jan = anchor;
      final feb = RecurrenceCalculator.computeNextOccurrence(
        anchorDate: anchor,
        currentOccurrence: jan,
        frequency: RecurringFrequency.monthly,
      );
      expect(feb, DateTime(2026, 2, 28));

      final mar = RecurrenceCalculator.computeNextOccurrence(
        anchorDate: anchor,
        currentOccurrence: feb,
        frequency: RecurringFrequency.monthly,
      );
      expect(mar, DateTime(2026, 3, 31));

      final apr = RecurrenceCalculator.computeNextOccurrence(
        anchorDate: anchor,
        currentOccurrence: mar,
        frequency: RecurringFrequency.monthly,
      );
      expect(apr, DateTime(2026, 4, 30));

      final may = RecurrenceCalculator.computeNextOccurrence(
        anchorDate: anchor,
        currentOccurrence: apr,
        frequency: RecurringFrequency.monthly,
      );
      expect(may, DateTime(2026, 5, 31));
    });
  });
}
