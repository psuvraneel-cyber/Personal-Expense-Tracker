import 'package:flutter/material.dart';
import 'package:pet/core/theme/color_tokens.dart';
import 'package:pet/core/theme/spacing.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:pet/core/theme/typography.dart';
import 'package:pet/services/spend_health_service.dart';
import 'package:pet/premium/screens/premium_hub_screen.dart';

/// A detailed Spend Health Score card for the redesigned dashboard.
///
/// Shows the score out of 100, the grade, per-dimension breakdown bars,
/// a tip, and a "See Full Report →" link.
///
/// Uses the canonical [SpendHealthService] to ensure scores match
/// the premium hub exactly.
class SpendHealthCard extends StatelessWidget {
  final SpendHealthResult result;

  const SpendHealthCard({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scoreColor = _scoreColor(result.totalScore);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(Spacing.radiusLg),
        border: isDark
            ? null
            : Border.all(color: Colors.black.withAlpha(8), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row: title + score badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Spend Health',
                style: AppTypography.sectionHeader(
                  color:
                      isDark ? AppTheme.textPrimary : AppTheme.textPrimaryLight,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: scoreColor.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${result.totalScore}/100  ${result.grade}',
                  style: AppTypography.labelMedium(color: scoreColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Overall progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: result.totalScore / 100),
              duration: const Duration(milliseconds: 1000),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) {
                return LinearProgressIndicator(
                  value: value,
                  minHeight: 8,
                  backgroundColor: isDark
                      ? Colors.white.withAlpha(10)
                      : Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation(scoreColor),
                );
              },
            ),
          ),
          const SizedBox(height: 16),

          // Per-dimension breakdown
          ...result.dimensions.map((dim) => _buildDimensionRow(dim, isDark)),
          const SizedBox(height: 12),

          // Tip
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withAlpha(5) : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.lightbulb_outline_rounded,
                  size: 16,
                  color: isDark
                      ? AppTheme.textSecondary
                      : AppTheme.textSecondaryLight,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    result.tip,
                    style: AppTypography.bodySmall(
                      color: isDark
                          ? AppTheme.textSecondary
                          : AppTheme.textSecondaryLight,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // CTA
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PremiumHubScreen()),
              );
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'See full report',
                  style: AppTypography.labelMedium(
                    color: AppTheme.accentPurple,
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: AppTheme.accentPurple,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDimensionRow(HealthDimension dim, bool isDark) {
    final dimColor = _scoreColor(dim.score);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(
            _dimensionIcon(dim.emoji),
            size: 16,
            color:
                isDark ? AppTheme.textSecondary : AppTheme.textSecondaryLight,
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Text(
              dim.label,
              style: AppTypography.caption(
                color: isDark
                    ? AppTheme.textSecondary
                    : AppTheme.textSecondaryLight,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: dim.score / 100),
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) {
                  return LinearProgressIndicator(
                    value: value,
                    minHeight: 5,
                    backgroundColor: isDark
                        ? Colors.white.withAlpha(8)
                        : Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation(dimColor),
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 28,
            child: Text(
              '${dim.score}',
              textAlign: TextAlign.right,
              style: AppTypography.caption(color: dimColor),
            ),
          ),
        ],
      ),
    );
  }

  static Color _scoreColor(int score) => ColorTokens.score(score);

  /// The service tags each dimension with an emoji; show a matching icon.
  static IconData _dimensionIcon(String emoji) => switch (emoji) {
        '\u{1F3AF}' => Icons.track_changes_rounded,
        '\u{1F3E6}' => Icons.savings_outlined,
        '\u{1F4CA}' => Icons.insights_rounded,
        '\u{1F9D8}' => Icons.self_improvement_rounded,
        _ => Icons.circle_outlined,
      };
}
