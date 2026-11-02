import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:pet/core/theme/color_tokens.dart';
import 'package:pet/core/theme/typography.dart';

/// Whether an amount is money in, money out, or neither.
enum AmountTone { neutral, income, expense, transfer }

/// A rupee amount with same-width digits and a lighter ₹ sign.
///
/// The sign is set a step smaller and lighter than the digits so the number
/// itself carries the weight. [tone] picks the colour and, with [showSign],
/// a leading + or −.
class AmountText extends StatelessWidget {
  const AmountText(
    this.amount, {
    super.key,
    this.size = 15,
    this.tone = AmountTone.neutral,
    this.showSign = false,
    this.decimals = 0,
    this.color,
    this.weight,
  });

  final double amount;
  final double size;
  final AmountTone tone;
  final bool showSign;
  final int decimals;

  /// Overrides the tone colour.
  final Color? color;
  final FontWeight? weight;

  static final Map<int, NumberFormat> _formats = {};

  /// Indian grouping without the symbol: 1,03,500.
  static String digits(double value, {int decimals = 0}) => _formats
      .putIfAbsent(
        decimals,
        () => NumberFormat.currency(
          locale: 'en_IN',
          symbol: '',
          decimalDigits: decimals,
        ),
      )
      .format(value)
      .trim();

  Color _toneColor(BuildContext context) => switch (tone) {
        AmountTone.income => AppTheme.incomeGreen,
        AmountTone.expense => AppTheme.expenseRed,
        AmountTone.transfer => ColorTokens.transfer,
        AmountTone.neutral => Theme.of(context).brightness == Brightness.dark
            ? AppTheme.textPrimary
            : AppTheme.textPrimaryLight,
      };

  @override
  Widget build(BuildContext context) {
    final c = color ?? _toneColor(context);
    final sign = !showSign
        ? ''
        : switch (tone) {
            AmountTone.income => '+',
            AmountTone.expense => '−',
            _ => '',
          };
    final style = AppTypography.amount(size: size, weight: weight, color: c);
    final text = digits(amount.abs(), decimals: decimals);
    final label = '$sign₹$text';
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Text.rich(
        TextSpan(
          children: [
            if (sign.isNotEmpty) TextSpan(text: '$sign '),
            TextSpan(
              text: '₹',
              style: style.copyWith(
                fontSize: size * 0.78,
                fontWeight: FontWeight.w500,
                color: c.withAlpha(200),
              ),
            ),
            TextSpan(text: text),
          ],
        ),
        style: style,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.fade,
      ),
    );
  }
}
