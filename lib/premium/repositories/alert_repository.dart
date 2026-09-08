import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:pet/data/database/database_helper.dart';
import 'package:pet/premium/models/app_alert.dart';

class AlertRepository {
  final DatabaseHelper _dbHelper;
  final Database? _database;

  AlertRepository({DatabaseHelper? dbHelper, Database? database})
      : _dbHelper = dbHelper ?? DatabaseHelper(),
        _database = database;

  Database? get database => _database;

  Future<Database> get _db async => _database ?? await _dbHelper.database;

  /// Legacy helper to fetch all alerts ordered by creation time.
  Future<List<AppAlert>> getAll() async {
    final db = await _db;
    final maps = await db.query(
      'alerts',
      where: 'isDismissed = 0',
      orderBy: 'createdAt DESC',
    );
    return maps.map((m) => AppAlert.fromMap(m)).toList();
  }

  /// Bounded query with limit, offset, and rich filtering.
  Future<List<AppAlert>> getPage({
    int limit = 20,
    int offset = 0,
    AppAlertType? type,
    AlertSeverity? severity,
    String? period,
    bool? unreadOnly,
    bool includeDismissed = false,
  }) async {
    final db = await _db;
    final whereClauses = <String>[];
    final whereArgs = <dynamic>[];

    if (!includeDismissed) {
      whereClauses.add('isDismissed = 0');
    }
    if (type != null) {
      whereClauses.add('type = ?');
      whereArgs.add(type.value);
    }
    if (severity != null) {
      whereClauses.add('severity = ?');
      whereArgs.add(severity.value);
    }
    if (period != null) {
      whereClauses.add('period = ?');
      whereArgs.add(period);
    }
    if (unreadOnly == true) {
      whereClauses.add('isRead = 0');
    }

    final whereString =
        whereClauses.isNotEmpty ? whereClauses.join(' AND ') : null;

    final maps = await db.query(
      'alerts',
      where: whereString,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: 'createdAt DESC',
      limit: limit,
      offset: offset,
    );

    return maps.map((m) => AppAlert.fromMap(m)).toList();
  }

