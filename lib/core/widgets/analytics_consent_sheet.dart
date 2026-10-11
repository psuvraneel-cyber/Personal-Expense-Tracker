import 'package:flutter/material.dart';
import 'package:pet/l10n/app_localizations.dart';
import 'package:pet/config/app_links.dart';
import 'package:pet/core/theme/app_theme.dart';
import 'package:pet/services/analytics_service.dart';

/// One-time request to share usage analytics. Declining is as easy as
/// accepting, nothing is pre-selected, and the choice can be changed in
/// Settings → Privacy.
Future<void> showAnalyticsConsentSheet(BuildContext context) async {
  final allowed = await showModalBottomSheet<bool>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) => const _AnalyticsConsentSheet(),
  );
  // Dismissing without choosing counts as "no" and isn't asked again.
  await AnalyticsService.instance.setEnabled(allowed ?? false);
}

class _AnalyticsConsentSheet extends StatelessWidget {
  const _AnalyticsConsentSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final l10n = AppLocalizations.of(context);

    Widget point(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: AppTheme.accentTeal),
              const SizedBox(width: 12),
              Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
            ],
          ),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.consentTitle,
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.consentIntro,
            style: theme.textTheme.bodyMedium?.copyWith(color: muted),
          ),
          const SizedBox(height: 16),
          point(Icons.insights_rounded, l10n.consentShared),
          point(Icons.lock_outline_rounded, l10n.consentNeverShared),
          point(Icons.tune_rounded, l10n.consentChangeLater),
          TextButton(
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            onPressed: () => AppLinks.open(context, AppLinks.privacyPolicy),
            child: Text(l10n.readPrivacyPolicy),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(l10n.consentDecline),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(l10n.consentAccept),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
