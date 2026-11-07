import 'package:flutter_test/flutter_test.dart';
import 'package:pet/services/sms_parser/self_consistency_checker.dart';
import 'package:pet/services/sms_parser/sms_transaction_parser.dart';
import 'package:pet/services/sms_parser/time_extractor.dart';

void main() {
  TimeResult extract(String text) => TimeExtractor.extract(text);

  group('TimeExtractor', () {
    test('parses explicit AM/PM times before generic at-time matching', () {
      expect(extract('at 04:41 PM').hour, 16);
      expect(extract('at 04:41 PM').minute, 41);
      expect(extract('at 04:41 AM').hour, 4);
      expect(extract('at 12:15 PM').hour, 12);
      expect(extract('at 12:15 AM').hour, 0);
      expect(extract('at 01:05 PM').hour, 13);
      expect(extract('at 11:59 PM').hour, 23);
    });

    test('supports lowercase and flexible whitespace around AM/PM', () {
      expect(extract('at 4:41 pm').hour, 16);
      expect(extract('at  04:41   pM').hour, 16);
      expect(extract('at 04:41:37 PM').second, 37);
    });

    test('an AM/PM time later in the message does not override "at HH:MM"', () {
      final t = extract(
          'Rs 500 debited at 14:30 on 05-Oct-26. Disputes: call before 11:59 PM');
      expect(t.hour, 14);
      expect(t.minute, 30);
    });

    test('an AM/PM time before a 24-hour "at" time still wins', () {
      final t = extract('On 05-Oct 2:30 PM, card used at 09:15');
      expect(t.hour, 14);
      expect(t.minute, 30);
    });

    test('preserves valid 24-hour times and seconds', () {
      expect(extract('at 14:41').hour, 14);
      expect(extract('at 23:59').hour, 23);
      expect(extract('at 04:41:37').second, 37);
    });

    test('rejects invalid 12-hour and minute values', () {
      expect(extract('at 00:15 PM').hasTime, isFalse,
          reason: '${extract('at 00:15 PM')}');
      expect(extract('at 13:15 PM').hasTime, isFalse,
          reason: '${extract('at 13:15 PM')}');
      expect(extract('at 04:60 PM').hasTime, isFalse,
          reason: '${extract('at 04:60 PM')}');
      expect(extract('at 24:00').hasTime, isFalse,
          reason: '${extract('at 24:00')}');
    });

    test('does not interpret date colons as a time', () {
      expect(extract('Transaction date 2026:09:22').hasTime, isFalse);
      expect(extract('Settled on 22/09/2026').hasTime, isFalse);
    });

    test('returns no time when the body has no reliable time', () {
      expect(extract('Payment of Rs 124 on 22/09/2026').hasTime, isFalse);
    });

    test('keeps the parenthesized BOB datetime format', () {
      final result = extract('Rs 500 (2026:02:13 01:45:36)');
      expect(result.hour, 1);
      expect(result.minute, 45);
      expect(result.second, 36);
    });
  });

  test('falls back to the OS timestamp when the body has no time', () {
    final result = SmsTransactionParser.parse(
      body: 'Rs 124 debited from A/c XX1234 on 22/09/2026.',
      sender: 'AD-HDFCBK',
      timestamp: DateTime(2026, 9, 22, 9, 27, 14),
    );
    expect(result.date, DateTime(2026, 9, 22, 9, 27, 14));
    expect(result.time, isNull);
  });

  test('exact Swiggy confirmation keeps PM through parser consensus', () {
    const body = 'Payment Confirmed! Your Swiggy Order #XX****1111 of Rs. '
        '124.0 was successfully paid on 22/09/2026 at 04:41 PM. '
        'Txn ID: 4123000045670001.';

    final consensus = SelfConsistencyChecker.check(
      body: body,
      sender: 'AD-SWIGGY-S',
      timestamp: DateTime(2026, 9, 22, 16, 41),
    );

    expect(
        consensus.result.isTransaction || consensus.result.isUncertain, isTrue);
    expect(consensus.result.date, DateTime(2026, 9, 22, 16, 41));
    expect(consensus.result.time?.hour, 16);
    expect(consensus.result.time?.minute, 41);
  });
}
