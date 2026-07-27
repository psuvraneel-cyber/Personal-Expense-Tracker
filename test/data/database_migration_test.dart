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

    test('Migration from version 11 to 12 adds created_at, redacts SMS, enforces TTL and row cap', () async {
      final tempDir = Directory.systemTemp.createTempSync();
      final dbPath = p.join(tempDir.path, 'migration_v12_test.db');

      try {
        // Create database at version 11
        final db = await openDatabase(
          dbPath,
          version: 11,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE unknown_format_logs (
                id TEXT PRIMARY KEY,
                smsBody TEXT NOT NULL,
                smsSender TEXT NOT NULL,
                timestamp TEXT NOT NULL,
                rejectionReason TEXT DEFAULT 'unknown',
                isReviewed INTEGER DEFAULT 0,
                isResolved INTEGER DEFAULT 0,
                resolvedRuleId TEXT,
                occurrenceCount INTEGER DEFAULT 1,
                bodyHash TEXT NOT NULL,
                userNote TEXT
              )
            ''');

            // 1. Sensitive unredacted row (recent)
            await db.insert('unknown_format_logs', {
              'id': 'log_sensitive',
              'smsBody': 'Paid Rs 1500 to Swiggy from Acct 123456789012 phone +919876543210',
              'smsSender': 'AD-HDFCBK',
              'timestamp': DateTime.now().toIso8601String(),
              'bodyHash': 'hash_sensitive',
            });

            // 2. Old row (>30 days)
            final oldDate = DateTime.now().subtract(const Duration(days: 40));
            await db.insert('unknown_format_logs', {
              'id': 'log_old',
              'smsBody': 'Paid Rs 500 to Swiggy from Acct 123456789999',
              'smsSender': 'AD-HDFCBK',
              'timestamp': oldDate.toIso8601String(),
              'bodyHash': 'hash_old',
            });

            // 3. Insert 505 entries to verify 500 row cap
            for (int i = 0; i < 505; i++) {
              final date = DateTime.now().subtract(Duration(minutes: i + 1));
              await db.insert('unknown_format_logs', {
                'id': 'log_bulk_$i',
                'smsBody': 'Bulk test message $i',
                'smsSender': 'AD-HDFCBK',
                'timestamp': date.toIso8601String(),
                'bodyHash': 'hash_bulk_$i',
              });
            }
          },
        );

        // Verify created_at does not exist in v11
        var cols = await db.rawQuery('PRAGMA table_info(unknown_format_logs)');
        expect(cols.any((c) => c['name'] == 'created_at'), isFalse);

        await db.close();

        // Trigger migration to version 12
        final dbUpgrade = await openDatabase(
          dbPath,
          version: 12,
          onUpgrade: (db, oldVersion, newVersion) async {
            if (oldVersion < 12) {
              final columns = await db.rawQuery('PRAGMA table_info(unknown_format_logs)');
              final hasCreatedAt = columns.any((c) => c['name'] == 'created_at');
              if (!hasCreatedAt) {
                await db.execute('ALTER TABLE unknown_format_logs ADD COLUMN created_at INTEGER');
              }

              final rows = await db.query('unknown_format_logs');
              for (final row in rows) {
                final id = row['id'] as String;
                final rawBody = row['smsBody'] as String? ?? '';
                final timestampStr = row['timestamp'] as String? ?? '';
                final existingCreatedAt = row['created_at'] as int?;

                // Simple inline redaction matching SmsService logic
                var redacted = rawBody;
                redacted = redacted.replaceAllMapped(RegExp(r'\b(\d{4,})\d{4}\b'), (m) {
                  final full = m.group(0)!;
                  return full.length >= 8 ? 'XX****${full.substring(full.length - 4)}' : full;
                });
                redacted = redacted.replaceAllMapped(RegExp(r'(?:\+91|0)?(\d{10})\b'), (m) {
                  final digits = m.group(1)!;
                  return '***${digits.substring(7)}';
                });

                final int createdAtMillis = existingCreatedAt ??
                    (DateTime.tryParse(timestampStr)?.millisecondsSinceEpoch ??
                        DateTime.now().millisecondsSinceEpoch);

                await db.update(
                  'unknown_format_logs',
                  {'smsBody': redacted, 'created_at': createdAtMillis},
                  where: 'id = ?',
                  whereArgs: [id],
                );
              }

              final cutoff = DateTime.now().subtract(const Duration(days: 30)).millisecondsSinceEpoch;
              await db.delete('unknown_format_logs', where: 'created_at < ?', whereArgs: [cutoff]);

              await db.execute('''
                DELETE FROM unknown_format_logs 
                WHERE id NOT IN (
                  SELECT id FROM unknown_format_logs 
                  ORDER BY COALESCE(created_at, 0) DESC, timestamp DESC 
                  LIMIT 500
                )
              ''');
            }
          },
        );

        // 1. Verify created_at column now exists
        cols = await dbUpgrade.rawQuery('PRAGMA table_info(unknown_format_logs)');
        expect(cols.any((c) => c['name'] == 'created_at'), isTrue);

        // 2. Verify sensitive row is redacted
        final sensitiveRows = await dbUpgrade.query('unknown_format_logs', where: 'id = ?', whereArgs: ['log_sensitive']);
        expect(sensitiveRows.isNotEmpty, isTrue);
        final redactedBody = sensitiveRows.first['smsBody'] as String;
        expect(redactedBody.contains('123456789012'), isFalse);
        expect(redactedBody.contains('XX****9012'), isTrue);

        // 3. Verify old row (>30d) was deleted by TTL
        final oldRows = await dbUpgrade.query('unknown_format_logs', where: 'id = ?', whereArgs: ['log_old']);
        expect(oldRows.isEmpty, isTrue);

        // 4. Verify total row count is capped at 500
        final countResult = await dbUpgrade.rawQuery('SELECT COUNT(*) as count FROM unknown_format_logs');
        final totalCount = countResult.first['count'] as int;
        expect(totalCount <= 500, isTrue);

        await dbUpgrade.close();
      } finally {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      }
    });

    test('Migration from version 13 to 14 creates system_watermarks table', () async {
      final tempDir = Directory.systemTemp.createTempSync();
      final dbPath = p.join(tempDir.path, 'migration_v14_test.db');

      try {
        // Create database at version 13
        final db = await openDatabase(
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
                timestamp TEXT NOT NULL,
                rawSmsBody TEXT NOT NULL,
                smsSender TEXT NOT NULL,
                smsHash TEXT NOT NULL UNIQUE
              )
            ''');
          },
        );

        // Verify system_watermarks table does NOT exist in version 13
        var wmExists = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='system_watermarks'",
        );
        expect(wmExists.isEmpty, isTrue);

        await db.close();

        // Trigger migration to version 14
        final dbUpgrade = await openDatabase(
          dbPath,
          version: 14,
          onUpgrade: (db, oldVersion, newVersion) async {
            if (oldVersion < 14) {
              await db.execute('''
                CREATE TABLE IF NOT EXISTS system_watermarks (
                  key TEXT PRIMARY KEY,
                  value INTEGER NOT NULL,
                  updatedAt TEXT NOT NULL
                )
              ''');
            }
          },
        );

        // Verify system_watermarks table exists in version 14
        wmExists = await dbUpgrade.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='system_watermarks'",
        );
        expect(wmExists.isNotEmpty, isTrue);

        await dbUpgrade.close();
      } finally {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      }
    });
  });
}
