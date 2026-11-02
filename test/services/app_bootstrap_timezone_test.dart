import 'package:flutter_test/flutter_test.dart';
import 'package:pet/services/app_bootstrap.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUpAll(tz.initializeTimeZones);

  test('current zone names resolve as they are', () {
    expect(AppBootstrap.locationFor('Asia/Kolkata').name, 'Asia/Kolkata');
    expect(AppBootstrap.locationFor('Europe/London').name, 'Europe/London');
  });

  test('old names that devices still report resolve to the current zone', () {
    // The Android emulator reports "Asia/Calcutta".
    expect(AppBootstrap.locationFor('Asia/Calcutta').name, 'Asia/Kolkata');
    expect(AppBootstrap.locationFor('Asia/Saigon').name, 'Asia/Ho_Chi_Minh');
    expect(AppBootstrap.locationFor('Asia/Katmandu').name, 'Asia/Kathmandu');
  });

  test('every mapped old name points at a zone the database has', () {
    for (final name in [
      'Asia/Calcutta',
      'Asia/Katmandu',
      'Asia/Dacca',
      'Asia/Rangoon',
      'Asia/Saigon',
      'Asia/Thimbu',
      'Asia/Ujung_Pandang',
      'Asia/Ulan_Bator',
      'Atlantic/Faeroe',
      'Europe/Kiev',
      'America/Buenos_Aires',
      'America/Indianapolis',
    ]) {
      expect(() => AppBootstrap.locationFor(name), returnsNormally,
          reason: name);
    }
  });

  test('unknown names still fail, so the caller falls back', () {
    expect(() => AppBootstrap.locationFor('Mars/Olympus_Mons'),
        throwsA(isA<tz.LocationNotFoundException>()));
  });
}
