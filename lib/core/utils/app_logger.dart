import 'package:flutter/foundation.dart';

/// Lightweight structured logger — wraps [debugPrint] with level tags
/// and optional context labels.
///
/// Replaces raw `debugPrint` calls with structured, filterable output.
/// All output is gated on [kDebugMode] and is a **complete no-op** in
/// profile and release builds — nothing reaches logcat or the console.
///
/// Usage:
/// ```dart
/// AppLogger.info('Loaded 42 transactions', label: 'TransactionProvider');
/// AppLogger.warn('Retrying sync', label: 'Sync');
/// AppLogger.error('Database open failed', error: e, stack: stack, label: 'DB');
/// ```
class AppLogger {
  AppLogger._(); // non-instantiable

  /// Informational message for normal operations.
  static void info(String message, {String? label}) {
    if (!kDebugMode) return;
    _log('INFO', message, label: label);
  }

  /// Warning — something unexpected but recoverable.
  static void warn(String message, {String? label}) {
    if (!kDebugMode) return;
    _log('WARN', message, label: label);
  }

  /// Error — something failed.
  static void error(
    String message, {
    Object? error,
    StackTrace? stack,
    String? label,
  }) {
    if (!kDebugMode) return;
    _log('ERROR', message, label: label);
    if (error != null) {
      debugPrint('  ↳ $error');
    }
    if (stack != null) {
      debugPrint('  ↳ $stack');
    }
  }

  /// Debug — verbose, only interesting during development.
  static void debug(String message, {String? label}) {
    if (!kDebugMode) return;
    _log('DEBUG', message, label: label);
  }

  static void _log(String level, String message, {String? label}) {
    // Completely silent in profile and release builds.
    if (!kDebugMode) return;
    final prefix = label != null ? '[$label] ' : '';
    debugPrint('[$level] $prefix$message');
  }
}
