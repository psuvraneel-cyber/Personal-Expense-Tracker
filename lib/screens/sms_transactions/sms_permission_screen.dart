import 'package:flutter/material.dart';
import 'package:pet/l10n/app_localizations.dart';
import 'package:pet/config/app_links.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:pet/providers/sms_transaction_provider.dart';
import 'package:pet/screens/sms_transactions/sms_transactions_screen.dart';

/// A clean UI flow for requesting SMS permissions.
///
/// Shows the user why SMS access is needed and what data is read.
/// Emphasizes the on-device, privacy-first approach.
class SmsPermissionScreen extends StatefulWidget {
  const SmsPermissionScreen({super.key});

  @override
  State<SmsPermissionScreen> createState() => _SmsPermissionScreenState();
}

class _SmsPermissionScreenState extends State<SmsPermissionScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  bool _isRequesting = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _handleGrantPermission() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _isRequesting = true);

    final provider = Provider.of<SmsTransactionProvider>(
      context,
      listen: false,
    );
    final granted = await provider.requestAndEnablePermissions();

    if (!mounted) return;

    if (granted) {
      // Start scanning and navigate to transactions screen
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.smsGranted),
          backgroundColor: AppTheme.incomeGreen,
        ),
      );

      // Perform initial scan
      await provider.scanInbox(lookbackDays: 90);

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const SmsTransactionsScreen()),
      );
    } else {
      final isPermanentlyDenied = await Permission.sms.isPermanentlyDenied;
      if (isPermanentlyDenied && mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l10n.smsBlockedTitle),
            content: Text(l10n.smsBlockedBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.cancel),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  openAppSettings();
                },
                child: Text(l10n.openSettings),
              ),
            ],
          ),
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.smsDenied),
              backgroundColor: AppTheme.expenseRed,
            ),
          );
        }
      }
    }

    setState(() => _isRequesting = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.smsScreenTitle),
        leading: IconButton(
          tooltip: l10n.back,
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 20),

              // Hero icon
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  gradient: AppTheme.heroGradient,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.accentPurple.withAlpha(60),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.sms_rounded,
                  size: 48,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 32),

              Text(
                l10n.smsHeadline,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color:
                      isDark ? AppTheme.textPrimary : AppTheme.textPrimaryLight,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 12),

              Text(
                l10n.smsIntro,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark
                      ? AppTheme.textSecondary
                      : AppTheme.textSecondaryLight,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 36),

              // Feature cards
              _FeatureCard(
                icon: Icons.security_rounded,
                title: l10n.smsOnDeviceTitle,
                description: l10n.smsOnDeviceBody,
                isDark: isDark,
              ),
              const SizedBox(height: 12),
              _FeatureCard(
                icon: Icons.auto_awesome_rounded,
                title: l10n.smsPersonalTitle,
                description: l10n.smsPersonalBody,
                isDark: isDark,
              ),
              const SizedBox(height: 12),
              _FeatureCard(
                icon: Icons.notifications_active_rounded,
                title: l10n.smsRealtimeTitle,
                description: l10n.smsRealtimeBody,
                isDark: isDark,
              ),
              const SizedBox(height: 12),
              _FeatureCard(
                icon: Icons.filter_alt_rounded,
                title: l10n.smsMaskedTitle,
                description: l10n.smsMaskedBody,
                isDark: isDark,
              ),

              const SizedBox(height: 36),

              // What we need section
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withAlpha(6)
                      : Colors.black.withAlpha(6),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withAlpha(10)
                        : Colors.black.withAlpha(10),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.smsPermissionsRequired,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? AppTheme.textPrimary
                            : AppTheme.textPrimaryLight,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _PermissionRow(
                      icon: Icons.mark_email_read_rounded,
                      label: 'READ_SMS',
                      description: l10n.smsReadSmsDescription,
                      isDark: isDark,
                    ),
                    const SizedBox(height: 8),
                    _PermissionRow(
                      icon: Icons.mark_email_unread_rounded,
                      label: 'RECEIVE_SMS',
                      description: l10n.smsReceiveSmsDescription,
                      isDark: isDark,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),
              TextButton(
                onPressed: () => AppLinks.open(context, AppLinks.privacyPolicy),
                child: Text(l10n.readPrivacyPolicy),
              ),
              const SizedBox(height: 16),

              // Grant permission button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isRequesting ? null : _handleGrantPermission,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentPurple,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: _isRequesting
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.check_circle_outline_rounded,
                                size: 20),
                            const SizedBox(width: 8),
                            Text(
                              l10n.smsGrant,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                ),
              ),

              const SizedBox(height: 16),

              // Skip button
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  l10n.maybeLater,
                  style: TextStyle(
                    color: isDark
                        ? AppTheme.textTertiary
                        : AppTheme.textSecondaryLight,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final bool isDark;

  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.cardDark : AppTheme.cardLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withAlpha(6) : Colors.black.withAlpha(6),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.accentPurple.withAlpha(isDark ? 30 : 20),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 22, color: AppTheme.accentPurple),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? AppTheme.textPrimary
                        : AppTheme.textPrimaryLight,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? AppTheme.textSecondary
                        : AppTheme.textSecondaryLight,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final bool isDark;

  const _PermissionRow({
    required this.icon,
    required this.label,
    required this.description,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.accentPurple),
        const SizedBox(width: 10),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: TextStyle(
                fontSize: 13,
                color: isDark
                    ? AppTheme.textSecondary
                    : AppTheme.textSecondaryLight,
              ),
              children: [
                TextSpan(
                  text: '$label — ',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(text: description),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
