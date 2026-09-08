import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pet/data/database/database_helper.dart';
import 'package:pet/premium/providers/premium_provider.dart';
import 'package:pet/premium/providers/recurring_provider.dart';
import 'package:pet/premium/screens/recurring_bills_screen.dart';
import 'package:pet/premium/services/notification_preferences_service.dart';
import 'package:pet/premium/services/notification_service.dart';
import 'package:pet/providers/category_provider.dart';

class FakePremiumProvider extends ChangeNotifier implements PremiumProvider {
  @override
  bool get isPremium => true;
  @override
  bool get isLoading => false;
  @override
  bool get experimentalEnabled => true;
  @override
  bool get isDeveloperPremiumAccessEnabled => true;
  @override
  Future<void> load({String? userId}) async {}
  @override
  Future<void> setDeveloperPremiumAccess(bool enabled) async {}
  @override
  Future<void> setExperimental(bool enabled) async {}
  @override
  Future<void> logInUser(String uid) async {}
  @override
  Future<void> logOutUser() async {}
  @override
  Future<void> clearData() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database testDb;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    testDb = await openDatabase(
      inMemoryDatabasePath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE recurring_payments (
            id TEXT PRIMARY KEY,
            merchantName TEXT NOT NULL,
            amount REAL NOT NULL,
            frequency TEXT NOT NULL,
            lastPaidAt TEXT NOT NULL,
            nextDueAt TEXT NOT NULL,
            categoryId TEXT NOT NULL,
            confidence REAL DEFAULT 0.6,
            source TEXT DEFAULT 'sms',
            status TEXT DEFAULT 'confirmed',
            isAutopay INTEGER DEFAULT 0,
            previousAmount REAL,
            priceChangeDetectedAt TEXT,
            notes TEXT,
            createdAt TEXT NOT NULL,
            updatedAt TEXT NOT NULL,
            detectionReason TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE recurring_payment_history (
            id TEXT PRIMARY KEY,
            recurringPaymentId TEXT NOT NULL,
            amount REAL NOT NULL,
            paidAt TEXT NOT NULL,
            source TEXT DEFAULT 'manual',
            transactionId TEXT,
            notes TEXT,
            createdAt TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE alerts (
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            title TEXT NOT NULL,
            message TEXT NOT NULL,
            categoryId TEXT,
            createdAt TEXT NOT NULL,
            isRead INTEGER DEFAULT 0,
            alertKey TEXT
          )
        ''');
      },
    );
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'has_pro_entitlement': true,
      'entitlement_cached_at': DateTime.now().toIso8601String(),
    });
    NotificationService.resetForTest();
    await NotificationPreferencesService.instance.load();

    await testDb.delete('recurring_payments');
    await testDb.delete('recurring_payment_history');
    await testDb.delete('alerts');

    DatabaseHelper.setTestDatabase(testDb);
  });

  tearDownAll(() async {
    DatabaseHelper.setTestDatabase(null);
    await testDb.close();
  });

  Widget createWidgetUnderTest(RecurringProvider recurringProvider) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<PremiumProvider>(create: (_) => FakePremiumProvider()),
        ChangeNotifierProvider<RecurringProvider>.value(value: recurringProvider),
        ChangeNotifierProvider<CategoryProvider>(create: (_) => CategoryProvider()),
      ],
      child: const MaterialApp(
        home: RecurringBillsScreen(),
      ),
    );
  }

  group('RecurringBillsScreen UI & Workflow Tests', () {
    testWidgets('renders empty state when no bills exist', (tester) async {
      final provider = RecurringProvider();
      await tester.runAsync(() => provider.load());

      await tester.pumpWidget(createWidgetUnderTest(provider));
      await tester.pump();

      expect(find.text('No Bills Tracked'), findsOneWidget);
      expect(find.text('Add Bill'), findsOneWidget);
    });

    testWidgets('renders summary banner, detected candidate, and confirmed list', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final now = DateTime.now();
      final provider = RecurringProvider();

      await tester.runAsync(() async {
        await testDb.insert('recurring_payments', {
          'id': 'bill_netflix',
          'merchantName': 'Netflix',
          'amount': 249.0,
          'frequency': 'monthly',
          'lastPaidAt': now.subtract(const Duration(days: 15)).toIso8601String(),
          'nextDueAt': now.add(const Duration(days: 15)).toIso8601String(),
          'categoryId': 'entertainment',
          'status': 'confirmed',
          'isAutopay': 1,
          'createdAt': now.toIso8601String(),
          'updatedAt': now.toIso8601String(),
        });

        await testDb.insert('recurring_payments', {
          'id': 'bill_spotify_detected',
          'merchantName': 'Spotify',
          'amount': 149.0,
          'frequency': 'monthly',
          'lastPaidAt': now.subtract(const Duration(days: 30)).toIso8601String(),
          'nextDueAt': now.toIso8601String(),
          'categoryId': 'other',
          'status': 'detected',
          'previousAmount': 119.0,
          'detectionReason': 'Detected repeating debit with price hike',
          'createdAt': now.toIso8601String(),
          'updatedAt': now.toIso8601String(),
        });

        await provider.load();
      });

      await tester.pumpWidget(createWidgetUnderTest(provider));
      await tester.pump();

      // Summary
      expect(find.text('Monthly Recurring'), findsOneWidget);
      expect(find.textContaining('Annual commitment:'), findsOneWidget);

      // Detected Section
      expect(find.text('Possible Recurring Payments (1)'), findsOneWidget);
      expect(find.text('Confirm'), findsOneWidget);
      expect(find.text('Dismiss'), findsOneWidget);

      // Confirmed List
      expect(find.text('Netflix'), findsOneWidget);
      expect(find.text('AUTOPAY'), findsOneWidget);
      expect(find.text('Active (1)'), findsOneWidget);
      expect(find.text('Cancelled (0)'), findsOneWidget);
    });

    testWidgets('shows detected candidate and displays confidence & candidate badge', (tester) async {
      final now = DateTime.now();
      final provider = RecurringProvider();

      await tester.runAsync(() async {
        await testDb.insert('recurring_payments', {
          'id': 'candidate_gym',
          'merchantName': 'Cult Gym',
          'amount': 1200.0,
          'frequency': 'monthly',
          'lastPaidAt': now.subtract(const Duration(days: 30)).toIso8601String(),
          'nextDueAt': now.toIso8601String(),
          'categoryId': 'other',
          'status': 'detected',
          'createdAt': now.toIso8601String(),
          'updatedAt': now.toIso8601String(),
        });

        await provider.load();
      });

      await tester.pumpWidget(createWidgetUnderTest(provider));
      await tester.pump();

      expect(find.text('Possible Recurring Payments (1)'), findsOneWidget);
      expect(find.text('Active (0)'), findsOneWidget);
      expect(find.text('Cult Gym'), findsOneWidget);
    });

    testWidgets('renders confirmed bills with correct details', (tester) async {
      final now = DateTime.now();
      final provider = RecurringProvider();

      await tester.runAsync(() async {
        await testDb.insert('recurring_payments', {
          'id': 'bill_wifi',
          'merchantName': 'Airtel Broadband',
          'amount': 999.0,
          'frequency': 'monthly',
          'lastPaidAt': now.subtract(const Duration(days: 30)).toIso8601String(),
          'nextDueAt': now.toIso8601String(),
          'categoryId': 'utilities',
          'status': 'confirmed',
          'createdAt': now.toIso8601String(),
          'updatedAt': now.toIso8601String(),
        });

        await provider.load();
      });

      await tester.pumpWidget(createWidgetUnderTest(provider));
      await tester.pump();

      expect(find.text('Airtel Broadband'), findsOneWidget);
      expect(find.text('Active (1)'), findsOneWidget);
      expect(find.text('Due today'), findsOneWidget);
    });
  });
}
