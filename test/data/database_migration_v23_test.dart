import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pet/core/constants/categories.dart';
import 'package:pet/data/database/database_helper.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/transaction.dart';

/// v22 → v23: the "From people" category and the trusted_templates table.
void main() {
  late Database db;
  late Directory dir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('mig_v23_');
    db = await openDatabase(
      p.join(dir.path, 'pet.db'),
      version: kDatabaseVersion,
      onCreate: (db, v) => DatabaseHelper().onCreateForTesting(db, v),
    );
    // Simulate a v22 database: no new category, no trusted templates.
    await db.delete('categories',
        where: 'id = ?', whereArgs: [kFromPeopleCategoryId]);
    await db.execute('DROP TABLE IF EXISTS trusted_templates');
  });

  tearDown(() async {
    await db.close();
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('adds the From people category and the trusted_templates table',
      () async {
    await DatabaseHelper().onUpgradeForTesting(db, 22, 23);

    final cat = await db.query('categories',
        where: 'id = ?', whereArgs: [kFromPeopleCategoryId]);
    expect(cat, hasLength(1));
    expect(cat.first['type'], 'income');

    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE name = 'trusted_templates'");
    expect(tables, hasLength(1));
  });

  test('running it twice is harmless (custom categories untouched)', () async {
    await db.insert('categories', {
      'id': 'my_custom',
      'name': 'Pets',
      'iconCodePoint': 1,
      'colorValue': 2,
      'isCustom': 1,
      'type': 'expense',
    });
    await DatabaseHelper().onUpgradeForTesting(db, 22, 23);
    await DatabaseHelper().onUpgradeForTesting(db, 22, 23);
    final rows = await db.query('categories',
        where: 'id IN (?, ?)', whereArgs: [kFromPeopleCategoryId, 'my_custom']);
    expect(rows, hasLength(2));
  });

  group('income rule', () {
    TransactionRecord txn(String categoryId,
            {TransactionType type = TransactionType.income}) =>
        TransactionRecord(
          id: 'x',
          amount: 100,
          type: type,
          categoryId: categoryId,
          date: DateTime(2026, 9, 1),
        );

    test('From people is money in but not income', () {
      final t = txn(kFromPeopleCategoryId);
      expect(t.isFromPeople, isTrue);
      expect(t.countsAsIncome, isFalse);
    });

    test('other income categories still count', () {
      expect(txn('cat_salary').countsAsIncome, isTrue);
      expect(txn('cat_other_income').countsAsIncome, isTrue);
    });

    test('expenses are never income', () {
      expect(txn('cat_food', type: TransactionType.expense).countsAsIncome,
          isFalse);
    });
  });
}
