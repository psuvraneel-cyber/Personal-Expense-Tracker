import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:pet/data/database/database_helper.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('SQLite Migration v18 Tests (Unified Financial Ingestion & Canonical Observation)', () {
    test('Fresh install at v18 creates financial_observations, merchant_learned_rules, and columns', () async {
      final tempDir = Directory.systemTemp.createTempSync();
      final dbPath = p.join(tempDir.path, 'v18_fresh_test.db');

      try {
        final db = await openDatabase(
          dbPath,
          version: 18,
          onCreate: (db, version) async {
            await DatabaseHelper().onCreateForTesting(db, version);
          },
        );

        // 1. Verify financial_observations table columns
        final obsCols = await db.rawQuery('PRAGMA table_info(financial_observations)');
        final obsColNames = obsCols.map((c) => c['name'] as String).toSet();

        expect(obsColNames.contains('observationId'), isTrue);
        expect(obsColNames.contains('source'), isTrue);
        expect(obsColNames.contains('sourceIdentifier'), isTrue);
        expect(obsColNames.contains('sender'), isTrue);
        expect(obsColNames.contains('packageName'), isTrue);
        expect(obsColNames.contains('title'), isTrue);
        expect(obsColNames.contains('body'), isTrue);
        expect(obsColNames.contains('normalizedText'), isTrue);
        expect(obsColNames.contains('receivedAt'), isTrue);
        expect(obsColNames.contains('sourceTimestamp'), isTrue);
        expect(obsColNames.contains('accountHint'), isTrue);
        expect(obsColNames.contains('schemaVersion'), isTrue);
        expect(obsColNames.contains('observationHash'), isTrue);
        expect(obsColNames.contains('sourceFingerprint'), isTrue);
        expect(obsColNames.contains('state'), isTrue);
        expect(obsColNames.contains('stateReason'), isTrue);
        expect(obsColNames.contains('confidence'), isTrue);
        expect(obsColNames.contains('canonicalTransactionId'), isTrue);

        // 2. Verify merchant_learned_rules columns
        final ruleCols = await db.rawQuery('PRAGMA table_info(merchant_learned_rules)');
        final ruleColNames = ruleCols.map((c) => c['name'] as String).toSet();

        expect(ruleColNames.contains('id'), isTrue);
        expect(ruleColNames.contains('identifier'), isTrue);
        expect(ruleColNames.contains('learnedMerchantName'), isTrue);
        expect(ruleColNames.contains('learnedCategoryId'), isTrue);

        // 3. Verify transactions table has sourceObservationId & sourceFingerprint
        final txnCols = await db.rawQuery('PRAGMA table_info(transactions)');
        final txnColNames = txnCols.map((c) => c['name'] as String).toSet();

        expect(txnColNames.contains('sourceObservationId'), isTrue);
        expect(txnColNames.contains('sourceFingerprint'), isTrue);

        // 4. Verify linked_accounts table has lastObservedBalance & accountTail
        final acctCols = await db.rawQuery('PRAGMA table_info(linked_accounts)');
        final acctColNames = acctCols.map((c) => c['name'] as String).toSet();

        expect(acctColNames.contains('accountTail'), isTrue);
        expect(acctColNames.contains('lastObservedBalance'), isTrue);
        expect(acctColNames.contains('lastObservedAt'), isTrue);
        expect(acctColNames.contains('bankName'), isTrue);

        // 5. Verify indexes
        final indexes = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='financial_observations'",
        );
        final indexNames = indexes.map((i) => i['name'] as String).toSet();

        expect(indexNames.contains('idx_obs_hash'), isTrue);
        expect(indexNames.contains('idx_obs_fingerprint'), isTrue);
        expect(indexNames.contains('idx_obs_state'), isTrue);

        await db.close();
      } finally {
        try {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        } catch (_) {}
      }
    });

    test('Migration from v17 to v18 adds new tables and backfills verified SMS rows without resurrecting deleted ones', () async {
      final tempDir = Directory.systemTemp.createTempSync();
      final dbPath = p.join(tempDir.path, 'v17_to_v18_migration_test.db');

      try {
        // 1. Create database at version 17 with transactions, sms_transactions, and sms_processing_state
        var db = await openDatabase(
          dbPath,
          version: 17,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE transactions (
                id TEXT PRIMARY KEY,
                amount REAL NOT NULL,
                type TEXT NOT NULL,
                categoryId TEXT NOT NULL,
                date TEXT NOT NULL,
                note TEXT,
                paymentMethod TEXT NOT NULL,
                isRecurring INTEGER NOT NULL DEFAULT 0,
                recurringFrequency TEXT,
                merchantName TEXT,
                taxCategory TEXT,
                source TEXT NOT NULL DEFAULT 'manual',
                accountId TEXT,
                updatedAt TEXT NOT NULL,
                recurringRuleId TEXT,
                occurrenceDate TEXT
              )
            ''');

            await db.execute('''
              CREATE TABLE sms_transactions (
                id TEXT PRIMARY KEY,
                amount REAL NOT NULL,
                merchantName TEXT NOT NULL,
                bankName TEXT NOT NULL,
                transactionType TEXT NOT NULL,
                transactionSubType TEXT,
                timestamp TEXT NOT NULL,
                rawSmsBody TEXT NOT NULL,
                smsSender TEXT NOT NULL,
                smsHash TEXT NOT NULL UNIQUE,
                category TEXT NOT NULL,
                referenceId TEXT,
                upiId TEXT,
                confidence REAL NOT NULL,
                isVerified INTEGER NOT NULL DEFAULT 0,
                source TEXT NOT NULL DEFAULT 'sms'
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

            // Insert 3 test SMS transactions:
            // SMS 1: Confirmed/Verified -> SHOULD BE BACKFILLED
            await db.insert('sms_transactions', {
              'id': 'sms_001',
              'amount': 450.0,
              'merchantName': 'Starbucks',
              'bankName': 'HDFC Bank',
              'transactionType': 'debit',
              'timestamp': '2026-08-15T10:30:00.000Z',
              'rawSmsBody': 'Rs 450 debited at Starbucks',
              'smsSender': 'HDFCBK',
              'smsHash': 'hash_001',
              'category': 'Food & Dining',
              'referenceId': 'REF12345',
              'confidence': 0.95,
              'isVerified': 1,
              'source': 'sms',
            });

            // SMS 2: High confidence, but user rejected/deleted -> MUST NOT BE RESURRECTED
            await db.insert('sms_transactions', {
              'id': 'sms_002',
              'amount': 1200.0,
              'merchantName': 'Electricity Bill',
              'bankName': 'SBI',
              'transactionType': 'debit',
              'timestamp': '2026-08-16T11:00:00.000Z',
              'rawSmsBody': 'Rs 1200 debited for Bill',
              'smsSender': 'SBIINB',
              'smsHash': 'hash_002',
              'category': 'Bills & Utilities',
              'confidence': 0.85,
              'isVerified': 0,
              'source': 'sms',
            });
            await db.insert('sms_processing_state', {
              'id': 'sms_002',
              'smsHash': 'hash_002',
              'status': 'rejected',
              'processedAt': '2026-08-16T11:05:00.000Z',
              'reason': 'user_rejected',
            });

            // SMS 3: Low confidence, unverified -> SHOULD NOT BE AUTO-BACKFILLED TO CORE LEDGER
            await db.insert('sms_transactions', {
              'id': 'sms_003',
              'amount': 50.0,
              'merchantName': 'Tea Stall',
              'bankName': 'Paytm',
              'transactionType': 'debit',
              'timestamp': '2026-08-17T12:00:00.000Z',
              'rawSmsBody': 'Rs 50 paid to vendor',
              'smsSender': 'PAYTM',
              'smsHash': 'hash_003',
              'category': 'Uncategorized',
              'confidence': 0.50,
              'isVerified': 0,
              'source': 'sms',
            });
          },
        );
        await db.close();

        // 2. Open at version 18 using DatabaseHelper migration
        db = await openDatabase(
          dbPath,
          version: 18,
          onUpgrade: (db, oldVersion, newVersion) async {
            await DatabaseHelper().onUpgradeForTesting(db, oldVersion, newVersion);
          },
        );

        // Verify backfilled transactions in canonical ledger
        final coreTxns = await db.query('transactions');
        expect(coreTxns.length, equals(1), reason: 'Only verified/eligible SMS should be backfilled');
        expect(coreTxns.first['amount'], equals(450.0));
        expect(coreTxns.first['merchantName'], equals('Starbucks'));
        expect(coreTxns.first['sourceObservationId'], equals('sms_001'));
        expect(coreTxns.first['sourceFingerprint'], isNotNull);

        // Verify financial_observations table
        final observations = await db.query('financial_observations');
        expect(observations.length, equals(1));
        expect(observations.first['observationId'], equals('sms_001'));
        expect(observations.first['state'], equals('promoted'));

        // 3. Test Idempotency: Running migration on upgrade should not duplicate rows
        await DatabaseHelper().onUpgradeForTesting(db, 17, 18);

        final coreTxnsAfter = await db.query('transactions');
        expect(coreTxnsAfter.length, equals(1), reason: 'Re-running migration must be strictly idempotent');

        await db.close();
      } finally {
        try {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        } catch (_) {}
      }
    });
  });
}
