import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pet/core/constants/categories.dart';
import 'package:pet/data/database/database_helper.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/services/category_mapper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Auto-imported transactions used to be filed under category IDs that do not
/// exist (`cat_other`, `cat_gifts`, `cat_investments`) and showed as "Unknown".
void main() {
  final realIds = defaultCategories.map((c) => c.id).toSet();

  test('every ID the mapper can return is a real category', () {
    expect(CategoryMapper.allMappedIds.difference(realIds), isEmpty);
  });

  test('unmatched merchants fall back to real Other categories', () {
    final expense = CategoryMapper.mapToCategoryId(merchantName: 'Q688163989');
    final income = CategoryMapper.mapToCategoryId(
      merchantName: 'UPI credit',
      isIncome: true,
    );
    expect(expense, 'cat_other_expense');
    expect(income, 'cat_other_income');
    expect(realIds, containsAll([expense, income]));
  });

  test('legacy IDs map to real categories', () {
    for (final id in CategoryMapper.legacyCategoryIds.values) {
      expect(realIds, contains(id));
    }
    expect(
        CategoryMapper.canonicalCategoryId('cat_other'), 'cat_other_expense');
    expect(CategoryMapper.canonicalCategoryId('cat_food'), 'cat_food');
  });

  test('rows from the cloud with a legacy ID are re-filed on read', () {
    final txn = TransactionRecord.fromFirestore('t1', {
      'amount': 40,
      'type': 'expense',
      'categoryId': 'cat_other',
    });
    expect(txn.categoryId, 'cat_other_expense');
  });

  group('v21 → v22 migration', () {
    late Database db;
    late Directory dir;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('mig_v22_');
      db = await openDatabase(
        p.join(dir.path, 'pet.db'),
        version: kDatabaseVersion,
        onCreate: (db, v) => DatabaseHelper().onCreateForTesting(db, v),
      );
    });

    tearDown(() async {
      await db.close();
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });

    Map<String, Object?> row(String id, String categoryId) => {
          'id': id,
          'amount': 110.0,
          'type': 'expense',
          'categoryId': categoryId,
          'date': DateTime(2026, 10, 12).toIso8601String(),
          'source': 'sms',
          'updatedAt': DateTime(2026, 10, 12).toIso8601String(),
        };

    test('re-files legacy IDs and queues the change for sync', () async {
      await db.insert('transactions', row('a', 'cat_other'));
      await db.insert('transactions', row('b', 'cat_gifts'));
      await db.insert('transactions', row('c', 'cat_food'));

      await DatabaseHelper().onUpgradeForTesting(db, 21, 22);

      final byId = {
        for (final r in await db.query('transactions'))
          r['id']: r['categoryId'],
      };
      expect(byId, {
        'a': 'cat_other_expense',
        'b': 'cat_gift_income',
        'c': 'cat_food',
      });

      final queued = await db.query(
        'transaction_sync_queue',
        where: "action = 'update'",
      );
      expect(queued.map((r) => r['transactionId']).toSet(), {'a', 'b'});
    });
  });
}
