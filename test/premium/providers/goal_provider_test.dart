import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pet/data/database/database_helper.dart';
import 'package:pet/premium/providers/goal_provider.dart';
import 'package:pet/premium/services/notification_preferences_service.dart';
import 'package:pet/premium/services/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    NotificationService.resetForTest();
    await NotificationPreferencesService.instance.load();

    final db = await openDatabase(
      inMemoryDatabasePath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE saving_goals (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            targetAmount REAL NOT NULL,
            currentAmount REAL NOT NULL,
            createdAt TEXT NOT NULL,
            targetDate TEXT,
            emoji TEXT,
            isPaused INTEGER NOT NULL DEFAULT 0
          )
        ''');
      },
    );
    DatabaseHelper.setTestDatabase(db);
  });

  tearDown(() {
    DatabaseHelper.setTestDatabase(null);
  });

  group('GoalProvider goal achievement notification', () {
    test('topUpGoal crossing target amount threshold fires notification', () async {
      final provider = GoalProvider();
      await provider.addGoal(
        name: 'New Bike',
        targetAmount: 5000,
      );

      final goalId = provider.goals.first.id;
      expect(provider.goals.first.currentAmount, 0);
      expect(NotificationService.pendingCount, 0);

      // Top up by 5000 -> reaches target
      await provider.topUpGoal(goalId, 5000);

      expect(provider.goals.first.currentAmount, 5000);
      expect(NotificationService.pendingCount, 1);
    });

    test('topUpGoal on already-achieved goal does not fire a second notification', () async {
      final provider = GoalProvider();
      await provider.addGoal(
        name: 'Emergency Fund',
        targetAmount: 2000,
      );

      final goalId = provider.goals.first.id;

      // Reaches target (1st notification queued)
      await provider.topUpGoal(goalId, 2000);
      expect(NotificationService.pendingCount, 1);

      NotificationService.resetForTest();
      expect(NotificationService.pendingCount, 0);

      // Top up again on already-achieved goal
      await provider.topUpGoal(goalId, 1000);

      expect(NotificationService.pendingCount, 0);
    });

    test('topUpGoal when still below target does not fire notification', () async {
      final provider = GoalProvider();
      await provider.addGoal(
        name: 'Laptop',
        targetAmount: 10000,
      );

      final goalId = provider.goals.first.id;
      expect(NotificationService.pendingCount, 0);

      // Top up partial amount
      await provider.topUpGoal(goalId, 3000);

      expect(NotificationService.pendingCount, 0);
    });
  });
}
