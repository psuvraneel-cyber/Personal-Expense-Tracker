import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:pet/data/database/database_helper.dart';
import 'package:pet/premium/models/family_member.dart';

class FamilyRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  Future<List<FamilyMember>> getAll() async {
    final db = await _dbHelper.database;
    final maps = await db.query('family_members', orderBy: 'name ASC');
    return maps.map((m) => FamilyMember.fromMap(m)).toList();
  }

  Future<void> upsert(FamilyMember member) async {
    final db = await _dbHelper.database;
    await db.insert(
      'family_members',
      member.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> delete(String id) async {
    final db = await _dbHelper.database;
    await db.delete('family_members', where: 'id = ?', whereArgs: [id]);
  }
}
