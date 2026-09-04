import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:pet/data/database/database_helper.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/premium/models/recurring_payment.dart';
import 'package:pet/premium/models/recurring_payment_history.dart';

class RecurringPaymentRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  static const String _dismissedKey = 'dismissed_recurring_candidates';

  Future<List<RecurringPayment>> getAll() async {
    final db = await _dbHelper.database;
    final maps = await db.query('recurring_payments', orderBy: 'nextDueAt ASC');
    return maps.map((m) => RecurringPayment.fromMap(m)).toList();
  }

  Future<List<RecurringPayment>> getConfirmed() async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'recurring_payments',
      where: 'status = ?',
      whereArgs: [RecurringStatus.confirmed.toJson()],
      orderBy: 'nextDueAt ASC',
    );
    return maps.map((m) => RecurringPayment.fromMap(m)).toList();
  }

  Future<List<RecurringPayment>> getDetected() async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'recurring_payments',
      where: 'status = ?',
      whereArgs: [RecurringStatus.detected.toJson()],
      orderBy: 'confidence DESC, nextDueAt ASC',
    );
    return maps.map((m) => RecurringPayment.fromMap(m)).toList();
  }

  Future<RecurringPayment?> getById(String id) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'recurring_payments',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return RecurringPayment.fromMap(maps.first);
  }

  Future<void> upsert(RecurringPayment payment) async {
    final db = await _dbHelper.database;
    await db.insert(
      'recurring_payments',
      payment.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> delete(String id) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      await txn.delete('recurring_payment_history', where: 'recurringPaymentId = ?', whereArgs: [id]);
      await txn.delete('recurring_payments', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<void> clearAll() async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      await txn.delete('recurring_payment_history');
      await txn.delete('recurring_payments');
    });
  }

  // ── Payment History Operations ──────────────────────────────────────────────

  Future<List<RecurringPaymentHistory>> getHistory(String recurringPaymentId) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'recurring_payment_history',
      where: 'recurringPaymentId = ?',
      whereArgs: [recurringPaymentId],
      orderBy: 'paidAt DESC',
    );
    return maps.map((m) => RecurringPaymentHistory.fromMap(m)).toList();
  }

  Future<void> insertHistory(RecurringPaymentHistory history) async {
    final db = await _dbHelper.database;
    await db.insert(
      'recurring_payment_history',
      history.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Atomically records an immutable payment history entry and advances the recurring payment schedule.
  Future<void> recordPaymentAndAdvance({
    required RecurringPaymentHistory history,
    required RecurringPayment updatedPayment,
  }) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      await txn.insert(
        'recurring_payment_history',
        history.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.insert(
        'recurring_payments',
        updatedPayment.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  // ── Candidate Dismissal & Suppression (Invariant L) ──────────────────────────

  /// Persists a dismissed candidate merchant so it does not resurrect on subsequent SMS scans.
  Future<void> dismissCandidate(String merchantName) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_dismissedKey) ?? [];
    final norm = merchantName.toLowerCase().trim();
    if (!list.contains(norm)) {
      list.add(norm);
      await prefs.setStringList(_dismissedKey, list);
    }
  }

  /// Removes a merchant from the dismissed list (e.g. on manual add or confirmation).
  Future<void> undismissCandidate(String merchantName) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_dismissedKey) ?? [];
    final norm = merchantName.toLowerCase().trim();
    if (list.contains(norm)) {
      list.remove(norm);
      await prefs.setStringList(_dismissedKey, list);
    }
  }

  /// Fetches the set of dismissed candidate normalized merchant names.
  Future<Set<String>> getDismissedCandidates() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_dismissedKey) ?? [];
    return list.map((s) => s.toLowerCase().trim()).toSet();
  }

  /// Atomically merges newly detected recurring bills without modifying or duplicating
  /// user-confirmed or user-cancelled recurring bills, suppressing user-dismissed candidates.
  Future<void> syncDetectedPayments(List<RecurringPayment> newlyDetected) async {
    final db = await _dbHelper.database;
    final dismissed = await getDismissedCandidates();

    await db.transaction((txn) async {
      // 1. Get current confirmed & cancelled merchant names for deduping
      final existingMaps = await txn.query(
        'recurring_payments',
        columns: ['merchantName', 'status'],
      );
      final activeMerchants = existingMaps
          .where((m) => m['status'] == RecurringStatus.confirmed.toJson() || m['status'] == RecurringStatus.cancelled.toJson())
          .map((m) => (m['merchantName'] as String).toLowerCase().trim())
          .toSet();

      // 2. Clear old unconfirmed detected payments
      await txn.delete(
        'recurring_payments',
        where: 'status = ?',
        whereArgs: [RecurringStatus.detected.toJson()],
      );

      // 3. Insert newly detected payments that don't collide with existing confirmed/cancelled
      // commitments and haven't been dismissed by the user.
      for (final payment in newlyDetected) {
        final norm = payment.merchantName.toLowerCase().trim();
        if (!activeMerchants.contains(norm) && !dismissed.contains(norm)) {
          await txn.insert(
            'recurring_payments',
            payment.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    });
  }
}
