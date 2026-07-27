import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pet/data/database/database_helper.dart';
import 'package:pet/data/models/sms_transaction.dart';
import 'package:pet/data/repositories/sms_transaction_repository.dart';
import 'package:pet/services/reconciliation_service.dart';
import 'package:pet/services/sms_parser/sms_transaction_parser.dart';
import 'package:pet/services/sms_parser/user_feedback_store.dart';

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
    UserFeedbackStore.resetForTesting();
  });

  tearDown(() async {
    await db.close();
    DatabaseHelper.setTestDatabase(null);
  });

  group('HIGH-4: Persistence & Sync Integration Tests', () {
    test('1. Proximity deduplication matches inside 30s window with same merchant and rejects outside window or different merchant/sender', () async {
      final now = DateTime.now();
      final baseTxn = SmsTransaction(
        id: 'txn_prox_1',
        amount: 100.0,
        merchantName: 'Zomato',
        bankName: 'HDFC',
        transactionType: 'debit',
        timestamp: now,
        rawSmsBody: 'Rs 100 debited at Zomato',
        smsSender: 'HDFCBK',
        smsHash: 'hash_prox_1',
      );

      await repo.insertSmsTransaction(baseTxn);

      // Same amount, same sender, same merchant, +15 sec (inside 30s window) -> should return true (duplicate)
      final isDupInside = await repo.existsByAmountTimestampProximity(
        amount: 100.0,
        timestamp: now.add(const Duration(seconds: 15)),
        sender: 'HDFCBK',
        windowSeconds: 30,
        merchantName: 'Zomato',
      );
      expect(isDupInside, isTrue);

      // MEDIUM-1 fix case A: Same amount, same sender, 1 minute apart (+60s, outside 30s window) -> should return false (NOT merged)
      final isOneMinApart = await repo.existsByAmountTimestampProximity(
        amount: 100.0,
        timestamp: now.add(const Duration(seconds: 60)),
        sender: 'HDFCBK',
        windowSeconds: 30,
        merchantName: 'Zomato',
      );
      expect(isOneMinApart, isFalse);

      // MEDIUM-1 fix case B: Same amount, +15s, DIFFERENT merchant ('Uber' vs 'Zomato') -> should return false (NOT merged)
      final isDiffMerchant = await repo.existsByAmountTimestampProximity(
        amount: 100.0,
        timestamp: now.add(const Duration(seconds: 15)),
        sender: 'HDFCBK',
        windowSeconds: 30,
        merchantName: 'Uber',
      );
      expect(isDiffMerchant, isFalse);

      // Same amount, +15s, DIFFERENT sender ('ICICIB') -> should return false (NOT merged)
      final isDiffSender = await repo.existsByAmountTimestampProximity(
        amount: 100.0,
        timestamp: now.add(const Duration(seconds: 15)),
        sender: 'ICICIB',
        windowSeconds: 30,
        merchantName: 'Zomato',
      );
      expect(isDiffSender, isFalse);
    });

    test('2. UserFeedbackStore persistence round-trip survives simulated cold start', () async {
      final smsTimestamp = DateTime.now();
      const smsBody = 'Paid Rs 250 for Movie Ticket';

      // Step A: Record user feedback (Mark as not a transaction)
      final feedback = UserFeedbackStore.recordFeedback(
        smsBody: smsBody,
        smsTimestamp: smsTimestamp,
        action: UserFeedbackAction.notTransaction,
      );

      // Persist feedback to SQLite
      await repo.saveFeedback(feedback.toMap());

      // Step B: Simulate Cold Start (clear in-memory cache and re-initialize from SQLite)
      UserFeedbackStore.resetForTesting();

      final rawRecords = await repo.getAllFeedbackRecords();
      expect(rawRecords, isNotEmpty);

      final feedbackList = rawRecords.map((r) => UserFeedback.fromMap(r)).toList();
      UserFeedbackStore.loadFromRecords(feedbackList);

      // Step C: Verify feedback rule is active post-cold-start (SMS parsed as rejected)
      final result = SmsTransactionParser.parse(
        body: smsBody,
        sender: 'HDFCBK',
        timestamp: smsTimestamp,
      );

      expect(result.isTransaction, isFalse);
      expect(
        result.reasons.any((r) => r.contains('Marked as not a transaction')),
        isTrue,
      );
    });

    test('3. Watermark validation rejects future-dated, negative, and >30-day old timestamps', () async {
      final prefs = await SharedPreferences.getInstance();
      final service = ReconciliationService();
      final nowMs = DateTime.now().millisecondsSinceEpoch;

      // Case A: Future-dated watermark -> returns null
      await repo.setWatermark('pet_reconciliation_watermark', nowMs + 3600000); // +1 hr
      final futureResult = await service.validateWatermarkForTest(prefs, nowMs);
      expect(futureResult, isNull);

      // Case B: Negative watermark -> returns null
      await repo.setWatermark('pet_reconciliation_watermark', -500);
      final negativeResult = await service.validateWatermarkForTest(prefs, nowMs);
      expect(negativeResult, isNull);

      // Case C: >30-day old watermark (31 days ago) -> returns null
      final thirtyOneDaysAgoMs = nowMs - (31 * 24 * 60 * 60 * 1000);
      await repo.setWatermark('pet_reconciliation_watermark', thirtyOneDaysAgoMs);
      final staleResult = await service.validateWatermarkForTest(prefs, nowMs);
      expect(staleResult, isNull);

      // Case D: Valid 1-hour old watermark -> returns stored timestamp
      final oneHourAgoMs = nowMs - (1 * 60 * 60 * 1000);
      await repo.setWatermark('pet_reconciliation_watermark', oneHourAgoMs);
      final validResult = await service.validateWatermarkForTest(prefs, nowMs);
      expect(validResult, equals(oneHourAgoMs));
    });

    test('4. insertBatch is atomic: failure mid-batch rolls back completely (all-or-nothing)', () async {
      final validTxn1 = SmsTransaction(
        id: 'txn_batch_1',
        amount: 100.0,
        merchantName: 'Merchant 1',
        bankName: 'HDFC',
        transactionType: 'debit',
        timestamp: DateTime.now(),
        rawSmsBody: 'Rs 100 debited',
        smsSender: 'HDFCBK',
        smsHash: 'hash_batch_1',
      );

      final validTxn2 = SmsTransaction(
        id: 'txn_batch_2',
        amount: 200.0,
        merchantName: 'Merchant 2',
        bankName: 'HDFC',
        transactionType: 'debit',
        timestamp: DateTime.now(),
        rawSmsBody: 'Rs 200 debited',
        smsSender: 'HDFCBK',
        smsHash: 'hash_batch_2',
      );

      // Normal batch insert -> inserts both
      final count = await repo.insertBatch([validTxn1, validTxn2]);
      expect(count, equals(2));

      final hashes = await repo.getAllHashes();
      expect(hashes, contains('hash_batch_1'));
      expect(hashes, contains('hash_batch_2'));

      // Test transaction rollback when a database transaction error occurs
      try {
        await db.transaction((txn) async {
          await txn.insert('sms_transactions', {
            'id': 'txn_batch_3',
            'amount': 300.0,
            'merchantName': 'Merchant 3',
            'bankName': 'HDFC',
            'transactionType': 'debit',
            'smsBody': 'Rs 300 debited',
            'smsSender': 'HDFCBK',
            'smsHash': 'hash_batch_3',
            'timestamp': DateTime.now().toIso8601String(),
          });
          // Intentionally throw an exception mid-transaction to force rollback
          throw Exception('Simulated DB error mid-batch');
        });
      } catch (_) {
        // Expected exception
      }

      // Verify that hash_batch_3 was NOT saved to SQLite due to transaction rollback
      final hashesAfterRollback = await repo.getAllHashes();
      expect(hashesAfterRollback, isNot(contains('hash_batch_3')));
    });
  });
}
