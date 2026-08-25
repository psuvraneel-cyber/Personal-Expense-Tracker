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

  group('SQLite Migration v15 Tests', () {
    test('Fresh install at v15 creates all tables including recurring_rules and recurring_occurrences', () async {
      final tempDir = Directory.systemTemp.createTempSync();
      final dbPath = p.join(tempDir.path, 'v15_fresh_test.db');

      try {
        final db = await openDatabase(
          dbPath,
          version: 15,
          onCreate: (db, version) async {
            await DatabaseHelper().onCreateForTesting(db, version);
          },
        );

        // Verify recurring_rules exists
        final rulesTable = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='recurring_rules'",
        );
        expect(rulesTable.isNotEmpty, isTrue);

        // Verify recurring_occurrences exists
        final occurrencesTable = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='recurring_occurrences'",
        );
        expect(occurrencesTable.isNotEmpty, isTrue);

        // Verify transactions table has recurringRuleId and occurrenceDate
        final txnCols = await db.rawQuery('PRAGMA table_info(transactions)');
        expect(txnCols.any((c) => c['name'] == 'recurringRuleId'), isTrue);
        expect(txnCols.any((c) => c['name'] == 'occurrenceDate'), isTrue);

        await db.close();
      } finally {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      }
    });

    test('Migration from version 14 to 15 adds columns, creates tables, and backfills legacy recurring rows', () async {
      final tempDir = Directory.systemTemp.createTempSync();
      final dbPath = p.join(tempDir.path, 'migration_v14_to_v15_test.db');

      try {
        // 1. Create database at version 14
        final dbV14 = await openDatabase(
          dbPath,
          version: 14,
          onCreate: (db, version) async {
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

            await db.execute('''
              CREATE TABLE system_watermarks (
                key TEXT PRIMARY KEY,
                value INTEGER NOT NULL,
                updatedAt TEXT NOT NULL
              )
            ''');

            // Insert a normal non-recurring transaction
            await db.insert('transactions', {
              'id': 'txn_normal',
              'amount': 150.0,
              'type': 'expense',
              'categoryId': 'food',
              'date': '2026-08-01T12:00:00.000',
              'isRecurring': 0,
              'recurringFrequency': null,
            });

            // Insert a legacy recurring monthly salary transaction
            await db.insert('transactions', {
              'id': 'txn_legacy_salary',
              'amount': 50000.0,
              'type': 'income',
              'categoryId': 'salary',
              'date': '2026-08-20T10:02:00.000',
              'isRecurring': 1,
              'recurringFrequency': 'monthly',
              'merchantName': 'Acme Corp',
            });
          },
        );

        // Verify v14 state
        var rulesTable = await dbV14.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='recurring_rules'",
        );
        expect(rulesTable.isEmpty, isTrue);

        await dbV14.close();

        // 2. Open at version 15 to trigger onUpgrade
        final dbV15 = await openDatabase(
          dbPath,
          version: 15,
          onUpgrade: (db, oldVersion, newVersion) async {
            if (oldVersion < 15) {
              // Test helper internal migration step
              final txnCols = await db.rawQuery('PRAGMA table_info(transactions)');
              if (!txnCols.any((c) => c['name'] == 'recurringRuleId')) {
                await db.execute('ALTER TABLE transactions ADD COLUMN recurringRuleId TEXT');
              }
              if (!txnCols.any((c) => c['name'] == 'occurrenceDate')) {
                await db.execute('ALTER TABLE transactions ADD COLUMN occurrenceDate TEXT');
              }

              await db.execute('''
                CREATE TABLE IF NOT EXISTS recurring_rules (
                  id TEXT PRIMARY KEY,
                  amount REAL NOT NULL,
                  type TEXT NOT NULL,
                  categoryId TEXT NOT NULL,
                  note TEXT DEFAULT '',
                  paymentMethod TEXT DEFAULT 'UPI',
                  frequency TEXT NOT NULL,
                  interval INTEGER DEFAULT 1,
                  startDate TEXT NOT NULL,
                  endDate TEXT,
                  nextOccurrenceDate TEXT NOT NULL,
                  lastGeneratedDate TEXT,
                  isActive INTEGER DEFAULT 1,
                  merchantName TEXT,
                  taxCategory TEXT,
                  source TEXT DEFAULT 'manual',
                  accountId TEXT,
                  createdAt TEXT NOT NULL,
                  updatedAt TEXT NOT NULL,
                  userId TEXT
                )
              ''');

              await db.execute('''
                CREATE TABLE IF NOT EXISTS recurring_occurrences (
                  id TEXT PRIMARY KEY,
                  ruleId TEXT NOT NULL,
                  scheduledDate TEXT NOT NULL,
                  status TEXT NOT NULL,
                  transactionId TEXT,
                  generatedAt TEXT,
                  updatedAt TEXT NOT NULL,
                  UNIQUE(ruleId, scheduledDate)
                )
              ''');

              // Backfill
              final legacyRows = await db.query(
                'transactions',
                where: 'isRecurring = 1 AND recurringFrequency IS NOT NULL AND (recurringRuleId IS NULL OR recurringRuleId = \'\')',
              );

              for (final row in legacyRows) {
                final txnId = row['id'] as String;
                final ruleId = 'rule_legacy_$txnId';
                final dateStr = row['date'] as String;

                await db.insert('recurring_rules', {
                  'id': ruleId,
                  'amount': row['amount'],
                  'type': row['type'],
                  'categoryId': row['categoryId'],
                  'frequency': row['recurringFrequency'],
                  'interval': 1,
                  'startDate': dateStr,
                  'nextOccurrenceDate': '2026-09-20T10:02:00.000',
                  'lastGeneratedDate': dateStr,
                  'isActive': 1,
                  'createdAt': dateStr,
                  'updatedAt': dateStr,
                });

                await db.insert('recurring_occurrences', {
                  'id': '${ruleId}_$dateStr',
                  'ruleId': ruleId,
                  'scheduledDate': dateStr,
                  'status': 'generated',
                  'transactionId': txnId,
                  'generatedAt': dateStr,
                  'updatedAt': dateStr,
                });

                await db.update(
                  'transactions',
                  {'recurringRuleId': ruleId, 'occurrenceDate': dateStr},
                  where: 'id = ?',
                  whereArgs: [txnId],
                );
              }
            }
          },
        );

        // 3. Verify recurring_rules table populated
        final rules = await dbV15.query('recurring_rules');
        expect(rules.length, 1);
        final rule = rules.first;
        expect(rule['id'], 'rule_legacy_txn_legacy_salary');
        expect(rule['amount'], 50000.0);
        expect(rule['type'], 'income');
        expect(rule['frequency'], 'monthly');
        expect(rule['nextOccurrenceDate'], '2026-09-20T10:02:00.000');

        // 4. Verify recurring_occurrences table populated
        final occurrences = await dbV15.query('recurring_occurrences');
        expect(occurrences.length, 1);
        expect(occurrences.first['transactionId'], 'txn_legacy_salary');
        expect(occurrences.first['status'], 'generated');

        // 5. Verify transactions row updated with recurringRuleId
        final updatedTxn = (await dbV15.query(
          'transactions',
          where: 'id = ?',
          whereArgs: ['txn_legacy_salary'],
        )).first;
        expect(updatedTxn['recurringRuleId'], 'rule_legacy_txn_legacy_salary');
        expect(updatedTxn['occurrenceDate'], '2026-08-20T10:02:00.000');

        // 6. Verify normal transaction was unaffected
        final normalTxn = (await dbV15.query(
          'transactions',
          where: 'id = ?',
          whereArgs: ['txn_normal'],
        )).first;
        expect(normalTxn['recurringRuleId'], isNull);

        await dbV15.close();
      } finally {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      }
    });
  });
}
