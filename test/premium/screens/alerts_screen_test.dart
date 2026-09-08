import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pet/data/database/database_helper.dart';
import 'package:pet/premium/models/app_alert.dart';
import 'package:pet/premium/providers/alert_provider.dart';
import 'package:pet/premium/providers/premium_provider.dart';
import 'package:pet/premium/repositories/alert_repository.dart';
import 'package:pet/premium/screens/alerts_screen.dart';
import 'package:pet/premium/services/alert_evaluation_coordinator.dart';
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

class MockPathProviderPlatform extends PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async {
    return Directory.systemTemp.path;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String dbPath;
  late Database testDb;
  late AlertRepository repository;
  late AlertEvaluationCoordinator coordinator;
  late AlertProvider alertProvider;
  late CategoryProvider categoryProvider;

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    PathProviderPlatform.instance = MockPathProviderPlatform();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync();
    dbPath = p.join(tempDir.path, 'alerts_screen_test.db');

    testDb = await openDatabase(
      dbPath,
      version: 17,
      onCreate: (db, version) async {
        await DatabaseHelper().onCreateForTesting(db, version);
      },
    );

    DatabaseHelper.setTestDatabase(testDb);

    repository = AlertRepository(database: testDb);
    coordinator = AlertEvaluationCoordinator(repository: repository);
    alertProvider = AlertProvider(repository: repository, coordinator: coordinator);
    coordinator.attachProvider(alertProvider);

    categoryProvider = CategoryProvider();
    await categoryProvider.loadCategories();
  });

  tearDown(() async {
    coordinator.detachProvider();
    DatabaseHelper.setTestDatabase(null);
    await testDb.close();
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  Widget createWidgetUnderTest() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<PremiumProvider>(create: (_) => FakePremiumProvider()),
        ChangeNotifierProvider<AlertProvider>.value(value: alertProvider),
        ChangeNotifierProvider<CategoryProvider>.value(value: categoryProvider),
      ],
      child: const MaterialApp(
        home: AlertsScreen(),
      ),
    );
  }

  group('AlertsScreen UI & Interaction Tests', () {
    testWidgets('renders empty state with all-clear banner when no alerts exist', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.runAsync(() => alertProvider.load());
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
      await tester.pump();

      expect(find.text('Alerts Centre'), findsOneWidget);
      expect(find.text('All caught up!'), findsOneWidget);
      expect(find.text('No Alerts'), findsOneWidget);
      expect(find.text('No active anomalies or budget overruns detected.'), findsOneWidget);
    });

    testWidgets('renders alert cards with badges, category details, progress bars, and action buttons', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final now = DateTime(2026, 7, 20);

      final alertBudget = AppAlert(
        id: 'alert_1',
        type: AppAlertType.budget,
        stage: AppAlertStage.warning,
        severity: AlertSeverity.warning,
        title: 'Food & Dining budget near limit',
        message: 'You have spent 95% of your ₹1,000 monthly budget.',
        categoryId: 'cat_food',
        amount: 950,
        targetAmount: 1000,
        ratio: 0.95,
        period: '2026-07',
        alertKey: 'budget:cat_food:2026-07:warning',
        actionType: AlertActionType.adjustBudget,
        createdAt: now,
      );

      final alertAnomaly = AppAlert(
        id: 'alert_2',
        type: AppAlertType.anomaly,
        stage: AppAlertStage.critical,
        severity: AlertSeverity.critical,
        title: 'Spending spike in Shopping',
        message: 'This category is 3.0x higher than your usual monthly baseline.',
        categoryId: 'cat_shopping',
        amount: 300,
        targetAmount: 100,
        ratio: 3.0,
        period: '2026-07',
        alertKey: 'anomaly:cat_shopping:2026-07',
        actionType: AlertActionType.viewTransactions,
        createdAt: now,
      );

      await tester.runAsync(() async {
        await repository.insertBatch([alertBudget, alertAnomaly]);
        await alertProvider.load();
      });

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
      await tester.pump();

      // Verify header summary banner
      expect(find.text('2 unread alerts'), findsOneWidget);

      // Verify cards content
      expect(find.text('Food & Dining budget near limit'), findsOneWidget);
      expect(find.text('Spending spike in Shopping'), findsOneWidget);

      // Verify category resolution
      expect(find.text('Food & Dining'), findsOneWidget);
      expect(find.text('Shopping'), findsOneWidget);

      // Verify severity badges
      expect(find.text('WARNING'), findsOneWidget);
      expect(find.text('CRITICAL'), findsOneWidget);

      // Verify contextual action buttons
      expect(find.text('Adjust'), findsOneWidget);
      expect(find.text('Transactions'), findsOneWidget);

      // Verify budget progress percentage
      expect(find.text('95% used'), findsOneWidget);
    });

    testWidgets('filtering by type updates displayed alerts', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final now = DateTime(2026, 7, 20);

      final alertBudget = AppAlert(
        id: 'alert_b',
        type: AppAlertType.budget,
        severity: AlertSeverity.warning,
        title: 'Food budget warning',
        message: 'Near limit',
        categoryId: 'cat_food',
        createdAt: now,
      );

      final alertAnomaly = AppAlert(
        id: 'alert_a',
        type: AppAlertType.anomaly,
        severity: AlertSeverity.critical,
        title: 'Spike in Shopping',
        message: '3x higher than usual',
        categoryId: 'cat_shopping',
        createdAt: now,
      );

      await tester.runAsync(() async {
        await repository.insertBatch([alertBudget, alertAnomaly]);
        await alertProvider.load();
      });

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
      await tester.pump();

      expect(find.text('Food budget warning'), findsOneWidget);
      expect(find.text('Spike in Shopping'), findsOneWidget);

      // Filter by Budgets
      await tester.runAsync(() => alertProvider.setFilterType(AppAlertType.budget));
      await tester.pump();

      expect(find.text('Food budget warning'), findsOneWidget);
      expect(find.text('Spike in Shopping'), findsNothing);

      // Filter by Anomalies
      await tester.runAsync(() => alertProvider.setFilterType(AppAlertType.anomaly));
      await tester.pump();

      expect(find.text('Food budget warning'), findsNothing);
      expect(find.text('Spike in Shopping'), findsOneWidget);

      // Clear filters (All)
      await tester.runAsync(() => alertProvider.clearFilters());
      await tester.pump();

      expect(find.text('Food budget warning'), findsOneWidget);
      expect(find.text('Spike in Shopping'), findsOneWidget);
    });

    testWidgets('swiping to dismiss removes alert and allows undo', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final now = DateTime(2026, 7, 20);

      final alert = AppAlert(
        id: 'alert_dismiss_test',
        type: AppAlertType.budget,
        severity: AlertSeverity.warning,
        title: 'Dismissible Alert',
        message: 'Swipe to test undo',
        createdAt: now,
      );

      await tester.runAsync(() async {
        await repository.insert(alert);
        await alertProvider.load();
      });

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
      await tester.pump();

      expect(find.text('Dismissible Alert'), findsOneWidget);

      // Swipe to dismiss
      await tester.drag(find.text('Dismissible Alert'), const Offset(-500, 0));
      await tester.pump();
      await tester.pumpAndSettle();

      // Card is dismissed and empty state appears
      expect(find.text('Dismissible Alert'), findsNothing);
      expect(find.text('Alert dismissed'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);

      // Trigger undo
      await tester.runAsync(() async {
        await alertProvider.undoDismiss(alert);
      });
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      // Alert is restored
      expect(find.text('Dismissible Alert'), findsOneWidget);
    });
  });
}
