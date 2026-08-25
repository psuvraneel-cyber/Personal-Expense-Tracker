import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet/premium/models/notification_category.dart';
import 'package:pet/premium/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final methodCalls = <MethodCall>[];

  setUpAll(() {
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

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    methodCalls.clear();
    NotificationService.resetForTest();
  });

  group('NotificationService channel mapping & configuration', () {
    test('channelIdFor maps all 7 categories correctly', () {
      expect(
        NotificationService.channelIdFor(NotificationCategory.budget),
        equals('pet_budget_alerts'),
      );
      expect(
        NotificationService.channelIdFor(NotificationCategory.anomaly),
        equals('pet_anomalies'),
      );
      expect(
        NotificationService.channelIdFor(NotificationCategory.bill),
        equals('pet_bill_reminders'),
      );
      expect(
        NotificationService.channelIdFor(NotificationCategory.dailySummary),
        equals('pet_daily_summary'),
      );
      expect(
        NotificationService.channelIdFor(NotificationCategory.weeklyReport),
        equals('pet_weekly_insights'),
      );
      expect(
        NotificationService.channelIdFor(NotificationCategory.goalProgress),
        equals('pet_goal_progress'),
      );
      expect(
        NotificationService.channelIdFor(NotificationCategory.cashflow),
        equals('pet_cashflow_insights'),
      );
    });

    test('channelFor defines expected importance and sound/vibration flags', () {
      final budgetCh = NotificationService.channelFor(NotificationCategory.budget);
      expect(budgetCh.importance, equals(Importance.high));
      expect(budgetCh.playSound, isTrue);
      expect(budgetCh.enableVibration, isTrue);

      final anomalyCh = NotificationService.channelFor(NotificationCategory.anomaly);
      expect(anomalyCh.importance, equals(Importance.high));
      expect(anomalyCh.playSound, isTrue);
      expect(anomalyCh.enableVibration, isTrue);

      final billCh = NotificationService.channelFor(NotificationCategory.bill);
      expect(billCh.importance, equals(Importance.high));
      expect(billCh.playSound, isTrue);
      expect(billCh.enableVibration, isTrue);

      final dailyCh = NotificationService.channelFor(NotificationCategory.dailySummary);
      expect(dailyCh.importance, equals(Importance.defaultImportance));
      expect(dailyCh.playSound, isTrue);
      expect(dailyCh.enableVibration, isFalse);

      final weeklyCh = NotificationService.channelFor(NotificationCategory.weeklyReport);
      expect(weeklyCh.importance, equals(Importance.low));
      expect(weeklyCh.playSound, isFalse);
      expect(weeklyCh.enableVibration, isFalse);

      final goalCh = NotificationService.channelFor(NotificationCategory.goalProgress);
      expect(goalCh.importance, equals(Importance.defaultImportance));
      expect(goalCh.playSound, isTrue);
      expect(goalCh.enableVibration, isFalse);

      final cashflowCh = NotificationService.channelFor(NotificationCategory.cashflow);
      expect(cashflowCh.importance, equals(Importance.defaultImportance));
      expect(cashflowCh.playSound, isTrue);
      expect(cashflowCh.enableVibration, isFalse);
    });

    test('allChannels contains 7 category channels + legacy channel', () {
      final channels = NotificationService.allChannels;
      expect(channels.length, equals(8));
      final ids = channels.map((c) => c.id).toSet();

      expect(ids, contains('pet_budget_alerts'));
      expect(ids, contains('pet_anomalies'));
      expect(ids, contains('pet_bill_reminders'));
      expect(ids, contains('pet_daily_summary'));
      expect(ids, contains('pet_weekly_insights'));
      expect(ids, contains('pet_goal_progress'));
      expect(ids, contains('pet_cashflow_insights'));
      expect(ids, contains('pet_alerts')); // legacy channel
    });

    test('initialize creates all 8 notification channels on Android', () async {
      await NotificationService.initialize();

      final channelCalls = methodCalls
          .where((call) => call.method == 'createNotificationChannel')
          .toList();

      expect(channelCalls.length, equals(8));
      final createdIds = channelCalls.map((c) => c.arguments['id']).toSet();

      expect(createdIds, contains('pet_budget_alerts'));
      expect(createdIds, contains('pet_anomalies'));
      expect(createdIds, contains('pet_bill_reminders'));
      expect(createdIds, contains('pet_daily_summary'));
      expect(createdIds, contains('pet_weekly_insights'));
      expect(createdIds, contains('pet_goal_progress'));
      expect(createdIds, contains('pet_cashflow_insights'));
      expect(createdIds, contains('pet_alerts'));
    });
  });
}
