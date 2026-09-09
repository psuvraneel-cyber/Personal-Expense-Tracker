import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:pet/data/database/database_helper.dart';
import 'package:pet/premium/models/weekly_limit.dart';
import 'package:pet/premium/repositories/weekly_planner_repository.dart';

void main() {
  late Directory tempDir;
  late String dbPath;
  late Database db;
  late WeeklyPlannerRepository repository;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync();
    dbPath = p.join(tempDir.path, 'weekly_repo_test.db');

    db = await openDatabase(
      dbPath,
      version: 20,
      onCreate: (d, v) async {
        await DatabaseHelper().onCreateForTesting(d, v);
      },
    );

    repository = WeeklyPlannerRepository(database: db);
  });

  tearDown(() async {
    try {
      await db.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('WeeklyPlannerRepository CRUD Tests', () {
    test('upsert and getLimit returns correct entity', () async {
      final now = DateTime(2026, 3, 9, 10, 0);
      final limit = WeeklyLimit(
        id: 'limit-groceries',
        categoryId: 'cat-food',
        categoryName: 'Food & Dining',
        weeklyLimit: 2500,
        createdAt: now,
        updatedAt: now,
        isActive: true,
      );

      await repository.upsert(limit);

      final retrieved = await repository.getLimit('cat-food');
      expect(retrieved, isNotNull);
      expect(retrieved!.id, 'limit-groceries');
      expect(retrieved.categoryId, 'cat-food');
      expect(retrieved.categoryName, 'Food & Dining');
      expect(retrieved.weeklyLimit, 2500.0);
      expect(retrieved.isActive, isTrue);
    });

    test('updating existing limit changes amount and updatedAt', () async {
      final now = DateTime(2026, 3, 9, 10, 0);
      final limit1 = WeeklyLimit(
        id: 'limit-shopping',
        categoryId: 'cat-shop',
        categoryName: 'Shopping',
        weeklyLimit: 1500,
        createdAt: now,
        updatedAt: now,
      );
      await repository.upsert(limit1);

      final later = now.add(const Duration(days: 2));
      final limit2 = limit1.copyWith(
        weeklyLimit: 3000,
        updatedAt: later,
      );
      await repository.upsert(limit2);

      final active = await repository.getAllActive();
      expect(active.length, 1);
      expect(active.first.weeklyLimit, 3000.0);
      expect(active.first.updatedAt, later);
    });

    test('deleteLimit removes limit by categoryId', () async {
      final limit = WeeklyLimit(
        id: 'limit-travel',
        categoryId: 'cat-travel',
        categoryName: 'Travel',
        weeklyLimit: 1000,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await repository.upsert(limit);
      expect(await repository.getLimit('cat-travel'), isNotNull);

      await repository.deleteLimit('cat-travel');
      expect(await repository.getLimit('cat-travel'), isNull);
    });

    test('wipeAllUserData clears weekly_limits table completely', () async {
      await repository.upsert(WeeklyLimit(
        id: 'limit-1',
        categoryId: 'c1',
        categoryName: 'Cat 1',
        weeklyLimit: 500,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
      await repository.upsert(WeeklyLimit(
        id: 'limit-2',
        categoryId: 'c2',
        categoryName: 'Cat 2',
        weeklyLimit: 1200,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      expect((await repository.getAllActive()).length, 2);

      // Perform atomic wipe on database helper
      await DatabaseHelper().wipeAllUserData(db: db);

      expect((await repository.getAllActive()).isEmpty, isTrue);
    });

    test(
        'supports both recurring baseline and designated one-off for same category',
        () async {
      final now = DateTime(2026, 3, 9, 10, 0); // Monday of week
      final recurringRule = WeeklyLimit(
        id: 'rule-recurring-food',
        categoryId: 'cat-food',
        categoryName: 'Food',
        weeklyLimit: 2000,
        createdAt: now,
        updatedAt: now,
        recurrencePolicy: WeeklyRecurrencePolicy.recurring,
      );

      final oneOffRule = WeeklyLimit(
        id: 'rule-one-off-food-festive',
        categoryId: 'cat-food',
        categoryName: 'Food',
        weeklyLimit: 5000,
        createdAt: now,
        updatedAt: now,
        recurrencePolicy: WeeklyRecurrencePolicy.oneOff,
        periodStart: DateTime(2026, 3, 9),
      );

      // Both can be persisted without UNIQUE constraint violation
      await repository.upsert(recurringRule);
      await repository.upsert(oneOffRule);

      final all = await repository.getAllActive();
      expect(all.length, 2);

      // For that specific designated week, getEffectiveLimit returns the one-off rule (5000)
      final effectiveThisWeek = await repository.getEffectiveLimit('cat-food',
          forDate: DateTime(2026, 3, 11));
      expect(effectiveThisWeek, isNotNull);
      expect(effectiveThisWeek!.id, 'rule-one-off-food-festive');
      expect(effectiveThisWeek.weeklyLimit, 5000.0);
      expect(effectiveThisWeek.recurrencePolicy, WeeklyRecurrencePolicy.oneOff);

      // For a different week, getEffectiveLimit falls back to the recurring baseline rule (2000)
      final effectiveNextWeek = await repository.getEffectiveLimit('cat-food',
          forDate: DateTime(2026, 3, 18));
      expect(effectiveNextWeek, isNotNull);
      expect(effectiveNextWeek!.id, 'rule-recurring-food');
      expect(effectiveNextWeek.weeklyLimit, 2000.0);
      expect(
          effectiveNextWeek.recurrencePolicy, WeeklyRecurrencePolicy.recurring);
    });

    test('retrieves and deletes specific rules by rule id', () async {
      final now = DateTime(2026, 3, 9, 10, 0);
      final rule = WeeklyLimit(
        id: 'rule-specific-123',
        categoryId: 'cat-gym',
        categoryName: 'Gym',
        weeklyLimit: 1200,
        createdAt: now,
        updatedAt: now,
      );

      await repository.upsert(rule);
      final fetched = await repository.getByRuleId('rule-specific-123');
      expect(fetched, isNotNull);
      expect(fetched!.categoryName, 'Gym');

      await repository.deleteRule('rule-specific-123');
      expect(await repository.getByRuleId('rule-specific-123'), isNull);
    });
  });

  group('WeeklyPlannerRepository Legacy SharedPreferences Migration', () {
    test('migrates legacy preferences into SQLite and sets completion flag',
        () async {
      SharedPreferences.setMockInitialValues({
        'weekly_limit_cat-dining': 2000.0,
        'weekly_limit_cat-fuel': 1500.0,
      });

      final categoryNames = {
        'cat-dining': 'Dining',
        'cat-fuel': 'Fuel',
      };

      await repository.migrateFromSharedPreferences(
          categoryNames: categoryNames);

      final active = await repository.getAllActive();
      expect(active.length, 2);

      final dining = active.firstWhere((l) => l.categoryId == 'cat-dining');
      expect(dining.weeklyLimit, 2000.0);
      expect(dining.categoryName, 'Dining');

      final fuel = active.firstWhere((l) => l.categoryId == 'cat-fuel');
      expect(fuel.weeklyLimit, 1500.0);
      expect(fuel.categoryName, 'Fuel');

      // Subsequent migration invocation should be idempotent and not duplicate
      await repository.migrateFromSharedPreferences(
          categoryNames: categoryNames);
      expect((await repository.getAllActive()).length, 2);
    });
  });
}
