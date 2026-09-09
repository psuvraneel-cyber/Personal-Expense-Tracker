import 'package:flutter/material.dart';
import 'package:pet/core/theme/pet_colors.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:pet/core/theme/typography.dart';
import 'package:intl/intl.dart';

/// A compact horizontal progress bar for category spending.
///
/// Shows the category emoji/name, a progress bar color-coded by budget usage,
/// and the spent-vs-budget amounts. Designed for the redesigned home screen's
/// "Top Categories" section.
class CategoryProgressBarNew extends StatelessWidget {
  final String categoryName;
  final String? emoji;
  final double spent;
  final double budget;
  final VoidCallback? onTap;

  static final NumberFormat _formatter = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );

  const CategoryProgressBarNew({
    super.key,
    required this.categoryName,
    this.emoji,
    required this.spent,
    required this.budget,
    this.onTap,
  });

  double get _percent => budget > 0 ? spent / budget : 0;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final barColor = PETColors.budgetRingColor(_percent);
    final isOver = _percent > 1.0;

    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          children: [
            Row(
              children: [
                Text(emoji ?? '📦', style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    categoryName,
                    style: AppTypography.titleSmall(
                      color: isDark
                          ? AppTheme.textPrimary
                          : AppTheme.textPrimaryLight,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  _formatter.format(spent),
                  style: AppTypography.financialSmall(
                    color: isOver
                        ? PETColors.alert
                        : (isDark
                            ? AppTheme.textPrimary
                            : AppTheme.textPrimaryLight),
                  ),
                ),
                if (budget > 0) ...[
                  Text(
                    ' / ${_formatter.format(budget)}',
                    style: AppTypography.caption(
                      color: isDark
                          ? AppTheme.textTertiary
                          : AppTheme.textSecondaryLight,
                    ),
                  ),
                ],
                if (isOver) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: PETColors.alert.withAlpha(25),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'OVER',
                      style: TextStyle(
                        color: PETColors.alert,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: _percent.clamp(0.0, 1.0)),
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) {
                  return LinearProgressIndicator(
                    value: value,
                    minHeight: 6,
                    backgroundColor: isDark
                        ? Colors.white.withAlpha(10)
                        : Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation(barColor),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
