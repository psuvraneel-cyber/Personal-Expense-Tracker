import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:pet/core/utils/app_logger.dart';
import 'package:pet/core/utils/calendar_utils.dart';
import 'package:pet/data/database/database_helper.dart';
import 'package:pet/premium/models/weekly_limit.dart';

class WeeklyPlannerRepository {
  final DatabaseHelper _dbHelper;
  final Database? _database;
  static const String _legacyPrefsKey = 'weekly_planner_entries';
  static const Uuid _uuid = Uuid();

  WeeklyPlannerRepository({DatabaseHelper? dbHelper, Database? database})
      : _dbHelper = dbHelper ?? DatabaseHelper(),
        _database = database;

  Future<Database> get _db async => _database ?? await _dbHelper.database;

  Future<List<WeeklyLimit>> getAll() async {
    final db = await _db;
    final maps = await db.query(
      'weekly_limits',
      orderBy: 'categoryName ASC',
    );
    return maps.map((m) => WeeklyLimit.fromMap(m)).toList();
  }

  /// Alias for getAll()
  Future<List<WeeklyLimit>> getAllActive() => getAll();

  /// Retrieves the effective weekly limit for a category.
  /// If an active one-off limit exists specifically for the week containing [forDate],
  /// it overrides the recurring baseline limit for that week.
  Future<WeeklyLimit?> getEffectiveLimit(
    String categoryId, {
    DateTime? forDate,
  }) async {
    final db = await _db;
    final date = forDate ?? DateTime.now();
    final weekStart = CalendarUtils.getWeekStart(date).toIso8601String();

    // 1. Check for one-off limit designated specifically for this week
    final oneOffMaps = await db.query(
      'weekly_limits',
      where: 'categoryId = ? AND recurrencePolicy = ? AND periodStart LIKE ? AND isActive = 1',
      whereArgs: [categoryId, 'oneOff', '$weekStart%'],
      limit: 1,
    );
    if (oneOffMaps.isNotEmpty) {
      return WeeklyLimit.fromMap(oneOffMaps.first);
    }

    // 2. Fall back to recurring baseline limit for this category
    final recurringMaps = await db.query(
      'weekly_limits',
      where: 'categoryId = ? AND recurrencePolicy = ? AND isActive = 1',
      whereArgs: [categoryId, 'recurring'],
      limit: 1,
    );
    if (recurringMaps.isNotEmpty) {
      return WeeklyLimit.fromMap(recurringMaps.first);
    }

    // 3. Fallback to any limit for this category
    final anyMaps = await db.query(
      'weekly_limits',
      where: 'categoryId = ?',
      whereArgs: [categoryId],
      limit: 1,
    );
    if (anyMaps.isNotEmpty) {
      return WeeklyLimit.fromMap(anyMaps.first);
    }
    return null;
  }

  Future<WeeklyLimit?> getByCategoryId(String categoryId, {DateTime? forDate}) =>
      getEffectiveLimit(categoryId, forDate: forDate);

  /// Alias for getByCategoryId()
  Future<WeeklyLimit?> getLimit(String categoryId, {DateTime? forDate}) =>
      getEffectiveLimit(categoryId, forDate: forDate);

  /// Retrieve a specific weekly limit rule by rule ID.
  Future<WeeklyLimit?> getByRuleId(String id) async {
    final db = await _db;
    final maps = await db.query(
      'weekly_limits',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return WeeklyLimit.fromMap(maps.first);
  }

  Future<void> upsert(WeeklyLimit limit) async {
    if (limit.weeklyLimit <= 0) {
      throw ArgumentError('Weekly limit must be greater than zero');
    }
    final db = await _db;
    await db.insert(
      'weekly_limits',
      limit.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> delete(String categoryId, {String? ruleId}) async {
    final db = await _db;
    if (ruleId != null) {
      await db.delete(
        'weekly_limits',
        where: 'id = ?',
        whereArgs: [ruleId],
      );
    } else {
      await db.delete(
        'weekly_limits',
        where: 'categoryId = ?',
        whereArgs: [categoryId],
      );
    }
  }

  /// Alias for delete()
  Future<void> deleteLimit(String categoryId, {String? ruleId}) =>
      delete(categoryId, ruleId: ruleId);

  /// Delete a specific limit rule by ID.
  Future<void> deleteRule(String id) => delete('', ruleId: id);

  Future<void> deleteAll() async {
    final db = await _db;
    await db.delete('weekly_limits');
  }

  /// Migrates legacy preferences into SQLite.
  /// Supports both JSON array 'weekly_planner_entries' and individual `weekly_limit_{catId}` keys.
  Future<void> migrateFromSharedPreferences({
    SharedPreferences? prefsInstance,
    Map<String, String>? categoryNames,
  }) async {
    try {
      final prefs = prefsInstance ?? await SharedPreferences.getInstance();
      final db = await _db;
      final now = DateTime.now();

      // 1. Check legacy JSON list format
      final raw = prefs.getString(_legacyPrefsKey);
      if (raw != null && raw.trim().isNotEmpty) {
        final list = jsonDecode(raw);
        if (list is List) {
          await db.transaction((txn) async {
            for (final item in list) {
              if (item is! Map<String, dynamic>) continue;
              final catId = item['categoryId'] as String?;
              final catName = item['categoryName'] as String?;
              final limit = (item['weeklyLimit'] as num?)?.toDouble();

              if (catId != null && catName != null && limit != null && limit > 0) {
                final weeklyLimit = WeeklyLimit(
                  id: _uuid.v4(),
                  categoryId: catId,
                  categoryName: catName,
                  weeklyLimit: limit,
                  createdAt: now,
                  updatedAt: now,
                );
                await txn.insert(
                  'weekly_limits',
                  weeklyLimit.toMap(),
                  conflictAlgorithm: ConflictAlgorithm.ignore,
                );
              }
            }
          });
          await prefs.remove(_legacyPrefsKey);
        }
      }

      // 2. Check individual weekly_limit_<catId> keys format
      final keys = prefs.getKeys().where((k) => k.startsWith('weekly_limit_')).toList();
      if (keys.isNotEmpty) {
        await db.transaction((txn) async {
          for (final k in keys) {
            final catId = k.substring('weekly_limit_'.length);
            final limit = prefs.getDouble(k) ?? (prefs.getInt(k)?.toDouble());
            if (limit != null && limit > 0) {
              final catName = categoryNames?[catId] ?? catId;
              final weeklyLimit = WeeklyLimit(
                id: _uuid.v4(),
                categoryId: catId,
                categoryName: catName,
                weeklyLimit: limit,
                createdAt: now,
                updatedAt: now,
              );
              await txn.insert(
                'weekly_limits',
                weeklyLimit.toMap(),
                conflictAlgorithm: ConflictAlgorithm.ignore,
              );
            }
          }
        });
        for (final k in keys) {
          await prefs.remove(k);
        }
      }

      AppLogger.info(
        'Successfully completed Weekly Planner SharedPreferences migration to SQLite.',
        label: 'WeeklyPlannerRepo',
      );
    } catch (e, st) {
      AppLogger.error(
        'Weekly Planner SharedPreferences migration failed',
        error: e,
        stack: st,
        label: 'WeeklyPlannerRepo',
      );
    }
  }

  /// Alias for backward compatibility
  Future<void> migrateFromSharedPreferencesIfNeeded({
    SharedPreferences? prefsInstance,
  }) =>
      migrateFromSharedPreferences(prefsInstance: prefsInstance);
}
