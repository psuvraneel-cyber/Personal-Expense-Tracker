import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:pet/data/database/database_helper.dart';
import 'package:pet/data/models/sms_transaction.dart';

/// Repository for SMS-parsed transactions.
/// All data is stored locally on-device via sqflite.
class SmsTransactionRepository {
  final DatabaseHelper _dbHelper;

  SmsTransactionRepository({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper();

  // ─── Watermark & Metadata Management ──────────────────────────────

  /// Get watermark value for a key from SQLite.
  /// Fallback: checks legacy SharedPreferences key if not found in SQLite,
  /// returns it and backfills into SQLite.
  Future<int?> getWatermark(String key) async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'system_watermarks',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );

    if (result.isNotEmpty) {
      return result.first['value'] as int?;
    }

    // Fallback: check legacy SharedPreferences key
    try {
      final prefs = await SharedPreferences.getInstance();
      final legacyKey = key == 'sms_watermark'
          ? 'pet_last_sms_timestamp'
          : (key == 'reconciliation_watermark'
              ? 'pet_reconciliation_watermark'
              : null);

      if (legacyKey != null) {
        final legacyVal = prefs.getInt(legacyKey);
        if (legacyVal != null && legacyVal > 0) {
          await setWatermark(key, legacyVal);
          return legacyVal;
        }
      }
    } catch (_) {
      // Ignore SharedPreferences errors during fallback
    }

    return null;
  }

