import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:pet/screens/reports/money_wrap_screen.dart';

/// Dashboard entry to last month's Money Wrap, shown in the first week of
/// each month.
class MoneyWrapEntryCard extends StatelessWidget {
  const MoneyWrapEntryCard({super.key, this.now});

  /// Overridable for tests.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final today = now ?? DateTime.now();
    if (today.day > 7) return const SizedBox.shrink();
    final month = DateTime(today.year, today.month - 1);

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Material(
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: const BoxDecoration(gradient: AppTheme.heroGradient),
          child: InkWell(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => MoneyWrapScreen(month: month)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.card_giftcard_rounded, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Your ${DateFormat('MMMM').format(month)} Money Wrap '
                      'is ready',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: Colors.white),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
