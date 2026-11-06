import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

import 'package:flutter/foundation.dart' show visibleForTesting;

/// Keeps WorkManager tasks out of each other's way, and out of the app's
/// while it starts.
///
/// Periodic tasks that fell due while the phone was off, or across an app
/// update, all fire together, each in its own isolate with its own database
/// work. On a slow phone that can hold the database long enough for the
/// app's first open to look like a failure. Tasks wait here and run one at a
/// time. Everything is best effort: past [maxWait] a task runs anyway, so a
/// stuck task or a stale marker can only delay work, never lose it.
///
/// [IsolateNameServer] is process-wide, and registering a name that's taken
/// fails, so it works as a lock between isolates that dies with the process.
class BackgroundTurn {
  BackgroundTurn._();

  static const String _uiStartingName = 'pet.ui.starting';
  static const String _turnName = 'pet.background.turn';

  static const Duration maxWait = Duration(minutes: 3);
  static const Duration _poll = Duration(seconds: 1);

  static ReceivePort? _uiPort;

  /// The app is starting; background tasks hold off until [markUiStarted].
  static void markUiStarting() {
    markUiStarted();
    final port = ReceivePort();
    IsolateNameServer.registerPortWithName(port.sendPort, _uiStartingName);
    _uiPort = port;
  }

  static void markUiStarted() {
    IsolateNameServer.removePortNameMapping(_uiStartingName);
    _uiPort?.close();
    _uiPort = null;
  }

  /// Runs [task] when the app has finished starting and no other background
  /// task is running.
  static Future<T> run<T>(
    Future<T> Function() task, {
    @visibleForTesting Duration wait = maxWait,
    @visibleForTesting Duration poll = _poll,
  }) async {
    final deadline = DateTime.now().add(wait);
    bool timedOut() => DateTime.now().isAfter(deadline);

    while (IsolateNameServer.lookupPortByName(_uiStartingName) != null &&
        !timedOut()) {
      await Future<void>.delayed(poll);
    }

    final port = ReceivePort();
    var holding = false;
    while (!timedOut()) {
      holding =
          IsolateNameServer.registerPortWithName(port.sendPort, _turnName);
      if (holding) break;
      await Future<void>.delayed(poll);
    }
    try {
      return await task();
    } finally {
      if (holding) IsolateNameServer.removePortNameMapping(_turnName);
      port.close();
    }
  }
}
