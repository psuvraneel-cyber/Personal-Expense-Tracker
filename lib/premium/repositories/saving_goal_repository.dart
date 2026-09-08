import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:pet/data/database/database_helper.dart';
import 'package:pet/premium/models/goal_history_item.dart';
import 'package:pet/premium/models/saving_goal.dart';

class SavingGoalRepository {
  final DatabaseHelper _dbHelper;
  final Database? _database;

  SavingGoalRepository({DatabaseHelper? dbHelper, Database? database})
      : _dbHelper = dbHelper ?? DatabaseHelper(),
        _database = database;

  Future<Database> get _db async => _database ?? await _dbHelper.database;

  Future<List<SavingGoal>> getAll() async {
    final db = await _db;
    final maps = await db.query('saving_goals', orderBy: 'createdAt DESC');
    return maps.map((m) => SavingGoal.fromMap(m)).toList();
  }

  Future<SavingGoal?> getById(String id) async {
    final db = await _db;
    final maps = await db.query(
      'saving_goals',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return SavingGoal.fromMap(maps.first);
  }

  Future<void> upsert(SavingGoal goal) async {
    if (goal.currentAmount < 0) {
      throw ArgumentError('SavingGoal currentAmount cannot be negative');
    }
    if (goal.targetAmount <= 0) {
      throw ArgumentError('SavingGoal targetAmount must be positive');
    }
    final db = await _db;
    await db.insert(
      'saving_goals',
      goal.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Deletes a savings goal and cascades deletion to its associated [goal_history] entries.
  /// Goal history is strictly scoped to its parent goal; deleting the goal cleans up historical records.
  Future<void> delete(String id) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('goal_history', where: 'goalId = ?', whereArgs: [id]);
      await txn.delete('saving_goals', where: 'id = ?', whereArgs: [id]);
    });
  }

  /// Deletes all savings goals and all goal history.
  Future<void> deleteAll() async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('goal_history');
      await txn.delete('saving_goals');
    });
  }

  /// Record an append-only audit trail event for a goal.
  ///
  /// Strictly enforces append-only semantics: cannot overwrite or update
  /// existing history records (uses [ConflictAlgorithm.abort]).
  Future<void> addHistory(GoalHistoryItem item) async {
    final db = await _db;
    await db.insert(
      'goal_history',
      item.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  /// Retrieve all history entries for a given [goalId], newest first.
  Future<List<GoalHistoryItem>> getHistory(String goalId) async {
    final db = await _db;
    final maps = await db.query(
      'goal_history',
      where: 'goalId = ?',
      whereArgs: [goalId],
      orderBy: 'createdAt DESC',
    );
    return maps.map((m) => GoalHistoryItem.fromMap(m)).toList();
  }
}
