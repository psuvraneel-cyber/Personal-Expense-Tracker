import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:pet/data/database/database_helper.dart';
import 'package:pet/data/models/budget.dart';

class BudgetRepository {
  final DatabaseHelper _dbHelper;
  final Database? _database;

  BudgetRepository({DatabaseHelper? dbHelper, Database? database})
      : _dbHelper = dbHelper ?? DatabaseHelper(),
        _database = database;

  Future<Database> get _db async => _database ?? await _dbHelper.database;

  Future<List<Budget>> getBudgetsByMonth(int month, int year) async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.query(
      'budgets',
      where: 'month = ? AND year = ?',
      whereArgs: [month, year],
    );
    return maps.map((map) => Budget.fromMap(map)).toList();
  }

  Future<Budget?> getBudgetForCategory(
    String categoryId,
    int month,
    int year,
  ) async {
    final db = await _db;
    final List<Map<String, dynamic>> maps = await db.query(
      'budgets',
      where: 'categoryId = ? AND month = ? AND year = ?',
      whereArgs: [categoryId, month, year],
    );
    if (maps.isEmpty) return null;
    return Budget.fromMap(maps.first);
  }

  Future<void> insertOrUpdateBudget(Budget budget) async {
    final db = await _db;
    await db.insert(
      'budgets',
      budget.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteBudget(String id) async {
    final db = await _db;
    await db.delete('budgets', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteBudgetForCategory(
    String categoryId,
    int month,
    int year,
  ) async {
    final db = await _db;
    await db.delete(
      'budgets',
      where: 'categoryId = ? AND month = ? AND year = ?',
      whereArgs: [categoryId, month, year],
    );
  }

  /// Delete ALL budgets from the database.
  /// Used during sign-out to clear the previous user's local data.
  Future<void> deleteAllBudgets() async {
    final db = await _dbHelper.database;
    await db.delete('budgets');
  }
}
