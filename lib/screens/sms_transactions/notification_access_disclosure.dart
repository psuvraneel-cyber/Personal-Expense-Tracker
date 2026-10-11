import 'package:flutter/material.dart';
import 'package:pet/l10n/app_localizations.dart';
import 'package:pet/config/app_links.dart';
import 'package:pet/core/theme/app_theme.dart';

/// Payment / banking apps whose notifications P.E.T reads. Must match
/// `TransactionNotificationListener.FINANCIAL_PACKAGES` on the native side.
const List<String> kNotificationSourceApps = [
  'Google Pay',
  'PhonePe',
  'Paytm',
  'BHIM',
  'Amazon Pay',
  'CRED',
  'Navi',
  'PayZapp',
  'MobiKwik',
  'Freecharge',
  'and major bank apps (SBI, HDFC, ICICI, Axis, Kotak and others)',
];

/// Prominent disclosure shown **before** sending the user to the system
/// Notification Access setting (Google Play User Data policy).
///
/// Returns `true` only if the user explicitly agrees.
Future<bool> showNotificationAccessDisclosure(BuildContext context) async {
  final agreed = await showModalBottomSheet<bool>(
    useSafeArea: true,
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => const _NotificationAccessDisclosureSheet(),
  );
  return agreed == true;
}

class _NotificationAccessDisclosureSheet extends StatelessWidget {
  const _NotificationAccessDisclosureSheet();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context);
    final apps = [
      ...kNotificationSourceApps.take(kNotificationSourceApps.length - 1),
      l10n.notifAccessBankApps,
    ];
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.notifAccessTitle, style: textTheme.titleLarge),
            const SizedBox(height: 12),
            Text(
              l10n.notifAccessIntro,
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(apps.join(', '), style: textTheme.bodySmall),
            const SizedBox(height: 16),
            _Point(
              icon: Icons.filter_alt_rounded,
              text: l10n.notifAccessOthersIgnored,
            ),
            _Point(
              icon: Icons.phone_android_rounded,
              text: l10n.notifAccessOnDevice,
            ),
            _Point(
              icon: Icons.toggle_off_rounded,
              text: l10n.notifAccessTurnOff,
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => AppLinks.open(context, AppLinks.privacyPolicy),
              child: Text(l10n.readPrivacyPolicy),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(l10n.notNow),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.accentPurple,
                    ),
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(l10n.notifAccessAgree),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Point({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppTheme.accentPurple),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
