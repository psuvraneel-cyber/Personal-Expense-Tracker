import 'package:flutter/material.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:pet/core/theme/color_tokens.dart';
import 'package:pet/core/theme/spacing.dart';
import 'package:intl/intl.dart';

/// A design-system summary card with gradient accent strip, animated value,
/// and semantic color coding.
///
/// Used on the Dashboard to display Income / Expense / Savings at a glance.
///
/// ```dart
/// EnhancedSummaryCard(
///   title: 'Income',
///   amount: 42500,
///   icon: Icons.arrow_downward_rounded,
///   color: ColorTokens.income,
///   gradient: ColorTokens.incomeGradient,
/// )
/// ```
class EnhancedSummaryCard extends StatelessWidget {
  final String title;
  final double amount;
  final IconData icon;
  final Color color;
  final LinearGradient? gradient;
  final VoidCallback? onTap;

  static final NumberFormat _formatter = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );

  const EnhancedSummaryCard({
    super.key,
    required this.title,
    required this.amount,
    required this.icon,
    required this.color,
    this.gradient,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(Spacing.cardPadding),
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
                isDark ? 15 : 10,
              ),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Icon + label row
            Row(
              children: [
                // Gradient icon container
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: gradient ??
                        LinearGradient(
                          colors: [
                            color.withAlpha(isDark ? 40 : 28),
                            color.withAlpha(isDark ? 15 : 10),
                          ],
                        ),
                    borderRadius: BorderRadius.circular(Spacing.chipRadius),
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark
                          ? AppTheme.textSecondary
                          : AppTheme.textSecondaryLight,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.cardItemGap + 2),

            // ── Animated amount
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: amount),
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) {
                return Text(
                  _formatter.format(value),
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                );
              },
            ),

            // ── Accent strip at bottom
            const SizedBox(height: Spacing.md),
            Container(
              height: 3,
              decoration: BoxDecoration(
                gradient: gradient ??
                    LinearGradient(colors: [color, color.withAlpha(60)]),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
