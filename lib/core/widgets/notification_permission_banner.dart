import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:pet/premium/services/notification_preferences_service.dart';
import 'package:pet/premium/services/notification_service.dart';

/// An educational, action-oriented banner displayed when notification permission
/// is not granted or permanently blocked.
///
/// Provides context on why notifications matter (budget alerts, bill reminders, anomaly warnings)
/// and directs the user to the in-app system prompt ("Enable") or OS app settings ("Settings").
class NotificationPermissionBanner extends StatefulWidget {
  /// If true, the banner ignores previous user dismissals (useful for settings screens).
  final bool forceShow;

  /// Whether to show the close/dismiss button.
  final bool isDismissible;

  const NotificationPermissionBanner({
    super.key,
    this.forceShow = false,
    this.isDismissible = true,
  });

  @override
  State<NotificationPermissionBanner> createState() =>
      _NotificationPermissionBannerState();
}

class _NotificationPermissionBannerState
    extends State<NotificationPermissionBanner> {
  bool _isLocallyDismissed = false;
  PermissionStatus? _lastStatus;

  @override
  void initState() {
    super.initState();
    // Re-verify current permission status on mount
    NotificationService.permissionStatus();
  }

  Future<void> _handleAction(bool isPermanentlyDenied) async {
    if (isPermanentlyDenied) {
      await openAppSettings();
    } else {
      final status = await NotificationService.requestPermission();
      if (status.isPermanentlyDenied) {
        // Automatically re-rendered by ValueListenableBuilder with "Settings" CTA
      }
    }
  }

  Future<void> _handleDismiss() async {
    setState(() {
      _isLocallyDismissed = true;
    });
    await NotificationPreferencesService.instance.setBannerDismissed(true);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListenableBuilder(
      listenable: NotificationPreferencesService.instance,
      builder: (context, _) {
        final isPermanentlyDismissed =
            NotificationPreferencesService.instance.isBannerDismissed;

        return ValueListenableBuilder<PermissionStatus>(
          valueListenable: NotificationService.permissionNotifier,
          builder: (context, status, child) {
            if (_lastStatus != status) {
              _lastStatus = status;
              _isLocallyDismissed = false;
            }

            // Hide banner if notifications are allowed, or if dismissed (unless forceShow is true)
            if (status.isGranted ||
                status.isLimited ||
                (!widget.forceShow &&
                    (_isLocallyDismissed || isPermanentlyDismissed))) {
              return const SizedBox.shrink();
            }

            final isPermanentlyDenied =
                status.isPermanentlyDenied || status.isRestricted;

            final bannerColor = isPermanentlyDenied
                ? (isDark
                    ? AppTheme.accentPurple.withAlpha(25)
                    : const Color(0xFFF3E8FF))
                : (isDark
                    ? AppTheme.warningYellow.withAlpha(25)
                    : const Color(0xFFFFFBEB));

            final borderColor = isPermanentlyDenied
                ? AppTheme.accentPurple.withAlpha(isDark ? 100 : 70)
                : AppTheme.warningYellow.withAlpha(isDark ? 100 : 70);

            final iconColor = isPermanentlyDenied
                ? (isDark ? AppTheme.accentPurple : const Color(0xFF7E22CE))
                : (isDark ? AppTheme.warningYellow : const Color(0xFFD97706));

            final buttonBgColor = isPermanentlyDenied
                ? (isDark
                    ? AppTheme.accentPurple.withAlpha(45)
                    : const Color(0xFFE9D5FF))
                : (isDark
                    ? AppTheme.warningYellow.withAlpha(45)
                    : const Color(0xFFFDE68A));

            final buttonTextColor = isPermanentlyDenied
                ? (isDark ? AppTheme.accentPurple : const Color(0xFF581C87))
                : (isDark ? AppTheme.warningYellow : const Color(0xFF78350F));

            final title = isPermanentlyDenied
                ? 'Notifications Blocked'
                : 'Stay Ahead of Overspending';

            final message = isPermanentlyDenied
                ? 'Notifications are turned off in device settings. Open settings to allow budget overspend alerts and bill reminders.'
                : 'Enable notifications for real-time budget overspend alerts, bill reminders, and spending anomaly warnings.';

            final ctaLabel = isPermanentlyDenied ? 'Settings' : 'Enable';

            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: bannerColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    isPermanentlyDenied
                        ? Icons.notifications_off_outlined
                        : Icons.notifications_active_outlined,
                    color: iconColor,
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? AppTheme.textPrimary
                                : (isPermanentlyDenied
                                    ? const Color(0xFF581C87)
                                    : const Color(0xFF92400E)),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          message,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            height: 1.3,
                            color: isDark
                                ? AppTheme.textSecondary
                                : (isPermanentlyDenied
                                    ? const Color(0xFF6B21A8)
                                    : const Color(0xFFB45309)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      backgroundColor: buttonBgColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () => _handleAction(isPermanentlyDenied),
                    child: Text(
                      ctaLabel,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: buttonTextColor,
                      ),
                    ),
                  ),
                  if (widget.isDismissible) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      color: isDark
                          ? AppTheme.textSecondary
                          : (isPermanentlyDenied
                              ? const Color(0xFF7E22CE)
                              : const Color(0xFF92400E)),
                      onPressed: _handleDismiss,
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}
