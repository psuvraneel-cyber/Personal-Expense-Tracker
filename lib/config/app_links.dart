import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Public URLs for legal pages and support.
///
/// The HTML pages live in `docs/` and are served by Firebase Hosting
/// (`firebase deploy --only hosting`). Keep these in sync with the URLs
/// entered in Play Console.
class AppLinks {
  AppLinks._();

  static const String _hostingBase =
      'https://personal-expense-tracker-6891b.web.app';

  static const String privacyPolicy = '$_hostingBase/privacy-policy.html';
  static const String terms = '$_hostingBase/terms.html';
  static const String accountDeletion = '$_hostingBase/account-deletion.html';
  static const String supportEmail = 'psuvraneel@gmail.com';

  static const String packageName = 'com.pet.tracker.pet';

  /// Google Play subscription management for this app.
  static const String manageSubscriptions =
      'https://play.google.com/store/account/subscriptions?package=$packageName';

  /// Opens [url] in the external browser; shows a snackbar if it can't.
  static Future<void> open(BuildContext context, String url) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    ).catchError((_) => false);
    if (!ok) {
      messenger?.showSnackBar(
        SnackBar(content: Text('Could not open $url')),
      );
    }
  }

  /// Opens the user's mail app addressed to support.
  static Future<void> emailSupport(BuildContext context) =>
      open(context, 'mailto:$supportEmail?subject=P.E.T%20support');
}
