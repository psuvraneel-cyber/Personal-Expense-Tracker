import 'package:flutter/material.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:intl/intl.dart';

class BudgetProgressBar extends StatelessWidget {
  final String categoryName;
  final IconData categoryIcon;
  final Color categoryColor;
  final double budgetAmount;
  final double spentAmount;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  // Static cached formatter
  static final NumberFormat _formatter = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );

  const BudgetProgressBar({
    super.key,
    required this.categoryName,
    required this.categoryIcon,
    required this.categoryColor,
    required this.budgetAmount,
    required this.spentAmount,
    this.onTap,
    this.onDelete,
  });

  Color _getProgressColor(double progress) {
    if (progress < 0.7) return AppTheme.incomeGreen;
    if (progress < 0.9) return AppTheme.warningYellow;
    return AppTheme.expenseRed;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final progress = budgetAmount > 0 ? (spentAmount / budgetAmount) : 0.0;
    final progressColor = _getProgressColor(progress);
    final formatter = _formatter;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
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
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        categoryColor.withAlpha(40),
                        categoryColor.withAlpha(15),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(categoryIcon, color: categoryColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        categoryName,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${formatter.format(spentAmount)} of ${formatter.format(budgetAmount)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${(progress * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                        color: progressColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    if (progress >= 1.0)
                      Container(
                        margin: const EdgeInsets.only(top: 2),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.expenseRed.withAlpha(30),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Over budget!',
                          style: TextStyle(
                            color: AppTheme.expenseRed,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: progress.clamp(0.0, 1.0)),
              duration: const Duration(milliseconds: 1000),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: value,
                    minHeight: 8,
                    backgroundColor:
                        isDark ? AppTheme.surfaceDark : const Color(0xFFE2E8F0),
                    valueColor: AlwaysStoppedAnimation(progressColor),
                  ),
                );
              },
            ),
            if (budgetAmount > 0 && spentAmount < budgetAmount) ...[
              const SizedBox(height: 8),
              Text(
                '${formatter.format(budgetAmount - spentAmount)} remaining',
                style: TextStyle(
                  color: progressColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
