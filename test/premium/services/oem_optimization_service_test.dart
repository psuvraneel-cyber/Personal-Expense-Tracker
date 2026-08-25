import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pet/premium/services/oem_optimization_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'PET',
      packageName: 'com.pet.tracker.pet',
      version: '1.0.1',
      buildNumber: '10',
      buildSignature: '',
    );
  });

  group('OemOptimizationService', () {
    test('isManufacturerAggressive detects aggressive OEM brands correctly', () {
      expect(OemOptimizationService.isManufacturerAggressive('Xiaomi'), isTrue);
      expect(OemOptimizationService.isManufacturerAggressive('Redmi'), isTrue);
      expect(OemOptimizationService.isManufacturerAggressive('POCO'), isTrue);
      expect(OemOptimizationService.isManufacturerAggressive('OPPO'), isTrue);
      expect(OemOptimizationService.isManufacturerAggressive('Realme'), isTrue);
      expect(OemOptimizationService.isManufacturerAggressive('Vivo'), isTrue);
      expect(OemOptimizationService.isManufacturerAggressive('iQOO'), isTrue);
      expect(OemOptimizationService.isManufacturerAggressive('Samsung'), isTrue);
      expect(OemOptimizationService.isManufacturerAggressive('Huawei'), isTrue);
      expect(OemOptimizationService.isManufacturerAggressive('Honor'), isTrue);

      expect(OemOptimizationService.isManufacturerAggressive('Google'), isFalse);
      expect(OemOptimizationService.isManufacturerAggressive('Motorola'), isFalse);
      expect(OemOptimizationService.isManufacturerAggressive('Nokia'), isFalse);
    });

    test('getPackageName reads runtime package name via PackageInfo', () async {
      final service = OemOptimizationService.instance;
      final packageName = await service.getPackageName();
      expect(packageName, equals('com.pet.tracker.pet'));
    });

    test('hasPromptBeenShown defaults to false and persists when marked shown', () async {
      final service = OemOptimizationService.instance;

      expect(await service.hasPromptBeenShown(), isFalse);

      await service.markPromptShown();

      expect(await service.hasPromptBeenShown(), isTrue);
    });
  });
}