  /// Set watermark value for a key in SQLite system_watermarks table.
  Future<void> setWatermark(String key, int timestamp) async {
    final db = await _dbHelper.database;
    await db.insert(
      'system_watermarks',
      {
        'key': key,
        'value': timestamp,
        'updatedAt': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Reset all watermarks in SQLite system_watermarks table.
  Future<void> clearWatermarks() async {
    final db = await _dbHelper.database;
    await db.delete('system_watermarks');
  }

  /// Insert a batch of transactions AND update watermarks in the EXACT SAME SQLite transaction.
  ///
  /// Guaranteed Atomicity: Either all transaction rows + watermark updates commit together,
  /// or NEITHER commits (on crash, error, or rollback).
  Future<int> insertBatchWithWatermark({
    required List<SmsTransaction> transactions,
    int? watermarkTimestamp,
    List<String> watermarkKeys = const ['sms_watermark'],
  }) async {
    final db = await _dbHelper.database;
    int insertedCount = 0;

    await db.transaction((txn) async {
      for (final transaction in transactions) {
        final stateCheck = await txn.query(
          'sms_processing_state',
          where: 'smsHash = ?',
          whereArgs: [transaction.smsHash],
          limit: 1,
        );
        final txnCheck = await txn.query(
          'sms_transactions',
          where: 'smsHash = ?',
          whereArgs: [transaction.smsHash],
          limit: 1,
        );

        if (stateCheck.isEmpty && txnCheck.isEmpty) {
          await txn.insert(
            'sms_transactions',
            transaction.toMap(),
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
          await txn.insert(
            'sms_processing_state',
            {
              'id': transaction.id,
              'smsHash': transaction.smsHash,
              'status': 'accepted',
              'processedAt': DateTime.now().toIso8601String(),
              'reason': 'batch_inserted',
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          insertedCount++;
        }
      }

      if (watermarkTimestamp != null && watermarkTimestamp > 0) {
        final nowIso = DateTime.now().toIso8601String();
        for (final key in watermarkKeys) {
          final existing = await txn.query(
            'system_watermarks',
            columns: ['value'],
            where: 'key = ?',
            whereArgs: [key],
            limit: 1,
          );
          final currentVal =
              existing.isNotEmpty ? (existing.first['value'] as int) : 0;
          if (watermarkTimestamp > currentVal) {
            await txn.insert(
              'system_watermarks',
              {
                'key': key,
                'value': watermarkTimestamp,
                'updatedAt': nowIso,
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }
      }
    });

    return insertedCount;
  }

  /// Batch insert SMS transactions, skipping duplicates.
  /// Delegates to atomic [insertBatchWithWatermark].
  Future<int> insertBatch(List<SmsTransaction> transactions) async {
    return insertBatchWithWatermark(transactions: transactions);
  }

  /// Get all SMS transactions, ordered by timestamp descending.
  Future<List<SmsTransaction>> getAllSmsTransactions() async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'sms_transactions',
      orderBy: 'timestamp DESC',
    );
    return maps.map((map) => SmsTransaction.fromMap(map)).toList();
  }

  /// Get SMS transactions within a date range.
  Future<List<SmsTransaction>> getSmsTransactionsByDateRange(
    DateTime start,
    DateTime end,
  ) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'sms_transactions',
      where: 'timestamp >= ? AND timestamp <= ?',
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
      orderBy: 'timestamp DESC',
    );
    return maps.map((map) => SmsTransaction.fromMap(map)).toList();
  }

  /// Get SMS transactions for a specific month.
  Future<List<SmsTransaction>> getSmsTransactionsByMonth(
    int month,
    int year,
  ) async {
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 0, 23, 59, 59);
    return getSmsTransactionsByDateRange(start, end);
  }

  /// Insert a new SMS transaction.
  /// Returns `true` if inserted, `false` if duplicate (hash already exists).
  /// Mark the processing state of an SMS hash in sms_processing_state table.
  Future<void> markSmsProcessingState({
    required String smsHash,
    required String status,
    String? reason,
  }) async {
    final db = await _dbHelper.database;
    final nowIso = DateTime.now().toIso8601String();
    await db.insert(
      'sms_processing_state',
      {
        'id': smsHash, // Use smsHash as primary key or uuid
        'smsHash': smsHash,
        'status': status,
        'processedAt': nowIso,
        'reason': reason,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Mark an SMS hash as explicitly ignored (e.g. "Not a transaction").
  Future<void> markSmsIgnored(String smsHash, {String? reason}) async {
    await markSmsProcessingState(
      smsHash: smsHash,
      status: 'ignored',
      reason: reason ?? 'user_ignored',
    );
  }

  /// Insert a new SMS transaction.
  /// Returns `true` if inserted, `false` if duplicate (hash already exists in processing state or transactions table).
  Future<bool> insertSmsTransaction(SmsTransaction transaction) async {
    final db = await _dbHelper.database;
    bool inserted = false;

    await db.transaction((txn) async {
      final stateCheck = await txn.query(
        'sms_processing_state',
        where: 'smsHash = ?',
        whereArgs: [transaction.smsHash],
        limit: 1,
      );
      if (stateCheck.isNotEmpty) return;

      final txnCheck = await txn.query(
        'sms_transactions',
        where: 'smsHash = ?',
        whereArgs: [transaction.smsHash],
        limit: 1,
      );
      if (txnCheck.isNotEmpty) return;

      final rowId = await txn.insert(
        'sms_transactions',
        transaction.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );

      if (rowId != 0 && rowId != -1) {
        await txn.insert(
          'sms_processing_state',
          {
            'id': transaction.id,
            'smsHash': transaction.smsHash,
            'status': 'accepted',
            'processedAt': DateTime.now().toIso8601String(),
            'reason': 'inserted',
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        inserted = true;
      }
    });

    return inserted;
  }

  /// Check if a transaction with the given hash already exists or has been processed/deleted/ignored.
  Future<bool> existsByHash(String hash) async {
    final db = await _dbHelper.database;
    final stateResult = await db.query(
      'sms_processing_state',
      where: 'smsHash = ?',
      whereArgs: [hash],
      limit: 1,
    );
    if (stateResult.isNotEmpty) return true;

    final txnResult = await db.query(
      'sms_transactions',
      where: 'smsHash = ?',
      whereArgs: [hash],
      limit: 1,
    );
    return txnResult.isNotEmpty;
  }

  /// Check if a transaction with the same reference ID, amount, and date exists.
  /// Used for cross-source dedup (SMS vs notification).
  Future<bool> existsByReferenceAndAmount(
    String referenceId,
    double amount,
    DateTime date,
  ) async {
    final db = await _dbHelper.database;
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    final result = await db.query(
      'sms_transactions',
      where:
          'referenceId = ? AND amount = ? AND timestamp >= ? AND timestamp < ?',
      whereArgs: [
        referenceId,
        amount,
        startOfDay.toIso8601String(),
        endOfDay.toIso8601String(),
      ],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  /// Get all processed SMS transaction hashes (from both sms_processing_state and sms_transactions).
  Future<Set<String>> getAllHashes() async {
    final db = await _dbHelper.database;
    final set = <String>{};

    final stateResult = await db.query('sms_processing_state', columns: ['smsHash']);
    for (final r in stateResult) {
      set.add(r['smsHash'] as String);
    }

    final txnResult = await db.query('sms_transactions', columns: ['smsHash']);
    for (final r in txnResult) {
      set.add(r['smsHash'] as String);
    }

    return set;
  }

  /// Get all processed SMS transaction hashes for transactions within a date range.
  Future<Set<String>> getHashesSince(DateTime since) async {
    final db = await _dbHelper.database;
    final sinceStr = since.toIso8601String();
    final set = <String>{};

    final stateResult = await db.query(
      'sms_processing_state',
      columns: ['smsHash'],
      where: 'processedAt >= ?',
      whereArgs: [sinceStr],
    );
    for (final r in stateResult) {
      set.add(r['smsHash'] as String);
    }

    final txnResult = await db.query(
      'sms_transactions',
      columns: ['smsHash'],
      where: 'timestamp >= ?',
      whereArgs: [sinceStr],
    );
    for (final r in txnResult) {
      set.add(r['smsHash'] as String);
    }

    return set;
  }

  /// Proximity-based deduplication check.
  ///
  /// Returns true if a transaction with the same amount and sender exists
  /// within [windowSeconds] (default 30 seconds) of the given timestamp,
  /// and matching merchant if provided. Used when no reference ID is
  /// available, to prevent duplicates from slightly different SMS timestamps
  /// (e.g., network delays, SMS retry).
  ///
  /// The window is intentionally tight (default 30 seconds) to avoid
  /// false positives on recurring payments or rapid consecutive purchases.
  Future<bool> existsByAmountTimestampProximity({
    required double amount,
    required DateTime timestamp,
    required String sender,
    int windowSeconds = 30,
    String? merchantName,
  }) async {
    final db = await _dbHelper.database;
    final windowStart = timestamp.subtract(Duration(seconds: windowSeconds));
    final windowEnd = timestamp.add(Duration(seconds: windowSeconds));

    String where =
        'amount = ? AND smsSender = ? AND timestamp >= ? AND timestamp <= ?';
    List<dynamic> whereArgs = [
      amount,
      sender,
      windowStart.toIso8601String(),
      windowEnd.toIso8601String(),
    ];

    if (merchantName != null &&
        merchantName.isNotEmpty &&
        merchantName != 'Unknown') {
      where += ' AND merchantName = ?';
      whereArgs.add(merchantName);
    }

    final result = await db.query(
      'sms_transactions',
      where: where,
      whereArgs: whereArgs,
      limit: 1,
    );
    return result.isNotEmpty;
  }

  /// Get all user feedback records from the user_feedback table.
  Future<List<Map<String, dynamic>>> getAllFeedbackRecords() async {
    final db = await _dbHelper.database;
    return db.query('user_feedback');
  }

  /// Save a user feedback record to the user_feedback table.
  Future<void> saveFeedback(Map<String, dynamic> feedback) async {
    final db = await _dbHelper.database;
    await db.insert(
      'user_feedback',
      feedback,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Update the category of an SMS transaction.
  Future<void> updateCategory(String id, String category) async {
    final db = await _dbHelper.database;
    await db.update(
      'sms_transactions',
      {'category': category},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Mark a transaction as verified (user-confirmed).
  Future<void> updateVerified(String id, bool verified) async {
    final db = await _dbHelper.database;
    await db.update(
      'sms_transactions',
      {'isVerified': verified ? 1 : 0, 'confidence': 1.0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Update the transaction type (debit/credit).
  Future<void> updateTransactionType(String id, String type) async {
    final db = await _dbHelper.database;
    await db.update(
      'sms_transactions',
      {'transactionType': type},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Delete an SMS transaction and permanently mark its smsHash as deleted (or ignored) in sms_processing_state.
  Future<void> deleteSmsTransaction(
    String id, {
    String status = 'deleted',
    String reason = 'user_deleted',
  }) async {
    final db = await _dbHelper.database;
    final txns = await db.query(
      'sms_transactions',
      columns: ['smsHash'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    final smsHash = txns.isNotEmpty ? txns.first['smsHash'] as String? : null;

    await db.transaction((txn) async {
      if (smsHash != null) {
        final existingState = await txn.query(
          'sms_processing_state',
          columns: ['status'],
          where: 'smsHash = ?',
          whereArgs: [smsHash],
          limit: 1,
        );
        final existingStatus =
            existingState.isNotEmpty
                ? existingState.first['status'] as String?
                : null;

        final targetStatus = (existingStatus == 'ignored' && status == 'deleted')
            ? 'ignored'
            : status;

        await txn.insert(
          'sms_processing_state',
          {
            'id': smsHash,
            'smsHash': smsHash,
            'status': targetStatus,
            'processedAt': DateTime.now().toIso8601String(),
            'reason': reason,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await txn.delete('sms_transactions', where: 'id = ?', whereArgs: [id]);
    });
  }

  /// Get total debits for a given month.
  Future<double> getTotalDebits(int month, int year) async {
    final db = await _dbHelper.database;
    final start = DateTime(year, month, 1).toIso8601String();
    final end = DateTime(year, month + 1, 0, 23, 59, 59).toIso8601String();
    final result = await db.rawQuery(
      'SELECT SUM(amount) as total FROM sms_transactions '
      'WHERE transactionType = ? AND timestamp >= ? AND timestamp <= ?',
      ['debit', start, end],
    );
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  /// Get total credits for a given month.
  Future<double> getTotalCredits(int month, int year) async {
    final db = await _dbHelper.database;
    final start = DateTime(year, month, 1).toIso8601String();
    final end = DateTime(year, month + 1, 0, 23, 59, 59).toIso8601String();
    final result = await db.rawQuery(
      'SELECT SUM(amount) as total FROM sms_transactions '
      'WHERE transactionType = ? AND timestamp >= ? AND timestamp <= ?',
      ['credit', start, end],
    );
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  /// Remove any duplicate rows that share the same smsHash.
  ///
  /// Keeps the oldest entry (lowest rowid) for each hash. This is a
  /// one-time cleanup for data inserted before the in-batch dedup fix.
  /// Safe to call on every cold start — it is a no-op if there are no dupes.
  Future<int> deduplicateExisting() async {
    final db = await _dbHelper.database;
    final result = await db.rawDelete('''
      DELETE FROM sms_transactions
      WHERE rowid NOT IN (
        SELECT MAX(rowid)
        FROM sms_transactions
        GROUP BY smsHash
      )
    ''');
    return result;
  }

  /// Get the count of all stored SMS transactions.
  Future<int> getCount() async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM sms_transactions',
    );
    return (result.first['count'] as int?) ?? 0;
  }
}
