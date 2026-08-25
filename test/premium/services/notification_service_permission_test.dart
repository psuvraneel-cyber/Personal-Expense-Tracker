import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pet/premium/services/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/permissions/methods'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'checkPermissionStatus') {
          return PermissionStatus.granted.index;
        }
        return null;
      },
    );
  });

  group('NotificationService permissionNotifier & permissionStatus', () {
    test('permissionNotifier initially defaults to granted or valid status', () {
      expect(
        NotificationService.permissionNotifier.value,
        isA<PermissionStatus>(),
      );
    });

    test('permissionStatus() updates permissionNotifier.value', () async {
      final status = await NotificationService.permissionStatus();
      expect(status, equals(PermissionStatus.granted));
      expect(
        NotificationService.permissionNotifier.value,
        equals(PermissionStatus.granted),
      );
    });
  });
}
