// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get cancel => 'Cancel';

  @override
  String get back => 'Back';

  @override
  String get close => 'Close';

  @override
  String get notNow => 'Not now';

  @override
  String get maybeLater => 'Maybe Later';

  @override
  String get openSettings => 'Open Settings';

  @override
  String get readPrivacyPolicy => 'Read the Privacy Policy';

  @override
  String get navHome => 'Home';

  @override
  String get navHistory => 'History';

  @override
  String get navBudget => 'Budget';

  @override
  String get navSettings => 'Settings';

  @override
  String navTabSemantics(String tab) {
    return 'Navigate to $tab tab';
  }

  @override
  String get addTransactionShort => 'Add';

  @override
  String get addTransactionSemantics => 'Add new transaction';

  @override
  String get onboardingSkip => 'Skip';

  @override
  String get onboardingContinue => 'Continue';

  @override
  String get onboardingGetStarted => 'Get Started';

  @override
  String get onboardingAutoTitle => 'Auto-Detect Transactions';

  @override
  String get onboardingAutoBody =>
      'P.E.T reads your bank SMS to track your spending automatically. Message text never leaves your phone.';

  @override
  String get onboardingAutoBadge => 'Processed on your phone';

  @override
  String get onboardingBudgetTitle => 'Set Your Monthly Budget';

  @override
  String get onboardingBudgetBody =>
      'Stay on top of your money with a budget for each spending category.';

  @override
  String get onboardingBudgetBadge => 'Smart Alerts';

  @override
  String get onboardingCategoriesTitle => 'Personalise Your Categories';

  @override
  String get onboardingCategoriesBody =>
      'Add categories that match your life: Food, Travel, Subscriptions, whatever you need.';

  @override
  String get onboardingCategoriesBadge => 'Fully Customisable';

  @override
  String get onboardingOemTitle => 'Allow Background Running';

  @override
  String onboardingOemBody(String manufacturer) {
    return 'Your device ($manufacturer) restricts apps running in the background. So P.E.T doesn\'t miss any transaction SMS, please turn off battery restrictions for P.E.T.';
  }

  @override
  String get onboardingOemButton => 'Open Battery Settings';

  @override
  String get smsScreenTitle => 'Auto-Detect Transactions';

  @override
  String get smsHeadline => 'Auto-Detect UPI\nTransactions';

  @override
  String get smsIntro =>
      'P.E.T reads the SMS messages you receive to find bank and UPI transaction alerts, so you don\'t have to type them in.';

  @override
  String get smsOnDeviceTitle => 'Processed on your device';

  @override
  String get smsOnDeviceBody =>
      'Message text is analysed on this phone and never uploaded. Only the extracted amount, merchant, date and category are saved, and backed up to your account if you sign in with Google.';

  @override
  String get smsPersonalTitle => 'Personal messages ignored';

  @override
  String get smsPersonalBody =>
      'Messages from personal phone numbers and messages without a payment amount are discarded immediately. Non-transaction messages are never stored.';

  @override
  String get smsRealtimeTitle => 'Real-Time Tracking';

  @override
  String get smsRealtimeBody =>
      'New transactions are captured instantly when you receive a bank SMS, even in the background.';

  @override
  String get smsMaskedTitle => 'Masked & auto-deleted';

  @override
  String get smsMaskedBody =>
      'Account, card and phone numbers are masked. Stored message text is deleted after 90 days. Turn this off any time in Settings.';

  @override
  String get smsPermissionsRequired => 'Permissions Required';

  @override
  String get smsReadSmsDescription =>
      'Read received messages (last 90 days) to find past transactions';

  @override
  String get smsReceiveSmsDescription => 'Detect new transactions in real time';

  @override
  String get smsGrant => 'Grant SMS Access';

  @override
  String get smsGranted => 'SMS access granted! Scanning your messages…';

  @override
  String get smsDenied =>
      'SMS permission denied. You can enable it from Settings.';

  @override
  String get smsBlockedTitle => 'Permission Required';

  @override
  String get smsBlockedBody =>
      'SMS permission is turned off for P.E.T. Turn it on in system settings to use automatic detection.';

  @override
  String get notifAccessTitle => 'Allow P.E.T to read payment notifications?';

  @override
  String get notifAccessIntro =>
      'Some payments only show up as app notifications, not bank SMS. With your permission, P.E.T reads notifications from these payment and banking apps to record transactions automatically:';

  @override
  String get notifAccessBankApps =>
      'and major bank apps (SBI, HDFC, ICICI, Axis, Kotak and others)';

  @override
  String get notifAccessOthersIgnored =>
      'Notifications from all other apps (including chat and social apps) are ignored and never stored.';

  @override
  String get notifAccessOnDevice =>
      'The notification text is processed on this device. Only the extracted amount, merchant, date and category are saved, and synced to your account if you are signed in.';

  @override
  String get notifAccessTurnOff =>
      'You can turn this off any time in Android Settings → Notification access.';

  @override
  String get notifAccessAgree => 'Agree & continue';

  @override
  String get consentTitle => 'Help improve P.E.T?';

  @override
  String get consentIntro =>
      'You can choose to share anonymous usage data so we can see which features help people and where the app gets in the way.';

  @override
  String get consentShared =>
      'What\'s shared: app events like \"opened the Premium screen\" or \"first automatic import\", plus device model, app version and approximate region.';

  @override
  String get consentNeverShared =>
      'Never shared: amounts, merchants, messages, categories or anything you type. No advertising ID.';

  @override
  String get consentChangeLater =>
      'Change your mind anytime in Settings → Privacy.';

  @override
  String get consentDecline => 'No thanks';

  @override
  String get consentAccept => 'Share usage data';

  @override
  String get paywallHeadline => 'Unlock P.E.T Premium';

  @override
  String get paywallSubtitle =>
      'Unlock AI insights, tax tracking, cash-flow forecasts and Focus Mode.';

  @override
  String get paywallRestore => 'Restore';

  @override
  String get paywallChoosePlan => 'Choose Your Subscription Plan';

  @override
  String get paywallNoPackages =>
      'No subscription packages available at this time.';

  @override
  String get paywallSubscribe => 'Subscribe & Continue';

  @override
  String get paywallFeatureAiTitle => 'AI Financial Copilot';

  @override
  String get paywallFeatureAiBody =>
      'Ask questions about your spending in plain language.';

  @override
  String get paywallFeatureTaxTitle => 'Advanced Tax Buckets';

  @override
  String get paywallFeatureTaxBody => 'Track 80C, 80D and HRA deductions.';

  @override
  String get paywallFeatureCashflowTitle => 'Cash-Flow Forecasting';

  @override
  String get paywallFeatureCashflowBody =>
      'Runway, safe-to-spend targets and projections.';

  @override
  String get paywallFeatureFocusTitle => 'Spending Focus Mode';

  @override
  String get paywallFeatureFocusBody =>
      'Pause categories you want a break from. Get a nudge when you log or receive a payment in one.';

  @override
  String get trustNoBankLogin => 'No bank login';

  @override
  String get trustEncrypted => 'Encrypted on your phone';

  @override
  String get trustNeverSell => 'We never sell your data';

  @override
  String get gateUnlock => 'Unlock Premium';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsNotifications => 'Notifications';

  @override
  String get settingsPremium => 'Premium';

  @override
  String get settingsCurrency => 'Currency';

  @override
  String get settingsDefaultPayment => 'Default Payment Method';

  @override
  String get settingsCategories => 'Categories';

  @override
  String get settingsAutoDetect => 'Auto-Detect Transactions';

  @override
  String get settingsExport => 'Export Transactions';

  @override
  String get settingsAccessibility => 'Accessibility';

  @override
  String get settingsPrivacy => 'Privacy';

  @override
  String get settingsSecurity => 'Security';

  @override
  String get settingsDeveloper => 'Developer Options';

  @override
  String get settingsAbout => 'About';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguageHint =>
      'Hindi is in beta: some screens are still in English.';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageHindi => 'हिन्दी (Beta)';

  @override
  String get settingsWidgetTitle => 'Home-screen widget';

  @override
  String get settingsWidgetSubtitle =>
      'Today\'s spending and budget left at a glance';

  @override
  String get settingsWidgetManual =>
      'Long-press your home screen, tap Widgets, then choose P.E.T.';

  @override
  String get settingsNotificationPrefs => 'Notification Preferences';

  @override
  String get settingsNotificationPrefsSubtitle =>
      'Manage budget, anomaly, bill and report notifications';

  @override
  String get settingsBattery => 'Battery & Autostart Settings';

  @override
  String get settingsPremiumHub => 'Premium Hub';

  @override
  String get settingsPremiumActive => 'Active';

  @override
  String get settingsPremiumPreview =>
      'Preview premium features with your data';

  @override
  String get settingsInvite => 'Invite friends';

  @override
  String get settingsInviteSubtitle => 'You both get a month of Premium free';

  @override
  String get settingsHaptics => 'Haptic Feedback';

  @override
  String get settingsHapticsSubtitle => 'Vibration on key actions';

  @override
  String get settingsCrashReports => 'Share crash reports';

  @override
  String get settingsCrashReportsSubtitle =>
      'Send anonymous crash details to help fix bugs';

  @override
  String get settingsAnalytics => 'Share usage analytics';

  @override
  String get settingsAnalyticsSubtitle =>
      'Anonymous feature usage, never amounts, merchants or messages';

  @override
  String get settingsBiometric => 'Biometric Lock';

  @override
  String get settingsPrivacyPolicy => 'Privacy Policy';

  @override
  String get settingsPrivacyPolicySubtitle =>
      'How your data is processed and protected';

  @override
  String get settingsTerms => 'Terms of Service';

  @override
  String get settingsTermsSubtitle => 'Rules for using P.E.T and subscriptions';

  @override
  String get settingsSupport => 'Contact Support';

  @override
  String get settingsManageSubscription => 'Manage Subscription';

  @override
  String get settingsManageSubscriptionSubtitle =>
      'Cancel or change your plan on Google Play';

  @override
  String get settingsHideAmounts => 'Hide amounts in notifications';

  @override
  String get settingsHideAmountsSubtitle =>
      'Show ₹••• instead of the amount. On by default when biometric lock is on.';
}
