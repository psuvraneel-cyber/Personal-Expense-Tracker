import 'package:flutter/material.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:pet/core/theme/color_tokens.dart';
import 'package:pet/core/theme/motion.dart';
import 'package:pet/core/theme/spacing.dart';
import 'package:pet/core/theme/typography.dart';
import 'package:pet/core/widgets/amount_text.dart';

/// The one hero surface on Home: what you've spent this month, and against
/// what. The greeting is a small line above, not the headline.
class HomeHero extends StatelessWidget {
  const HomeHero({
    super.key,
    required this.greeting,
    required this.monthLabel,
    required this.spent,
    required this.budget,
    required this.income,
    this.status,
  });

  /// e.g. "Good evening, Tester".
  final String greeting;

  /// e.g. "November".
  final String monthLabel;
  final double spent;

  /// Total of category budgets; 0 when none are set.
  final double budget;
  final double income;

  /// Small status shown opposite the greeting (the sync chip on Home).
  final Widget? status;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasBudget = budget > 0;
    final used = hasBudget ? spent / budget : 0.0;
    final left = budget - spent;
    final soft = Colors.white.withAlpha(190);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        gradient: ColorTokens.homeHero(isDark: isDark),
        borderRadius: BorderRadius.circular(Spacing.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  greeting,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmall(color: soft)
                      .copyWith(fontSize: 13),
                ),
              ),
              if (status != null) status!,
            ],
          ),
          const SizedBox(height: Spacing.base),
          Text(
            'Spent in $monthLabel',
            style: AppTypography.overline(color: soft),
          ),
          const SizedBox(height: Spacing.xs),
          _CountUp(
            value: spent,
            builder: (v) => AmountText(v, size: 38, color: Colors.white),
          ),
          const SizedBox(height: Spacing.base),
          if (hasBudget) ...[
            _BudgetLine(fraction: used),
            const SizedBox(height: Spacing.sm),
            Text(
              left >= 0
                  ? '₹${AmountText.digits(left)} left of '
                      '₹${AmountText.digits(budget)}'
                  : '₹${AmountText.digits(-left)} over your '
                      '₹${AmountText.digits(budget)} budget',
              style: AppTypography.bodySmall(color: soft).copyWith(
                  fontSize: 13, fontFeatures: AppTypography.tabularFigures),
            ),
          ] else
            Text(
              income > 0
                  ? '₹${AmountText.digits(income)} came in this month'
                  : 'Set a budget to see how much is left',
              style: AppTypography.bodySmall(color: soft).copyWith(
                  fontSize: 13, fontFeatures: AppTypography.tabularFigures),
            ),
        ],
      ),
    );
  }
}

class _BudgetLine extends StatelessWidget {
  const _BudgetLine({required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        height: 6,
        child: Stack(
          children: [
            Container(color: Colors.white.withAlpha(40)),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: fraction.clamp(0.0, 1.0)),
              duration: Motion.of(context, Motion.emphasized * 2),
              curve: Motion.easeOut,
              builder: (_, v, __) => FractionallySizedBox(
                widthFactor: v,
                child: Container(
                  color: fraction >= 1
                      ? ColorTokens.alert
                      : (fraction >= 0.85 ? ColorTokens.caution : Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Counts a number up once when it first appears or changes, never on an
/// unrelated rebuild. Skipped with reduced motion.
class _CountUp extends StatelessWidget {
  const _CountUp({required this.value, required this.builder});

  final double value;
  final Widget Function(double) builder;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: Motion.of(context, const Duration(milliseconds: 700)),
      curve: Motion.easeOut,
      builder: (_, v, __) => builder(v),
    );
  }
}

/// Three numbers at a glance on one quiet surface. Only the numbers carry
/// colour, and only when the colour means something.
class HomeStatStrip extends StatelessWidget {
  const HomeStatStrip({
    super.key,
    required this.spentToday,
    required this.budget,
    required this.spentThisMonth,
    required this.score,
    this.onScoreTap,
  });

  final double spentToday;
  final double budget;
  final double spentThisMonth;
  final int score;
  final VoidCallback? onScoreTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = isDark ? AppTheme.textPrimary : AppTheme.textPrimaryLight;
    final hasBudget = budget > 0;
    final left = budget - spentThisMonth;
    final days = _daysLeftInMonth(DateTime.now());

    final cells = <Widget>[
      _Stat(
        label: 'Today',
        value: AmountText(spentToday, size: 19, color: text),
      ),
      if (hasBudget && left >= 0)
        _Stat(
          label: 'Per day left',
          value: AmountText(left / days, size: 19, color: text),
        )
      else if (hasBudget)
        _Stat(
          label: 'Over budget',
          value: AmountText(-left, size: 19, color: ColorTokens.alert),
        )
      else
        _Stat(
          label: 'Daily average',
          value: AmountText(
            spentThisMonth / DateTime.now().day,
            size: 19,
            color: text,
          ),
        ),
      _Stat(
        label: 'Health score',
        onTap: onScoreTap,
        value: Text(
          '$score',
          style:
              AppTypography.amount(size: 19, color: ColorTokens.score(score)),
        ),
      ),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.cardDark : AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(Spacing.radiusLg),
        border: isDark
            ? null
            : Border.all(color: Colors.black.withAlpha(8), width: 1),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            for (var i = 0; i < cells.length; i++) ...[
              if (i > 0)
                const VerticalDivider(width: 1, indent: 4, endIndent: 4),
              Expanded(child: cells[i]),
            ],
          ],
        ),
      ),
    );
  }

  static int _daysLeftInMonth(DateTime now) {
    final last = DateTime(now.year, now.month + 1, 0).day;
    return last - now.day + 1;
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.onTap});

  final String label;
  final Widget value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final child = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: value,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodySmall(
              color:
                  isDark ? AppTheme.textSecondary : AppTheme.textSecondaryLight,
            ).copyWith(fontSize: 12),
          ),
        ],
      ),
    );
    if (onTap == null) return child;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Spacing.radiusMd),
      child: child,
    );
  }
}
