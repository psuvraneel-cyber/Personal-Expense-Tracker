import 'package:flutter_test/flutter_test.dart';
import 'package:pet/core/utils/crash_scrubber.dart';

/// Audit P3-11: crash reports must not carry amounts, account numbers or
/// emails from parsed messages.
void main() {
  test('amounts, long numbers and emails are removed', () {
    final scrubbed = CrashScrubber.scrub(
      'FormatException: Rs 1,23,456.78 debited from A/c 50100123456789 '
      'Ref 412345678901 for user priya.s@example.com on 24-08-2026',
    );
    expect(scrubbed, isNot(contains('1,23,456')));
    expect(scrubbed, isNot(contains('50100123456789')));
    expect(scrubbed, isNot(contains('412345678901')));
    expect(scrubbed, isNot(contains('priya.s@example.com')));
    expect(scrubbed, isNot(contains('24-08-2026')));
    expect(scrubbed, contains('FormatException'));
  });

  test('scrubbed errors keep their type for grouping', () {
    final error = CrashScrubber.scrubError(StateError('bad amount ₹950'));
    expect(error.toString(), startsWith('StateError'));
    expect(error.toString(), isNot(contains('950')));
  });
}
