import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet/services/ingestion_diagnostics.dart';
import 'package:pet/services/native_sms_reader.dart';
import 'package:pet/services/sms_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// No handler is registered for `com.pet.tracker/sms_reader` here, which is
/// exactly what a Flutter engine without the native plugin looks like.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    NativeSmsReader.debugOverrideIsSupported = true;
    SmsService.debugOverrideIsSupported = true;
    IngestionDiagnostics.instance.backgroundFailures = 0;
  });

  tearDown(() {
    NativeSmsReader.debugOverrideIsSupported = null;
    SmsService.debugOverrideIsSupported = null;
  });

  group('missing native plugin is an error, not "no messages"', () {
    final reader = NativeSmsReader.forTesting();

    test('inbox reads throw', () async {
      await expectLater(
        reader.getInboxSms(),
        throwsA(isA<MissingPluginException>()),
      );
      await expectLater(
        reader.getAllSms(),
        throwsA(isA<MissingPluginException>()),
      );
    });

    test('reconciliation read throws', () async {
      await expectLater(
        reader.getSmsSinceTimestamp(sinceTimestamp: 1),
        throwsA(isA<MissingPluginException>()),
      );
    });

    test('cached-notification read throws', () async {
      await expectLater(
        reader.peekPendingNotifications(),
        throwsA(isA<MissingPluginException>()),
      );
    });

    test('each occurrence is counted in diagnostics', () async {
      await expectLater(
        reader.getInboxSms(),
        throwsA(isA<MissingPluginException>()),
      );
      expect(IngestionDiagnostics.instance.backgroundFailures, 1);
    });
  });

  test('inbox scan records a detection failure', () async {
    final service = SmsService(nativeReader: NativeSmsReader.forTesting());

    final count = await service.scanInbox(lookbackDays: 2);

    expect(count, 0);
    expect(await SmsService.getLastFailureTime(), isNotNull);
  });
}
