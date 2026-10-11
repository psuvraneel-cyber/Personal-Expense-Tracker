import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:pet/premium/providers/recurring_provider.dart';
import 'package:pet/premium/screens/recurring_bills_screen.dart';
import 'package:pet/premium/services/premium_teasers.dart';

/// Dashboard insight: "We found 7 recurring payments costing ₹2,340 a
/// month". A moment of value — free users who tap it see the preview and
/// the upgrade offer right after learning something useful.
class SubscriptionsFoundCard extends StatelessWidget {
  const SubscriptionsFoundCard({super.key});

  @override
  Widget build(BuildContext context) {
    final message = PremiumTeasers.recurring(
      context.watch<RecurringProvider>().recurring,
    );
    if (message == null) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Material(
        color: AppTheme.accentTeal.withAlpha(isDark ? 40 : 26),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const RecurringBillsScreen()),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.repeat_rounded, color: AppTheme.accentTeal),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    message,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
