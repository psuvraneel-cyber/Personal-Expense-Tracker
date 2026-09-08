import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pet/data/database/database_helper.dart';
import 'package:pet/data/models/sms_transaction.dart';
import 'package:pet/data/repositories/sms_transaction_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late SmsTransactionRepository repo;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await openDatabase(
      inMemoryDatabasePath,
      version: 14,
      onCreate: (db, version) async {
        await DatabaseHelper().onCreateForTesting(db, version);
      },
    );
    DatabaseHelper.setTestDatabase(db);
    repo = SmsTransactionRepository();
  });

  tearDown(() async {
    await db.close();
    DatabaseHelper.setTestDatabase(null);
  });

  group('INVESTMENT-GRADE RELIABILITY: Atomic Watermark & Persistence Tests', () {
    test('1. Watermark starts empty and is null initially', () async {
      final wm = await repo.getWatermark('sms_watermark');
      expect(wm, isNull);
    });

    test('2. Atomic Commit: Transactions + Watermark commit together on success', () async {
      final now = DateTime.now();
      final txn1 = SmsTransaction(
        id: 'atomic_1',
        amount: 500.0,
        merchantName: 'Swiggy',
        bankName: 'HDFC',
        transactionType: 'debit',
        timestamp: now,
        smsSender: 'TESTBK',
        rawSmsBody: 'Paid Rs 500 to Swiggy',
        smsHash: 'hash_atomic_1',
      );

      final watermarkTimestamp = 1700000000000;
      final inserted = await repo.insertBatchWithWatermark(
        transactions: [txn1],
        watermarkTimestamp: watermarkTimestamp,
        watermarkKeys: const ['sms_watermark', 'reconciliation_watermark'],
      );

      expect(inserted, equals(1));

      // Assert both transactions and watermarks exist
      final count = await repo.getCount();
      expect(count, equals(1));

      final smsWm = await repo.getWatermark('sms_watermark');
      final recWm = await repo.getWatermark('reconciliation_watermark');

      expect(smsWm, equals(watermarkTimestamp));
      expect(recWm, equals(watermarkTimestamp));
    });

    test('3. Atomic Rollback: Exception before commit rolls back BOTH rows AND watermark', () async {
      final initialWm = 1600000000000;
      await repo.setWatermark('sms_watermark', initialWm);

      final txn1 = SmsTransaction(
        id: 'rollback_1',
        amount: 250.0,
        merchantName: 'Uber',
        bankName: 'ICICI',
        transactionType: 'debit',
        timestamp: DateTime.now(),
        smsSender: 'TESTBK',
        rawSmsBody: 'Paid Rs 250 to Uber',
        smsHash: 'hash_rollback_1',
      );

      // Attempt transaction with simulated failure inside transaction
      bool caughtError = false;
      try {
        await db.transaction((txn) async {
          await txn.insert('sms_transactions', txn1.toMap());
          await txn.insert('system_watermarks', {
            'key': 'sms_watermark',
            'value': 1800000000000,
            'updatedAt': DateTime.now().toIso8601String(),
          });
          // Simulate crash / exception before COMMIT
          throw Exception('Simulated power loss or crash before commit');
        });
      } catch (e) {
        caughtError = true;
      }

      expect(caughtError, isTrue);

      // Assert: Database rolled back completely. Row count = 0, Watermark = initialWm
      final count = await repo.getCount();
      expect(count, equals(0));

      final currentWm = await repo.getWatermark('sms_watermark');
      expect(currentWm, equals(initialWm));
    });

    test('4. Recovery after crash: Subsequent scan succeeds from un-advanced watermark', () async {
      final initialWm = 1600000000000;
      await repo.setWatermark('sms_watermark', initialWm);

      final txnCandidate = SmsTransaction(
        id: 'recov_1',
        amount: 1200.0,
        merchantName: 'Amazon',
        bankName: 'SBI',
        transactionType: 'debit',
        timestamp: DateTime.now(),
        smsSender: 'TESTBK',
        rawSmsBody: 'Paid Rs 1200 at Amazon',
        smsHash: 'hash_recov_1',
      );

      // Batch 1 fails
      try {
        await db.transaction((txn) async {
          await txn.insert('sms_transactions', txnCandidate.toMap());
          throw Exception('Interrupted batch');
        });
      } catch (_) {}

      // Watermark is still initialWm
      expect(await repo.getWatermark('sms_watermark'), equals(initialWm));

      // Batch 2 succeeds (Recovery scan)
      final newWm = 1650000000000;
      final inserted = await repo.insertBatchWithWatermark(
        transactions: [txnCandidate],
        watermarkTimestamp: newWm,
        watermarkKeys: const ['sms_watermark'],
      );

      expect(inserted, equals(1));
      expect(await repo.getCount(), equals(1));
      expect(await repo.getWatermark('sms_watermark'), equals(newWm));
    });

    test('5. Duplicate Scan Idempotency: Re-scanning committed batch does not duplicate rows or corrupt watermark', () async {
      final txn = SmsTransaction(
        id: 'dup_1',
        amount: 99.0,
        merchantName: 'Jio',
        bankName: 'Axis',
        transactionType: 'debit',
        timestamp: DateTime.now(),
        smsSender: 'TESTBK',
        rawSmsBody: 'Recharge Rs 99 successful',
        smsHash: 'hash_dup_1',
      );

      final wm = 1710000000000;

      // First scan
      final firstInsert = await repo.insertBatchWithWatermark(
        transactions: [txn],
        watermarkTimestamp: wm,
      );
      expect(firstInsert, equals(1));

      // Second scan (re-scan exact same batch)
      final secondInsert = await repo.insertBatchWithWatermark(
        transactions: [txn],
        watermarkTimestamp: wm,
      );
      expect(secondInsert, equals(0)); // 0 new rows

      // Assert row count remains 1 and watermark is preserved
      expect(await repo.getCount(), equals(1));
      expect(await repo.getWatermark('sms_watermark'), equals(wm));
    });

    test('6. MASSIVE STRESS TEST: 1,000 Interrupted Scans & Recovery Cycles', () async {
      int totalCommittedTxns = 0;
      int currentWatermark = 1000;

      for (int i = 1; i <= 1000; i++) {
        final candidate = SmsTransaction(
          id: 'stress_$i',
          amount: (i * 10).toDouble(),
          merchantName: 'Merchant_$i',
          bankName: 'Bank',
          transactionType: 'debit',
          timestamp: DateTime.fromMillisecondsSinceEpoch(1000 + i * 1000),
          smsSender: 'TESTBK',
        rawSmsBody: 'Rs ${i * 10} paid to Merchant_$i',
          smsHash: 'hash_stress_$i',
        );

        final proposedWatermark = 1000 + i * 1000;

        // 50% chance of crash/interruption mid-transaction
        final shouldCrash = (i % 2 == 0);

        if (shouldCrash) {
          try {
            await db.transaction((txn) async {
              await txn.insert('sms_transactions', candidate.toMap());
              await txn.insert('system_watermarks', {
                'key': 'sms_watermark',
                'value': proposedWatermark,
                'updatedAt': DateTime.now().toIso8601String(),
              });
              throw Exception('Simulated power loss at step $i');
            });
          } catch (_) {
            // Crash caught — transaction rolled back
          }

          // Assert watermark DID NOT advance on crash
          final actualWm = await repo.getWatermark('sms_watermark');
          expect(actualWm, equals(currentWatermark == 1000 ? null : currentWatermark));
        } else {
          // Clean commit
          final inserted = await repo.insertBatchWithWatermark(
            transactions: [candidate],
            watermarkTimestamp: proposedWatermark,
          );
          expect(inserted, equals(1));
          totalCommittedTxns++;
          currentWatermark = proposedWatermark;

          final actualWm = await repo.getWatermark('sms_watermark');
          expect(actualWm, equals(currentWatermark));
        }
      }

      // Final DB assertions
      final dbCount = await repo.getCount();
      expect(dbCount, equals(totalCommittedTxns));
      expect(await repo.getWatermark('sms_watermark'), equals(currentWatermark));
    });
  });
}
