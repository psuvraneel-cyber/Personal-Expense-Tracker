import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pet/data/database/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// v25 → v26: payments waiting to be confirmed against an invoice.
void main() {
  late Database db;
  late Directory dir;
  const table = 'invoice_payment_suggestions';

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('mig_v26_');
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

  Future<bool> exists() async => (await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
          [table]))
      .isNotEmpty;

  test('new installs have the table', () async {
    expect(await exists(), isTrue);
  });

  test('upgrading from v25 adds it, and running twice is harmless', () async {
    await db.execute('DROP TABLE $table');
    expect(await exists(), isFalse);
    await DatabaseHelper().onUpgradeForTesting(db, 25, 26);
    await DatabaseHelper().onUpgradeForTesting(db, 25, 26);
    expect(await exists(), isTrue);
  });

  test('sign-out wipes it with everything else', () async {
    await db.insert(table, {
      'id': 's',
      'invoiceId': 'i',
      'transactionId': 't',
      'amount': 1,
      'date': '2026-11-06',
    });
    await DatabaseHelper().wipeAllUserData(db: db);
    expect(await db.query(table), isEmpty);
  });
}
