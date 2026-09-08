import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pet/core/widgets/notification_permission_banner.dart';
import 'package:pet/premium/services/notification_preferences_service.dart';
import 'package:pet/premium/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await NotificationPreferencesService.instance.load();
    NotificationService.permissionNotifier.value = PermissionStatus.denied;
  });

  group('NotificationPermissionBanner Widget Tests', () {
    testWidgets('Hidden when permission status is granted', (tester) async {
      NotificationService.permissionNotifier.value = PermissionStatus.granted;

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NotificationPermissionBanner(),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(NotificationPermissionBanner), findsOneWidget);
      expect(find.text('Stay Ahead of Overspending'), findsNothing);
      expect(find.text('Enable'), findsNothing);
    });

    testWidgets('Displays rationale and "Enable" CTA when denied (not yet granted)', (tester) async {
      NotificationService.permissionNotifier.value = PermissionStatus.denied;

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NotificationPermissionBanner(),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Stay Ahead of Overspending'), findsOneWidget);
      expect(find.text('Enable'), findsOneWidget);
      expect(
        find.textContaining('real-time budget overspend alerts'),
        findsOneWidget,
      );
    });

    testWidgets('Displays blocked rationale and "Settings" CTA when permanently denied', (tester) async {
      NotificationService.permissionNotifier.value =
          PermissionStatus.permanentlyDenied;

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NotificationPermissionBanner(),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Notifications Blocked'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      expect(
        find.textContaining('Notifications are turned off in device settings'),
        findsOneWidget,
      );
    });

    testWidgets('Tapping dismiss button hides the banner and saves preference', (tester) async {
      NotificationService.permissionNotifier.value = PermissionStatus.denied;

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NotificationPermissionBanner(),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Stay Ahead of Overspending'), findsOneWidget);

      final closeButton = find.byIcon(Icons.close);
      expect(closeButton, findsOneWidget);
      await tester.tap(closeButton);
      await tester.pumpAndSettle();

      expect(find.text('Stay Ahead of Overspending'), findsNothing);
      expect(NotificationPreferencesService.instance.isBannerDismissed, isTrue);
    });

    testWidgets('forceShow: true ignores dismissal and displays banner', (tester) async {
      NotificationService.permissionNotifier.value = PermissionStatus.denied;
      await NotificationPreferencesService.instance.setBannerDismissed(true);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NotificationPermissionBanner(
              forceShow: true,
              isDismissible: false,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Stay Ahead of Overspending'), findsOneWidget);
      expect(find.text('Enable'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsNothing);
    });
  });
}
