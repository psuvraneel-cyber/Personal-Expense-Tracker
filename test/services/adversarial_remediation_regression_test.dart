import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pet/data/database/database_helper.dart';
import 'package:pet/services/financial_ingestion_service.dart';
import 'package:pet/services/sms_service.dart';
import 'package:pet/services/reconciliation_service.dart';
import 'package:pet/services/native_sms_reader.dart';
import 'package:pet/services/ingestion_diagnostics.dart';
import 'package:pet/main.dart';
import 'package:pet/screens/sms_transactions/pending_review_screen.dart';

class MockNativeSmsReader extends NativeSmsReader {
  MockNativeSmsReader() : super.forTesting();

  List<NativeSmsMessage> messages = [];

  @override
  Future<List<NativeSmsMessage>> getAllSms({int lookbackDays = 90}) async {
    return List.from(messages);
  }

  @override
  Future<List<NativeSmsMessage>> getSmsSinceTimestamp({
    int? sinceTimestamp,
    int fallbackDays = 30,
  }) async {
    if (sinceTimestamp == null) return List.from(messages);
    return messages.where((m) => m.dateMillis > sinceTimestamp).toList();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late Directory tempDir;
  late MockNativeSmsReader mockReader;
  late SmsService smsService;
  late ReconciliationService reconciliationService;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'notifications_enabled': false,
    });

    tempDir = Directory.systemTemp.createTempSync('remediation_test_');
    final dbPath = p.join(tempDir.path, 'pet_remediation_test.db');
    db = await openDatabase(
      dbPath,
      version: 18,
      onCreate: (db, version) async {
        await DatabaseHelper().onCreateForTesting(db, version);
      },
    );

    DatabaseHelper.setTestDatabase(db);
    mockReader = MockNativeSmsReader();
    smsService = SmsService(nativeReader: mockReader);
    reconciliationService = ReconciliationService(nativeReader: mockReader);

    SmsService.debugOverrideIsSupported = true;
    NativeSmsReader.debugOverrideIsSupported = true;
    ReconciliationService.debugOverrideIsSupported = true;
    ReconciliationService.debugOverridePermissionGranted = true;

    IngestionDiagnostics().reset();
  });

  tearDown(() async {
    DatabaseHelper.setTestDatabase(null);
    await db.close();
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('Adversarial Remediation Regression Tests (DEF-01 through DEF-05)', () {
    test(
        'Test A — Live notification + inbox scan produces exactly one canonical transaction',
        () async {
      final notif = NativeSmsMessage(
        address: 'PhonePe',
        packageName: 'com.phonepe.app',
        title: 'Paid to Starbucks',
        body: 'Rs 350.00 debited for UPI ref 8899001122',
        dateMillis: DateTime(2026, 8, 24, 10, 0).millisecondsSinceEpoch,
        source: 'notification',
      );
      await FinancialIngestionService().ingestMessage(notif);

      var txns = await db.query('transactions');
      expect(txns.length, equals(1));
      final canonicalTxnId = txns.first['id'];

      // Later, inbox scan retrieves corresponding SMS with same reference and amount
      mockReader.messages = [
        NativeSmsMessage(
          address: 'HDFCBK',
          body:
              'Rs 350.00 debited from HDFC Bank A/c XX1234 on 24-Aug-26 at Starbucks. Ref UPI/8899001122.',
          dateMillis: DateTime(2026, 8, 24, 10, 0).millisecondsSinceEpoch,
          source: 'sms',
        ),
      ];
      await smsService.scanInbox();

      // Exactly 1 canonical transaction, no duplicates
      txns = await db.query('transactions');
      expect(txns.length, equals(1));
      expect(txns.first['id'], equals(canonicalTxnId));

      // Both observations recorded for full provenance
      final observations = await db.query('financial_observations');
      expect(observations.length, equals(2));
    });

    test(
        'Test B — Live SMS + reconciliation preserves exactly one canonical transaction',
        () async {
      final liveSms = NativeSmsMessage(
        address: 'SBIBNK',
        body:
            'Rs 1,200.00 debited from A/c XX5678 on 24-Aug-26 to Reliance Fresh. Ref 99887766.',
        dateMillis: DateTime(2026, 8, 24, 11, 0).millisecondsSinceEpoch,
        source: 'sms',
      );
      await FinancialIngestionService().ingestMessage(liveSms);
      var txns = await db.query('transactions');
      expect(txns.length, equals(1));

      // Reconciliation discovers the same SMS later
      mockReader.messages = [liveSms];
      await reconciliationService.reconcile(force: true);

      // Remains exactly one canonical transaction
      txns = await db.query('transactions');
      expect(txns.length, equals(1));
    });

    test(
        'Test C — Reconciliation-only transaction is properly promoted to canonical ledger',
        () async {
      // Offline / background missed event
      final missedSms = NativeSmsMessage(
        address: 'HDFCBK',
        body:
            'Rs 750.00 debited from HDFC Bank A/c XX1234 on 24-Aug-26 at BookMyShow. Avl Bal Rs 20,000.00. Ref BMS123456.',
        dateMillis: DateTime(2026, 8, 24, 12, 0).millisecondsSinceEpoch,
        source: 'sms',
      );
      mockReader.messages = [missedSms];

      await reconciliationService.reconcile(force: true);

      // Assert canonical transaction is created in transactions
      final txns = await db.query('transactions');
      expect(txns.length, equals(1));
      expect(txns.first['amount'], equals(750.0));
      expect(txns.first['merchantName'], equals('BookMyShow'));

      // Assert observation is recorded with promoted status and SMS provenance
      final obs = await db.query('financial_observations');
      expect(obs.length, equals(1));
      expect(obs.first['state'], equals('promoted'));
      expect(obs.first['source'], equals('sms'));
    });

    test(
        'Test D — Bill found by reconciliation creates recurring commitment and 0 expenses',
        () async {
      final billSms = NativeSmsMessage(
        address: 'HDFCBK',
        body:
            'Total amount due on your HDFC Bank Credit Card ending 9876 is Rs 14,520.00. Due date is 15-Sep-2026. Min due Rs 1,452.00.',
        dateMillis: DateTime(2026, 8, 24, 13, 0).millisecondsSinceEpoch,
        source: 'sms',
      );
      mockReader.messages = [billSms];

      await reconciliationService.reconcile(force: true);

      // 0 completed expenses in transactions table
      final txns = await db.query('transactions');
      expect(txns.isEmpty, isTrue);

      // 1 bill/recurring rule created in recurring_payments
      final bills = await db.query('recurring_payments');
      expect(bills.length, equals(1));
      expect(bills.first['amount'], equals(14520.0));
    });

    test(
        'Test E — Balance found by reconciliation updates linked account and creates 0 transactions',
        () async {
      // Pre-seed matching linked account
      await db.insert('linked_accounts', {
        'id': 'acct_sbi_1234',
        'provider': 'manual',
        'accountName': 'SBI Savings',
        'bankName': 'SBI',
        'accountTail': '1234',
        'accountType': 'savings',
        'lastObservedBalance': 50000.0,
        'lastObservedAt': DateTime(2026, 8, 20).toIso8601String(),
        'status': 'active',
      });

      final balanceSms = NativeSmsMessage(
        address: 'SBIINB',
        body:
            'Dear Customer, Available balance for your A/c XX1234 is Rs 82,450.00 as on 24-Aug-2026.',
        dateMillis: DateTime(2026, 8, 24, 14, 0).millisecondsSinceEpoch,
        source: 'sms',
      );
      mockReader.messages = [balanceSms];

      await reconciliationService.reconcile(force: true);

      // 0 transactions
      final txns = await db.query('transactions');
      expect(txns.isEmpty, isTrue);

      // Linked account updated
      final accounts = await db.query('linked_accounts');
      expect(accounts.length, equals(1));
      expect(accounts.first['lastObservedBalance'], equals(82450.0));
      expect(IngestionDiagnostics().balanceObservations, equals(1));
    });

    test(
        'Test F — Rejected/OTP message found by reconciliation creates 0 transactions and persists rejected state',
        () async {
      final otpSms = NativeSmsMessage(
        address: 'HDFCBK',
        body:
            '482910 is your OTP for transaction of Rs 500.00 at Amazon. Do NOT share this OTP with anyone.',
        dateMillis: DateTime(2026, 8, 24, 15, 0).millisecondsSinceEpoch,
        source: 'sms',
      );
      mockReader.messages = [otpSms];

      await reconciliationService.reconcile(force: true);

      // 0 transactions
      final txns = await db.query('transactions');
      expect(txns.isEmpty, isTrue);

      // Observation state is rejected
      final obs = await db.query('financial_observations');
      expect(obs.length, equals(1));
      expect(obs.first['state'], equals('rejected'));
    });

    test(
        'Test G — Reconciliation repeated is idempotent and produces no duplicates',
        () async {
      final sms = NativeSmsMessage(
        address: 'ICICIB',
        body:
            'Your A/c XX4321 is debited for Rs 899.00 on 24-Aug-26 at Flipkart. UPI Ref 334455.',
        dateMillis: DateTime(2026, 8, 24, 16, 0).millisecondsSinceEpoch,
        source: 'sms',
      );
      mockReader.messages = [sms];

      final count1 = await reconciliationService.reconcile(force: true);
      expect(count1, equals(1));
      final txns1 = await db.query('transactions');
      expect(txns1.length, equals(1));
      final id1 = txns1.first['id'];

      // Run second time
      final count2 = await reconciliationService.reconcile(force: true);
      expect(count2, equals(0));
      final txns2 = await db.query('transactions');
      expect(txns2.length, equals(1));
      expect(txns2.first['id'], equals(id1));
    });

    test(
        'Test H — Inbox scan repeated is idempotent and produces no duplicates',
        () async {
      final sms = NativeSmsMessage(
        address: 'AXISBK',
        body:
            'INR 450.00 debited from A/c no. XX9988 on 24-Aug-2026 17:00:00 at Dominos. Ref 556677.',
        dateMillis: DateTime(2026, 8, 24, 17, 0).millisecondsSinceEpoch,
        source: 'sms',
      );
      mockReader.messages = [sms];

      final count1 = await smsService.scanInbox();
      expect(count1, equals(1));
      var txns = await db.query('transactions');
      expect(txns.length, equals(1));

      // Second inbox scan
      final count2 = await smsService.scanInbox();
      expect(count2, equals(0));
      txns = await db.query('transactions');
      expect(txns.length, equals(1),
          reason:
              'Repeated scanInbox must not duplicate canonical transactions');
    });

    test(
        'Test I — Delete/ignore followed by inbox scan does not resurrect deleted transactions',
        () async {
      final sms = NativeSmsMessage(
        address: 'HDFCBK',
        body:
            'Rs 600.00 debited from HDFC Bank A/c XX1234 on 24-Aug-26 at Cinepolis. Ref 112244.',
        dateMillis: DateTime(2026, 8, 24, 18, 0).millisecondsSinceEpoch,
        source: 'sms',
      );
      // 1. Initial ingestion
      final txn = await FinancialIngestionService().ingestMessage(sms);
      expect(txn, isNotNull);

      final obs = await db.query('financial_observations');
      final obsId = obs.first['observationId'] as String;

      // 2. User deletes/rejects
      await FinancialIngestionService()
          .rejectObservation(observationId: obsId, reason: 'user_deleted');
      await db.delete('transactions', where: 'id = ?', whereArgs: [txn!.id]);

      var txns = await db.query('transactions');
      expect(txns.isEmpty, isTrue);

      // 3. Inbox scan runs
      mockReader.messages = [sms];
      await smsService.scanInbox();

      // Assert transaction is NOT resurrected
      txns = await db.query('transactions');
      expect(txns.isEmpty, isTrue,
          reason: 'Tombstone must prevent resurrection by inbox scan');
    });

    test(
        'Test J — Notification obs: deep link routes to PendingReviewScreen and preserves observationId',
        () {
      const payload = 'obs:test_observation_abc_123';
      final widget = PETApp.screenForPayload(payload);

      expect(widget, isA<PendingReviewScreen>());
      expect((widget as PendingReviewScreen).initialObservationId,
          equals('test_observation_abc_123'));
    });

    test('Test K — Legitimate transactions with same amount remain distinct',
        () async {
      // Two distinct legitimate transactions with identical amounts at different times/merchants
      final sms1 = NativeSmsMessage(
        address: 'HDFCBK',
        body:
            'Rs 500.00 debited from HDFC Bank A/c XX1234 on 24-Aug-26 at Swiggy. Ref 101010.',
        dateMillis: DateTime(2026, 8, 24, 10, 0).millisecondsSinceEpoch,
        source: 'sms',
      );
      final sms2 = NativeSmsMessage(
        address: 'HDFCBK',
        body:
            'Rs 500.00 debited from HDFC Bank A/c XX1234 on 24-Aug-26 at Uber. Ref 202020.',
        dateMillis: DateTime(2026, 8, 24, 14, 0).millisecondsSinceEpoch,
        source: 'sms',
      );

      mockReader.messages = [sms1, sms2];
      await smsService.scanInbox();

      final txns = await db.query('transactions', orderBy: 'date ASC');
      expect(txns.length, equals(2),
          reason: 'Two legitimate ₹500 transactions must not be collapsed');
      expect(txns[0]['amount'], equals(500.0));
      expect(txns[0]['merchantName'], equals('Swiggy'));
      expect(txns[1]['amount'], equals(500.0));
      expect(txns[1]['merchantName'], equals('Uber'));
    });

    test(
        'Test L — Cross-source identity produces 2 observations and exactly 1 canonical transaction',
        () async {
      final notif = NativeSmsMessage(
        address: 'Google Pay',
        packageName: 'com.google.android.apps.nbu.paisa.user',
        title: 'Paid to DMart',
        body: '₹1,500.00 debited for UPI ref 445566778899',
        dateMillis: DateTime(2026, 8, 24, 19, 0).millisecondsSinceEpoch,
        source: 'notification',
      );
      final sms = NativeSmsMessage(
        address: 'HDFCBK',
        body:
            'Rs 1500.00 debited from HDFC Bank A/c XX1234 on 24-Aug-26 at DMart. Ref UPI/445566778899.',
        dateMillis: DateTime(2026, 8, 24, 19, 0).millisecondsSinceEpoch,
        source: 'sms',
      );

      // Ingest notification live
      await FinancialIngestionService().ingestMessage(notif);

      // Inbox scan sees the SMS
      mockReader.messages = [sms];
      await smsService.scanInbox();

      // Assert: Exactly 2 observations recorded
      final observations = await db.query('financial_observations');
      expect(observations.length, equals(2));

      // Assert: Exactly 1 canonical transaction created
      final txns = await db.query('transactions');
      expect(txns.length, equals(1));
      expect(txns.first['amount'], equals(1500.0));
      expect(txns.first['merchantName'], equals('DMart'));
    });
  });
}
