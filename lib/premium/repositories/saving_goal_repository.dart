import 'package:sqflite/sqflite.dart';
import 'package:pet/data/database/database_helper.dart';
import 'package:pet/premium/models/saving_goal.dart';

class SavingGoalRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  Future<List<SavingGoal>> getAll() async {
    final db = await _dbHelper.database;
    final maps = await db.query('saving_goals', orderBy: 'createdAt DESC');
    return maps.map((m) => SavingGoal.fromMap(m)).toList();
  }

  Future<void> upsert(SavingGoal goal) async {
    if (goal.currentAmount < 0) {
      throw ArgumentError('SavingGoal currentAmount cannot be negative');
    }
    final db = await _dbHelper.database;
    await db.insert(
      'saving_goals',
      goal.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> delete(String id) async {
    final db = await _dbHelper.database;
    await db.delete('saving_goals', where: 'id = ?', whereArgs: [id]);
  }
}
