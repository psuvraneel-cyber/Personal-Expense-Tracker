import 'package:flutter/material.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:pet/core/theme/typography.dart';
import 'package:pet/premium/screens/premium_hub_screen.dart';

/// A soft "insight of the day" card that replaces the old premium CTA banner.
///
/// Instead of showing a paywall, it demonstrates the AI Copilot feature
/// by surfacing one contextual insight for free. Tapping it opens the
/// Copilot screen in the Premium Hub.
class AiCopilotTeaserCard extends StatelessWidget {
  /// The insight message to display. If null, a default is shown.
  final String? insight;

  const AiCopilotTeaserCard({super.key, this.insight});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final message = insight ??
        'Track more transactions to unlock personalised spending insights from your AI Copilot.';

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PremiumHubScreen()),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppTheme.accentPurple.withAlpha(isDark ? 30 : 18),
              AppTheme.accentTeal.withAlpha(isDark ? 20 : 12),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color:
                isDark ? Colors.white.withAlpha(10) : Colors.black.withAlpha(6),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.accentPurple.withAlpha(isDark ? 35 : 22),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text('🤖', style: TextStyle(fontSize: 18)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AI Insight',
                    style: AppTypography.labelMedium(
                      color: AppTheme.accentPurple,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: AppTypography.bodySmall(
                      color: isDark
                          ? AppTheme.textSecondary
                          : AppTheme.textSecondaryLight,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Ask Copilot →',
                    style: AppTypography.labelMedium(
                      color: AppTheme.accentPurple,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
