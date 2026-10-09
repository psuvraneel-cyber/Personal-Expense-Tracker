import 'package:flutter/services.dart';

/// Parsing, validation and formatting for money amounts typed by the user.
class AmountInput {
  AmountInput._();

  /// Largest amount accepted for a single transaction (₹10 crore).
  static const double maxAmount = 100000000;

  /// Digits, Indian/International grouping commas, one decimal point and at
  /// most two decimal places.
  static final List<TextInputFormatter> formatters = [
    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
    TextInputFormatter.withFunction((oldValue, newValue) {
      final raw = newValue.text.replaceAll(',', '');
      if (raw.isEmpty) return newValue;
      if (!RegExp(r'^\d*\.?\d{0,2}$').hasMatch(raw)) return oldValue;
      return newValue;
    }),
  ];

  /// Returns the amount, or null if [text] isn't a valid positive amount.
  static double? parse(String text) {
    final cleaned = text.replaceAll(',', '').trim();
    if (!RegExp(r'^\d+(\.\d{1,2})?$|^\.\d{1,2}$').hasMatch(cleaned)) {
      return null;
    }
    final value = double.tryParse(cleaned);
    if (value == null || !value.isFinite || value <= 0 || value > maxAmount) {
      return null;
    }
    return value;
  }

  /// Form validator message, or null when valid.
  static String? validate(String text) {
    final cleaned = text.replaceAll(',', '').trim();
    final value = double.tryParse(cleaned);
    if (value != null && value > maxAmount) {
      return 'Amount is too large';
    }
    return parse(text) == null ? 'Enter a valid amount' : null;
  }

  /// Shows whole amounts without decimals and keeps paise otherwise
  /// (editing ₹99.50 must not round it to ₹100).
  static String format(double amount) => amount == amount.truncateToDouble()
      ? amount.toStringAsFixed(0)
      : amount.toStringAsFixed(2);
}
