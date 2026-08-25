import 'package:flutter/material.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:pet/premium/services/oem_optimization_service.dart';

/// Guided dialog explaining why aggressive Android OEMs (Xiaomi, Oppo, Vivo, Samsung, etc.)
/// require autostart / battery saver whitelisting for background SMS scanning and bill reminders.
class OemBatteryDialog extends StatelessWidget {
  const OemBatteryDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      backgroundColor:
          isDark ? AppTheme.cardDarkSurface : AppTheme.cardLight,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.accentPurple.withAlpha(isDark ? 40 : 25),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.battery_saver_rounded,
              color: AppTheme.accentPurple,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Background Reliability',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your device manufacturer restricts background tasks by default. To ensure budget alerts and automated SMS transaction detection arrive reliably, please whitelist P.E.T:',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: isDark
                    ? AppTheme.textSecondary
                    : AppTheme.textSecondaryLight,
              ),
            ),
            const SizedBox(height: 12),
            _buildCheckItem(
              context,
              isDark: isDark,
              icon: Icons.flash_on_rounded,
              text: 'Enable Autostart for P.E.T',
            ),
            const SizedBox(height: 6),
            _buildCheckItem(
              context,
              isDark: isDark,
              icon: Icons.battery_charging_full_rounded,
              text: 'Set Battery Saver to "No Restrictions"',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await OemOptimizationService.instance.markPromptShown();
            if (context.mounted) {
              Navigator.of(context).pop();
            }
          },
          child: Text(
            'Later',
            style: TextStyle(
              color: isDark
                  ? AppTheme.textSecondary
                  : AppTheme.textSecondaryLight,
            ),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.accentPurple,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          onPressed: () async {
            await OemOptimizationService.instance.markPromptShown();
            if (context.mounted) {
              Navigator.of(context).pop();
            }
            await OemOptimizationService.instance.openOptimizationSettings();
          },
          child: const Text('Manage Settings'),
        ),
      ],
    );
  }

  Widget _buildCheckItem(
    BuildContext context, {
    required bool isDark,
    required IconData icon,
    required String text,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: AppTheme.incomeGreen,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? AppTheme.textPrimary : AppTheme.textPrimaryLight,
            ),
          ),
        ),
      ],
    );
  }
}
