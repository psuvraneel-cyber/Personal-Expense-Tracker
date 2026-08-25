import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet/data/database/database_helper.dart';
import 'package:pet/premium/models/budget_alert.dart';
import 'package:pet/premium/models/notification_category.dart';
import 'package:pet/premium/providers/alert_provider.dart';
import 'package:pet/premium/services/notification_preferences_service.dart';
import 'package:pet/premium/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/data/latest.dart' as tz;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final methodCalls = <MethodCall>[];
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tz.initializeTimeZones();
    AndroidFlutterLocalNotificationsPlugin.registerWith();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/permissions/methods'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'checkPermissionStatus') {
          return 1; // PermissionStatus.granted
        }
        if (methodCall.method == 'requestPermissions') {
          return {38: 1, 0: 1};
        }
        return 1;
      },
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'),
      (MethodCall methodCall) async {
        methodCalls.add(methodCall);
        if (methodCall.method == 'getNotificationAppLaunchDetails') {
          return {'notificationLaunchedApp': false};
        }
        if (methodCall.method == 'requestNotificationsPermission') {
          return true;
        }
        if (methodCall.method == 'initialize') {
          return true;
        }
        return true;
      },
    );
  });

  tearDownAll(() {
    debugDefaultTargetPlatformOverride = null;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await openDatabase(
      inMemoryDatabasePath,
      version: 14,
      onCreate: (db, version) async {
        await DatabaseHelper().onCreateForTesting(db, version);
      },
    );
    DatabaseHelper.setTestDatabase(db);
    methodCalls.clear();
    NotificationService.resetForTest();
    await NotificationPreferencesService.instance.load();
    await NotificationService.initialize();
    methodCalls.clear();
  });

  tearDown(() async {
    await db.close();
    DatabaseHelper.setTestDatabase(null);
  });

  group('Android Notification Grouping & Summary in NotificationService', () {
    test('isAlertCategory identifies alert categories correctly', () {
      expect(NotificationService.isAlertCategory(NotificationCategory.budget), isTrue);
      expect(NotificationService.isAlertCategory(NotificationCategory.anomaly), isTrue);
      expect(NotificationService.isAlertCategory(NotificationCategory.bill), isTrue);

      expect(NotificationService.isAlertCategory(NotificationCategory.dailySummary), isFalse);
      expect(NotificationService.isAlertCategory(NotificationCategory.weeklyReport), isFalse);
      expect(NotificationService.isAlertCategory(NotificationCategory.goalProgress), isFalse);
      expect(NotificationService.isAlertCategory(NotificationCategory.cashflow), isFalse);
    });

    test('showInstant assigns groupKey to alert categories', () async {
      await NotificationService.showInstant(
        id: 101,
        title: 'Budget Alert',
        body: 'Over budget in Food',
        category: NotificationCategory.budget,
      );

      final showCalls = methodCalls.where((c) => c.method == 'show').toList();
      expect(showCalls.length, equals(1));
      expect(showCalls.first.arguments['id'], equals(101));
      final specifics = showCalls.first.arguments['platformSpecifics'] as Map?;
      expect(
        specifics?['groupKey'],
        equals(NotificationService.alertsGroupKey),
      );
      expect(specifics?['setAsGroupSummary'], isFalse);
    });

    test('showInstant does not assign groupKey to non-alert categories', () async {
      await NotificationService.showInstant(
        id: 102,
        title: 'Daily Summary',
        body: 'Here is your daily summary',
        category: NotificationCategory.dailySummary,
      );

      final showCalls = methodCalls.where((c) => c.method == 'show').toList();
      expect(showCalls.length, equals(1));
      expect(showCalls.first.arguments['id'], equals(102));
      final specifics = showCalls.first.arguments['platformSpecifics'] as Map?;
      expect(specifics?['groupKey'], isNull);
    });

    test('rolling window: <= 2 alerts does NOT trigger group summary', () async {
      await NotificationService.showInstant(
        id: 201,
        title: 'Alert 1',
        body: 'Body 1',
        category: NotificationCategory.budget,
      );
      await NotificationService.showInstant(
        id: 202,
        title: 'Alert 2',
        body: 'Body 2',
        category: NotificationCategory.anomaly,
      );

      final showCalls = methodCalls.where((c) => c.method == 'show').toList();
      expect(showCalls.length, equals(2));
      expect(
        showCalls.any((c) => c.arguments['id'] == NotificationService.alertsSummaryNotificationId),
        isFalse,
      );
    });

    test('rolling window: > 2 alerts triggers group summary notification', () async {
      await NotificationService.showInstant(
        id: 201,
        title: 'Alert 1',
        body: 'Body 1',
        category: NotificationCategory.budget,
      );
      await NotificationService.showInstant(
        id: 202,
        title: 'Alert 2',
        body: 'Body 2',
        category: NotificationCategory.anomaly,
      );
      await NotificationService.showInstant(
        id: 203,
        title: 'Alert 3',
        body: 'Body 3',
        category: NotificationCategory.bill,
      );

      final showCalls = methodCalls.where((c) => c.method == 'show').toList();
      // 3 individual alerts + 1 group summary update on the 3rd alert
      expect(showCalls.length, equals(4));

      final summaryCall = showCalls.firstWhere(
        (c) => c.arguments['id'] == NotificationService.alertsSummaryNotificationId,
      );
      final specifics = summaryCall.arguments['platformSpecifics'] as Map?;
      expect(specifics?['groupKey'], equals(NotificationService.alertsGroupKey));
      expect(specifics?['setAsGroupSummary'], isTrue);
      expect(summaryCall.arguments['title'], equals('3 new alerts'));
      expect(specifics?['style'], equals(AndroidNotificationStyle.inbox.index));
      final styleInfo = specifics?['styleInformation'] as Map?;
      expect(
        styleInfo?['lines'],
        containsAll(['Alert 1: Body 1', 'Alert 2: Body 2', 'Alert 3: Body 3']),
      );
    });
  });

  group('AlertProvider batching and debouncing', () {
    test('single live alert fires immediately without delay', () async {
      final provider = AlertProvider();
      final alert = BudgetAlert(
        id: 'alert_single_1',
        title: 'Single Anomaly',
        message: 'Unusual amount detected',
        type: 'anomaly',
        createdAt: DateTime.now(),
        alertKey: 'key_single_1',
      );

      await provider.recordAlert(alert);

      final showCalls = methodCalls.where((c) => c.method == 'show').toList();
      expect(showCalls.length, equals(1));
      expect(showCalls.first.arguments['title'], equals('Single Anomaly'));
      final specifics = showCalls.first.arguments['platformSpecifics'] as Map?;
      expect(specifics?['groupKey'], equals(NotificationService.alertsGroupKey));
    });

    test('batch of <= 2 alerts fires individual notifications', () async {
      final provider = AlertProvider();
      final alerts = <BudgetAlert>[
        BudgetAlert(
          id: 'alert_b2_1',
          title: 'Alert 1',
          message: 'Message 1',
          type: 'budget',
          createdAt: DateTime.now(),
          alertKey: 'key_b2_1',
        ),
        BudgetAlert(
          id: 'alert_b2_2',
          title: 'Alert 2',
          message: 'Message 2',
          type: 'anomaly',
          createdAt: DateTime.now(),
          alertKey: 'key_b2_2',
        ),
      ];

      await provider.recordAlerts(alerts);

      final showCalls = methodCalls.where((c) => c.method == 'show').toList();
      expect(showCalls.length, equals(2));
      expect(
        showCalls.any((c) => c.arguments['id'] == NotificationService.alertsSummaryNotificationId),
        isFalse,
      );
    });

    test('batch of 8 alerts (sweep) caps individual banners at 2 and posts 1 summary', () async {
      final provider = AlertProvider();
      final alerts = List<BudgetAlert>.generate(
        8,
        (i) => BudgetAlert(
          id: 'alert_sweep_$i',
          title: 'Sweep Alert $i',
          message: 'Message for alert $i',
          type: i % 2 == 0 ? 'budget' : 'anomaly',
          createdAt: DateTime.now(),
          alertKey: 'key_sweep_$i',
        ),
      );

      await provider.recordAlerts(alerts);

      final showCalls = methodCalls.where((c) => c.method == 'show').toList();
      // Should have exactly 2 individual banners + 1 summary banner
      final individualCalls = showCalls.where(
        (c) => c.arguments['id'] != NotificationService.alertsSummaryNotificationId,
      ).toList();
      final summaryCalls = showCalls.where(
        (c) => c.arguments['id'] == NotificationService.alertsSummaryNotificationId,
      ).toList();

      expect(individualCalls.length, equals(2));
      expect(summaryCalls.length, equals(1));
      expect(summaryCalls.first.arguments['title'], equals('8 new alerts'));
      final summarySpecifics = summaryCalls.first.arguments['platformSpecifics'] as Map?;
      expect(summarySpecifics?['setAsGroupSummary'], isTrue);
      expect(summarySpecifics?['groupKey'], equals(NotificationService.alertsGroupKey));
    });
  });
}
