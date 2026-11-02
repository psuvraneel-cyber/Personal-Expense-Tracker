import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pet/providers/sms_transaction_provider.dart';
import 'package:pet/services/native_sms_reader.dart';
import 'package:pet/services/sms_service.dart';

/// Records whether anything subscribed to the live SMS stream.
class FakeNativeSmsReader extends NativeSmsReader {
  FakeNativeSmsReader() : super.forTesting();

  final StreamController<NativeSmsMessage> sms =
      StreamController<NativeSmsMessage>.broadcast();
  final StreamController<NativeSmsMessage> notifications =
      StreamController<NativeSmsMessage>.broadcast();

  @override
  Stream<NativeSmsMessage> get incomingSmsStream => sms.stream;

  @override
  Stream<NativeSmsMessage> get incomingNotificationStream =>
      notifications.stream;

  @override
  Future<bool> hasNotificationAccess() async => false;

  @override
  Future<void> stopListening() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const permissionChannel =
      MethodChannel('flutter.baseflow.com/permissions/methods');
  late FakeNativeSmsReader reader;
  late PermissionStatus smsStatus;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    reader = FakeNativeSmsReader();
    SmsService(nativeReader: reader);
    SmsService.debugOverrideIsSupported = true;
    smsStatus = PermissionStatus.granted;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissionChannel, (call) async {
      switch (call.method) {
        case 'requestPermissions':
          return {
            for (final p in call.arguments as List) p as int: smsStatus.index,
          };
        case 'checkPermissionStatus':
          return smsStatus.index;
      }
      return null;
    });
  });

  tearDown(() {
    SmsService().stopListening();
    SmsService.debugOverrideIsSupported = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissionChannel, null);
  });

  test('granting SMS permission starts the live listener without a restart',
      () async {
    final provider = SmsTransactionProvider();
    expect(SmsService().isListening, isFalse);

    final granted = await provider.requestAndEnablePermissions();

    expect(granted, isTrue);
    expect(provider.smsFeatureEnabled, isTrue);
    expect(SmsService().isListening, isTrue);
    expect(reader.sms.hasListener, isTrue);
    provider.dispose();
  });

  test('denied SMS permission leaves the live listener off', () async {
    smsStatus = PermissionStatus.denied;
    final provider = SmsTransactionProvider();

    final granted = await provider.requestAndEnablePermissions();

    expect(granted, isFalse);
    expect(SmsService().isListening, isFalse);
    expect(reader.sms.hasListener, isFalse);
    provider.dispose();
  });
}
