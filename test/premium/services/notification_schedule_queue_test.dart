import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pet/premium/models/notification_category.dart';
import 'package:pet/premium/services/notification_preferences_service.dart';
import 'package:pet/premium/services/notification_service.dart';
import 'package:timezone/data/latest.dart' as tz;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final methodCalls = <MethodCall>[];

  setUpAll(() {
    tz.initializeTimeZones();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/permissions/methods'),
      (MethodCall methodCall) async {
        return 1; // PermissionStatus.granted
      },
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'),
      (MethodCall methodCall) async {
        methodCalls.add(methodCall);
        if (methodCall.method == 'initialize') {
          return true;
        }
        if (methodCall.method == 'getNotificationAppLaunchDetails') {
          return {'notificationLaunched': false};
        }
        return true;
      },
    );
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    methodCalls.clear();
    NotificationService.resetForTest();
    await NotificationPreferencesService.instance.load();
  });

  group('NotificationService scheduleNotification queueing', () {
    test('scheduleNotification before initialize queues and flushes on initialize completion', () async {
      final futureDate = DateTime.now().add(const Duration(days: 2));

      expect(NotificationService.pendingScheduledCount, equals(0));

      // Call scheduleNotification BEFORE initialize()
      await NotificationService.scheduleNotification(
        id: 201,
        title: 'Queued Bill',
        body: 'Due in 2 days',
        scheduledDate: futureDate,
        category: NotificationCategory.bill,
        payload: 'bill:201',
      );

      // Verify request is queued in _pendingScheduled
      expect(NotificationService.pendingScheduledCount, equals(1));

      // Now complete initialize()
      await NotificationService.initialize();

      // Assert queue is flushed
      expect(NotificationService.pendingScheduledCount, equals(0));
    });

    test('scheduleNotification before initialize drops expired item when initialize completes', () async {
      final pastDate = DateTime.now().subtract(const Duration(days: 1));

      expect(NotificationService.pendingScheduledCount, equals(0));

      // Call scheduleNotification BEFORE initialize() with an already expired date
      await NotificationService.scheduleNotification(
        id: 202,
        title: 'Expired Bill',
        body: 'Was due yesterday',
        scheduledDate: pastDate,
        category: NotificationCategory.bill,
      );

      expect(NotificationService.pendingScheduledCount, equals(1));

      await NotificationService.initialize();

      // Expired item should be cleared during flush
      expect(NotificationService.pendingScheduledCount, equals(0));
    });
  });
}
