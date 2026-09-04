import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pet/premium/models/spend_pause.dart';
import 'package:pet/premium/services/spend_pause_service.dart';

void main() {
  group('SpendPauseService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('default state is disabled with empty blocked categories', () async {
      final state = await SpendPauseService.getState();
      expect(state.enabled, isFalse);
      expect(state.isActive, isFalse);
      expect(state.blockedCategories, isEmpty);
    });

    test('persists and restores active pause with custom duration and categories', () async {
      final customDate = DateTime.now().add(const Duration(days: 5));
      final pause = SpendPause(
        enabled: true,
        until: customDate,
        blockedCategories: ['Shopping', 'Entertainment'],
      );

      await SpendPauseService.setState(pause);
      final restored = await SpendPauseService.getState();

      expect(restored.enabled, isTrue);
      expect(restored.isActive, isTrue);
      expect(restored.until, isNotNull);
      expect(restored.blockedCategories, containsAll(['Shopping', 'Entertainment']));
    });

    test('auto-expires past pause date and returns disabled', () async {
      final pastDate = DateTime.now().subtract(const Duration(hours: 2));
      final pause = SpendPause(
        enabled: true,
        until: pastDate,
        blockedCategories: ['Dining'],
      );

      await SpendPauseService.setState(pause);
      final restored = await SpendPauseService.getState();

      expect(restored.enabled, isFalse);
      expect(restored.isActive, isFalse);
    });
  });
}
