import 'package:flutter/material.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:pet/core/widgets/notification_permission_banner.dart';
import 'package:pet/premium/models/notification_category.dart';
import 'package:pet/premium/services/notification_preferences_service.dart';

/// Screen allowing users to toggle individual notification category preferences on or off
/// and configure daily reminder execution hour.
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  final NotificationPreferencesService _prefsService =
      NotificationPreferencesService.instance;

  @override
  void initState() {
    super.initState();
    _prefsService.load();
  }

  String _formatHour(int hour) {
    if (hour == 0) return '12:00 AM (Midnight)';
    if (hour < 12) return '$hour:00 AM';
    if (hour == 12) return '12:00 PM (Noon)';
    final pm = hour - 12;
    return '$pm:00 PM${hour == 20 ? ' (Default)' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification Preferences'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListenableBuilder(
        listenable: _prefsService,
        builder: (context, child) {
          final dailyEnabled = _prefsService.isEnabled(
            NotificationCategory.dailySummary,
          );

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const NotificationPermissionBanner(
                forceShow: true,
                isDismissible: false,
              ),
              ...NotificationCategory.values.map((category) {
                final enabled = _prefsService.isEnabled(category);

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppTheme.cardDarkSurface
                          : AppTheme.cardLight,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withAlpha(15)
                            : Colors.black.withAlpha(10),
                      ),
                    ),
                    child: SwitchListTile(
                      title: Text(
                        category.label,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? AppTheme.textPrimary
                              : AppTheme.textPrimaryLight,
                        ),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          category.description,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? AppTheme.textSecondary
                                : AppTheme.textSecondaryLight,
                          ),
                        ),
                      ),
                      value: enabled,
                      activeThumbColor: AppTheme.accentPurple,
                      onChanged: (bool val) {
                        _prefsService.setCategoryEnabled(category, val);
                      },
                    ),
                  ),
                );
              }),
              if (dailyEnabled) ...[
                const SizedBox(height: 8),
                Text(
                  'Reminder Timing',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.accentPurple,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppTheme.cardDarkSurface
                        : AppTheme.cardLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withAlpha(15)
                          : Colors.black.withAlpha(10),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Daily Reminder Time',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? AppTheme.textPrimary
                                  : AppTheme.textPrimaryLight,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Check for unlogged expenses at this hour',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? AppTheme.textSecondary
                                  : AppTheme.textSecondaryLight,
                            ),
                          ),
                        ],
                      ),
                      DropdownButton<int>(
                        value: _prefsService.reminderHour,
                        dropdownColor: isDark
                            ? AppTheme.cardDarkSurface
                            : AppTheme.cardLight,
                        underline: const SizedBox(),
                        items: [18, 19, 20, 21, 22].map((hour) {
                          return DropdownMenuItem<int>(
                            value: hour,
                            child: Text(
                              _formatHour(hour),
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark
                                    ? AppTheme.textPrimary
                                    : AppTheme.textPrimaryLight,
                              ),
                            ),
                          );
                        }).toList(),
                        onChanged: (int? newHour) {
                          if (newHour != null) {
                            _prefsService.setReminderHour(newHour);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
