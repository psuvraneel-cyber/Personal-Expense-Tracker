import 'package:flutter/material.dart';
import 'package:pet/l10n/app_localizations.dart';

/// Shows a home tab (Budget, History) as its own page, for when it's opened
/// from a notification or another screen rather than from the nav bar.
/// The tabs have no Scaffold of their own because the home shell gives them
/// one.
class StandaloneTab extends StatelessWidget {
  const StandaloneTab({super.key, required this.title, required this.child});

  /// Picks the page title from the current translations.
  final String Function(AppLocalizations l10n) title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title(AppLocalizations.of(context)))),
      body: child,
    );
  }
}
