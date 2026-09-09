import 'package:flutter/material.dart';
import 'package:pet/core/theme/app_theme.dart';

/// A reusable illustrated empty-state widget.
///
/// Shows a large icon, title, subtitle, and an optional CTA button.
/// Used across Transactions, Budget, Goals, and SMS screens to
/// replace plain "No data" text and reduce onboarding drop-off.
class EmptyStateWidget extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String subtitle;
  final String? ctaLabel;
  final VoidCallback? onCtaTap;

  const EmptyStateWidget({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.iconColor,
    this.ctaLabel,
    this.onCtaTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Animated icon container
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (iconColor ?? AppTheme.accentPurple).withAlpha(
                  isDark ? 30 : 20,
                ),
              ),
              child: Icon(
                icon,
                size: 48,
                color: iconColor ?? AppTheme.accentPurple,
              ),
            ),
            const SizedBox(height: 24),

            // Title
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
            ),
            const SizedBox(height: 8),

            // Subtitle
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: isDark
                        ? AppTheme.textSecondary
                        : AppTheme.textSecondaryLight,
                    height: 1.4,
                  ),
            ),

            // Optional CTA
            if (ctaLabel != null && onCtaTap != null) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onCtaTap,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(ctaLabel!),
                style: FilledButton.styleFrom(
                  backgroundColor: iconColor ?? AppTheme.accentPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
