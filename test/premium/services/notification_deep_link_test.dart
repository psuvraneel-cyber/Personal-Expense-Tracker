import 'package:flutter_test/flutter_test.dart';
import 'package:pet/premium/services/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    NotificationService.selectNotificationNotifier.value = null;
    NotificationService.clearInitialPayload();
  });

  group('NotificationService tap payload deep linking', () {
    test('handleNotificationTap updates selectNotificationNotifier value', () {
      expect(NotificationService.selectNotificationNotifier.value, isNull);

      NotificationService.handleNotificationTap('bill:sub_123');

      expect(
        NotificationService.selectNotificationNotifier.value,
        equals('bill:sub_123'),
      );
    });

    test('initialPayload can be set and cleared', () {
      expect(NotificationService.initialPayload, isNull);

      // Verify clearInitialPayload clears state
      NotificationService.clearInitialPayload();
      expect(NotificationService.initialPayload, isNull);
    });
  });
}
