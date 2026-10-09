import 'package:flutter_test/flutter_test.dart';
import 'package:pet/core/utils/amount_input.dart';

void main() {
  test('parses plain, decimal and comma-grouped amounts', () {
    expect(AmountInput.parse('500'), 500);
    expect(AmountInput.parse('99.5'), 99.5);
    expect(AmountInput.parse('1,00,000.25'), 100000.25);
  });

  test('rejects non-finite, zero, negative, too precise and too large', () {
    for (final bad in ['NaN', 'Infinity', '0', '-5', '1e5', '1.234', '', '.']) {
      expect(AmountInput.parse(bad), isNull, reason: bad);
    }
    expect(AmountInput.parse('100000001'), isNull);
    expect(AmountInput.validate('100000001'), 'Amount is too large');
  });

  test('format keeps paise and drops .00', () {
    expect(AmountInput.format(99.5), '99.50');
    expect(AmountInput.format(100), '100');
  });
}
