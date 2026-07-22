import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:pet/data/database/database_helper.dart';
import 'package:pet/data/models/unknown_format_log.dart';

/// Repository for unknown format logs.
/// All data is stored locally on-device via sqflite.
class ClassificationRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  // ═══════════════════════════════════════════════════════════════════
  //  UNKNOWN FORMAT LOGS
  // ═══════════════════════════════════════════════════════════════════

  /// Get all unknown format logs, ordered by occurrence count descending.
  Future<List<UnknownFormatLog>> getAllUnknownLogs() async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'unknown_format_logs',
      orderBy: 'occurrenceCount DESC, timestamp DESC',
    );
    return maps.map((m) => UnknownFormatLog.fromMap(m)).toList();
  }

  /// Get only unresolved unknown format logs.
  Future<List<UnknownFormatLog>> getUnresolvedLogs() async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'unknown_format_logs',
      where: 'isResolved = 0',
      orderBy: 'occurrenceCount DESC, timestamp DESC',
    );
    return maps.map((m) => UnknownFormatLog.fromMap(m)).toList();
  }

  /// Insert or increment an unknown format log.
  /// If a log with the same bodyHash exists, increment its occurrence count.
  /// Returns the log entry (existing or new).
  Future<UnknownFormatLog> upsertUnknownLog(UnknownFormatLog log) async {
    final db = await _dbHelper.database;

    // Check for existing entry with same body hash
    final existing = await db.query(
      'unknown_format_logs',
      where: 'bodyHash = ?',
      whereArgs: [log.bodyHash],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      // Increment occurrence count
      final existingLog = UnknownFormatLog.fromMap(existing.first);
      final updated = existingLog.copyWith(
        occurrenceCount: existingLog.occurrenceCount + 1,
        timestamp: log.timestamp, // Update to latest occurrence
      );
      await db.update(
        'unknown_format_logs',
        updated.toMap(),
        where: 'id = ?',
        whereArgs: [existingLog.id],
      );
      return updated;
    }

    // Insert new entry
    await db.insert(
      'unknown_format_logs',
      log.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    return log;
  }

  /// Mark a log entry as reviewed.
  Future<void> markLogReviewed(String id) async {
    final db = await _dbHelper.database;
    await db.update(
      'unknown_format_logs',
      {'isReviewed': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Mark a log entry as resolved (rule created from it).
  Future<void> markLogResolved(String logId, String ruleId) async {
    final db = await _dbHelper.database;
    await db.update(
      'unknown_format_logs',
      {'isResolved': 1, 'resolvedRuleId': ruleId},
      where: 'id = ?',
      whereArgs: [logId],
    );
  }

  /// Delete an unknown format log.
  Future<void> deleteUnknownLog(String id) async {
    final db = await _dbHelper.database;
    await db.delete('unknown_format_logs', where: 'id = ?', whereArgs: [id]);
  }

  /// Delete all resolved logs.
  Future<int> deleteResolvedLogs() async {
    final db = await _dbHelper.database;
    return await db.delete('unknown_format_logs', where: 'isResolved = 1');
  }

  /// Get the count of unresolved unknown format logs.
  Future<int> getUnresolvedCount() async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM unknown_format_logs WHERE isResolved = 0',
    );
    return (result.first['count'] as int?) ?? 0;
  }

  /// Add a user note to a log entry.
  Future<void> updateLogNote(String id, String note) async {
    final db = await _dbHelper.database;
    await db.update(
      'unknown_format_logs',
      {'userNote': note},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
