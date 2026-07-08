import 'package:sqflite/sqflite.dart';
import 'package:pet/data/database/database_helper.dart';
import 'package:pet/data/models/sms_transaction.dart';

/// Repository for SMS-parsed transactions.
/// All data is stored locally on-device via sqflite.
class SmsTransactionRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper();

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
  Future<bool> insertSmsTransaction(SmsTransaction transaction) async {
    final db = await _dbHelper.database;

    // Check for duplicate using SMS hash
    final existing = await db.query(
      'sms_transactions',
      where: 'smsHash = ?',
      whereArgs: [transaction.smsHash],
      limit: 1,
    );

    if (existing.isNotEmpty) return false; // Duplicate — skip

    await db.insert(
      'sms_transactions',
      transaction.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    return true;
  }

  /// Batch insert SMS transactions, skipping duplicates.
  /// Returns the count of newly inserted transactions.
  Future<int> insertBatch(List<SmsTransaction> transactions) async {
    final db = await _dbHelper.database;
    int insertedCount = 0;

    await db.transaction((txn) async {
      for (final transaction in transactions) {
        final existing = await txn.query(
          'sms_transactions',
          where: 'smsHash = ?',
          whereArgs: [transaction.smsHash],
          limit: 1,
        );

        if (existing.isEmpty) {
          await txn.insert(
            'sms_transactions',
            transaction.toMap(),
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
          insertedCount++;
        }
      }
    });

    return insertedCount;
  }

  /// Check if a transaction with the given hash already exists.
  Future<bool> existsByHash(String hash) async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'sms_transactions',
      where: 'smsHash = ?',
      whereArgs: [hash],
      limit: 1,
    );
    return result.isNotEmpty;
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

  /// Get all SMS transaction hashes for dedup.
  Future<Set<String>> getAllHashes() async {
    final db = await _dbHelper.database;
    final result = await db.query('sms_transactions', columns: ['smsHash']);
    return result.map((r) => r['smsHash'] as String).toSet();
  }

  /// Get all SMS transaction hashes for transactions within a date range.
  /// More efficient than [getAllHashes] for reconciliation scopes.
  Future<Set<String>> getHashesSince(DateTime since) async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'sms_transactions',
      columns: ['smsHash'],
      where: 'timestamp >= ?',
      whereArgs: [since.toIso8601String()],
    );
    return result.map((r) => r['smsHash'] as String).toSet();
  }

  /// Proximity-based deduplication check.
  ///
  /// Returns true if a transaction with the same amount and sender exists
  /// within [windowMinutes] of the given timestamp. Used when no
  /// reference ID is available, to prevent duplicates from slightly
  /// different SMS timestamps (e.g., network delays, SMS retry).
  ///
  /// The window is intentionally tight (default 2 minutes) to avoid
  /// false positives on recurring payments.
  Future<bool> existsByAmountTimestampProximity({
    required double amount,
    required DateTime timestamp,
    required String sender,
    int windowMinutes = 2,
  }) async {
    final db = await _dbHelper.database;
    final windowStart = timestamp.subtract(Duration(minutes: windowMinutes));
    final windowEnd = timestamp.add(Duration(minutes: windowMinutes));
    final result = await db.query(
      'sms_transactions',
      where:
          'amount = ? AND smsSender = ? AND timestamp >= ? AND timestamp <= ?',
      whereArgs: [
        amount,
        sender,
        windowStart.toIso8601String(),
        windowEnd.toIso8601String(),
      ],
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

  /// Delete an SMS transaction (e.g., false positive).
  Future<void> deleteSmsTransaction(String id) async {
    final db = await _dbHelper.database;
    await db.delete('sms_transactions', where: 'id = ?', whereArgs: [id]);
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
        GROUP BY rawSmsBody
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
