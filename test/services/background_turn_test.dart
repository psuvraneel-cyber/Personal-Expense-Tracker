import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pet/services/background_turn.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const poll = Duration(milliseconds: 5);
  tearDown(BackgroundTurn.markUiStarted);

  test('background tasks run one at a time', () async {
    var running = 0, most = 0;
    Future<int> task(int v) async {
      running++;
      if (running > most) most = running;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      running--;
      return v;
    }

    final results = await Future.wait([
      for (var i = 0; i < 3; i++) BackgroundTurn.run(() => task(i), poll: poll),
    ]);
    expect(results, [0, 1, 2]);
    expect(most, 1);
  });

  test('a failing task gives up its turn', () async {
    await expectLater(
      BackgroundTurn.run<void>(() async => throw StateError('x'), poll: poll),
      throwsStateError,
    );
    expect(await BackgroundTurn.run(() async => 'next', poll: poll), 'next');
  });

  test('tasks wait while the app starts', () async {
    BackgroundTurn.markUiStarting();
    var ran = false;
    final task = BackgroundTurn.run(() async => ran = true, poll: poll);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(ran, isFalse);
    BackgroundTurn.markUiStarted();
    await task;
    expect(ran, isTrue);
  });

  test('a stuck app start only delays a task, up to the limit', () async {
    BackgroundTurn.markUiStarting();
    final done = await BackgroundTurn.run(
      () async => true,
      poll: poll,
      wait: const Duration(milliseconds: 30),
    );
    expect(done, isTrue);
  });

  test('a stuck task only delays the next one, up to the limit', () async {
    final hold = Completer<void>();
    final stuck = BackgroundTurn.run(() => hold.future, poll: poll);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final next = await BackgroundTurn.run(
      () async => 'ran',
      poll: poll,
      wait: const Duration(milliseconds: 30),
    );
    expect(next, 'ran');
    hold.complete();
    await stuck;
  });

  test('marking the start twice is harmless (recovery re-runs main)', () {
    BackgroundTurn.markUiStarting();
    BackgroundTurn.markUiStarting();
    BackgroundTurn.markUiStarted();
  });
}
