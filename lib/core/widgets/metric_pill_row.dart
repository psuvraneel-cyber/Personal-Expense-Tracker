import 'package:flutter/material.dart';
import 'package:pet/core/theme/pet_colors.dart';
import 'package:pet/core/theme/typography.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:intl/intl.dart';

/// A row of three metric pills showing at-a-glance financial data.
///
/// Designed for the redesigned home screen, placed below the [HeroGreetingCard].
/// Each pill shows a value and label with a semantic background tint.
class MetricPillRow extends StatelessWidget {
  final double spentToday;
  final double budgetRemaining;
  final int spendScore;

  static final NumberFormat _formatter = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );

  const MetricPillRow({
    super.key,
    required this.spentToday,
    required this.budgetRemaining,
    required this.spendScore,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      children: [
        Expanded(
          child: _MetricPill(
            value: _formatter.format(spentToday),
            label: 'Spent\nToday',
            backgroundColor: PETColors.spentPillBg(isDark),
            valueColor:
                isDark ? AppTheme.textPrimary : AppTheme.textPrimaryLight,
            labelColor:
                isDark ? AppTheme.textSecondary : AppTheme.textSecondaryLight,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MetricPill(
            value: _formatter.format(budgetRemaining.abs()),
            label: budgetRemaining >= 0 ? 'Budget\nLeft' : 'Over\nBudget',
            backgroundColor: PETColors.budgetPillBg(isDark),
            valueColor:
                budgetRemaining >= 0 ? PETColors.success : PETColors.alert,
            labelColor:
                isDark ? AppTheme.textSecondary : AppTheme.textSecondaryLight,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MetricPill(
            value: '$spendScore',
            label: 'Score\n/100',
            backgroundColor: PETColors.scorePillBg(isDark),
            valueColor: _scoreColor(spendScore),
            labelColor:
                isDark ? AppTheme.textSecondary : AppTheme.textSecondaryLight,
          ),
        ),
      ],
    );
  }

  static Color _scoreColor(int score) {
    if (score >= 70) return PETColors.success;
    if (score >= 40) return PETColors.warning;
    return PETColors.alert;
  }
}

class _MetricPill extends StatelessWidget {
  final String value;
  final String label;
  final Color backgroundColor;
  final Color valueColor;
  final Color labelColor;

  const _MetricPill({
    required this.value,
    required this.label,
    required this.backgroundColor,
    required this.valueColor,
    required this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withAlpha(8) : Colors.black.withAlpha(6),
        ),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: AppTypography.metricValue(color: valueColor),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: AppTypography.metricLabel(color: labelColor),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
