import 'dart:convert';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:pet/core/utils/app_logger.dart';
import 'package:pet/data/database/database_helper.dart';
import 'package:pet/data/models/recurring_occurrence.dart';
import 'package:pet/data/models/recurring_rule.dart';
import 'package:pet/data/models/transaction.dart';

/// Repository for persisting, querying, and atomically generating recurring rules
/// and occurrences in SQLite.
class RecurringTransactionRepository {
  final DatabaseHelper _dbHelper;
  final Uuid _uuid = const Uuid();

  RecurringTransactionRepository({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper();

  // ── Rule Queries ─────────────────────────────────────────────────────────

  Future<List<RecurringRule>> getAllRules({String? userId}) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> rows = await db.query(
      'recurring_rules',
      where: userId != null ? 'userId = ? OR userId IS NULL' : null,
      whereArgs: userId != null ? [userId] : null,
      orderBy: 'createdAt DESC',
    );
    return rows.map((r) => RecurringRule.fromMap(r)).toList();
  }

  Future<List<RecurringRule>> getActiveRules({String? userId}) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> rows = await db.query(
      'recurring_rules',
      where: userId != null
          ? 'isActive = 1 AND (userId = ? OR userId IS NULL)'
          : 'isActive = 1',
      whereArgs: userId != null ? [userId] : null,
      orderBy: 'nextOccurrenceDate ASC',
    );
    return rows.map((r) => RecurringRule.fromMap(r)).toList();
  }

  Future<List<RecurringRule>> getDueRules(DateTime now, {String? userId}) async {
    final db = await _dbHelper.database;
    final nowIso = now.toIso8601String();
    final List<Map<String, dynamic>> rows = await db.query(
      'recurring_rules',
      where: userId != null
          ? 'isActive = 1 AND nextOccurrenceDate <= ? AND (userId = ? OR userId IS NULL)'
          : 'isActive = 1 AND nextOccurrenceDate <= ?',
      whereArgs: userId != null ? [nowIso, userId] : [nowIso],
      orderBy: 'nextOccurrenceDate ASC',
    );
    return rows.map((r) => RecurringRule.fromMap(r)).toList();
  }

