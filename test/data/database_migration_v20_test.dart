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

  group('SQLite Migration v20 Tests (Weekly Limits Partial Uniqueness & Goal History Audit)', () {
    test('Fresh install at v20 creates weekly_limits with partial indexes and enriched goal_history', () async {
      final tempDir = Directory.systemTemp.createTempSync();
      final dbPath = p.join(tempDir.path, 'v20_fresh_test.db');

      try {
        final db = await openDatabase(
          dbPath,
          version: 20,
          onCreate: (db, version) async {
            await DatabaseHelper().onCreateForTesting(db, version);
          },
        );

        // 1. Verify weekly_limits columns and indexes
        final limitCols = await db.rawQuery('PRAGMA table_info(weekly_limits)');
        final limitColNames = limitCols.map((c) => c['name'] as String).toSet();
        expect(limitColNames.contains('id'), isTrue);
        expect(limitColNames.contains('categoryId'), isTrue);
        expect(limitColNames.contains('categoryName'), isTrue);
        expect(limitColNames.contains('weeklyLimit'), isTrue);
        expect(limitColNames.contains('recurrencePolicy'), isTrue);
        expect(limitColNames.contains('periodStart'), isTrue);
        expect(limitColNames.contains('isActive'), isTrue);
        expect(limitColNames.contains('createdAt'), isTrue);
        expect(limitColNames.contains('updatedAt'), isTrue);

        final limitIndexes = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='weekly_limits'");
        final indexNames = limitIndexes.map((i) => i['name'] as String).toSet();
        expect(indexNames.contains('idx_weekly_limits_recurring'), isTrue);
        expect(indexNames.contains('idx_weekly_limits_one_off'), isTrue);

        // 2. Verify goal_history enriched audit columns
        final historyCols = await db.rawQuery('PRAGMA table_info(goal_history)');
        final historyColNames = historyCols.map((c) => c['name'] as String).toSet();
        expect(historyColNames.contains('previousAmount'), isTrue);
        expect(historyColNames.contains('resultingAmount'), isTrue);
        expect(historyColNames.contains('source'), isTrue);
        expect(historyColNames.contains('transactionId'), isTrue);

        await db.close();
      } finally {
        try {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        } catch (_) {}
      }
    });

    test('Migration from v19 to v20 preserves existing weekly_limits and goal_history, enables coexisting recurring and one-off limits', () async {
      final tempDir = Directory.systemTemp.createTempSync();
      final dbPath = p.join(tempDir.path, 'v19_to_v20_migration_test.db');

      try {
        // 1. Create database at version 19 with legacy strict UNIQUE on categoryId
        var db = await openDatabase(
          dbPath,
          version: 19,
          onCreate: (db, version) async {
            // Core minimum tables needed for v19
            await db.execute('''
              CREATE TABLE saving_goals (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                targetAmount REAL NOT NULL,
                currentAmount REAL NOT NULL DEFAULT 0.0,
                targetDate TEXT,
                emoji TEXT,
                colorValue INTEGER,
                isCompleted INTEGER NOT NULL DEFAULT 0,
                isPaused INTEGER NOT NULL DEFAULT 0,
                createdAt TEXT NOT NULL,
                updatedAt TEXT NOT NULL,
                notes TEXT
              )
            ''');

            await db.execute('''
              CREATE TABLE goal_history (
                id TEXT PRIMARY KEY,
                goalId TEXT NOT NULL,
                amount REAL NOT NULL,
                actionType TEXT NOT NULL,
                createdAt TEXT NOT NULL,
                note TEXT,
                FOREIGN KEY (goalId) REFERENCES saving_goals (id) ON DELETE CASCADE
              )
            ''');

            // Legacy v19 weekly_limits table with categoryId TEXT UNIQUE NOT NULL
            await db.execute('''
              CREATE TABLE weekly_limits (
                id TEXT PRIMARY KEY,
                categoryId TEXT UNIQUE NOT NULL,
                categoryName TEXT NOT NULL,
                weeklyLimit REAL NOT NULL,
                createdAt TEXT NOT NULL,
                updatedAt TEXT NOT NULL,
                isActive INTEGER DEFAULT 1,
                periodStart TEXT,
                recurrencePolicy TEXT DEFAULT 'recurring'
              )
            ''');

            // Insert initial v19 data
            await db.insert('saving_goals', {
              'id': 'goal_emergency',
              'name': 'Emergency Fund',
              'targetAmount': 50000.0,
              'currentAmount': 10000.0,
              'createdAt': '2026-01-01T00:00:00.000Z',
              'updatedAt': '2026-01-01T00:00:00.000Z',
            });

            await db.insert('goal_history', {
              'id': 'hist_001',
              'goalId': 'goal_emergency',
              'actionType': 'topUp',
              'amount': 10000.0,
              'createdAt': '2026-01-01T10:00:00.000Z',
              'note': 'Initial seed',
            });

            await db.insert('weekly_limits', {
              'id': 'rule_food_rec',
              'categoryId': 'cat_food',
              'categoryName': 'Food & Dining',
              'weeklyLimit': 2500.0,
              'recurrencePolicy': 'recurring',
              'periodStart': null,
              'createdAt': '2026-01-01T00:00:00.000Z',
              'updatedAt': '2026-01-01T00:00:00.000Z',
              'isActive': 1,
            });
          },
        );
        await db.close();

        // 2. Open at version 20 to trigger migration
        db = await openDatabase(
          dbPath,
          version: 20,
          onUpgrade: (db, oldVersion, newVersion) async {
            await DatabaseHelper().onUpgradeForTesting(db, oldVersion, newVersion);
          },
        );

        // Verify existing rows survived migration
        final limitsAfter = await db.query('weekly_limits');
        expect(limitsAfter.length, equals(1));
        expect(limitsAfter.first['id'], equals('rule_food_rec'));
        expect(limitsAfter.first['categoryId'], equals('cat_food'));
        expect(limitsAfter.first['categoryName'], equals('Food & Dining'));
        expect(limitsAfter.first['weeklyLimit'], equals(2500.0));

        final historyAfter = await db.query('goal_history');
        expect(historyAfter.length, equals(1));
        expect(historyAfter.first['id'], equals('hist_001'));
        expect(historyAfter.first['actionType'], equals('topUp'));
        expect(historyAfter.first['amount'], equals(10000.0));
        expect(historyAfter.first.containsKey('previousAmount'), isTrue);
        expect(historyAfter.first.containsKey('resultingAmount'), isTrue);
        expect(historyAfter.first.containsKey('source'), isTrue);
        expect(historyAfter.first.containsKey('transactionId'), isTrue);

        // 3. Verify that we can now co-exist a recurring limit and a one-off limit for the same category
        await db.insert('weekly_limits', {
          'id': 'rule_food_oneoff_w10',
          'categoryId': 'cat_food',
          'categoryName': 'Food & Dining',
          'weeklyLimit': 4000.0,
          'recurrencePolicy': 'oneOff',
          'periodStart': '2026-03-02T00:00:00.000Z',
          'createdAt': '2026-03-02T00:00:00.000Z',
          'updatedAt': '2026-03-02T00:00:00.000Z',
          'isActive': 1,
        });

        final limitsWithOneOff = await db.query('weekly_limits', where: 'categoryId = ?', whereArgs: ['cat_food']);
        expect(limitsWithOneOff.length, equals(2), reason: 'Recurring and one-off limits can co-exist for the same category');

        // 4. Verify partial index enforcement: duplicate recurring limit should FAIL
        expect(
          () => db.insert('weekly_limits', {
            'id': 'rule_food_rec_dup',
            'categoryId': 'cat_food',
            'categoryName': 'Food & Dining',
            'weeklyLimit': 3000.0,
            'recurrencePolicy': 'recurring',
            'createdAt': '2026-03-02T00:00:00.000Z',
            'updatedAt': '2026-03-02T00:00:00.000Z',
            'isActive': 1,
          }),
          throwsA(isA<DatabaseException>()),
          reason: 'Duplicate recurring rule for same category must be rejected by partial unique index',
        );

        // 5. Verify partial index enforcement: duplicate one-off for SAME periodStart should FAIL
        expect(
          () => db.insert('weekly_limits', {
            'id': 'rule_food_oneoff_dup',
            'categoryId': 'cat_food',
            'categoryName': 'Food & Dining',
            'weeklyLimit': 5000.0,
            'recurrencePolicy': 'oneOff',
            'periodStart': '2026-03-02T00:00:00.000Z',
            'createdAt': '2026-03-02T00:00:00.000Z',
            'updatedAt': '2026-03-02T00:00:00.000Z',
            'isActive': 1,
          }),
          throwsA(isA<DatabaseException>()),
          reason: 'Duplicate one-off rule for same category and periodStart must be rejected',
        );

        // 6. Test Idempotency: Re-running migration v19 -> v20 should succeed cleanly
        await DatabaseHelper().onUpgradeForTesting(db, 19, 20);

        final limitsFinal = await db.query('weekly_limits');
        expect(limitsFinal.length, equals(2), reason: 'Re-running migration must not alter existing rows');

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
