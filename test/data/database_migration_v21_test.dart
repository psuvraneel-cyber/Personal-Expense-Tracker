import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pet/data/database/database_helper.dart';

/// v20 → v21: collapse duplicate auto-imported rows, add the UNIQUE
/// fingerprint index, and queue auto-imported rows for their first sync.
void main() {
  late Database db;
  late Directory dir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('mig_v21_');
    db = await openDatabase(
      p.join(dir.path, 'pet.db'),
      version: kDatabaseVersion,
      onCreate: (db, v) => DatabaseHelper().onCreateForTesting(db, v),
    );
    // Simulate a v20 database: no unique index yet.
    await db.execute('DROP INDEX IF EXISTS idx_txn_fingerprint_unique');
  });

  tearDown(() async {
    await db.close();
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Map<String, Object?> row(String id, {String? fp, String source = 'sms'}) => {
        'id': id,
        'amount': 100.0,
        'type': 'expense',
        'categoryId': 'food',
        'date': DateTime(2026, 8, 1).toIso8601String(),
        'source': source,
        'sourceFingerprint': fp,
        'updatedAt': DateTime(2026, 8, 1).toIso8601String(),
      };

  test('collapses duplicates, enforces uniqueness, backfills sync queue',
      () async {
    await db.insert('transactions', row('a', fp: 'fp1'));
    await db.insert('transactions', row('b', fp: 'fp1')); // race duplicate
    await db.insert('transactions', row('c', fp: 'fp2'));
    await db.insert('transactions', row('m', source: 'manual')); // untouched

    await DatabaseHelper().onUpgradeForTesting(db, 20, 21);

    final ids = (await db.query('transactions', orderBy: 'id'))
        .map((r) => r['id'])
        .toList();
    expect(ids, ['a', 'c', 'm']);

    await expectLater(
      db.insert('transactions', row('d', fp: 'fp2')),
      throwsA(isA<DatabaseException>()),
    );

    final queued = (await db.query('transaction_sync_queue'))
        .map((r) => r['transactionId'])
        .toSet();
    expect(queued, {'a', 'c'},
        reason: 'only auto-imported rows are backfilled');
  });
}
