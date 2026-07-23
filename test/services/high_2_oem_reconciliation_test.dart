import 'package:flutter_test/flutter_test.dart';
import 'package:pet/services/native_sms_reader.dart';
import 'package:pet/services/reconciliation_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HIGH-2: Foreground Reconciliation & OEM Whitelist Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('Aggressive OEM detection identifies Xiaomi, OPPO, Vivo, Realme', () {
      final aggressiveOems = NativeSmsReader.aggressiveOems;
      expect(aggressiveOems, contains('xiaomi'));
      expect(aggressiveOems, contains('oppo'));
      expect(aggressiveOems, contains('vivo'));
      expect(aggressiveOems, contains('realme'));
      expect(aggressiveOems, contains('redmi'));
      expect(aggressiveOems, contains('poco'));
    });

    test('ReconciliationService respects 5-minute throttle between runs', () async {
      SharedPreferences.setMockInitialValues({
        'pet_reconciliation_last_run': DateTime.now().millisecondsSinceEpoch,
      });

      final service = ReconciliationService();
      // Should return 0 immediately due to 5-min throttle
      final count = await service.reconcile();
      expect(count, equals(0));
    });

    test('getLastSyncTimestamp reads watermark or last run correctly', () async {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues({
        'pet_reconciliation_watermark': nowMs - 60000, // 1 min ago
      });

      final service = ReconciliationService();
      final lastSync = await service.getLastSyncTimestamp();

      expect(lastSync, isNotNull);
      expect(lastSync!.millisecondsSinceEpoch, equals(nowMs - 60000));
    });
  });
}
