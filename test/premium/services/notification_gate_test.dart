import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pet/premium/models/notification_category.dart';
import 'package:pet/premium/services/notification_preferences_service.dart';
import 'package:pet/premium/services/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final methodCalls = <MethodCall>[];

  setUpAll(() {
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
        return null;
      },
    );
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    methodCalls.clear();
    NotificationService.resetForTest();
    await NotificationPreferencesService.instance.load();
  });

  group('NotificationService central preference gate', () {
    test('showInstant drops notification when category is disabled', () async {
      // Disable budget notifications
      await NotificationPreferencesService.instance.setCategoryEnabled(
        NotificationCategory.budget,
        false,
      );

      await NotificationService.showInstant(
        id: 101,
        title: 'Budget Warning',
        body: 'Close to limit',
        category: NotificationCategory.budget,
      );

      final isEnabled = NotificationPreferencesService.instance.isEnabled(
        NotificationCategory.budget,
      );
      expect(isEnabled, isFalse);
    });

    test('showInstant processes notification when category is enabled', () async {
      await NotificationPreferencesService.instance.setCategoryEnabled(
        NotificationCategory.budget,
        true,
      );

      final isEnabled = NotificationPreferencesService.instance.isEnabled(
        NotificationCategory.budget,
      );
      expect(isEnabled, isTrue);
    });

    test('scheduleNotification drops notification when category is disabled', () async {
      await NotificationPreferencesService.instance.setCategoryEnabled(
        NotificationCategory.bill,
        false,
      );

      await NotificationService.scheduleNotification(
        id: 103,
        title: 'Bill Reminder',
        body: 'Due in 3 days',
        scheduledDate: DateTime.now().add(const Duration(days: 2)),
        category: NotificationCategory.bill,
      );

      final isEnabled = NotificationPreferencesService.instance.isEnabled(
        NotificationCategory.bill,
      );
      expect(isEnabled, isFalse);
    });
  });
}
