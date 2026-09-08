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

  group('SQLite Migration v16 Tests (Recurring Commitments Upgrade)', () {
    test('Fresh install at v16 creates all tables including recurring_payment_history with all columns', () async {
      final tempDir = Directory.systemTemp.createTempSync();
      final dbPath = p.join(tempDir.path, 'v16_fresh_test.db');

      try {
        final db = await openDatabase(
          dbPath,
          version: 16,
          onCreate: (db, version) async {
            await DatabaseHelper().onCreateForTesting(db, version);
          },
        );

        // Verify recurring_payments columns
        final recCols = await db.rawQuery('PRAGMA table_info(recurring_payments)');
        final colNames = recCols.map((c) => c['name'] as String).toSet();
        expect(colNames.contains('status'), isTrue);
        expect(colNames.contains('isAutopay'), isTrue);
        expect(colNames.contains('previousAmount'), isTrue);
        expect(colNames.contains('priceChangeDetectedAt'), isTrue);
        expect(colNames.contains('notes'), isTrue);
        expect(colNames.contains('createdAt'), isTrue);
        expect(colNames.contains('updatedAt'), isTrue);
        expect(colNames.contains('detectionReason'), isTrue);

        // Verify recurring_payment_history table exists
        final historyTable = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='recurring_payment_history'",
        );
        expect(historyTable.isNotEmpty, isTrue);

        await db.close();
      } finally {
        try {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        } catch (_) {}
      }
    });

    test('Migration from version 15 to 16 preserves existing rows and defaults new columns', () async {
      final tempDir = Directory.systemTemp.createTempSync();
      final dbPath = p.join(tempDir.path, 'migration_v15_to_v16_test.db');

      try {
        // 1. Create database at version 15 with legacy recurring_payments table schema
        final dbV15 = await openDatabase(
          dbPath,
          version: 15,
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
                source TEXT DEFAULT 'sms'
              )
            ''');
          },
        );

        // Insert legacy recurring payment row
        await dbV15.insert('recurring_payments', {
          'id': 'legacy_rec_1',
          'merchantName': 'Netflix',
          'amount': 199.0,
          'frequency': 'monthly',
          'lastPaidAt': '2026-07-01T10:00:00.000Z',
          'nextDueAt': '2026-08-01T10:00:00.000Z',
          'categoryId': 'entertainment',
          'confidence': 0.8,
          'source': 'sms',
        });

        await dbV15.close();

        // 2. Open at version 16 (triggers migration to 16)
        final dbV16 = await openDatabase(
          dbPath,
          version: 16,
          onUpgrade: (db, oldVersion, newVersion) async {
            if (oldVersion < 16) {
              final cols = await db.rawQuery('PRAGMA table_info(recurring_payments)');
              final colNames = cols.map((c) => c['name'] as String).toSet();

              if (!colNames.contains('status')) {
                await db.execute("ALTER TABLE recurring_payments ADD COLUMN status TEXT DEFAULT 'confirmed'");
              }
              if (!colNames.contains('isAutopay')) {
                await db.execute('ALTER TABLE recurring_payments ADD COLUMN isAutopay INTEGER DEFAULT 0');
              }
              if (!colNames.contains('previousAmount')) {
                await db.execute('ALTER TABLE recurring_payments ADD COLUMN previousAmount REAL');
              }
              if (!colNames.contains('priceChangeDetectedAt')) {
                await db.execute('ALTER TABLE recurring_payments ADD COLUMN priceChangeDetectedAt TEXT');
              }
              if (!colNames.contains('notes')) {
                await db.execute('ALTER TABLE recurring_payments ADD COLUMN notes TEXT');
              }
              if (!colNames.contains('createdAt')) {
                await db.execute('ALTER TABLE recurring_payments ADD COLUMN createdAt TEXT');
                await db.execute('UPDATE recurring_payments SET createdAt = lastPaidAt WHERE createdAt IS NULL');
              }
              if (!colNames.contains('updatedAt')) {
                await db.execute('ALTER TABLE recurring_payments ADD COLUMN updatedAt TEXT');
                await db.execute('UPDATE recurring_payments SET updatedAt = lastPaidAt WHERE updatedAt IS NULL');
              }
              if (!colNames.contains('detectionReason')) {
                await db.execute('ALTER TABLE recurring_payments ADD COLUMN detectionReason TEXT');
              }

              await db.execute('''
                CREATE TABLE IF NOT EXISTS recurring_payment_history (
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
            }
          },
        );

        // 3. Verify existing row is preserved and has new column defaults
        final rows = await dbV16.query('recurring_payments', where: 'id = ?', whereArgs: ['legacy_rec_1']);
        expect(rows.length, equals(1));
        final row = rows.first;
        expect(row['merchantName'], equals('Netflix'));
        expect(row['amount'], equals(199.0));
        expect(row['status'], equals('confirmed'));
        expect(row['isAutopay'], equals(0));
        expect(row['createdAt'], equals('2026-07-01T10:00:00.000Z'));

        await dbV16.close();
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
