import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pet/data/database/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// v24 → v25: invoice tables.
void main() {
  late Database db;
  late Directory dir;
  const tables = ['invoices', 'invoice_clients', 'invoice_profile'];

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('mig_v25_');
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

  Future<List<String>> existing() async => (await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN "
          "('invoices', 'invoice_clients', 'invoice_profile')"))
      .map((r) => r['name'] as String)
      .toList();

  test('new installs have the invoice tables', () async {
    expect(await existing(), unorderedEquals(tables));
  });

  test('upgrading from v24 adds them, and running twice is harmless', () async {
    for (final t in tables) {
      await db.execute('DROP TABLE $t');
    }
    expect(await existing(), isEmpty);
    await DatabaseHelper().onUpgradeForTesting(db, 24, 25);
    await DatabaseHelper().onUpgradeForTesting(db, 24, 25);
    expect(await existing(), unorderedEquals(tables));
  });
}
