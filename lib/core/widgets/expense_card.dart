import 'package:flutter/material.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:pet/core/theme/color_tokens.dart';
import 'package:pet/core/theme/spacing.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/data/models/category.dart';
import 'package:intl/intl.dart';

/// A modern, design-system-aligned expense/income card with gradient accent,
/// category icon, amount, and metadata.
///
/// Replaces inline transaction rows with a self-contained, reusable widget.
///
/// ```dart
/// ExpenseCard(
///   transaction: txn,
///   category: cat,
///   onTap: () => editTransaction(txn),
/// )
/// ```
class ExpenseCard extends StatelessWidget {
  final TransactionRecord transaction;
  final Category? category;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  /// If true, shows a compact version (for lists). Default is false (detail).
  final bool compact;

  static final NumberFormat _formatter = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );
  static final DateFormat _dateFmt = DateFormat('dd MMM, hh:mm a');

  const ExpenseCard({
    super.key,
    required this.transaction,
    this.category,
    this.onTap,
    this.onEdit,
    this.onDelete,
    this.compact = false,
  });

  IconData _paymentIcon() {
    switch (transaction.paymentMethod) {
      case PaymentMethod.upi:
        return Icons.phone_android;
      case PaymentMethod.creditCard:
        return Icons.credit_card;
      case PaymentMethod.debitCard:
        return Icons.credit_card_outlined;
      case PaymentMethod.cash:
        return Icons.payments_outlined;
      default:
        return Icons.payment;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final amountColor = switch (transaction.type) {
      TransactionType.expense => ColorTokens.expense,
      TransactionType.income => ColorTokens.income,
      TransactionType.transfer => ColorTokens.transfer,
    };
    final catColor = category?.color ?? Colors.grey;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.only(bottom: compact ? Spacing.sm : Spacing.md),
        padding: EdgeInsets.all(
          compact ? Spacing.cardPaddingCompact : Spacing.cardPadding,
        ),
        decoration: BoxDecoration(
          gradient: isDark
              ? ColorTokens.darkCardGradient
              : ColorTokens.lightCardGradient,
          borderRadius: BorderRadius.circular(Spacing.cardRadius),
          border: Border.all(
            color: isDark ? ColorTokens.darkBorder : ColorTokens.lightBorder,
          ),
          boxShadow: [
            BoxShadow(
              color: (isDark ? Colors.black : Colors.grey).withAlpha(
                isDark ? 20 : 10,
              ),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // ── Category icon with gradient background
            Container(
              width: compact ? 42 : 48,
              height: compact ? 42 : 48,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    catColor.withAlpha(isDark ? 40 : 28),
                    catColor.withAlpha(isDark ? 15 : 10),
                  ],
                ),
                borderRadius: BorderRadius.circular(Spacing.chipRadius + 2),
              ),
              child: Icon(
                category?.icon ?? Icons.category,
                color: catColor,
                size: compact ? 20 : 22,
              ),
            ),
            SizedBox(width: compact ? Spacing.md : Spacing.cardItemGap),

            // ── Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category?.name ?? 'Unknown',
                    style: TextStyle(
                      fontSize: compact ? 14 : 15,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppTheme.textPrimary
                          : AppTheme.textPrimaryLight,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(
                        _paymentIcon(),
                        size: 12,
                        color: AppTheme.textTertiary,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          '${transaction.paymentMethod.displayName} • ${_dateFmt.format(transaction.date)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? AppTheme.textTertiary
                                : AppTheme.textSecondaryLight,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (transaction.note.isNotEmpty && !compact)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        transaction.note,
                        style: TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: isDark
                              ? AppTheme.textTertiary
                              : AppTheme.textSecondaryLight,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),

            // ── Amount + recurring badge
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${transaction.type.amountSign}${_formatter.format(transaction.amount)}',
                  style: TextStyle(
                    color: amountColor,
                    fontWeight: FontWeight.bold,
                    fontSize: compact ? 14 : 15,
                  ),
                ),
                if (transaction.isRecurring)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.accentTeal.withAlpha(25),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.repeat,
                          size: 10,
                          color: AppTheme.accentTeal,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          transaction.recurringFrequency?.displayName ??
                              'recurring',
                          style: const TextStyle(
                            color: AppTheme.accentTeal,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
