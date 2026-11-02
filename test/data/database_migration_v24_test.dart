import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pet/core/constants/categories.dart';
import 'package:pet/data/database/database_helper.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/transaction.dart';

/// v23 → v24: the "Transfer" category.
void main() {
  late Database db;
  late Directory dir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('mig_v24_');
    db = await openDatabase(
      p.join(dir.path, 'pet.db'),
      version: kDatabaseVersion,
      onCreate: (db, v) => DatabaseHelper().onCreateForTesting(db, v),
    );
    // Simulate a v23 database: no Transfer category yet.
    await db.delete('categories',
        where: 'id = ?', whereArgs: [kTransferCategoryId]);
  });

  tearDown(() async {
    await db.close();
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('adds the Transfer category', () async {
    await DatabaseHelper().onUpgradeForTesting(db, 23, 24);
    final rows = await db
        .query('categories', where: 'id = ?', whereArgs: [kTransferCategoryId]);
    expect(rows, hasLength(1));
    expect(rows.single['type'], 'transfer');
  });

  test('a transfer counts as neither income nor spending', () {
    final t = TransactionRecord(
      id: 't',
      amount: 15000,
      type: TransactionType.transfer,
      categoryId: kTransferCategoryId,
      date: DateTime(2026, 11, 2),
    );
    expect(t.countsAsIncome, isFalse);
    expect(t.type == TransactionType.expense, isFalse);
  });
}
