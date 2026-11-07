import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:pet/data/database/database_helper.dart';
import 'package:pet/services/ingestion_diagnostics.dart';
import 'package:pet/services/sms_parser/sms_transaction_parser.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// Read-only, debug-build diagnostics for SMS ingestion and data integrity.
///
/// This service deliberately returns aggregate counts and short digests rather
/// than identifiers, message bodies, account numbers, or UPI addresses.
class DebugDiagnosticsService {
  DebugDiagnosticsService({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper();

  final DatabaseHelper _dbHelper;

  Future<Map<String, dynamic>> collect({
    Map<String, dynamic>? smsService,
    Map<String, dynamic>? reconciliation,
  }) async {
    final db = await _dbHelper.database;
    final generatedAt = DateTime.now().toIso8601String();
    final ingestion = IngestionDiagnostics.instance.getSummary();

    return {
      'generatedAt': generatedAt,
      'database': {
        'schemaVersion': kDatabaseVersion,
        'canonicalTransactions': await _count(db, 'transactions'),
        'transactionsBySource': await _group(db, 'transactions', 'source'),
        'smsTransactions': await _count(db, 'sms_transactions'),
        'smsTransactionsBySource':
            await _group(db, 'sms_transactions', 'source'),
        'financialObservations': await _count(db, 'financial_observations'),
        'observationsBySource':
            await _group(db, 'financial_observations', 'source'),
        'observationsByState':
            await _group(db, 'financial_observations', 'state'),
        'processingStateByStatus':
            await _group(db, 'sms_processing_state', 'status'),
        'pendingReview': await _count(
          db,
          'financial_observations',
          where: 'state = ?',
          args: ['uncertain'],
        ),
        'syncQueueByAction':
            await _group(db, 'transaction_sync_queue', 'action'),
        'syncQueueFailed': await _count(
          db,
          'transaction_sync_queue',
          where: 'lastError IS NOT NULL AND lastError != ?',
          args: [''],
        ),
      },
      'smsService': smsService ?? <String, dynamic>{},
      'reconciliation': reconciliation ?? <String, dynamic>{},
      'ingestion': {
        for (final entry in ingestion.entries)
          if (entry.key != 'recentEvents') entry.key: entry.value,
      },
    };
  }

  /// Inspects the known ₹124/22-Sep-2026 event without returning raw text.
  Future<Map<String, dynamic>> duplicateCandidateReport({
    String referenceId = '4123000045670001',
    double amount = 124,
    DateTime? date,
  }) async {
    final db = await _dbHelper.database;
    date ??= DateTime(2026, 9, 22);
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    final referenceDigest = _digest(referenceId);

    final ledger = await db.query(
      'transactions',
      columns: [
        'id',
        'amount',
        'date',
        'source',
        'sourceObservationId',
        'sourceFingerprint',
      ],
      where: 'amount BETWEEN ? AND ? AND date >= ? AND date < ?',
      whereArgs: [
        amount - 0.01,
        amount + 0.01,
        start.toIso8601String(),
        end.toIso8601String()
      ],
      orderBy: 'date ASC',
    );

    final smsRows = await db.query(
      'sms_transactions',
      columns: [
        'id',
        'amount',
        'timestamp',
        'source',
        'referenceId',
        'smsHash',
      ],
      where: 'amount BETWEEN ? AND ? AND timestamp >= ? AND timestamp < ?',
      whereArgs: [
        amount - 0.01,
        amount + 0.01,
        start.toIso8601String(),
        end.toIso8601String()
      ],
      orderBy: 'timestamp ASC',
    );

    final observations = await db.query(
      'financial_observations',
      columns: [
        'observationId',
        'source',
        'sourceTimestamp',
        'state',
        'sourceFingerprint',
        'canonicalTransactionId',
        'observationHash',
        'body',
        'normalizedText',
      ],
      where: 'sourceTimestamp >= ? AND sourceTimestamp < ?',
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
      orderBy: 'sourceTimestamp ASC',
    );

    final candidates = <Map<String, dynamic>>[];
    for (final row in ledger) {
      candidates.add({
        'kind': 'canonical_transaction',
        'source': row['source'],
        'amount': row['amount'],
        'timestamp': row['date'],
        'referenceMatches': false,
        'referenceDigest': referenceDigest,
        'recordDigest': _digest(row['id'] as String?),
        'sourceObservationDigest':
            _digest(row['sourceObservationId'] as String?),
        'sourceFingerprintDigest': _digest(row['sourceFingerprint'] as String?),
      });
    }
    for (final row in smsRows) {
      final rowReference = row['referenceId'] as String?;
      candidates.add({
        'kind': 'sms_transaction',
        'source': row['source'],
        'amount': row['amount'],
        'timestamp': row['timestamp'],
        'referenceMatches': rowReference == referenceId,
        'referenceDigest': rowReference == null ? null : _digest(rowReference),
        'recordDigest': _digest(row['id'] as String?),
        'smsHashDigest': _digest(row['smsHash'] as String?),
      });
    }
    for (final row in observations) {
      final body = '${row['body'] ?? ''} ${row['normalizedText'] ?? ''}';
      final referenceMatches = body.contains(referenceId);
      candidates.add({
        'kind': 'financial_observation',
        'source': row['source'],
        'state': row['state'],
        'timestamp': row['sourceTimestamp'],
        'referenceMatches': referenceMatches,
        'referenceDigest': referenceMatches ? referenceDigest : null,
        'recordDigest': _digest(row['observationId'] as String?),
        'sourceFingerprintDigest': _digest(row['sourceFingerprint'] as String?),
        'canonicalTransactionDigest':
            _digest(row['canonicalTransactionId'] as String?),
        'hasOriginalTextEvidence': body.trim().isNotEmpty,
      });
    }

    final matchingReferences = candidates
        .where((candidate) => candidate['referenceMatches'] == true)
        .toList();
    final fingerprints = matchingReferences
        .map((candidate) => candidate['sourceFingerprintDigest'])
        .whereType<String>()
        .toSet();
    final linkedCanonical = matchingReferences
        .map((candidate) => candidate['canonicalTransactionDigest'])
        .whereType<String>()
        .toSet();

    return {
      'query': {
        'amount': amount,
        'calendarDate': start.toIso8601String().split('T').first,
        'referenceDigest': referenceDigest,
      },
      'candidateCount': candidates.length,
      'referenceMatchCount': matchingReferences.length,
      'sharedReference': matchingReferences.length > 1,
      'sharedSourceFingerprint':
          fingerprints.length == 1 && fingerprints.isNotEmpty,
      'sameCanonicalTransaction':
          linkedCanonical.length == 1 && linkedCanonical.isNotEmpty,
      'pendingReviewCount': candidates
          .where((candidate) =>
              candidate['kind'] == 'financial_observation' &&
              candidate['state'] == 'uncertain')
          .length,
      'candidates': candidates,
    };
  }

  /// Re-parses retained evidence but never writes a timestamp.
  Future<Map<String, dynamic>> timestampRepairDryRun({
    double amount = 124,
    DateTime? date,
  }) async {
    final db = await _dbHelper.database;
    date ??= DateTime(2026, 9, 22);
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    final rows = await db.query(
      'transactions',
      columns: ['id', 'amount', 'date', 'source', 'sourceObservationId'],
      where: 'amount BETWEEN ? AND ? AND date >= ? AND date < ?',
      whereArgs: [
        amount - 0.01,
        amount + 0.01,
        start.toIso8601String(),
        end.toIso8601String()
      ],
    );
    final reports = <Map<String, dynamic>>[];
    for (final row in rows) {
      final observationId = row['sourceObservationId'] as String?;
      Map<String, dynamic>? observation;
      if (observationId != null) {
        final matches = await db.query(
          'financial_observations',
          where: 'observationId = ?',
          whereArgs: [observationId],
          limit: 1,
        );
        if (matches.isNotEmpty) observation = matches.first;
      }
      final body = observation == null
          ? ''
          : '${observation['normalizedText'] ?? ''}'.trim();
      final parsed = body.isEmpty
          ? null
          : SmsTransactionParser.parse(
              body: body,
              sender: observation?['sender'] as String? ?? '',
              timestamp: DateTime.tryParse(
                    observation?['sourceTimestamp'] as String? ?? '',
                  ) ??
                  DateTime.parse(row['date'] as String),
            );
      final current = DateTime.parse(row['date'] as String);
      reports.add({
        'recordDigest': _digest(row['id'] as String?),
        'source': row['source'],
        'currentTimestamp': current.toIso8601String(),
        'evidenceAvailable': body.isNotEmpty,
        'reparsedTimestamp': parsed?.date?.toIso8601String(),
        'strongTimeEvidence': parsed?.time != null,
        'calendarDatePreserved': parsed?.date == null
            ? null
            : parsed!.date!.year == current.year &&
                parsed.date!.month == current.month &&
                parsed.date!.day == current.day,
        'manualModificationStatus': row['source'] == 'manual'
            ? 'manual_record'
            : 'not_determinable_from_current_schema',
        'repairWouldBeWritten': false,
      });
    }
    return {
      'queryAmount': amount,
      'calendarDate': start.toIso8601String().split('T').first,
      'candidateCount': reports.length,
      'candidates': reports,
      'writePerformed': false,
    };
  }

  Future<int> _count(
    Database db,
    String table, {
    String? where,
    List<Object?>? args,
  }) async {
    try {
      final rows = await db.query(
        table,
        columns: ['COUNT(*) AS count'],
        where: where,
        whereArgs: args,
      );
      return (rows.first['count'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<Map<String, int>> _group(
    Database db,
    String table,
    String column,
  ) async {
    try {
      final rows = await db.rawQuery(
        'SELECT COALESCE($column, ?) AS value, COUNT(*) AS count '
        'FROM $table GROUP BY $column',
        ['unknown'],
      );
      return {
        for (final row in rows)
          row['value'] as String: (row['count'] as num).toInt(),
      };
    } catch (_) {
      return {};
    }
  }

  static String? _digest(String? value) {
    if (value == null || value.isEmpty) return null;
    return sha256.convert(utf8.encode(value)).toString().substring(0, 12);
  }
}
