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

  group('SQLite Migration v17 Tests (Alerts Centre 2.0 Upgrade)', () {
    test('Fresh install at v17 creates alerts table with all columns and composite indexes', () async {
      final tempDir = Directory.systemTemp.createTempSync();
      final dbPath = p.join(tempDir.path, 'v17_fresh_test.db');

      try {
        final db = await openDatabase(
          dbPath,
          version: 17,
          onCreate: (db, version) async {
            await DatabaseHelper().onCreateForTesting(db, version);
          },
        );

        // Verify alerts columns
        final alertCols = await db.rawQuery('PRAGMA table_info(alerts)');
        final colNames = alertCols.map((c) => c['name'] as String).toSet();

        expect(colNames.contains('id'), isTrue);
        expect(colNames.contains('type'), isTrue);
        expect(colNames.contains('title'), isTrue);
        expect(colNames.contains('message'), isTrue);
        expect(colNames.contains('createdAt'), isTrue);
        expect(colNames.contains('categoryId'), isTrue);
        expect(colNames.contains('isRead'), isTrue);
        expect(colNames.contains('alertKey'), isTrue);
        expect(colNames.contains('severity'), isTrue);
        expect(colNames.contains('stage'), isTrue);
        expect(colNames.contains('actionType'), isTrue);
        expect(colNames.contains('amount'), isTrue);
        expect(colNames.contains('targetAmount'), isTrue);
        expect(colNames.contains('ratio'), isTrue);
        expect(colNames.contains('period'), isTrue);
        expect(colNames.contains('transactionId'), isTrue);
        expect(colNames.contains('recurringPaymentId'), isTrue);
        expect(colNames.contains('goalId'), isTrue);
        expect(colNames.contains('isDismissed'), isTrue);
        expect(colNames.contains('updatedAt'), isTrue);
        expect(colNames.contains('expiresAt'), isTrue);
        expect(colNames.contains('resolvedAt'), isTrue);

        // Verify indexes
        final indexes = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='alerts'");
        final indexNames = indexes.map((i) => i['name'] as String).toSet();

        expect(indexNames.contains('idx_alert_key'), isTrue);
        expect(indexNames.contains('idx_alerts_active'), isTrue);
        expect(indexNames.contains('idx_alerts_type'), isTrue);
        expect(indexNames.contains('idx_alerts_period'), isTrue);

        await db.close();
      } finally {
        try {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        } catch (_) {}
      }
    });

    test('Migration from version 16 to 17 adds new columns, removes duplicates, and creates unique index', () async {
      final tempDir = Directory.systemTemp.createTempSync();
      final dbPath = p.join(tempDir.path, 'migration_v16_to_v17_test.db');

      try {
        // 1. Create database at version 16 with legacy alerts table
        var db = await openDatabase(
          dbPath,
          version: 16,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE alerts (
                id TEXT PRIMARY KEY,
                type TEXT NOT NULL,
                title TEXT NOT NULL,
                message TEXT NOT NULL,
                createdAt TEXT NOT NULL,
                categoryId TEXT,
                isRead INTEGER NOT NULL DEFAULT 0,
                alertKey TEXT
              )
            ''');

            // Insert historical rows, including duplicate alertKey rows
            await db.insert('alerts', {
              'id': 'a1',
              'type': 'budget',
              'title': 'Old Alert 1',
              'message': 'Older alert',
              'createdAt': '2026-07-01T10:00:00.000Z',
              'categoryId': 'cat_food',
              'isRead': 1,
              'alertKey': 'budget_cat_food_7',
            });
            await db.insert('alerts', {
              'id': 'a2',
              'type': 'budget',
              'title': 'Newer Duplicate Alert',
              'message': 'Newer duplicate alert',
              'createdAt': '2026-07-02T10:00:00.000Z',
              'categoryId': 'cat_food',
              'isRead': 0,
              'alertKey': 'budget_cat_food_7',
            });
          },
        );
        await db.close();

        // 2. Open at version 17 using DatabaseHelper migration
        db = await openDatabase(
          dbPath,
          version: 17,
          onUpgrade: (db, oldVersion, newVersion) async {
            await DatabaseHelper().onUpgradeForTesting(db, oldVersion, newVersion);
          },
        );

        // Verify duplicate alertKey deduplicated (retaining row a1)
        final rows = await db.query('alerts');
        expect(rows.length, equals(1));
        expect(rows.first['id'], equals('a1'));
        expect(rows.first['severity'], equals('warning'));
        expect(rows.first['isDismissed'], equals(0));

        // Verify unique index enforcement
        expect(
          () async => await db.insert('alerts', {
            'id': 'a3',
            'type': 'budget',
            'title': 'Another Dup',
            'message': 'Should fail uniqueness',
            'createdAt': '2026-07-03T10:00:00.000Z',
            'alertKey': 'budget_cat_food_7',
          }),
          throwsA(isA<DatabaseException>()),
        );

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
