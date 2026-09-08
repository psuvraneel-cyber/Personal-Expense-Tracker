import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pet/premium/models/spend_pause.dart';
import 'package:pet/premium/services/spend_pause_service.dart';
import 'package:pet/premium/providers/spend_pause_provider.dart';
import 'package:pet/services/firestore_sync_service.dart';

class FakeSyncServiceForSpendPause implements FirestoreSyncService {
  String? _uid;

  void setUid(String? uid) {
    _uid = uid;
  }

  @override
  String? get currentUserIdOrNull => _uid;

  @override
  String get currentUserId {
    if (_uid == null) throw StateError('Not authenticated');
    return _uid!;
  }

  @override
  bool get isAuthenticated => _uid != null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SpendPauseService Account Isolation', () {
    test('State is isolated per userId and logged-out state is always disabled', () async {
      final prefs = await SharedPreferences.getInstance();

      final pauseUserA = SpendPause(
        enabled: true,
        until: DateTime.now().add(const Duration(hours: 4)),
        blockedCategoryIds: ['dining', 'shopping'],
      );

      // Save for user_a
      await SpendPauseService.setState(pauseUserA, userId: 'user_a', prefsInstance: prefs);

      // Check user_a state
      final retrievedA = await SpendPauseService.getState(userId: 'user_a', prefsInstance: prefs);
      expect(retrievedA.enabled, isTrue);
      expect(retrievedA.blockedCategoryIds, containsAll(['dining', 'shopping']));

      // Check user_b state - MUST be disabled / empty
      final retrievedB = await SpendPauseService.getState(userId: 'user_b', prefsInstance: prefs);
      expect(retrievedB.enabled, isFalse);
      expect(retrievedB.blockedCategoryIds, isEmpty);

      // Check null (unauthenticated) state - MUST be disabled / empty
      final retrievedNull = await SpendPauseService.getState(userId: null, prefsInstance: prefs);
      expect(retrievedNull.enabled, isFalse);
      expect(retrievedNull.blockedCategoryIds, isEmpty);
    });

    test('Clearing one user does not clear another user', () async {
      final prefs = await SharedPreferences.getInstance();

      final pauseA = SpendPause(
        enabled: true,
        until: DateTime.now().add(const Duration(hours: 2)),
        blockedCategoryIds: ['electronics'],
      );
      final pauseB = SpendPause(
        enabled: true,
        until: DateTime.now().add(const Duration(hours: 1)),
        blockedCategoryIds: ['travel'],
      );

      await SpendPauseService.setState(pauseA, userId: 'user_a', prefsInstance: prefs);
      await SpendPauseService.setState(pauseB, userId: 'user_b', prefsInstance: prefs);

      // Clear user_a
      await SpendPauseService.clear(userId: 'user_a', prefsInstance: prefs);

      final stateA = await SpendPauseService.getState(userId: 'user_a', prefsInstance: prefs);
      final stateB = await SpendPauseService.getState(userId: 'user_b', prefsInstance: prefs);

      expect(stateA.enabled, isFalse);
      expect(stateB.enabled, isTrue);
      expect(stateB.blockedCategoryIds, equals(['travel']));
    });
  });

  group('SpendPauseProvider Account Isolation & Lifecycle', () {
    test('clearData() resets in-memory state and disables active pause', () async {
      final fakeSync = FakeSyncServiceForSpendPause()..setUid('user_a');
      final provider = SpendPauseProvider(firestoreSync: fakeSync);

      await provider.activate(
        until: DateTime.now().add(const Duration(hours: 3)),
        categoryIds: ['dining'],
      );

      expect(provider.isActive, isTrue);
      expect(provider.blockedCategoryIds, contains('dining'));

      // Simulate sign-out
      fakeSync.setUid(null);
      await provider.clearData();

      expect(provider.isActive, isFalse);
      expect(provider.blockedCategoryIds, isEmpty);
      expect(provider.pause.enabled, isFalse);

      provider.dispose();
    });
  });
}
