import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pet/data/database/database_helper.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/sms_transaction.dart';
import 'package:pet/premium/providers/recurring_provider.dart';
import 'package:pet/premium/services/notification_preferences_service.dart';
import 'package:pet/premium/services/notification_service.dart';

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
  late Database testDb;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    NotificationService.resetForTest();
    await NotificationPreferencesService.instance.load();

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
          CREATE TABLE alerts (
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            title TEXT NOT NULL,
            message TEXT NOT NULL,
            categoryId TEXT,
            createdAt TEXT NOT NULL,
            isRead INTEGER DEFAULT 0,
            alertKey TEXT
          )
        ''');
      },
    );

    // Clean tables before each test
    await testDb.delete('recurring_payments');
    await testDb.delete('recurring_payment_history');
    await testDb.delete('alerts');

    DatabaseHelper.setTestDatabase(testDb);
  });

  tearDown(() async {
    DatabaseHelper.setTestDatabase(null);
    await testDb.close();
  });

  group('RecurringProvider Full Lifecycle Tests', () {
    test('addManual creates confirmed commitment and schedules reminder', () async {
      final provider = RecurringProvider();
      await provider.addManual(
        merchantName: 'Netflix',
        amount: 249.0,
        frequency: 'monthly',
        nextDueAt: DateTime(2026, 9, 20),
        categoryId: 'entertainment',
        isAutopay: true,
      );

      expect(provider.recurring.length, equals(1));
      expect(provider.confirmedBills.length, equals(1));
      expect(provider.detectedBills.length, equals(0));

      final bill = provider.confirmedBills.first;
      expect(bill.merchantName, equals('Netflix'));
      expect(bill.amount, equals(249.0));
      expect(bill.status, equals(RecurringStatus.confirmed));
      expect(bill.isAutopay, isTrue);
    });

    test('markAsPaid records immutable history and advances next due date', () async {
      final provider = RecurringProvider();
      await provider.addManual(
        merchantName: 'Spotify',
        amount: 119.0,
        frequency: 'monthly',
        nextDueAt: DateTime(2026, 8, 15),
      );

      final billId = provider.confirmedBills.first.id;

      // Mark paid on Aug 15
      await provider.markAsPaid(
        billId,
        paidAt: DateTime(2026, 8, 15),
        amount: 119.0,
        note: 'UPI Payment Ref #999',
      );

      final updatedBill = provider.confirmedBills.first;
      expect(updatedBill.lastPaidAt, equals(DateTime(2026, 8, 15)));
      expect(updatedBill.nextDueAt, equals(DateTime(2026, 9, 15)));

      // Verify payment history entry
      final history = await provider.getHistory(billId);
      expect(history.length, equals(1));
      expect(history.first.amount, equals(119.0));
      expect(history.first.notes, equals('UPI Payment Ref #999'));
    });

    test('snoozeBill pushes next due date by 1 billing cycle', () async {
      final provider = RecurringProvider();
      await provider.addManual(
        merchantName: 'Rent',
        amount: 20000.0,
        frequency: 'monthly',
        nextDueAt: DateTime(2026, 8, 1),
      );

      final billId = provider.confirmedBills.first.id;
      await provider.snoozeBill(billId);

      final snoozed = provider.confirmedBills.first;
      expect(snoozed.nextDueAt.month, equals(9));
      expect(snoozed.nextDueAt.day, equals(1));
    });

    test('cancelBill transitions commitment to cancelled while retaining history', () async {
      final provider = RecurringProvider();
      await provider.addManual(
        merchantName: 'Gym Membership',
        amount: 1500.0,
        frequency: 'monthly',
        nextDueAt: DateTime(2026, 8, 1),
      );

      final billId = provider.confirmedBills.first.id;

      await provider.markAsPaid(billId, paidAt: DateTime(2026, 8, 1));
      await provider.cancelBill(billId);

      expect(provider.confirmedBills, isEmpty);
      expect(provider.cancelledBills.length, equals(1));
      expect(provider.cancelledBills.first.status, equals(RecurringStatus.cancelled));

      // History is preserved
      final history = await provider.getHistory(billId);
      expect(history.length, equals(1));

      // Reopening brings it back to confirmed
      await provider.reopenBill(billId);
      expect(provider.confirmedBills.length, equals(1));
      expect(provider.cancelledBills, isEmpty);
    });

    test('deleteBill permanently erases bill and history', () async {
      final provider = RecurringProvider();
      await provider.addManual(
        merchantName: 'Old Trial',
        amount: 50.0,
        frequency: 'monthly',
        nextDueAt: DateTime(2026, 8, 1),
      );

      final billId = provider.confirmedBills.first.id;
      await provider.markAsPaid(billId);
      await provider.deleteBill(billId);

      expect(provider.recurring, isEmpty);
      final history = await provider.getHistory(billId);
      expect(history, isEmpty);
    });

    test('refreshFromSms merges detected candidates without altering confirmed commitments', () async {
      final provider = RecurringProvider();

      // 1. User has an existing confirmed bill
      await provider.addManual(
        merchantName: 'Netflix',
        amount: 249.0,
        frequency: 'monthly',
        nextDueAt: DateTime(2026, 9, 20),
      );

      // 2. Incoming SMS has Netflix (already confirmed) + Hotstar (newly detected)
      final sms = [
        _createSms(
          id: '1',
          merchantName: 'Netflix',
          amount: 249.0,
          timestamp: DateTime(2026, 6, 20),
        ),
        _createSms(
          id: '2',
          merchantName: 'Netflix',
          amount: 249.0,
          timestamp: DateTime(2026, 7, 20),
        ),
        _createSms(
          id: '3',
          merchantName: 'Disney+ Hotstar',
          amount: 299.0,
          timestamp: DateTime(2026, 6, 10),
        ),
        _createSms(
          id: '4',
          merchantName: 'Disney+ Hotstar',
          amount: 299.0,
          timestamp: DateTime(2026, 7, 10),
        ),
      ];

      await provider.refreshFromSms(sms);

      // Confirmed Netflix is intact and NOT duplicated
      expect(provider.confirmedBills.length, equals(1));
      expect(provider.confirmedBills.first.merchantName, equals('Netflix'));

      // Disney Hotstar is placed in detectedBills
      expect(provider.detectedBills.length, equals(1));
      expect(provider.detectedBills.first.merchantName, contains('Hotstar'));
      expect(provider.detectedBills.first.status, equals(RecurringStatus.detected));

      // User confirms Hotstar
      final hotstarId = provider.detectedBills.first.id;
      await provider.confirmDetected(hotstarId);

      expect(provider.confirmedBills.length, equals(2));
      expect(provider.detectedBills, isEmpty);
    });

    test('clearData resets all state on signout', () async {
      final provider = RecurringProvider();
      await provider.addManual(
        merchantName: 'Water Bill',
        amount: 300.0,
        frequency: 'monthly',
        nextDueAt: DateTime(2026, 8, 25),
      );

      expect(provider.recurring.isNotEmpty, isTrue);

      provider.clearData();

      expect(provider.recurring, isEmpty);
      expect(provider.confirmedBills, isEmpty);
      expect(provider.detectedBills, isEmpty);
    });
  });
}
