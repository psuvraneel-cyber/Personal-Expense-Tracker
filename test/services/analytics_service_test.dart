import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pet/services/analytics_service.dart';
import 'package:pet/services/local_data_wiper.dart';

class FakeAnalyticsBackend implements AnalyticsBackend {
  bool? collectionEnabled;
  bool resetCalled = false;
  final events = <String>[];
  final params = <String, Map<String, Object>?>{};
  final userProperties = <String, String?>{};

  @override
  Future<void> setCollectionEnabled(bool enabled) async =>
      collectionEnabled = enabled;

  @override
  Future<void> logEvent(String name, Map<String, Object>? parameters) async {
    events.add(name);
    params[name] = parameters;
  }

  @override
  Future<void> setUserProperty(String name, String? value) async =>
      userProperties[name] = value;

  @override
  Future<void> resetData() async => resetCalled = true;

  @override
  Future<String?> appInstanceId() async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeAnalyticsBackend backend;
  late AnalyticsService analytics;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    backend = FakeAnalyticsBackend();
    analytics = AnalyticsService(backend: backend);
  });

  test('is off by default: nothing is sent before consent', () async {
    await analytics.init();
    expect(analytics.isEnabled, isFalse);
    expect(backend.collectionEnabled, isFalse);

    await analytics.logEvent(AnalyticsEvents.paywallView, {'source': 'x'});
    await analytics.setUserProperty('is_premium', 'false');
    expect(backend.events, isEmpty);
    expect(backend.userProperties, isEmpty);
    expect(await AnalyticsService.shouldAskForConsent(), isTrue);
  });

  test('opting in enables collection, logs opt-in and remembers the answer',
      () async {
    await analytics.init();
    await analytics.setEnabled(true);

    expect(analytics.isEnabled, isTrue);
    expect(backend.collectionEnabled, isTrue);
    expect(backend.events, [AnalyticsEvents.optIn]);
    expect(await AnalyticsService.shouldAskForConsent(), isFalse);

    await analytics.logEvent(AnalyticsEvents.paywallView, {'source': 'x'});
    expect(backend.events.last, AnalyticsEvents.paywallView);

    // Re-applied on the next launch.
    final next = AnalyticsService(backend: FakeAnalyticsBackend());
    await next.init();
    expect(next.isEnabled, isTrue);
  });

  test('declining is remembered and deletes on-device analytics data',
      () async {
    await analytics.setEnabled(false);
    expect(analytics.isEnabled, isFalse);
    expect(backend.collectionEnabled, isFalse);
    expect(backend.resetCalled, isTrue);
    expect(backend.events, isEmpty);
    expect(await AnalyticsService.shouldAskForConsent(), isFalse);
  });

  test('the consent choice survives sign-out', () {
    expect(LocalDataWiper.deviceSettingKeys,
        containsAll([kAnalyticsPrefKey, kAnalyticsConsentAskedKey]));
  });
}
