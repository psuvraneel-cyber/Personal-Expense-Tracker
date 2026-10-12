import 'package:flutter/material.dart';
import 'package:pet/core/theme/app_theme.dart';

/// Label/value row used in the detected-transaction and review detail sheets.
class SmsDetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isDark;

  const SmsDetailRow({
    super.key,
    required this.label,
    required this.value,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isDark
                    ? AppTheme.textTertiary
                    : AppTheme.textSecondaryLight,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color:
                    isDark ? AppTheme.textPrimary : AppTheme.textPrimaryLight,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Original SMS" heading and the message text (account and phone numbers
/// are already redacted before storage).
class OriginalSmsBox extends StatelessWidget {
  final String body;
  final bool isDark;

  const OriginalSmsBox({super.key, required this.body, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Original SMS',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color:
                isDark ? AppTheme.textSecondary : AppTheme.textSecondaryLight,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color:
                isDark ? Colors.white.withAlpha(6) : Colors.black.withAlpha(6),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark
                  ? Colors.white.withAlpha(8)
                  : Colors.black.withAlpha(8),
            ),
          ),
          child: SelectableText(
            body.isEmpty ? 'Message text is no longer stored.' : body,
            style: TextStyle(
              fontSize: 12,
              color:
                  isDark ? AppTheme.textSecondary : AppTheme.textSecondaryLight,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}
