import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:pet/data/database/database_helper.dart';
import 'package:pet/premium/models/recurring_payment.dart';

class RecurringPaymentRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  Future<List<RecurringPayment>> getAll() async {
    final db = await _dbHelper.database;
    final maps = await db.query('recurring_payments', orderBy: 'nextDueAt ASC');
    return maps.map((m) => RecurringPayment.fromMap(m)).toList();
  }

  Future<void> upsert(RecurringPayment payment) async {
    final db = await _dbHelper.database;
    await db.insert(
      'recurring_payments',
      payment.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> clearAll() async {
    final db = await _dbHelper.database;
    await db.delete('recurring_payments');
  }

  Future<void> delete(String id) async {
    final db = await _dbHelper.database;
    await db.delete('recurring_payments', where: 'id = ?', whereArgs: [id]);
  }

  /// Atomically replaces all records: clears the table and re-inserts
  /// [manuals] and [detected] within a single SQL transaction.
  /// If any insert fails, the entire operation rolls back — no data loss.
  Future<void> replaceAll(
    List<RecurringPayment> manuals,
    List<RecurringPayment> detected,
  ) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      await txn.delete('recurring_payments');
      for (final manual in manuals) {
        await txn.insert(
          'recurring_payments',
          manual.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final payment in detected) {
        await txn.insert(
          'recurring_payments',
          payment.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }
}
