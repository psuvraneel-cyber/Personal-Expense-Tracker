import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:pet/data/database/database_helper.dart';
import 'package:pet/premium/models/linked_account.dart';

class LinkedAccountRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  Future<List<LinkedAccount>> getAll() async {
    final db = await _dbHelper.database;
    final maps = await db.query('linked_accounts', orderBy: 'accountName ASC');
    return maps.map((m) => LinkedAccount.fromMap(m)).toList();
  }

  Future<void> upsert(LinkedAccount account) async {
    final db = await _dbHelper.database;
    await db.insert(
      'linked_accounts',
      account.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> delete(String id) async {
    final db = await _dbHelper.database;
    await db.delete('linked_accounts', where: 'id = ?', whereArgs: [id]);
  }
}
