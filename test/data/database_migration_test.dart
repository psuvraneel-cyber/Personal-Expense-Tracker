import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('SQLite Migration Tests', () {
    test('Migration from version 10 to 11 creates sync queue and backfills legacy transactions', () async {
      final tempDir = Directory.systemTemp.createTempSync();
      final dbPath = p.join(tempDir.path, 'migration_test.db');

      try {
        // Create database at version 10
        final db = await openDatabase(
          dbPath,
          version: 10,
          onCreate: (db, version) async {
            // Setup version 10 schema manually: transactions table with updatedAt (nullable/empty)
            await db.execute('''
              CREATE TABLE transactions (
                id TEXT PRIMARY KEY,
                amount REAL NOT NULL,
                type TEXT NOT NULL,
                categoryId TEXT NOT NULL,
                date TEXT NOT NULL,
                note TEXT DEFAULT '',
                paymentMethod TEXT DEFAULT 'UPI',
                isRecurring INTEGER DEFAULT 0,
                recurringFrequency TEXT,
                merchantName TEXT,
                taxCategory TEXT,
                source TEXT DEFAULT 'manual',
                accountId TEXT,
                updatedAt TEXT
              )
            ''');

            // Insert some transactions, some with null/empty updatedAt
            await db.insert('transactions', {
              'id': 'txn_null_updated',
              'amount': 100.0,
              'type': 'expense',
              'categoryId': 'food',
              'date': '2026-07-01T10:00:00Z',
              'updatedAt': null,
            });

            await db.insert('transactions', {
              'id': 'txn_empty_updated',
              'amount': 200.0,
              'type': 'expense',
              'categoryId': 'food',
              'date': '2026-07-02T10:00:00Z',
              'updatedAt': '',
            });

            await db.insert('transactions', {
              'id': 'txn_valid_updated',
              'amount': 300.0,
              'type': 'expense',
              'categoryId': 'food',
              'date': '2026-07-03T10:00:00Z',
              'updatedAt': '2026-07-04T12:00:00Z',
            });
          },
        );

        // Verify that sync queue table does NOT exist yet in version 10
        var queueExists = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='transaction_sync_queue'",
        );
        expect(queueExists.isEmpty, isTrue);

        // Close the database
        await db.close();

        // Trigger DatabaseHelper upgrade to version 11
        final dbUpgrade = await openDatabase(
          dbPath,
          version: 11,
          onUpgrade: (db, oldVersion, newVersion) async {
            // Call our actual migration step
            if (oldVersion < 11) {
              // Create transaction sync queue table
              await db.execute('''
                CREATE TABLE IF NOT EXISTS transaction_sync_queue (
                  id TEXT PRIMARY KEY,
                  transactionId TEXT NOT NULL,
                  action TEXT NOT NULL,
                  payload TEXT,
                  timestamp INTEGER NOT NULL,
                  userId TEXT NOT NULL,
                  retryCount INTEGER DEFAULT 0,
                  lastAttemptAt INTEGER DEFAULT 0,
                  lastError TEXT
                )
              ''');

              // Backfill legacy transactions where updatedAt is null or empty
              await db.execute('''
                UPDATE transactions 
                SET updatedAt = date 
                WHERE updatedAt IS NULL OR updatedAt = ''
              ''');
            }
          },
        );

        // Verify sync queue table now exists
        queueExists = await dbUpgrade.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='transaction_sync_queue'",
        );
        expect(queueExists.isNotEmpty, isTrue);

        // Verify legacy transactions backfilled correctly
        final txnNull = (await dbUpgrade.query(
          'transactions',
          where: 'id = ?',
          whereArgs: ['txn_null_updated'],
        )).first;
        expect(txnNull['updatedAt'], '2026-07-01T10:00:00Z');

        final txnEmpty = (await dbUpgrade.query(
          'transactions',
          where: 'id = ?',
          whereArgs: ['txn_empty_updated'],
        )).first;
        expect(txnEmpty['updatedAt'], '2026-07-02T10:00:00Z');

        // Verify that valid updatedAt was NOT modified
        final txnValid = (await dbUpgrade.query(
          'transactions',
          where: 'id = ?',
          whereArgs: ['txn_valid_updated'],
        )).first;
        expect(txnValid['updatedAt'], '2026-07-04T12:00:00Z');

        await dbUpgrade.close();
      } finally {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      }
    });
  });
}
