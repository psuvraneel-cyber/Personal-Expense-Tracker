import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pet/data/database/database_helper.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/data/repositories/transaction_repository.dart';
import 'package:pet/models/account_session.dart';
import 'package:pet/providers/transaction_provider.dart';
import 'package:pet/services/firestore_sync_service.dart';

class _OfflineSync implements FirestoreSyncService {
  @override
  bool get isAuthenticated => false;
  @override
  String? get currentUserIdOrNull => null;
  @override
  AccountSession get currentSession =>
      const AccountSession(uid: null, generation: 1);
  @override
  Stream<List<TransactionRecord>> transactionsStream({int? limit = 1000}) =>
      const Stream.empty();
  @override
  Stream<List<Map<String, dynamic>>> tombstonesStream() => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Audit P2-12 (search) and P2-13 (date filter boundaries).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late TransactionProvider provider;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(
      inMemoryDatabasePath,
      version: kDatabaseVersion,
      onCreate: (db, v) => DatabaseHelper().onCreateForTesting(db, v),
    );
    DatabaseHelper.setTestDatabase(db);
    final repo = TransactionRepository();
    TransactionRecord t(String id, DateTime date, {String? merchant}) =>
        TransactionRecord(
          id: id,
          amount: 250,
          type: TransactionType.expense,
          categoryId: 'food',
          date: date,
          merchantName: merchant,
          updatedAt: date,
        );
    await repo.insertTransaction(t('eve', DateTime(2026, 5, 4, 21)));
    await repo.insertTransaction(t('start', DateTime(2026, 5, 5, 9)));
    await repo.insertTransaction(
        t('end', DateTime(2026, 5, 10, 23, 30), merchant: 'Swiggy'));
    await repo.insertTransaction(t('after', DateTime(2026, 5, 11, 0, 5)));

    provider =
        TransactionProvider(repository: repo, firestoreSync: _OfflineSync())
          ..categoryNameLookup = (id) => id == 'food' ? 'Food & Dining' : null;
    await provider.reloadFromLocal();
  });

  tearDown(() async {
    await db.close();
    DatabaseHelper.setTestDatabase(null);
  });

  test('date range is inclusive of whole start/end days only', () {
    provider.setFilters(
      startDate: DateTime(2026, 5, 5),
      endDate: DateTime(2026, 5, 10),
    );
    expect(provider.transactions.map((t) => t.id).toSet(), {'start', 'end'});
  });

  test('search matches merchant name and category name', () {
    provider.setSearchQuery('swiggy');
    expect(provider.transactions.map((t) => t.id), ['end']);
    provider.setSearchQuery('dining');
    expect(provider.transactions, hasLength(4));
  });
}
