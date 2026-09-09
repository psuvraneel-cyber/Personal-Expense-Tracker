import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pet/data/database/database_helper.dart';
import 'package:pet/models/account_session.dart';
import 'package:pet/premium/models/weekly_limit.dart';
import 'package:pet/premium/providers/weekly_planner_provider.dart';
import 'package:pet/premium/repositories/weekly_planner_repository.dart';
import 'package:pet/services/firestore_sync_service.dart';

class MockWeeklyPlannerSyncService implements FirestoreSyncService {
  String? _uid;
  int _generation = 1;

  final StreamController<List<WeeklyLimit>> weeklyLimitsController =
      StreamController<List<WeeklyLimit>>.broadcast();

  final List<WeeklyLimit> upsertedLimits = [];
  final List<String> deletedLimitIds = [];

  void setSession(String? uid, int generation) {
    _uid = uid;
    _generation = generation;
  }

  @override
  bool get isAuthenticated => _uid != null;

  @override
  String? get currentUserIdOrNull => _uid;

  @override
  String get currentUserId {
    if (_uid == null) throw StateError('Not authenticated');
    return _uid!;
  }

  @override
  int get sessionGeneration => _generation;

  @override
  AccountSession get currentSession =>
      AccountSession(uid: _uid, generation: _generation);

  @override
  Stream<List<WeeklyLimit>> weeklyLimitsStream() =>
      weeklyLimitsController.stream;

  @override
  Future<void> upsertWeeklyLimit(WeeklyLimit limit) async {
    upsertedLimits.add(limit);
  }

  @override
  Future<void> deleteWeeklyLimit(String categoryId) async {
    deletedLimitIds.add(categoryId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late WeeklyPlannerRepository repository;
  late MockWeeklyPlannerSyncService fakeSync;
  late WeeklyPlannerProvider provider;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(
      inMemoryDatabasePath,
      version: 20,
      onCreate: (db, version) async {
        await DatabaseHelper().onCreateForTesting(db, version);
      },
    );
    repository = WeeklyPlannerRepository(database: db);
    fakeSync = MockWeeklyPlannerSyncService();
    provider =
        WeeklyPlannerProvider(repository: repository, firestoreSync: fakeSync);
  });

  tearDown(() async {
    provider.dispose();
    await db.close();
  });

  group('WeeklyPlanner Firestore Sync Parity & Session Guards', () {
    test(
        'mirrors setLimit and removeLimit mutations to cloud when authenticated',
        () async {
      fakeSync.setSession('user-A', 1);

      await provider.setLimit(
        categoryId: 'groceries',
        categoryName: 'Groceries',
        weeklyLimit: 2500,
      );

      expect(fakeSync.upsertedLimits, hasLength(1));
      expect(fakeSync.upsertedLimits.first.categoryId, 'groceries');
      expect(fakeSync.upsertedLimits.first.weeklyLimit, 2500.0);

      await provider.removeLimit('groceries');

      expect(fakeSync.deletedLimitIds, contains('groceries'));
    });

    test('consumes incoming remote weekly limits and updates local state',
        () async {
      fakeSync.setSession('user-A', 1);
      await provider.load();

      final now = DateTime.now();
      final remoteLimit = WeeklyLimit(
        id: 'dining',
        categoryId: 'dining',
        categoryName: 'Dining Out',
        weeklyLimit: 1200,
        createdAt: now,
        updatedAt: now,
      );

      fakeSync.weeklyLimitsController.add([remoteLimit]);
      await pumpEventQueue();

      expect(provider.entries, hasLength(1));
      expect(provider.entries.first.categoryId, 'dining');
      expect(provider.entries.first.weeklyLimit, 1200.0);
    });

    test('ignores stream events received after session mismatch / switch',
        () async {
      fakeSync.setSession('user-A', 1);
      await provider.load();

      // Switch session before event arrives
      fakeSync.setSession('user-B', 2);

      final now = DateTime.now();
      final staleLimit = WeeklyLimit(
        id: 'travel',
        categoryId: 'travel',
        categoryName: 'Travel',
        weeklyLimit: 5000,
        createdAt: now,
        updatedAt: now,
      );

      fakeSync.weeklyLimitsController.add([staleLimit]);
      await pumpEventQueue();

      // Should be ignored due to mismatched session guard
      expect(provider.entries, isEmpty);
    });

    test(
        'clearData unhooks remote stream so subsequent events do not resurrect entries',
        () async {
      fakeSync.setSession('user-A', 1);
      await provider.load();

      await provider.clearData();

      final now = DateTime.now();
      final ghostLimit = WeeklyLimit(
        id: 'entertainment',
        categoryId: 'entertainment',
        categoryName: 'Entertainment',
        weeklyLimit: 800,
        createdAt: now,
        updatedAt: now,
      );

      fakeSync.weeklyLimitsController.add([ghostLimit]);
      await pumpEventQueue();

      expect(provider.entries, isEmpty);
    });
  });
}
