import 'package:flutter_test/flutter_test.dart';
import 'package:pet/data/models/enums.dart';

void main() {
  group('TransactionType', () {
    test('serializes to expected JSON string', () {
      expect(TransactionType.income.toJson(), 'income');
      expect(TransactionType.expense.toJson(), 'expense');
    });

    test('deserializes from valid JSON string', () {
      expect(TransactionType.fromJson('income'), TransactionType.income);
      expect(TransactionType.fromJson('expense'), TransactionType.expense);
    });

    test('deserializes unknown value to expense (default)', () {
      expect(TransactionType.fromJson(null), TransactionType.expense);
      expect(TransactionType.fromJson('invalid'), TransactionType.expense);
    });

    test('displayName returns capitalized label', () {
      expect(TransactionType.income.displayName, 'Income');
      expect(TransactionType.expense.displayName, 'Expense');
    });
  });

  group('PaymentMethod', () {
    test('roundtrip serialization', () {
      for (final method in PaymentMethod.values) {
        final json = method.toJson();
        final decoded = PaymentMethod.fromJson(json);
        expect(
          decoded,
          method,
          reason: '${method.name} should survive roundtrip',
        );
      }
    });

    test('displayName matches toJson', () {
      // toJson uses displayName for backward compat
      for (final method in PaymentMethod.values) {
        expect(method.toJson(), method.displayName);
      }
    });

    test('fromJson with null defaults to UPI', () {
      expect(PaymentMethod.fromJson(null), PaymentMethod.upi);
      expect(PaymentMethod.fromJson(''), PaymentMethod.upi);
    });

    test('fromJson with unknown string defaults to UPI', () {
      expect(PaymentMethod.fromJson('Bitcoin'), PaymentMethod.upi);
    });

    test('displayNames returns all human-readable labels', () {
      final names = PaymentMethod.displayNames;
      expect(names, contains('UPI'));
      expect(names, contains('Credit Card'));
      expect(names, contains('Cash'));
      expect(names.length, PaymentMethod.values.length);
    });
  });

  group('TransactionSource', () {
    test('roundtrip serialization', () {
      for (final source in TransactionSource.values) {
        final json = source.toJson();
        final decoded = TransactionSource.fromJson(json);
        expect(decoded, source);
      }
    });

    test('fromJson unknown defaults to manual', () {
      expect(TransactionSource.fromJson(null), TransactionSource.manual);
      expect(TransactionSource.fromJson('bluetooth'), TransactionSource.manual);
    });
  });

  group('RecurringFrequency', () {
    test('roundtrip serialization', () {
      for (final freq in RecurringFrequency.values) {
        final json = freq.toJson();
        final decoded = RecurringFrequency.fromJson(json);
        expect(decoded, freq);
      }
    });

    test('fromJson null returns null', () {
      expect(RecurringFrequency.fromJson(null), isNull);
    });

    test('fromJson unknown defaults to monthly', () {
      expect(
        RecurringFrequency.fromJson('biweekly'),
        RecurringFrequency.monthly,
      );
    });

    test('displayName returns capitalized label', () {
      expect(RecurringFrequency.daily.displayName, 'Daily');
      expect(RecurringFrequency.yearly.displayName, 'Yearly');
    });
  });
}
