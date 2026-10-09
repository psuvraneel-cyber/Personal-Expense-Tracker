import 'package:flutter/material.dart';
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
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Allow P.E.T to read payment notifications?',
                style: textTheme.titleLarge),
            const SizedBox(height: 12),
            Text(
              'Some payments only show up as app notifications, not bank SMS. '
              'With your permission, P.E.T reads notifications from these '
              'payment and banking apps to record transactions automatically:',
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(kNotificationSourceApps.join(', '),
                style: textTheme.bodySmall),
            const SizedBox(height: 16),
            const _Point(
              icon: Icons.filter_alt_rounded,
              text: 'Notifications from all other apps (including chat and '
                  'social apps) are ignored and never stored.',
            ),
            const _Point(
              icon: Icons.phone_android_rounded,
              text: 'The notification text is processed on this device. Only '
                  'the extracted amount, merchant, date and category are '
                  'saved — and synced to your account if you are signed in.',
            ),
            const _Point(
              icon: Icons.toggle_off_rounded,
              text: 'You can turn this off any time in Android Settings → '
                  'Notification access.',
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => AppLinks.open(context, AppLinks.privacyPolicy),
              child: const Text('Read the Privacy Policy'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Not now'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.accentPurple,
                    ),
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Agree & continue'),
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
