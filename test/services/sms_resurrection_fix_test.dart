import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pet/data/database/database_helper.dart';
import 'package:pet/data/models/sms_transaction.dart';
import 'package:pet/data/repositories/sms_transaction_repository.dart';
import 'package:pet/providers/sms_transaction_provider.dart';
import 'package:pet/services/native_sms_reader.dart';
import 'package:pet/services/sms_parser/user_feedback_store.dart';

void main() {
  late Database db;
  late DatabaseHelper dbHelper;
  late SmsTransactionRepository repository;
  late Directory tempDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
  });

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('sms_resurrection_test_');
    final dbPath = p.join(tempDir.path, 'pet_test.db');
    db = await openDatabase(
      dbPath,
      version: 13,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE sms_transactions (
            id TEXT PRIMARY KEY,
            amount REAL NOT NULL,
            merchantName TEXT NOT NULL,
            bankName TEXT NOT NULL DEFAULT 'Unknown Bank',
            transactionType TEXT NOT NULL,
            transactionSubType TEXT DEFAULT 'payment',
            timestamp TEXT NOT NULL,
            rawSmsBody TEXT NOT NULL,
            smsSender TEXT DEFAULT '',
            smsHash TEXT NOT NULL UNIQUE,
            category TEXT DEFAULT 'Uncategorized',
            isVerified INTEGER DEFAULT 0,
            referenceId TEXT,
            upiId TEXT,
            confidence REAL DEFAULT 0.5,
            source TEXT DEFAULT 'sms',
            timestamp_is_approximate INTEGER DEFAULT 0
          )
        ''');

        await db.execute('''
          CREATE TABLE sms_processing_state (
            id TEXT PRIMARY KEY,
            smsHash TEXT NOT NULL UNIQUE,
            status TEXT NOT NULL,
            processedAt TEXT NOT NULL,
            reason TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE user_feedback (
            smsHash TEXT PRIMARY KEY,
            action TEXT NOT NULL,
            createdAt TEXT NOT NULL,
            confirmedAmount REAL
          )
        ''');

        await db.execute('''
          CREATE TABLE system_watermarks (
            key TEXT PRIMARY KEY,
            value INTEGER NOT NULL,
            updatedAt TEXT NOT NULL
          )
        ''');
      },
    );

    dbHelper = DatabaseHelper();
    DatabaseHelper.setTestDatabase(db);
    repository = SmsTransactionRepository(dbHelper: dbHelper);
    UserFeedbackStore.resetForTesting();
  });

  tearDown(() async {
    await db.close();
    DatabaseHelper.setTestDatabase(null);
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('SMS Auto-Detection Resurrection Bug Fix', () {
    final testTimestamp = DateTime(2026, 7, 24, 10, 30);
    const testSmsBody =
        'Rs. 500.00 debited from A/C XX1234 at SWIGGY via UPI Ref 61234567890.';
    const testSender = 'AD-HDFCBK';
    final testHash = SmsTransaction.generateHash(testSmsBody, testTimestamp);

    SmsTransaction createSampleTransaction({
      String id = 'txn_101',
      bool isVerified = true,
      double confidence = 0.9,
    }) {
      return SmsTransaction(
        id: id,
        amount: 500.0,
        merchantName: 'Swiggy',
        bankName: 'HDFC Bank',
        transactionType: 'debit',
        transactionSubType: 'payment',
        timestamp: testTimestamp,
        rawSmsBody: testSmsBody,
        smsSender: testSender,
        smsHash: testHash,
        category: 'Food',
        isVerified: isVerified,
        referenceId: '61234567890',
        confidence: confidence,
        source: 'sms',
      );
    }

    test('1. Delete transaction -> Refresh -> Still deleted', () async {
      final txn = createSampleTransaction();
      final inserted = await repository.insertSmsTransaction(txn);
      expect(inserted, isTrue);

      // Verify inserted in both tables
      expect(await repository.existsByHash(testHash), isTrue);
      final allBefore = await repository.getAllSmsTransactions();
      expect(allBefore.length, equals(1));

      // User deletes transaction
      await repository.deleteSmsTransaction(txn.id);

      // Verify deleted from sms_transactions, but retained in sms_processing_state as 'deleted'
      final allAfterDelete = await repository.getAllSmsTransactions();
      expect(allAfterDelete, isEmpty);

      final stateRows = await db.query(
        'sms_processing_state',
        where: 'smsHash = ?',
        whereArgs: [testHash],
      );
      expect(stateRows.length, equals(1));
      expect(stateRows.first['status'], equals('deleted'));

      // Simulate refresh / inbox scan attempting to re-insert the same SMS
      final reinsertAttempt = await repository.insertSmsTransaction(txn);
      expect(reinsertAttempt, isFalse, reason: 'Re-insertion must be blocked by deleted processing state');

      final allAfterRefresh = await repository.getAllSmsTransactions();
      expect(allAfterRefresh, isEmpty, reason: 'Transaction must remain deleted after refresh');
    });

    test('2. Delete transaction -> Restart app -> Still deleted', () async {
      final txn = createSampleTransaction();
      await repository.insertSmsTransaction(txn);
      await repository.deleteSmsTransaction(txn.id);

      // Simulate app restart by re-instantiating repository on same database
      final restartedRepository = SmsTransactionRepository(dbHelper: dbHelper);

      // Verify hash is recognized as processed/deleted
      expect(await restartedRepository.existsByHash(testHash), isTrue);

      // Attempting to batch insert candidate from inbox scan after restart
      final insertedCount = await restartedRepository.insertBatch([txn]);
      expect(insertedCount, equals(0), reason: 'Cold start scan must not recreate deleted transaction');

      final txns = await restartedRepository.getAllSmsTransactions();
      expect(txns, isEmpty);
    });

    test('3. Delete transaction -> Background SMS scan -> Still deleted', () async {
      final txn = createSampleTransaction();
      await repository.insertSmsTransaction(txn);
      await repository.deleteSmsTransaction(txn.id);

      // Simulate background worker reading native SMS candidates
      final candidateMessages = [
        NativeSmsMessage(
          address: testSender,
          body: testSmsBody,
          dateMillis: testTimestamp.millisecondsSinceEpoch,
          type: 1,
        ),
      ];

      final processedHashes = await repository.getAllHashes();
      final unparsed = candidateMessages.where((m) {
        final hash = SmsTransaction.generateHash(m.body, m.dateTime);
        return !processedHashes.contains(hash);
      }).toList();

      expect(unparsed, isEmpty, reason: 'Background scanner pre-filter must drop deleted SMS hash');
    });

    test('4. Not a transaction -> Refresh -> Never returns', () async {
      final provider = SmsTransactionProvider();

      final uncertainTxn = createSampleTransaction(
        id: 'uncertain_202',
        isVerified: false,
        confidence: 0.45,
      );
      await repository.insertSmsTransaction(uncertainTxn);
      await provider.loadTransactions();

      expect(provider.uncertainTransactions.length, equals(1));

      // User presses "Not a transaction" in Pending Review
      await provider.rejectUncertainTransaction(uncertainTxn.id);

      expect(provider.uncertainTransactions, isEmpty);

      // Verify processing state is set to 'ignored'
      final stateRows = await db.query(
        'sms_processing_state',
        where: 'smsHash = ?',
        whereArgs: [testHash],
      );
      expect(stateRows.length, equals(1));
      expect(stateRows.first['status'], equals('ignored'));

      // Simulate manual refresh scan
      final reinsertCount = await repository.insertBatch([uncertainTxn]);
      expect(reinsertCount, equals(0), reason: 'Ignored transaction must never be re-inserted on refresh');

      await provider.loadTransactions();
      expect(provider.transactions, isEmpty);
      expect(provider.uncertainTransactions, isEmpty);
    });

    test('5. Not a transaction -> Restart -> Never returns', () async {
      final provider = SmsTransactionProvider();
      final uncertainTxn = createSampleTransaction(
        id: 'uncertain_303',
        isVerified: false,
        confidence: 0.40,
      );
      await repository.insertSmsTransaction(uncertainTxn);
      await provider.loadTransactions();

      await provider.rejectUncertainTransaction(uncertainTxn.id);

      // Simulate app restart
      final newProvider = SmsTransactionProvider();
      await newProvider.loadTransactions();

      expect(newProvider.transactions, isEmpty);
      expect(newProvider.uncertainTransactions, isEmpty);

      // Background scan after restart
      final reinsert = await repository.insertSmsTransaction(uncertainTxn);
      expect(reinsert, isFalse);
    });

    test('6. Duplicate SMS scan -> Already processed hash -> Skipped O(1)', () async {
      final txn = createSampleTransaction();

      final firstInsert = await repository.insertSmsTransaction(txn);
      expect(firstInsert, isTrue);

      final secondInsert = await repository.insertSmsTransaction(txn);
      expect(secondInsert, isFalse, reason: 'Duplicate hash must be skipped');

      final batchResult = await repository.insertBatch([txn, txn]);
      expect(batchResult, equals(0));
    });

    test('7. Ignored SMS -> Parser executes -> Skipped', () async {
      // Pre-mark hash as ignored
      await repository.markSmsIgnored(testHash, reason: 'user_blacklisted');

      expect(await repository.existsByHash(testHash), isTrue);

      final txn = createSampleTransaction();
      final inserted = await repository.insertSmsTransaction(txn);
      expect(inserted, isFalse);
    });

    test('8. Delete wins over refresh, parser, and synchronization', () async {
      final txn = createSampleTransaction();
      await repository.insertSmsTransaction(txn);

      // Action 1: Delete
      await repository.deleteSmsTransaction(txn.id);

      // Action 2: Refresh attempt
      final refreshInsert = await repository.insertSmsTransaction(txn);
      expect(refreshInsert, isFalse);

      // Action 3: Batch re-import attempt
      final batchInsert = await repository.insertBatch([txn]);
      expect(batchInsert, equals(0));

      // Action 4: Ignored check
      final isProcessed = await repository.existsByHash(testHash);
      expect(isProcessed, isTrue);

      // Verify table state
      final storedTxns = await repository.getAllSmsTransactions();
      expect(storedTxns, isEmpty);
    });
  });
}
