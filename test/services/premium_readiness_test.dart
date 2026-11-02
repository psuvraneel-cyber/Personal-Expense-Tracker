import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pet/data/database/database_helper.dart';
import 'package:pet/premium/providers/linked_account_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;

  setUp(() async {
    db = await openDatabase(
      inMemoryDatabasePath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE linked_accounts (
            id TEXT PRIMARY KEY,
            accountName TEXT,
            institutionName TEXT,
            accountType TEXT,
            balance REAL,
            currency TEXT,
            lastSyncedAt TEXT
          )
        ''');
      },
    );
    DatabaseHelper.setTestDatabase(db);
  });

  tearDown(() async {
    await db.close();
    DatabaseHelper.setTestDatabase(null);
  });

  group('Premium Readiness Gating Tests', () {
    test(
      'LinkedAccountProvider prevents mock data connection in production configuration',
      () async {
        final provider = LinkedAccountProvider();

        // Enforce production mode
        provider.isTesting = false;

        // 1. Loading when empty should NOT pull mock aggregator feeds
        await provider.load();
        expect(provider.accounts, isEmpty);

        // 2. Tapping connect mock account must raise UnsupportedError
        expect(
          () => provider.connectMockAccount(),
          throwsA(isA<UnsupportedError>()),
        );
      },
    );
  });
}