  /// Returns unread active alert count using direct SQL COUNT(*).
  Future<int> getUnreadCount() async {
    final db = await _db;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM alerts WHERE isRead = 0 AND isDismissed = 0',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Returns total active (non-dismissed) alert count.
  Future<int> getActiveCount() async {
    final db = await _db;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM alerts WHERE isDismissed = 0',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Checks if an alert with the given unique alertKey already exists.
  Future<bool> existsByKey(String alertKey) async {
    final db = await _db;
    final result = await db.query(
      'alerts',
      columns: ['id'],
      where: 'alertKey = ?',
      whereArgs: [alertKey],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  /// Look up an alert by its ID.
  Future<AppAlert?> getById(String id) async {
    final db = await _db;
    final result = await db.query(
      'alerts',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (result.isEmpty) return null;
    return AppAlert.fromMap(result.first);
  }

  /// Conflict-safe insert for a single alert.
  /// If an alert with the same alertKey was previously auto-resolved (isDismissed == 1 and resolvedAt != null),
  /// it is reactivated (un-dismissed) and updated with fresh amounts.
  /// Returns true if the alert was inserted or reactivated, false if already active or manually dismissed.
  Future<bool> insert(AppAlert alert) async {
    final db = await _db;
    if (alert.alertKey == null) {
      final rowId = await db.insert(
        'alerts',
        alert.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      return rowId > 0;
    }

    final existing = await db.query(
      'alerts',
      where: 'alertKey = ?',
      whereArgs: [alert.alertKey],
      limit: 1,
    );

    if (existing.isEmpty) {
      final rowId = await db.insert(
        'alerts',
        alert.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      return rowId > 0;
    }

    final row = existing.first;
    final isDismissed = (row['isDismissed'] as int? ?? 0) == 1;
    final resolvedAt = row['resolvedAt'] as String?;

    // If already active, it's a no-op (idempotent)
    if (!isDismissed) {
      return false;
    }

    // If manually dismissed by user (resolvedAt is null), honor user dismissal
    if (resolvedAt == null) {
      return false;
    }

    // Previously auto-resolved by system, but condition has re-occurred: reactivate
    final nowStr = DateTime.now().toIso8601String();
    final updated = await db.update(
      'alerts',
      {
        'isDismissed': 0,
        'isRead': 0,
        'resolvedAt': null,
        'updatedAt': nowStr,
        if (alert.amount != null) 'amount': alert.amount,
        if (alert.targetAmount != null) 'targetAmount': alert.targetAmount,
        if (alert.ratio != null) 'ratio': alert.ratio,
        'message': alert.message,
        'title': alert.title,
      },
      where: 'alertKey = ?',
      whereArgs: [alert.alertKey],
    );
    return updated > 0;
  }

  /// Dismiss/resolve alerts matching a custom WHERE condition.
  /// Returns the number of alerts resolved.
  Future<int> dismissWhere(String where, List<dynamic> whereArgs) async {
    final db = await _db;
    final nowStr = DateTime.now().toIso8601String();
    return await db.update(
      'alerts',
      {
        'isDismissed': 1,
        'resolvedAt': nowStr,
        'updatedAt': nowStr,
      },
      where: '$where AND isDismissed = 0',
      whereArgs: whereArgs,
    );
  }

  /// Batch insert alerts in a single SQLite transaction.
  Future<void> insertBatch(List<AppAlert> alerts) async {
    if (alerts.isEmpty) return;
    final db = await _db;
    final batch = db.batch();
    for (final alert in alerts) {
      batch.insert(
        'alerts',
        alert.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Mark an alert as read.
  Future<void> markRead(String id) async {
    final db = await _db;
    final nowStr = DateTime.now().toIso8601String();
    await db.update(
      'alerts',
      {'isRead': 1, 'updatedAt': nowStr},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Mark all active alerts as read in a single SQL operation.
  Future<void> markAllRead({AppAlertType? type}) async {
    final db = await _db;
    final nowStr = DateTime.now().toIso8601String();
    if (type != null) {
      await db.update(
        'alerts',
        {'isRead': 1, 'updatedAt': nowStr},
        where: 'isRead = 0 AND isDismissed = 0 AND type = ?',
        whereArgs: [type.value],
      );
    } else {
      await db.update(
        'alerts',
        {'isRead': 1, 'updatedAt': nowStr},
        where: 'isRead = 0 AND isDismissed = 0',
      );
    }
  }

  /// Dismiss an alert (soft delete).
  Future<void> dismiss(String id) async {
    final db = await _db;
    final nowStr = DateTime.now().toIso8601String();
    await db.update(
      'alerts',
      {'isDismissed': 1, 'updatedAt': nowStr},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Dismiss all read alerts.
  Future<void> dismissAllRead() async {
    final db = await _db;
    final nowStr = DateTime.now().toIso8601String();
    await db.update(
      'alerts',
      {'isDismissed': 1, 'updatedAt': nowStr},
      where: 'isRead = 1 AND isDismissed = 0',
    );
  }

  /// Undo dismissal of an alert.
  Future<void> undoDismiss(String id) async {
    final db = await _db;
    final nowStr = DateTime.now().toIso8601String();
    await db.update(
      'alerts',
      {'isDismissed': 0, 'updatedAt': nowStr},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Permanently delete an alert by ID.
  Future<void> delete(String id) async {
    final db = await _db;
    await db.delete('alerts', where: 'id = ?', whereArgs: [id]);
  }

  /// Delete all alerts.
  Future<void> deleteAll() async {
    final db = await _db;
    await db.delete('alerts');
  }

  /// Purge old dismissed or read alerts older than retention period (e.g. 90 days),
  /// while preserving active/unresolved alerts.
  Future<int> purgeOldDismissedAlerts({
    Duration retention = const Duration(days: 90),
    DateTime? now,
    DateTime? retentionThreshold,
  }) async {
    final db = await _db;
    final cutoff = (retentionThreshold ??
            (now ?? DateTime.now()).subtract(retention))
        .toIso8601String();
    final count = await db.delete(
      'alerts',
      where: '(isDismissed = 1 OR isRead = 1) AND createdAt < ?',
      whereArgs: [cutoff],
    );
    return count;
  }
}
