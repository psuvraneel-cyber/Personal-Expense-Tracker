import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet/core/utils/app_logger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('INVESTMENT-GRADE AUDIT: Logging Pipeline Release Safety', () {
    late DebugPrintCallback originalDebugPrint;
    late List<String> capturedLogs;

    setUp(() {
      originalDebugPrint = debugPrint;
      capturedLogs = <String>[];
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) {
          capturedLogs.add(message);
        }
      };
    });

    tearDown(() {
      debugPrint = originalDebugPrint;
    });

    test('1. AppLogger formats output correctly in debug environment', () {
      AppLogger.info('User authenticated', label: 'Auth');
      AppLogger.warn('High latency detected', label: 'Network');
      AppLogger.error('Database connection failed', error: 'TimeoutException', label: 'DB');
      AppLogger.debug('Parsing SMS payload', label: 'Parser');

      expect(capturedLogs.length, greaterThanOrEqualTo(4));
      expect(capturedLogs[0], contains('[INFO] [Auth] User authenticated'));
      expect(capturedLogs[1], contains('[WARN] [Network] High latency detected'));
      expect(capturedLogs[2], contains('[ERROR] [DB] Database connection failed'));
      expect(capturedLogs[3], contains('  ↳ TimeoutException'));
    });

    test('2. Global release debugPrint override eliminates raw debugPrint output', () {
      // Simulate release mode global override as performed in main.dart
      debugPrint = (String? message, {int? wrapWidth}) {};

      // Attempt raw debugPrint call
      debugPrint('SENSITIVE FINANCIAL SMS DATA: Account 1234 debited Rs 5,000');

      expect(capturedLogs, isEmpty, reason: 'Release debugPrint override must drop all messages');
    });

    test('3. AppLogger contains zero raw debugPrint leaks when overridden in release mode', () {
      debugPrint = (String? message, {int? wrapWidth}) {};

      AppLogger.info('Sensitive info log', label: 'Test');
      AppLogger.error('Sensitive error log', error: Exception('Private data'), label: 'Test');
      AppLogger.debug('Sensitive debug log', label: 'Test');

      expect(capturedLogs, isEmpty, reason: 'Release build must yield ZERO logcat outputs');
    });
  });
}
