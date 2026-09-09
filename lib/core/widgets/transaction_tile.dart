import 'package:flutter/material.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/data/models/category.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:intl/intl.dart';

class TransactionTile extends StatelessWidget {
  final TransactionRecord transaction;
  final Category? category;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  // Static cached formatters to avoid recreation per tile
  static final NumberFormat _formatter = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );
  static final DateFormat _dateFormatter = DateFormat('dd MMM, hh:mm a');

  const TransactionTile({
    super.key,
    required this.transaction,
    this.category,
    this.onTap,
    this.onEdit,
    this.onDelete,
  });

  IconData _getPaymentIcon() {
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
    final isExpense = transaction.type == TransactionType.expense;
    final amountColor = isExpense ? AppTheme.expenseRed : AppTheme.incomeGreen;
    final formatter = _formatter;
    final dateFormatter = _dateFormatter;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.cardDark : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color:
                isDark ? Colors.white.withAlpha(6) : Colors.black.withAlpha(6),
          ),
          boxShadow: [
            BoxShadow(
              color: (isDark ? Colors.black : Colors.grey).withAlpha(
                isDark ? 15 : 8,
              ),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            // Category icon
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: (category?.color ?? Colors.grey).withAlpha(
                  isDark ? 25 : 18,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                category?.icon ?? Icons.category,
                color: category?.color ?? Colors.grey,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            // Transaction details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category?.name ?? 'Unknown',
                    style: TextStyle(
                      fontSize: 15,
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
                        _getPaymentIcon(),
                        size: 12,
                        color: isDark
                            ? AppTheme.textTertiary
                            : AppTheme.textTertiary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        transaction.paymentMethod.displayName,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? AppTheme.textTertiary
                              : AppTheme.textSecondaryLight,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '•',
                        style: TextStyle(
                          color: isDark
                              ? AppTheme.textTertiary
                              : AppTheme.textTertiary,
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          dateFormatter.format(transaction.date),
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
                  if (transaction.note.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
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
                  ],
                ],
              ),
            ),
            // Amount
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${isExpense ? '-' : '+'}${formatter.format(transaction.amount)}',
                  style: TextStyle(
                    color: amountColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
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
