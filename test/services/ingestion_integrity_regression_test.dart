import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pet/data/database/database_helper.dart';
import 'package:pet/data/models/financial_observation.dart';
import 'package:pet/services/financial_ingestion_service.dart';
import 'package:pet/services/native_sms_reader.dart';
import 'package:pet/services/notification_action_handler.dart';
import 'package:pet/providers/transaction_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseException;

/// Regression tests for the Play-readiness audit fixes P0-3, P1-1, P1-2, P1-3
/// and P1-5, exercised against the real production schema.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late Directory tempDir;
  late FinancialIngestionService service;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({'notifications_enabled': false});
    tempDir = Directory.systemTemp.createTempSync('ingestion_integrity_');
    db = await openDatabase(
      p.join(tempDir.path, 'pet.db'),
      version: kDatabaseVersion,
      onCreate: (db, v) => DatabaseHelper().onCreateForTesting(db, v),
    );
    DatabaseHelper.setTestDatabase(db);
    service = FinancialIngestionService();
  });

  tearDown(() async {
    DatabaseHelper.setTestDatabase(null);
    await db.close();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  NativeSmsMessage debitSms({int minuteOffset = 0}) => NativeSmsMessage(
        address: 'AD-HDFCBK',
        body: 'Rs 500.00 debited from HDFC Bank A/c XX1234 on 24-Aug-26 at '
            'Swiggy. Avl Bal Rs 24,500.00. Ref 123456789.',
        dateMillis: DateTime(2026, 8, 24, 14, 30)
            .add(Duration(milliseconds: minuteOffset))
            .millisecondsSinceEpoch,
        source: 'sms',
      );

  Future<int> ledgerCount() async =>
      (await db.rawQuery('SELECT COUNT(*) AS c FROM transactions')).first['c']
          as int;

  test('P1-2: the same SMS delivered concurrently creates ONE ledger row',
      () async {
    // Same message via two paths with slightly different timestamps
    // (different observation hashes, same canonical fingerprint).
    await Future.wait([
      service.ingestMessage(debitSms()),
      service.ingestMessage(debitSms(minuteOffset: 7)),
      service.ingestMessage(debitSms()),
    ]);
    expect(await ledgerCount(), 1);
  });

  test('P1-2: UNIQUE index rejects a second row with the same fingerprint',
      () async {
    await service.ingestMessage(debitSms());
    final row = (await db.query('transactions')).first;
    final dup = Map<String, Object?>.from(row)..['id'] = 'other_id';
    await expectLater(
      db.insert('transactions', dup),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('P1-1: auto-promoted transactions are queued for cloud sync', () async {
    final txn = await service.ingestMessage(debitSms());
    expect(txn, isNotNull);
    final queued = await db.query(
      'transaction_sync_queue',
      where: 'transactionId = ? AND action = ?',
      whereArgs: [txn!.id, 'create'],
    );
    expect(queued, hasLength(1));
    expect(queued.first['payload'], isNotNull);
  });

  test('P1-3: rejecting an auto-imported SMS removes it from the ledger',
      () async {
    final txn = await service.ingestMessage(debitSms());
    expect(await ledgerCount(), 1);

    await service.rejectObservation(observationId: txn!.sourceObservationId!);

    expect(await ledgerCount(), 0);
    final deletes = await db.query(
      'transaction_sync_queue',
      where: 'transactionId = ? AND action = ?',
      whereArgs: [txn.id, 'delete'],
    );
    expect(deletes, hasLength(1));

    // And it is never re-imported.
    await service.ingestMessage(debitSms());
    expect(await ledgerCount(), 0);
  });

  test('P1-5: ledger changes bump ledgerRevision for UI refresh', () async {
    final before = FinancialIngestionService.ledgerRevision.value;
    await service.ingestMessage(debitSms());
    expect(FinancialIngestionService.ledgerRevision.value, greaterThan(before));
  });

  test('P0-3: non-financial messages are stored as hash only (no text)',
      () async {
    final personal = NativeSmsMessage(
      address: 'JX-INFORM',
      body: 'Hi! Your parcel will reach in 2 hours. Thanks for shopping.',
      dateMillis: DateTime(2026, 8, 24, 9).millisecondsSinceEpoch,
      source: 'sms',
    );
    await service.ingestMessage(personal);
    final rows = await db.query('financial_observations');
    for (final r in rows.where((r) => r['state'] == 'rejected')) {
      expect(r['body'], '');
      expect(r['normalizedText'], '');
    }
  });

  test('P0-3: stored observation text is redacted', () {
    final obs = FinancialObservation(
      observationId: 'o1',
      source: FinancialObservationSource.sms,
      sourceIdentifier: 'AD-HDFCBK',
      body: 'Rs 10 debited from A/c 123456789012 call 9876543210',
      normalizedText: 'Rs 10 debited from A/c 123456789012 call 9876543210',
      receivedAt: DateTime(2026),
      sourceTimestamp: DateTime(2026),
      observationHash: 'h',
      state: FinancialObservationState.promoted,
    );
    final stored = FinancialIngestionService.minimiseForTesting(obs);
    expect(stored.body.contains('123456789012'), isFalse);
    expect(stored.body.contains('9876543210'), isFalse);
  });

  test('P0-3: retention purge clears old message text and old logs', () async {
    await service.ingestMessage(debitSms());
    await DatabaseHelper().purgeExpiredSensitiveData(
      db: db,
      now: DateTime.now().add(const Duration(days: 120)),
    );
    final rows = await db.query('financial_observations');
    expect(rows, isNotEmpty);
    for (final r in rows) {
      expect(r['body'], '');
    }
    // Extracted ledger data is kept.
    expect(await ledgerCount(), 1);
  });

  test('P1-6: notification "Ignore" on an auto-imported item removes it',
      () async {
    final txn = await service.ingestMessage(debitSms());
    final consumed = await handleTransactionNotificationAction(
      'ignore',
      '$kImportedPayloadPrefix${txn!.sourceObservationId}',
    );
    expect(consumed, isTrue);
    expect(await ledgerCount(), 0);
  });

  test('P1-6: "edit" is not consumed (falls through to deep link)', () async {
    final consumed =
        await handleTransactionNotificationAction('edit', 'txn:any');
    expect(consumed, isFalse);
  });

  test(
      'P1-7: wipeAllUserData clears every user table, keeps default categories',
      () async {
    await service.ingestMessage(debitSms());
    await db.insert('system_watermarks',
        {'key': 'sms_watermark', 'value': 1, 'updatedAt': 'x'});
    await db.insert('merchant_learned_rules', {
      'id': 'r1',
      'identifier': 'swiggy@upi',
      'learnedMerchantName': 'Swiggy',
      'createdAt': 'x',
      'updatedAt': 'x',
    });

    await DatabaseHelper().wipeAllUserData(db: db);

    final tables = (await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' "
      "AND name NOT LIKE 'sqlite_%' AND name NOT IN ('categories', 'android_metadata')",
    ))
        .map((r) => r['name'] as String);
    for (final t in tables) {
      final n = (await db.rawQuery('SELECT COUNT(*) AS c FROM $t')).first['c'];
      expect(n, 0, reason: 'table $t should be empty after wipe');
    }
    final cats =
        (await db.rawQuery('SELECT COUNT(*) AS c FROM categories')).first['c'];
    expect(cats as int, greaterThan(0));
  });

  test('P1-10: permanent sync errors are recognised (no queue poisoning)', () {
    expect(
      TransactionProvider.isPermanentSyncError(
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
      ),
      isTrue,
    );
    expect(
      TransactionProvider.isPermanentSyncError(
        FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
      ),
      isFalse,
    );
    expect(
      TransactionProvider.isPermanentSyncError(const FormatException('bad')),
      isTrue,
    );
  });
}