  Future<RecurringRule?> getRuleById(String id) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> rows = await db.query(
      'recurring_rules',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty) return null;
    return RecurringRule.fromMap(rows.first);
  }

  Future<void> insertRule(RecurringRule rule) async {
    final db = await _dbHelper.database;
    await db.insert(
      'recurring_rules',
      rule.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateRule(RecurringRule rule) async {
    final db = await _dbHelper.database;
    await db.update(
      'recurring_rules',
      rule.toMap(),
      where: 'id = ?',
      whereArgs: [rule.id],
    );
  }

  Future<void> deleteRule(String id) async {
    final db = await _dbHelper.database;
    await db.delete('recurring_rules', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deactivateRule(String id) async {
    final db = await _dbHelper.database;
    await db.update(
      'recurring_rules',
      {
        'isActive': 0,
        'updatedAt': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ── Occurrence Queries ───────────────────────────────────────────────────

  Future<List<RecurringOccurrence>> getOccurrencesForRule(String ruleId) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> rows = await db.query(
      'recurring_occurrences',
      where: 'ruleId = ?',
      whereArgs: [ruleId],
      orderBy: 'scheduledDate DESC',
    );
    return rows.map((r) => RecurringOccurrence.fromMap(r)).toList();
  }

  Future<RecurringOccurrence?> getOccurrence(
    String ruleId,
    DateTime scheduledDate,
  ) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> rows = await db.query(
      'recurring_occurrences',
      where: 'ruleId = ? AND scheduledDate = ?',
      whereArgs: [ruleId, scheduledDate.toIso8601String()],
    );
    if (rows.isEmpty) return null;
    return RecurringOccurrence.fromMap(rows.first);
  }

  Future<RecurringOccurrence?> getOccurrenceByTransactionId(
    String transactionId,
  ) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> rows = await db.query(
      'recurring_occurrences',
      where: 'transactionId = ?',
      whereArgs: [transactionId],
    );
    if (rows.isEmpty) return null;
    return RecurringOccurrence.fromMap(rows.first);
  }

  // ── Atomic Generation & Idempotency Engine ───────────────────────────────

  /// Atomically creates a transaction, records the occurrence, advances the rule's
  /// nextOccurrenceDate, and enqueues sync actions in a single SQLite transaction.
  ///
  /// Returns the newly created [TransactionRecord], or `null` if the occurrence was
  /// already generated or skipped (idempotent no-op).
  Future<TransactionRecord?> atomicGenerateOccurrence({
    required RecurringRule rule,
    required DateTime scheduledDate,
    required TransactionRecord transaction,
    required DateTime nextOccurrenceDate,
    String? userId,
  }) async {
    final db = await _dbHelper.database;

    return await db.transaction((txn) async {
      final scheduledDateIso = scheduledDate.toIso8601String();
      final occId = RecurringOccurrence.generateId(rule.id, scheduledDate);

      // Check if occurrence already exists (idempotency guard)
      final existingOccurrences = await txn.query(
        'recurring_occurrences',
        where: 'ruleId = ? AND scheduledDate = ?',
        whereArgs: [rule.id, scheduledDateIso],
      );

      if (existingOccurrences.isNotEmpty) {
        AppLogger.debug(
          '[RecurringRepo] Occurrence $occId already exists (status: ${existingOccurrences.first['status']}). Skipping.',
          label: 'Recurring',
        );
        // Advance rule nextOccurrenceDate if rule is still stuck behind
        await txn.update(
          'recurring_rules',
          {
            'nextOccurrenceDate': nextOccurrenceDate.toIso8601String(),
            'updatedAt': DateTime.now().toIso8601String(),
          },
          where: 'id = ? AND nextOccurrenceDate <= ?',
          whereArgs: [rule.id, scheduledDateIso],
        );
        return null;
      }

      // 1. Insert the generated TransactionRecord into transactions table
      await txn.insert(
        'transactions',
        transaction.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // 2. Insert occurrence record
      final occurrence = RecurringOccurrence(
        id: occId,
        ruleId: rule.id,
        scheduledDate: scheduledDate,
        status: RecurringOccurrenceStatus.generated,
        transactionId: transaction.id,
        generatedAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await txn.insert(
        'recurring_occurrences',
        occurrence.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // 3. Advance the recurring rule's nextOccurrenceDate and lastGeneratedDate
      final nowStr = DateTime.now().toIso8601String();
      await txn.update(
        'recurring_rules',
        {
          'nextOccurrenceDate': nextOccurrenceDate.toIso8601String(),
          'lastGeneratedDate': scheduledDateIso,
          'updatedAt': nowStr,
        },
        where: 'id = ?',
        whereArgs: [rule.id],
      );

      // 4. Enqueue sync action for the new transaction
      final effectiveUserId = userId ?? rule.userId ?? 'guest_user';
      await txn.insert(
        'transaction_sync_queue',
        {
          'id': _uuid.v4(),
          'transactionId': transaction.id,
          'action': 'create',
          'payload': jsonEncode(transaction.toMap()),
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'userId': effectiveUserId,
          'retryCount': 0,
          'lastAttemptAt': 0,
          'lastError': null,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      AppLogger.info(
        '[RecurringRepo] Generated occurrence for rule ${rule.id} at $scheduledDateIso (txn: ${transaction.id})',
        label: 'Recurring',
      );

      return transaction;
    });
  }

  /// Marks a specific occurrence as skipped so it will never be generated.
  Future<void> markOccurrenceSkipped({
    required String ruleId,
    required DateTime scheduledDate,
    DateTime? nextOccurrenceDate,
  }) async {
    final db = await _dbHelper.database;
    final occId = RecurringOccurrence.generateId(ruleId, scheduledDate);
    final now = DateTime.now();

    await db.transaction((txn) async {
      await txn.insert(
        'recurring_occurrences',
        {
          'id': occId,
          'ruleId': ruleId,
          'scheduledDate': scheduledDate.toIso8601String(),
          'status': RecurringOccurrenceStatus.skipped.toJson(),
          'transactionId': null,
          'generatedAt': null,
          'updatedAt': now.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      if (nextOccurrenceDate != null) {
        await txn.update(
          'recurring_rules',
          {
            'nextOccurrenceDate': nextOccurrenceDate.toIso8601String(),
            'updatedAt': now.toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [ruleId],
        );
      }
    });
  }

  /// Deletes a generated transaction occurrence and marks the occurrence record as skipped.
  Future<void> deleteOccurrenceAndSkip({
    required String transactionId,
    required String ruleId,
    required DateTime scheduledDate,
    String? userId,
  }) async {
    final db = await _dbHelper.database;
    final occId = RecurringOccurrence.generateId(ruleId, scheduledDate);
    final now = DateTime.now();

    await db.transaction((txn) async {
      // 1. Delete transaction
      await txn.delete('transactions', where: 'id = ?', whereArgs: [transactionId]);

      // 2. Mark occurrence as skipped
      await txn.insert(
        'recurring_occurrences',
        {
          'id': occId,
          'ruleId': ruleId,
          'scheduledDate': scheduledDate.toIso8601String(),
          'status': RecurringOccurrenceStatus.skipped.toJson(),
          'transactionId': null,
          'generatedAt': null,
          'updatedAt': now.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // 3. Enqueue delete action for Firestore sync
      final effectiveUserId = userId ?? 'guest_user';
      await txn.insert(
        'transaction_sync_queue',
        {
          'id': _uuid.v4(),
          'transactionId': transactionId,
          'action': 'delete',
          'payload': null,
          'timestamp': now.millisecondsSinceEpoch,
          'userId': effectiveUserId,
          'retryCount': 0,
          'lastAttemptAt': 0,
          'lastError': null,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  /// Deletes a recurring rule and all related transactions generated by it.
  Future<void> deleteRuleAndAllOccurrences(String ruleId, {String? userId}) async {
    final db = await _dbHelper.database;
    final effectiveUserId = userId ?? 'guest_user';

    await db.transaction((txn) async {
      // 1. Find all generated transactions for this rule
      final rows = await txn.query(
        'transactions',
        columns: ['id'],
        where: 'recurringRuleId = ?',
        whereArgs: [ruleId],
      );

      // 2. Delete transactions and enqueue deletes
      for (final row in rows) {
        final tId = row['id'] as String;
        await txn.delete('transactions', where: 'id = ?', whereArgs: [tId]);
        await txn.insert(
          'transaction_sync_queue',
          {
            'id': _uuid.v4(),
            'transactionId': tId,
            'action': 'delete',
            'payload': null,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
            'userId': effectiveUserId,
            'retryCount': 0,
            'lastAttemptAt': 0,
            'lastError': null,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      // 3. Delete occurrences
      await txn.delete('recurring_occurrences', where: 'ruleId = ?', whereArgs: [ruleId]);

      // 4. Delete rule
      await txn.delete('recurring_rules', where: 'id = ?', whereArgs: [ruleId]);
    });
  }

  /// Wipes all recurring tables (used during account deletion/reset).
  Future<void> deleteAllRecurringData() async {
    final db = await _dbHelper.database;
    await db.delete('recurring_occurrences');
    await db.delete('recurring_rules');
  }
}
