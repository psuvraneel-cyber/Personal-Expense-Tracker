import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pet/data/database/database_helper.dart';
import 'package:pet/data/models/financial_observation.dart';
import 'package:pet/services/debug_diagnostics_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late Directory directory;

  const body = 'Payment Confirmed! Your Swiggy Order #XX****1111 of Rs. '
      '124.0 was successfully paid on 22/09/2026 at 04:41 PM. '
      'Txn ID: 4123000045670001.';

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'pet_sms_last_scan': DateTime(2026, 9, 22, 16, 45).millisecondsSinceEpoch,
    });
    directory = Directory.systemTemp.createTempSync('debug_diagnostics_');
    db = await openDatabase(
      p.join(directory.path, 'pet.db'),
      version: kDatabaseVersion,
      onCreate: (database, version) =>
          DatabaseHelper().onCreateForTesting(database, version),
    );
    DatabaseHelper.setTestDatabase(db);
  });

  tearDown(() async {
    DatabaseHelper.setTestDatabase(null);
    await db.close();
    try {
      directory.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('collects privacy-safe database and ingestion aggregates', () async {
    await db.insert('transactions', {
      'id': 'txn_private_id',
      'amount': 124.0,
      'type': 'expense',
      'categoryId': 'cat_food',
      'date': DateTime(2026, 9, 22, 4, 41).toIso8601String(),
      'source': 'sms',
      'sourceObservationId': 'obs_private_id',
      'sourceFingerprint': 'fingerprint_private',
    });
    await db.insert('financial_observations',
        _observation('obs_private_id', FinancialObservationState.promoted));
    await db.insert('sms_processing_state', {
      'id': 'obs_private_id',
      'smsHash': 'sms_private_hash',
      'status': 'accepted',
      'processedAt': DateTime(2026, 9, 22).toIso8601String(),
    });
    await db.insert('transaction_sync_queue', {
      'id': 'queue_private_id',
      'transactionId': 'txn_private_id',
      'action': 'create',
      'timestamp': 1,
      'userId': 'guest_user',
    });

    final report = await DebugDiagnosticsService().collect(
      smsService: {'smsPermissionStatus': 'granted'},
    );
    final json = report.toString();

    expect(report['database']['canonicalTransactions'], 1);
    expect(report['database']['observationsByState']['promoted'], 1);
    expect(report['database']['syncQueueByAction']['create'], 1);
    expect(json, isNot(contains('txn_private_id')));
    expect(json, isNot(contains('fingerprint_private')));
  });

  test('reports duplicate relationships and performs no writes', () async {
    final observation = _observation(
      'obs_swiggy',
      FinancialObservationState.promoted,
      bodyOverride: body,
      canonicalTransactionId: 'txn_swiggy',
    );
    await db.insert('financial_observations', observation);
    await db.insert('transactions', {
      'id': 'txn_swiggy',
      'amount': 124.0,
      'type': 'expense',
      'categoryId': 'cat_food',
      'date': DateTime(2026, 9, 22, 4, 41).toIso8601String(),
      'source': 'sms',
      'sourceObservationId': 'obs_swiggy',
      'sourceFingerprint': 'same_fingerprint',
    });
    await db.insert('sms_transactions', {
      'id': 'obs_swiggy',
      'amount': 124.0,
      'merchantName': 'Unknown',
      'bankName': 'Unknown Bank',
      'transactionType': 'debit',
      'timestamp': DateTime(2026, 9, 22, 4, 41).toIso8601String(),
      'rawSmsBody': body,
      'smsSender': 'AD-SWIGGY-S',
      'smsHash': 'sms_hash',
      'referenceId': '4123000045670001',
      'category': 'Other Expense',
      'source': 'sms',
    });

    final before = (await db.rawQuery('SELECT COUNT(*) AS c FROM transactions'))
        .first['c'];
    final report = await DebugDiagnosticsService().duplicateCandidateReport();
    final after = (await db.rawQuery('SELECT COUNT(*) AS c FROM transactions'))
        .first['c'];

    expect(report['referenceMatchCount'], greaterThanOrEqualTo(2));
    expect(report['sharedReference'], isTrue);
    expect(report['sameCanonicalTransaction'], isTrue);
    expect(before, after);
    expect(report.toString(), isNot(contains(body)));
    expect(report.toString(), isNot(contains('4123000045670001')));
  });

  test('timestamp dry run reparses retained PM evidence without writing',
      () async {
    await db.insert('transactions', {
      'id': 'txn_timestamp',
      'amount': 124.0,
      'type': 'expense',
      'categoryId': 'cat_other_expense',
      'date': DateTime(2026, 9, 22, 4, 41).toIso8601String(),
      'source': 'sms',
      'sourceObservationId': 'obs_timestamp',
    });
    await db.insert(
        'financial_observations',
        _observation(
          'obs_timestamp',
          FinancialObservationState.promoted,
          bodyOverride: body,
          canonicalTransactionId: 'txn_timestamp',
        ));

    final report = await DebugDiagnosticsService().timestampRepairDryRun();
    final candidate = (report['candidates'] as List).single as Map;

    expect(report['writePerformed'], isFalse);
    expect(candidate['evidenceAvailable'], isTrue);
    expect(candidate['strongTimeEvidence'], isTrue);
    expect(candidate['reparsedTimestamp'], contains('T16:41:00'));
    expect(candidate['currentTimestamp'], contains('T04:41:00'));
  });
}

Map<String, Object?> _observation(
  String id,
  FinancialObservationState state, {
  String? bodyOverride,
  String? canonicalTransactionId,
}) {
  final timestamp = DateTime(2026, 9, 22, 16, 41);
  return FinancialObservation(
    observationId: id,
    source: FinancialObservationSource.sms,
    sourceIdentifier: 'AD-SWIGGY-S',
    sender: 'AD-SWIGGY-S',
    body: bodyOverride ?? 'redacted body',
    normalizedText: bodyOverride ?? 'redacted body',
    receivedAt: timestamp,
    sourceTimestamp: timestamp,
    observationHash: 'hash_$id',
    sourceFingerprint: 'same_fingerprint',
    state: state,
    confidence: 0.9,
    canonicalTransactionId: canonicalTransactionId,
  ).toMap();
}
