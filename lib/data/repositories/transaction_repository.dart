import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:pet/data/database/database_helper.dart';
import 'package:pet/data/models/transaction.dart';

class TransactionRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  Future<List<TransactionRecord>> getAllTransactions({int limit = 1000}) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'transactions',
      orderBy: 'date DESC',
      limit: limit,
    );
    return maps.map((map) => TransactionRecord.fromMap(map)).toList();
  }

  Future<List<TransactionRecord>> getTransactionsByDateRange(
    DateTime start,
    DateTime end,
  ) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'transactions',
      where: 'date >= ? AND date <= ?',
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
      orderBy: 'date DESC',
    );
    return maps.map((map) => TransactionRecord.fromMap(map)).toList();
  }

  Future<List<TransactionRecord>> getTransactionsByMonth(
    int month,
    int year,
  ) async {
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 0, 23, 59, 59);
    return getTransactionsByDateRange(start, end);
  }

  Future<List<TransactionRecord>> getTransactionsByCategory(
    String categoryId,
  ) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'transactions',
      where: 'categoryId = ?',
      whereArgs: [categoryId],
      orderBy: 'date DESC',
    );
    return maps.map((map) => TransactionRecord.fromMap(map)).toList();
  }

  /// Escapes SQL LIKE wildcard characters in user input to prevent
  /// unexpected matches. The `%` and `_` characters have special meaning
  /// in LIKE patterns and must be escaped when they appear in search terms.
  String _escapeLikePattern(String input) {
    return input
        .replaceAll('\\', '\\\\')
        .replaceAll('%', '\\%')
        .replaceAll('_', '\\_');
  }

  Future<List<TransactionRecord>> searchTransactions(String keyword) async {
    final escaped = _escapeLikePattern(keyword);
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'transactions',
      where: "note LIKE ? ESCAPE '\\' OR paymentMethod LIKE ? ESCAPE '\\'",
      whereArgs: ['%$escaped%', '%$escaped%'],
      orderBy: 'date DESC',
    );
    return maps.map((map) => TransactionRecord.fromMap(map)).toList();
  }

  Future<List<TransactionRecord>> getFilteredTransactions({
    DateTime? startDate,
    DateTime? endDate,
    String? categoryId,
    double? minAmount,
    double? maxAmount,
    String? type,
    String? paymentMethod,
    String? keyword,
  }) async {
    final db = await _dbHelper.database;
    final List<String> whereClauses = [];
    final List<dynamic> whereArgs = [];

    if (startDate != null) {
      whereClauses.add('date >= ?');
      whereArgs.add(startDate.toIso8601String());
    }
    if (endDate != null) {
      whereClauses.add('date <= ?');
      whereArgs.add(endDate.toIso8601String());
    }
    if (categoryId != null) {
      whereClauses.add('categoryId = ?');
      whereArgs.add(categoryId);
    }
    if (minAmount != null) {
      whereClauses.add('amount >= ?');
      whereArgs.add(minAmount);
    }
    if (maxAmount != null) {
      whereClauses.add('amount <= ?');
      whereArgs.add(maxAmount);
    }
    if (type != null) {
      whereClauses.add('type = ?');
      whereArgs.add(type);
    }
    if (paymentMethod != null) {
      whereClauses.add('paymentMethod = ?');
      whereArgs.add(paymentMethod);
    }
    if (keyword != null && keyword.isNotEmpty) {
      final escaped = _escapeLikePattern(keyword);
      whereClauses.add("note LIKE ? ESCAPE '\\'");
      whereArgs.add('%$escaped%');
    }

    final List<Map<String, dynamic>> maps = await db.query(
      'transactions',
      where: whereClauses.isNotEmpty ? whereClauses.join(' AND ') : null,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: 'date DESC',
    );
    return maps.map((map) => TransactionRecord.fromMap(map)).toList();
  }

  Future<void> insertTransaction(TransactionRecord transaction) async {
    final db = await _dbHelper.database;
    await db.insert(
      'transactions',
      transaction.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Insert multiple transactions atomically using a batch.
  Future<void> insertTransactionsBatch(
    List<TransactionRecord> transactions,
  ) async {
    if (transactions.isEmpty) return;
    final db = await _dbHelper.database;
    final batch = db.batch();
    for (final t in transactions) {
      batch.insert(
        'transactions',
        t.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> updateTransaction(TransactionRecord transaction) async {
    final db = await _dbHelper.database;
    await db.update(
      'transactions',
      transaction.toMap(),
      where: 'id = ?',
      whereArgs: [transaction.id],
    );
  }

  Future<void> deleteTransaction(String id) async {
    final db = await _dbHelper.database;
    await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
  }

  /// Delete ALL rows from the transactions table.
  /// Used during sign-out to clear the previous user's local data.
  Future<void> deleteAllTransactions() async {
    final db = await _dbHelper.database;
    await db.delete('transactions');
    await db.delete('sms_transactions');
  }

  Future<double> getTotalByType(String type, int month, int year) async {
    final db = await _dbHelper.database;
    final start = DateTime(year, month, 1).toIso8601String();
    final end = DateTime(year, month + 1, 0, 23, 59, 59).toIso8601String();
    final result = await db.rawQuery(
      'SELECT SUM(amount) as total FROM transactions WHERE type = ? AND date >= ? AND date <= ?',
      [type, start, end],
    );
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  Future<Map<String, double>> getCategoryWiseSpending(
    int month,
    int year,
  ) async {
    final db = await _dbHelper.database;
    final start = DateTime(year, month, 1).toIso8601String();
    final end = DateTime(year, month + 1, 0, 23, 59, 59).toIso8601String();
    final result = await db.rawQuery(
      'SELECT categoryId, SUM(amount) as total FROM transactions WHERE type = ? AND date >= ? AND date <= ? GROUP BY categoryId ORDER BY total DESC',
      ['expense', start, end],
    );
    final Map<String, double> spending = {};
    for (final row in result) {
      spending[row['categoryId'] as String] = (row['total'] as num).toDouble();
    }
    return spending;
  }

  Future<List<Map<String, dynamic>>> getDailySpending(
    int month,
    int year,
  ) async {
    final db = await _dbHelper.database;
    final start = DateTime(year, month, 1).toIso8601String();
    final end = DateTime(year, month + 1, 0, 23, 59, 59).toIso8601String();
    final result = await db.rawQuery(
      'SELECT date, SUM(amount) as total FROM transactions WHERE type = ? AND date >= ? AND date <= ? GROUP BY substr(date, 1, 10) ORDER BY date ASC',
      ['expense', start, end],
    );
    return result;
  }

  Future<double> getSpentInCategory(
    String categoryId,
    int month,
    int year,
  ) async {
    final db = await _dbHelper.database;
    final start = DateTime(year, month, 1).toIso8601String();
    final end = DateTime(year, month + 1, 0, 23, 59, 59).toIso8601String();
    final result = await db.rawQuery(
      'SELECT SUM(amount) as total FROM transactions WHERE categoryId = ? AND type = ? AND date >= ? AND date <= ?',
      [categoryId, 'expense', start, end],
    );
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  /// Delete multiple transactions in a single batch operation.
  ///
  /// Used by Firestore sync reconciliation to avoid O(n) sequential deletes.
  Future<void> deleteTransactionsBatch(List<String> ids) async {
    if (ids.isEmpty) return;
    final db = await _dbHelper.database;
    final batch = db.batch();
    for (final id in ids) {
      batch.delete('transactions', where: 'id = ?', whereArgs: [id]);
    }
    await batch.commit(noResult: true);
  }

  // ── Sync Queue Methods ───────────────────────────────────────────────

  Future<void> enqueueSyncAction(
    String id,
    String transactionId,
    String action,
    String? payload,
    String userId,
  ) async {
    final db = await _dbHelper.database;
    await db.insert('transaction_sync_queue', {
      'id': id,
      'transactionId': transactionId,
      'action': action,
      'payload': payload,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'userId': userId,
      'retryCount': 0,
      'lastAttemptAt': 0,
      'lastError': null,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getPendingSyncActions(
    String userId,
  ) async {
    final db = await _dbHelper.database;
    return await db.query(
      'transaction_sync_queue',
      where: 'userId = ?',
      whereArgs: [userId],
      orderBy: 'timestamp ASC',
    );
  }

  Future<void> deleteSyncAction(String id) async {
    final db = await _dbHelper.database;
    await db.delete('transaction_sync_queue', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> incrementSyncRetry(String id, String error) async {
    final db = await _dbHelper.database;
    await db.rawUpdate(
      'UPDATE transaction_sync_queue SET retryCount = retryCount + 1, lastAttemptAt = ?, lastError = ? WHERE id = ?',
      [DateTime.now().millisecondsSinceEpoch, error, id],
    );
  }

  Future<void> migrateGuestSyncActions(
    String guestUserId,
    String authenticatedUserId,
  ) async {
    final db = await _dbHelper.database;
    await db.update(
      'transaction_sync_queue',
      {'userId': authenticatedUserId},
      where: 'userId = ?',
      whereArgs: [guestUserId],
    );
  }

  Future<void> clearSyncQueueForUser(String userId) async {
    final db = await _dbHelper.database;
    await db.delete(
      'transaction_sync_queue',
      where: 'userId = ?',
      whereArgs: [userId],
    );
  }
}
