import 'package:flutter/material.dart';
import 'package:pet/core/theme/app_theme.dart';

/// A reusable empty-state widget with icon, title, subtitle, and optional CTA.
///
/// Use this for screens that have no data to display — provides visual
/// feedback instead of a blank white/black area.
///
/// ```dart
/// EmptyState(
///   icon: Icons.receipt_long_outlined,
///   title: 'No Transactions Yet',
///   subtitle: 'Add your first transaction to get started.',
///   actionLabel: 'Add Transaction',
///   onAction: () => Navigator.push(...),
/// )
/// ```
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon with subtle gradient background
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppTheme.accentPurple.withAlpha(isDark ? 30 : 20),
                    AppTheme.accentPurple.withAlpha(isDark ? 15 : 8),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                icon,
                size: 36,
                color: isDark
                    ? AppTheme.textTertiary
                    : AppTheme.textSecondaryLight,
              ),
            ),
            const SizedBox(height: 20),

            // Title
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color:
                    isDark ? AppTheme.textPrimary : AppTheme.textPrimaryLight,
                letterSpacing: -0.3,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),

            // Subtitle
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 14,
                color: isDark
                    ? AppTheme.textSecondary
                    : AppTheme.textSecondaryLight,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),

            // Optional CTA button
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: onAction,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  actionLabel!,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
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
