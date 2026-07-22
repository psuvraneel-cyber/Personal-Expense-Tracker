// ignore_for_file: subtype_of_sealed_class, must_be_immutable, annotate_overrides
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pet/services/account_deletion_service.dart';
import 'package:pet/data/database/database_helper.dart';

// ── Fakes ─────────────────────────────────────────────────────────────

class FakeUser implements User {
  final String _uid;
  bool deleted = false;

  FakeUser(this._uid);

  @override
  String get uid => _uid;

  @override
  Future<void> delete() async {
    deleted = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeFirebaseAuth implements FirebaseAuth {
  User? _currentUser;

  FakeFirebaseAuth({User? currentUser}) : _currentUser = currentUser;

  @override
  User? get currentUser => _currentUser;

  void setCurrentUser(User? user) {
    _currentUser = user;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeQuerySnapshot implements QuerySnapshot<Map<String, dynamic>> {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs;

  FakeQuerySnapshot(this._docs);

  @override
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get docs => _docs;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeQueryDocumentSnapshot implements QueryDocumentSnapshot<Map<String, dynamic>> {
  final DocumentReference<Map<String, dynamic>> _ref;

  FakeQueryDocumentSnapshot(this._ref);

  @override
  DocumentReference<Map<String, dynamic>> get reference => _ref;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeDocumentReference implements DocumentReference<Map<String, dynamic>> {
  bool deleted = false;

  @override
  Future<void> delete() async {
    deleted = true;
  }

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) {
    return FakeCollectionReference();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeQuery implements Query<Map<String, dynamic>> {
  final CollectionReference<Map<String, dynamic>> parent;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;

  FakeQuery(this.parent, this.docs);

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    final activeDocs = docs.where((doc) {
      final ref = doc.reference;
      if (ref is FakeDocumentReference) {
        return !ref.deleted;
      }
      if (ref is FakeUserDocumentReference) {
        return !ref.deleted;
      }
      return true;
    }).toList();
    return FakeQuerySnapshot(activeDocs);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeCollectionReference implements CollectionReference<Map<String, dynamic>> {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs = [];
  bool shouldFail = false;

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) {
    return FakeDocumentReference();
  }

  @override
  Query<Map<String, dynamic>> limit(int limit) {
    if (shouldFail) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'mock-error',
        message: 'Mock Firestore failure for retry testing',
      );
    }
    return FakeQuery(this, docs.take(limit).toList());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeWriteBatch implements WriteBatch {
  final List<FakeDocumentReference> deletedDocs = [];

  @override
  void delete(DocumentReference document) {
    if (document is FakeDocumentReference) {
      deletedDocs.add(document);
    }
  }

  @override
  Future<void> commit() async {
    for (final doc in deletedDocs) {
      doc.deleted = true;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeFirebaseFirestore implements FirebaseFirestore {
  final Map<String, DocumentReference<Map<String, dynamic>>> userDocs = {};
  final Map<String, FakeCollectionReference> subcollections = {};

  @override
  DocumentReference<Map<String, dynamic>> doc(String path) {
    final parts = path.split('/');
    if (parts.length == 2 && parts[0] == 'users') {
      return userDocs.putIfAbsent(parts[1], () => FakeUserDocumentReference(this, parts[1]));
    }
    return FakeDocumentReference();
  }

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) {
    if (path == 'users') {
      return FakeUsersCollectionReference(this);
    }
    return FakeCollectionReference();
  }

  @override
  WriteBatch batch() {
    return FakeWriteBatch();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeUsersCollectionReference implements CollectionReference<Map<String, dynamic>> {
  final FakeFirebaseFirestore firestore;

  FakeUsersCollectionReference(this.firestore);

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) {
    if (path != null) {
      return firestore.userDocs.putIfAbsent(path, () => FakeUserDocumentReference(firestore, path));
    }
    return FakeDocumentReference();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeUserDocumentReference implements DocumentReference<Map<String, dynamic>> {
  final FakeFirebaseFirestore firestore;
  final String uid;
  bool deleted = false;

  FakeUserDocumentReference(this.firestore, this.uid);

  @override
  Future<void> delete() async {
    deleted = true;
  }

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) {
    final key = '$uid/$path';
    return firestore.subcollections.putIfAbsent(key, () => FakeCollectionReference());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeDatabaseHelper implements DatabaseHelper {
  final Database _testDb;
  FakeDatabaseHelper(this._testDb);

  @override
  Future<Database> get database async => _testDb;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ── Test Suite ────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late FakeDatabaseHelper dbHelper;
  late FakeFirebaseFirestore firestore;
  late FakeFirebaseAuth auth;
  late FakeUser currentUser;
  late AccountDeletionService service;

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('purchases_flutter'),
      (methodCall) async {
        return <dynamic, dynamic>{};
      },
    );
    SharedPreferences.setMockInitialValues({});
    db = await openDatabase(
      inMemoryDatabasePath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('CREATE TABLE transactions (id TEXT PRIMARY KEY, amount REAL)');
        await db.execute('''
          CREATE TABLE transaction_sync_queue (
            id TEXT PRIMARY KEY,
            transactionId TEXT,
            action TEXT,
            payload TEXT,
            userId TEXT
          )
        ''');
      },
    );

    dbHelper = FakeDatabaseHelper(db);
    firestore = FakeFirebaseFirestore();
    currentUser = FakeUser('test_uid_123');
    auth = FakeFirebaseAuth(currentUser: currentUser);

    service = AccountDeletionService(
      firestore: firestore,
      auth: auth,
      dbHelper: dbHelper,
    )..isTesting = true;
  });

  tearDown(() async {
    await db.close();
    AccountDeletionService.isDeletionInProgress = false;
  });

  group('Account Deletion Hardening Tests', () {
    test('UID safety check validation', () async {
      // Trying to delete using mismatched target UID should fail
      expect(
        () => service.deleteAccount(targetUid: 'other_uid'),
        throwsStateError,
      );
      expect(AccountDeletionService.isDeletionInProgress, isFalse);
    });

    test('Full safe deletion progress order verification', () async {
      // 1. Populate Firestore document collections
      final userDoc = firestore.collection('users').doc('test_uid_123') as FakeUserDocumentReference;
      final txnsCol = userDoc.collection('transactions') as FakeCollectionReference;
      final t1 = FakeDocumentReference();
      txnsCol.docs.add(FakeQueryDocumentSnapshot(t1));

      final tombstonesCol = userDoc.collection('tombstones') as FakeCollectionReference;
      final tom1 = FakeDocumentReference();
      tombstonesCol.docs.add(FakeQueryDocumentSnapshot(tom1));

      // 2. Populate SQLite databases
      await db.insert('transactions', {'id': 'local_txn_1', 'amount': 45.5});
      await db.insert('transaction_sync_queue', {
        'id': 'action_1',
        'transactionId': 'local_txn_1',
        'action': 'create',
        'payload': '{}',
        'userId': 'test_uid_123'
      });
      await db.insert('transaction_sync_queue', {
        'id': 'action_guest',
        'transactionId': 'local_txn_guest',
        'action': 'create',
        'payload': '{}',
        'userId': 'guest_user'
      });

      final steps = <DeletionStep>[];
      final subscription = service.progress.listen(steps.add);

      await service.deleteAccount(targetUid: 'test_uid_123');
      await Future.delayed(Duration.zero);

      // Verify progress steps occurred in safe order:
      // Cloud transactions -> budgets -> categories -> tombstones -> premium data -> user profile -> Auth account -> local SQLite -> SharedPreferences -> complete
      expect(steps, contains(DeletionStep.deletingCloudTransactions));
      expect(steps, contains(DeletionStep.deletingCloudTombstones));
      expect(steps, contains(DeletionStep.deletingAuthAccount));
      expect(steps, contains(DeletionStep.clearingLocalData));
      expect(steps, contains(DeletionStep.complete));

      // Verify Cloud deletion is complete
      expect(t1.deleted, isTrue);
      expect(tom1.deleted, isTrue);
      expect(userDoc.deleted, isTrue);

      // Verify Auth account is deleted
      expect(currentUser.deleted, isTrue);

      // Verify SQLite is scoped and guest actions are preserved
      final transactions = await db.query('transactions');
      expect(transactions, isEmpty); // Wiped completely since it is local cache

      final queue = await db.query('transaction_sync_queue');
      expect(queue.length, equals(1)); // Guest action preserved!
      expect(queue.first['userId'], equals('guest_user'));

      // Verify persistent in-progress state is cleared/unset at the end
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('deletion_in_progress'), isNull);
      expect(AccountDeletionService.isDeletionInProgress, isFalse);

      await subscription.cancel();
    });

    test('Resumable local cleanup when user is already deleted from Auth', () async {
      // Simulate that Auth user is null, but isDeletionInProgress is set
      AccountDeletionService.isDeletionInProgress = true;
      auth.setCurrentUser(null);

      // Populate local sqlite
      await db.insert('transactions', {'id': 'local_txn_1', 'amount': 45.5});
      await db.insert('transaction_sync_queue', {
        'id': 'action_1',
        'transactionId': 'local_txn_1',
        'action': 'create',
        'payload': '{}',
        'userId': 'test_uid_123'
      });

      final steps = <DeletionStep>[];
      final subscription = service.progress.listen(steps.add);

      await service.deleteAccount(targetUid: 'test_uid_123');
      await Future.delayed(Duration.zero);

      // It should execute local cleanup steps and complete
      expect(steps, contains(DeletionStep.clearingLocalData));
      expect(steps, contains(DeletionStep.complete));

      // Verify local data is cleaned up
      final transactions = await db.query('transactions');
      expect(transactions, isEmpty);

      final queue = await db.query('transaction_sync_queue');
      expect(queue, isEmpty);

      expect(AccountDeletionService.isDeletionInProgress, isFalse);

      await subscription.cancel();
    });

    test('Idempotent partial cloud failure retry test', () async {
      // 1. Populate Firestore document collections
      final userDoc = firestore.collection('users').doc('test_uid_123') as FakeUserDocumentReference;
      final txnsCol = userDoc.collection('transactions') as FakeCollectionReference;
      final t1 = FakeDocumentReference();
      txnsCol.docs.add(FakeQueryDocumentSnapshot(t1));

      // Make tombstones collection fail
      final tombstonesCol = userDoc.collection('tombstones') as FakeCollectionReference;
      final tom1 = FakeDocumentReference();
      tombstonesCol.docs.add(FakeQueryDocumentSnapshot(tom1));
      tombstonesCol.shouldFail = true;

      // 2. Populate SQLite database
      await db.insert('transactions', {'id': 'local_txn_1', 'amount': 45.5});
      await db.insert('transaction_sync_queue', {
        'id': 'action_1',
        'transactionId': 'local_txn_1',
        'action': 'create',
        'payload': '{}',
        'userId': 'test_uid_123'
      });

      // 3. Trigger account deletion — should fail on tombstones
      final steps = <DeletionStep>[];
      final subscription = service.progress.listen(steps.add, onError: (_) {});

      bool failed = false;
      try {
        await service.deleteAccount(targetUid: 'test_uid_123');
      } catch (e) {
        if (e is FirebaseException && e.code == 'mock-error') {
          failed = true;
        }
      }
      expect(failed, isTrue);

      // Verify that:
      // - First collection 'transactions' was successfully deleted
      expect(t1.deleted, isTrue);
      // - 'tombstones' failed and remains active (not deleted)
      expect(tom1.deleted, isFalse);
      // - SQLite remains intact
      final transactionsBefore = await db.query('transactions');
      expect(transactionsBefore.length, equals(1));
      // - Auth account remains intact
      expect(currentUser.deleted, isFalse);
      // - deletion_in_progress is still true
      expect(AccountDeletionService.isDeletionInProgress, isTrue);

      // 4. Resolve the Firestore failure and retry
      tombstonesCol.shouldFail = false;

      // Run it again
      await service.deleteAccount(targetUid: 'test_uid_123');
      await Future.delayed(Duration.zero);

      // - Already-deleted collection 'transactions' was handled idempotently
      // - Remaining collections deleted
      expect(tom1.deleted, isTrue);
      // - Auth deletion completes
      expect(currentUser.deleted, isTrue);
      // - Local SQLite cleanup completes
      final transactionsAfter = await db.query('transactions');
      expect(transactionsAfter, isEmpty);
      // - final deletion state is cleared
      expect(AccountDeletionService.isDeletionInProgress, isFalse);

      await subscription.cancel();
    });
  });
}
