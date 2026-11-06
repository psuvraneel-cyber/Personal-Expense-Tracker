import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pet/data/database/database_helper.dart';
import 'package:pet/screens/splash/database_recovery_screen.dart';
import 'package:pet/services/secure_storage_service.dart';

void main() {
  final locked = Exception('DatabaseException(database is locked (code 5))');
  final damaged = Exception('DatabaseException(malformed disk image)');

  var restarts = 0;
  setUp(() => restarts = 0);

  Future<void> pump(
    WidgetTester t,
    Object error, {
    required Future<void> Function() open,
  }) =>
      t.pumpWidget(DatabaseRecoveryApp(
        error: error,
        open: open,
        onRestart: () async => restarts++,
      ));

  group('isTemporaryOpenFailure', () {
    test('busy is temporary', () {
      expect(DatabaseHelper.isTemporaryOpenFailure(locked), isTrue);
      expect(
        DatabaseHelper.isTemporaryOpenFailure(TimeoutException('open')),
        isTrue,
      );
      expect(
        DatabaseHelper.isTemporaryOpenFailure(
            StateError('SQLCipher is unavailable; refusing to open')),
        isTrue,
      );
    });

    test('damage and lost keys are not', () {
      expect(DatabaseHelper.isTemporaryOpenFailure(damaged), isFalse);
      expect(
        DatabaseHelper.isTemporaryOpenFailure(
            DatabaseKeyUnavailableException('no key')),
        isFalse,
      );
    });
  });

  testWidgets('busy: waits, never offers Reset, and starts when it opens',
      (t) async {
    await pump(t, locked, open: () async {});
    expect(find.text('Finishing your update'), findsOneWidget);
    expect(find.textContaining('Your data is safe'), findsOneWidget);
    expect(find.text('Reset local data'), findsNothing);
    expect(find.text('Try again'), findsNothing);

    await t.pump(const Duration(seconds: 3));
    expect(restarts, 1);
  });

  testWidgets('still busy after waiting: Try again, but never Reset',
      (t) async {
    await pump(t, locked, open: () async => throw locked);
    await t.pump(const Duration(seconds: 3));
    await t.pump(const Duration(seconds: 3));
    await t.pump(const Duration(seconds: 3));
    await t.pump();
    expect(find.text('This is taking longer than usual'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);

    await t.tap(find.text('Try again'));
    await t.pumpAndSettle();
    expect(find.text('Reset local data'), findsNothing);
    expect(restarts, 0);
  });

  testWidgets('a timeout that turns out to be damage is treated as damage',
      (t) async {
    await pump(t, TimeoutException('open'), open: () async => throw damaged);
    await t.pump(const Duration(seconds: 3));
    await t.pump();
    expect(find.text("Your data couldn't be unlocked"), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('a real failure offers Reset only after Try again fails',
      (t) async {
    await pump(t, damaged, open: () async => throw damaged);
    expect(find.text("Your data couldn't be unlocked"), findsOneWidget);
    expect(find.text('Reset local data'), findsNothing);

    await t.tap(find.text('Try again'));
    await t.pumpAndSettle();
    expect(find.text('Reset local data'), findsOneWidget);
    expect(restarts, 0);
  });

  testWidgets('a lost key explains itself', (t) async {
    final e = DatabaseKeyUnavailableException('no key');
    await pump(t, e, open: () async => throw e);
    expect(find.textContaining('Android could not provide the key'),
        findsOneWidget);
  });

  testWidgets('Try again starts the app once it opens', (t) async {
    var fail = true;
    await pump(t, damaged, open: () async {
      if (fail) throw damaged;
    });
    fail = false;
    await t.tap(find.text('Try again'));
    await t.pumpAndSettle();
    expect(restarts, 1);
  });

  group('the first open', () {
    tearDown(() {
      DatabaseHelper.openOverride = null;
      DatabaseHelper.setTestDatabase(null);
    });

    test('a failed open can be tried again', () async {
      var opens = 0;
      DatabaseHelper.openOverride = () async {
        opens++;
        throw locked;
      };
      await expectLater(DatabaseHelper().database, throwsException);
      await expectLater(DatabaseHelper().database, throwsException);
      expect(opens, 2);
    });

    test('callers waiting at once share one open', () async {
      var opens = 0;
      final open = Completer<Never>();
      DatabaseHelper.openOverride = () {
        opens++;
        return open.future;
      };
      final a = DatabaseHelper().database;
      final b = DatabaseHelper().database;
      open.completeError(locked);
      await expectLater(a, throwsException);
      await expectLater(b, throwsException);
      expect(opens, 1);
    });
  });
}
