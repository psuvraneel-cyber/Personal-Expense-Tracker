import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pet/premium/models/notification_category.dart';
import 'package:pet/premium/services/notification_preferences_service.dart';
import 'package:pet/premium/services/notification_service.dart';
import 'package:timezone/data/latest.dart' as tz;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
        if (methodCall.method == 'initialize') {
          return true;
        }
        if (methodCall.method == 'show' || methodCall.method == 'zonedSchedule') {
          throw PlatformException(
            code: 'TEST_ERROR',
            message: 'Simulated notification error for telemetry testing',
          );
        }
        return null;
      },
    );
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    NotificationService.resetForTest();
    await NotificationPreferencesService.instance.load();
    await NotificationService.initialize();
  });

  group('NotificationService Crashlytics telemetry fallback', () {
    test('showInstant error degrades gracefully without crashing when Crashlytics is uninitialized', () async {
      // Calling showInstant when plugin throws PlatformException
      await expectLater(
        NotificationService.showInstant(
          id: 999,
          title: 'Test Title',
          body: 'Test Body',
          category: NotificationCategory.budget,
        ),
        completes,
      );
    });

    test('scheduleNotification error degrades gracefully without crashing when Crashlytics is uninitialized', () async {
      await expectLater(
        NotificationService.scheduleNotification(
          id: 998,
          title: 'Test Scheduled Title',
          body: 'Test Scheduled Body',
          scheduledDate: DateTime.now().add(const Duration(days: 1)),
          category: NotificationCategory.bill,
        ),
        completes,
      );
    });
  });
}
