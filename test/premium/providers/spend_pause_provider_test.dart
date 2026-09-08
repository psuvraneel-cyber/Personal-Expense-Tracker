import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pet/premium/providers/spend_pause_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SpendPauseProvider provider;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    provider = SpendPauseProvider();
  });

  tearDown(() {
    provider.dispose();
  });

  group('SpendPauseProvider - Focus Mode Rearchitecture (Phase C)', () {
    test('initial state is inactive with no countdown timer running', () {
      expect(provider.isActive, isFalse);
      expect(provider.until, isNull);
      expect(provider.blockedCategoryIds, isEmpty);
      expect(provider.isCategoryBlocked('any-id'), isFalse);
    });

    test('activate starts pause, sets ID-based blocks and timer', () async {
      final until = DateTime.now().add(const Duration(hours: 4));
      final blockedIds = ['cat-dining', 'cat-shopping'];

      await provider.activate(
        until: until,
        categoryIds: blockedIds,
      );

      expect(provider.isActive, isTrue);
      expect(provider.until, isNotNull);
      expect(provider.blockedCategoryIds, containsAll(['cat-dining', 'cat-shopping']));

      // Exact ID-based blocking verification
      expect(provider.isCategoryBlocked('cat-dining'), isTrue);
      expect(provider.isCategoryBlocked('cat-shopping'), isTrue);
      expect(provider.isCategoryBlocked('cat-groceries'), isFalse);

      // Substring attacks must NOT match: "cat-dining-extra" is not blocked
      expect(provider.isCategoryBlocked('cat-dining-extra'), isFalse);
      expect(provider.isCategoryBlocked('shop'), isFalse);
    });

    test('deactivate immediately stops pause and clears active state', () async {
      await provider.activate(
        until: DateTime.now().add(const Duration(hours: 2)),
        categoryIds: ['cat-entertainment'],
      );
      expect(provider.isActive, isTrue);

      await provider.deactivate();
      expect(provider.isActive, isFalse);
      expect(provider.until, isNull);
      expect(provider.isCategoryBlocked('cat-entertainment'), isFalse);
    });

    test('pruneDeletedCategories cleans up references when categories are deleted (C2)', () async {
      await provider.activate(
        until: DateTime.now().add(const Duration(hours: 2)),
        categoryIds: ['cat-1', 'cat-2', 'cat-3'],
      );

      // cat-2 was deleted, only cat-1 and cat-3 remain valid
      provider.pruneDeletedCategories({'cat-1', 'cat-3'});

      expect(provider.blockedCategoryIds, ['cat-1', 'cat-3']);
      expect(provider.isCategoryBlocked('cat-2'), isFalse);
    });

    test('clearData wipes memory and persisted state on logout (C4)', () async {
      await provider.activate(
        until: DateTime.now().add(const Duration(hours: 3)),
        categoryIds: ['cat-food'],
      );
      expect(provider.isActive, isTrue);

      // Account wipe on sign out
      await provider.clearData();

      expect(provider.isActive, isFalse);
      expect(provider.until, isNull);
      expect(provider.blockedCategoryIds, isEmpty);

      // Re-instantiate to verify SharedPreferences was cleared
      final freshProvider = SpendPauseProvider();
      await freshProvider.load();
      expect(freshProvider.isActive, isFalse);
      freshProvider.dispose();
    });
  });
}
