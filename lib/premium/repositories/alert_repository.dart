import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:pet/data/database/database_helper.dart';
import 'package:pet/premium/models/budget_alert.dart';

class AlertRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  Future<List<BudgetAlert>> getAll() async {
    final db = await _dbHelper.database;
    final maps = await db.query('alerts', orderBy: 'createdAt DESC');
    return maps.map((m) => BudgetAlert.fromMap(m)).toList();
  }

  Future<bool> existsByKey(String alertKey) async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'alerts',
      where: 'alertKey = ?',
      whereArgs: [alertKey],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  Future<void> insert(BudgetAlert alert) async {
    final db = await _dbHelper.database;
    await db.insert(
      'alerts',
      alert.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> markRead(String id) async {
    final db = await _dbHelper.database;
    await db.update('alerts', {'isRead': 1}, where: 'id = ?', whereArgs: [id]);
  }
}
