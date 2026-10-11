import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_hi.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('hi')
  ];

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @notNow.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get notNow;

  /// No description provided for @maybeLater.
  ///
  /// In en, this message translates to:
  /// **'Maybe Later'**
  String get maybeLater;

  /// No description provided for @openSettings.
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get openSettings;

  /// No description provided for @readPrivacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Read the Privacy Policy'**
  String get readPrivacyPolicy;

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get navHistory;

  /// No description provided for @navBudget.
  ///
  /// In en, this message translates to:
  /// **'Budget'**
  String get navBudget;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @navTabSemantics.
  ///
  /// In en, this message translates to:
  /// **'Navigate to {tab} tab'**
  String navTabSemantics(String tab);

  /// No description provided for @addTransactionShort.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get addTransactionShort;

  /// No description provided for @addTransactionSemantics.
  ///
  /// In en, this message translates to:
  /// **'Add new transaction'**
  String get addTransactionSemantics;

  /// No description provided for @onboardingSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get onboardingSkip;

  /// No description provided for @onboardingContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get onboardingContinue;

  /// No description provided for @onboardingGetStarted.
  ///
  /// In en, this message translates to:
  /// **'Get Started'**
  String get onboardingGetStarted;

  /// No description provided for @onboardingAutoTitle.
  ///
  /// In en, this message translates to:
  /// **'Auto-Detect Transactions'**
  String get onboardingAutoTitle;

  /// No description provided for @onboardingAutoBody.
  ///
  /// In en, this message translates to:
  /// **'P.E.T reads your bank SMS to track your spending automatically. Message text never leaves your phone.'**
  String get onboardingAutoBody;

  /// No description provided for @onboardingAutoBadge.
  ///
  /// In en, this message translates to:
  /// **'Processed on your phone'**
  String get onboardingAutoBadge;

  /// No description provided for @onboardingBudgetTitle.
  ///
  /// In en, this message translates to:
  /// **'Set Your Monthly Budget'**
  String get onboardingBudgetTitle;

  /// No description provided for @onboardingBudgetBody.
  ///
  /// In en, this message translates to:
  /// **'Stay on top of your money with a budget for each spending category.'**
  String get onboardingBudgetBody;

  /// No description provided for @onboardingBudgetBadge.
  ///
  /// In en, this message translates to:
  /// **'Smart Alerts'**
  String get onboardingBudgetBadge;

  /// No description provided for @onboardingCategoriesTitle.
  ///
  /// In en, this message translates to:
  /// **'Personalise Your Categories'**
  String get onboardingCategoriesTitle;

  /// No description provided for @onboardingCategoriesBody.
  ///
  /// In en, this message translates to:
  /// **'Add categories that match your life: Food, Travel, Subscriptions, whatever you need.'**
  String get onboardingCategoriesBody;

  /// No description provided for @onboardingCategoriesBadge.
  ///
  /// In en, this message translates to:
  /// **'Fully Customisable'**
  String get onboardingCategoriesBadge;

  /// No description provided for @onboardingOemTitle.
  ///
  /// In en, this message translates to:
  /// **'Allow Background Running'**
  String get onboardingOemTitle;

  /// No description provided for @onboardingOemBody.
  ///
  /// In en, this message translates to:
  /// **'Your device ({manufacturer}) restricts apps running in the background. So P.E.T doesn\'t miss any transaction SMS, please turn off battery restrictions for P.E.T.'**
  String onboardingOemBody(String manufacturer);

  /// No description provided for @onboardingOemButton.
  ///
  /// In en, this message translates to:
  /// **'Open Battery Settings'**
  String get onboardingOemButton;

  /// No description provided for @smsScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'Auto-Detect Transactions'**
  String get smsScreenTitle;

  /// No description provided for @smsHeadline.
  ///
  /// In en, this message translates to:
  /// **'Auto-Detect UPI\nTransactions'**
  String get smsHeadline;

  /// No description provided for @smsIntro.
  ///
  /// In en, this message translates to:
  /// **'P.E.T reads the SMS messages you receive to find bank and UPI transaction alerts, so you don\'t have to type them in.'**
  String get smsIntro;

  /// No description provided for @smsOnDeviceTitle.
  ///
  /// In en, this message translates to:
  /// **'Processed on your device'**
  String get smsOnDeviceTitle;

  /// No description provided for @smsOnDeviceBody.
  ///
  /// In en, this message translates to:
  /// **'Message text is analysed on this phone and never uploaded. Only the extracted amount, merchant, date and category are saved, and backed up to your account if you sign in with Google.'**
  String get smsOnDeviceBody;

  /// No description provided for @smsPersonalTitle.
  ///
  /// In en, this message translates to:
  /// **'Personal messages ignored'**
  String get smsPersonalTitle;

  /// No description provided for @smsPersonalBody.
  ///
  /// In en, this message translates to:
  /// **'Messages from personal phone numbers and messages without a payment amount are discarded immediately. Non-transaction messages are never stored.'**
  String get smsPersonalBody;

  /// No description provided for @smsRealtimeTitle.
  ///
  /// In en, this message translates to:
  /// **'Real-Time Tracking'**
  String get smsRealtimeTitle;

  /// No description provided for @smsRealtimeBody.
  ///
  /// In en, this message translates to:
  /// **'New transactions are captured instantly when you receive a bank SMS, even in the background.'**
  String get smsRealtimeBody;

  /// No description provided for @smsMaskedTitle.
  ///
  /// In en, this message translates to:
  /// **'Masked & auto-deleted'**
  String get smsMaskedTitle;

  /// No description provided for @smsMaskedBody.
  ///
  /// In en, this message translates to:
  /// **'Account, card and phone numbers are masked. Stored message text is deleted after 90 days. Turn this off any time in Settings.'**
  String get smsMaskedBody;

  /// No description provided for @smsPermissionsRequired.
  ///
  /// In en, this message translates to:
  /// **'Permissions Required'**
  String get smsPermissionsRequired;

  /// No description provided for @smsReadSmsDescription.
  ///
  /// In en, this message translates to:
  /// **'Read received messages (last 90 days) to find past transactions'**
  String get smsReadSmsDescription;

  /// No description provided for @smsReceiveSmsDescription.
  ///
  /// In en, this message translates to:
  /// **'Detect new transactions in real time'**
  String get smsReceiveSmsDescription;

  /// No description provided for @smsGrant.
  ///
  /// In en, this message translates to:
  /// **'Grant SMS Access'**
  String get smsGrant;

  /// No description provided for @smsGranted.
  ///
  /// In en, this message translates to:
  /// **'SMS access granted! Scanning your messages…'**
  String get smsGranted;

  /// No description provided for @smsDenied.
  ///
  /// In en, this message translates to:
  /// **'SMS permission denied. You can enable it from Settings.'**
  String get smsDenied;

  /// No description provided for @smsBlockedTitle.
  ///
  /// In en, this message translates to:
  /// **'Permission Required'**
  String get smsBlockedTitle;

  /// No description provided for @smsBlockedBody.
  ///
  /// In en, this message translates to:
  /// **'SMS permission is turned off for P.E.T. Turn it on in system settings to use automatic detection.'**
  String get smsBlockedBody;

  /// No description provided for @notifAccessTitle.
  ///
  /// In en, this message translates to:
  /// **'Allow P.E.T to read payment notifications?'**
  String get notifAccessTitle;

  /// No description provided for @notifAccessIntro.
  ///
  /// In en, this message translates to:
  /// **'Some payments only show up as app notifications, not bank SMS. With your permission, P.E.T reads notifications from these payment and banking apps to record transactions automatically:'**
  String get notifAccessIntro;

  /// No description provided for @notifAccessBankApps.
  ///
  /// In en, this message translates to:
  /// **'and major bank apps (SBI, HDFC, ICICI, Axis, Kotak and others)'**
  String get notifAccessBankApps;

  /// No description provided for @notifAccessOthersIgnored.
  ///
  /// In en, this message translates to:
  /// **'Notifications from all other apps (including chat and social apps) are ignored and never stored.'**
  String get notifAccessOthersIgnored;

  /// No description provided for @notifAccessOnDevice.
  ///
  /// In en, this message translates to:
  /// **'The notification text is processed on this device. Only the extracted amount, merchant, date and category are saved, and synced to your account if you are signed in.'**
  String get notifAccessOnDevice;

  /// No description provided for @notifAccessTurnOff.
  ///
  /// In en, this message translates to:
  /// **'You can turn this off any time in Android Settings → Notification access.'**
  String get notifAccessTurnOff;

  /// No description provided for @notifAccessAgree.
  ///
  /// In en, this message translates to:
  /// **'Agree & continue'**
  String get notifAccessAgree;

  /// No description provided for @consentTitle.
  ///
  /// In en, this message translates to:
  /// **'Help improve P.E.T?'**
  String get consentTitle;

  /// No description provided for @consentIntro.
  ///
  /// In en, this message translates to:
  /// **'You can choose to share anonymous usage data so we can see which features help people and where the app gets in the way.'**
  String get consentIntro;

  /// No description provided for @consentShared.
  ///
  /// In en, this message translates to:
  /// **'What\'s shared: app events like \"opened the Premium screen\" or \"first automatic import\", plus device model, app version and approximate region.'**
  String get consentShared;

  /// No description provided for @consentNeverShared.
  ///
  /// In en, this message translates to:
  /// **'Never shared: amounts, merchants, messages, categories or anything you type. No advertising ID.'**
  String get consentNeverShared;

  /// No description provided for @consentChangeLater.
  ///
  /// In en, this message translates to:
  /// **'Change your mind anytime in Settings → Privacy.'**
  String get consentChangeLater;

  /// No description provided for @consentDecline.
  ///
  /// In en, this message translates to:
  /// **'No thanks'**
  String get consentDecline;

  /// No description provided for @consentAccept.
  ///
  /// In en, this message translates to:
  /// **'Share usage data'**
  String get consentAccept;

  /// No description provided for @paywallHeadline.
  ///
  /// In en, this message translates to:
  /// **'Unlock P.E.T Premium'**
  String get paywallHeadline;

  /// No description provided for @paywallSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Unlock AI insights, tax tracking, cash-flow forecasts and Focus Mode.'**
  String get paywallSubtitle;

  /// No description provided for @paywallRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get paywallRestore;

  /// No description provided for @paywallChoosePlan.
  ///
  /// In en, this message translates to:
  /// **'Choose Your Subscription Plan'**
  String get paywallChoosePlan;

  /// No description provided for @paywallNoPackages.
  ///
  /// In en, this message translates to:
  /// **'No subscription packages available at this time.'**
  String get paywallNoPackages;

  /// No description provided for @paywallSubscribe.
  ///
  /// In en, this message translates to:
  /// **'Subscribe & Continue'**
  String get paywallSubscribe;

  /// No description provided for @paywallFeatureAiTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Financial Copilot'**
  String get paywallFeatureAiTitle;

  /// No description provided for @paywallFeatureAiBody.
  ///
  /// In en, this message translates to:
  /// **'Ask questions about your spending in plain language.'**
  String get paywallFeatureAiBody;

  /// No description provided for @paywallFeatureTaxTitle.
  ///
  /// In en, this message translates to:
  /// **'Advanced Tax Buckets'**
  String get paywallFeatureTaxTitle;

  /// No description provided for @paywallFeatureTaxBody.
  ///
  /// In en, this message translates to:
  /// **'Track 80C, 80D and HRA deductions.'**
  String get paywallFeatureTaxBody;

  /// No description provided for @paywallFeatureCashflowTitle.
  ///
  /// In en, this message translates to:
  /// **'Cash-Flow Forecasting'**
  String get paywallFeatureCashflowTitle;

  /// No description provided for @paywallFeatureCashflowBody.
  ///
  /// In en, this message translates to:
  /// **'Runway, safe-to-spend targets and projections.'**
  String get paywallFeatureCashflowBody;

  /// No description provided for @paywallFeatureFocusTitle.
  ///
  /// In en, this message translates to:
  /// **'Spending Focus Mode'**
  String get paywallFeatureFocusTitle;

  /// No description provided for @paywallFeatureFocusBody.
  ///
  /// In en, this message translates to:
  /// **'Get warned before spending in paused categories.'**
  String get paywallFeatureFocusBody;

  /// No description provided for @trustNoBankLogin.
  ///
  /// In en, this message translates to:
  /// **'No bank login'**
  String get trustNoBankLogin;

  /// No description provided for @trustEncrypted.
  ///
  /// In en, this message translates to:
  /// **'Encrypted on your phone'**
  String get trustEncrypted;

  /// No description provided for @trustNeverSell.
  ///
  /// In en, this message translates to:
  /// **'We never sell your data'**
  String get trustNeverSell;

  /// No description provided for @gateUnlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock Premium'**
  String get gateUnlock;

  /// No description provided for @settingsAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearance;

  /// No description provided for @settingsNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get settingsNotifications;

  /// No description provided for @settingsPremium.
  ///
  /// In en, this message translates to:
  /// **'Premium'**
  String get settingsPremium;

  /// No description provided for @settingsCurrency.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get settingsCurrency;

  /// No description provided for @settingsDefaultPayment.
  ///
  /// In en, this message translates to:
  /// **'Default Payment Method'**
  String get settingsDefaultPayment;

  /// No description provided for @settingsCategories.
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get settingsCategories;

  /// No description provided for @settingsAutoDetect.
  ///
  /// In en, this message translates to:
  /// **'Auto-Detect Transactions'**
  String get settingsAutoDetect;

  /// No description provided for @settingsExport.
  ///
  /// In en, this message translates to:
  /// **'Export Transactions'**
  String get settingsExport;

  /// No description provided for @settingsAccessibility.
  ///
  /// In en, this message translates to:
  /// **'Accessibility'**
  String get settingsAccessibility;

  /// No description provided for @settingsPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get settingsPrivacy;

  /// No description provided for @settingsSecurity.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get settingsSecurity;

  /// No description provided for @settingsDeveloper.
  ///
  /// In en, this message translates to:
  /// **'Developer Options'**
  String get settingsDeveloper;

  /// No description provided for @settingsAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsAbout;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @settingsLanguageHint.
  ///
  /// In en, this message translates to:
  /// **'Hindi is in beta: some screens are still in English.'**
  String get settingsLanguageHint;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageHindi.
  ///
  /// In en, this message translates to:
  /// **'हिन्दी (Beta)'**
  String get languageHindi;

  /// No description provided for @settingsWidgetTitle.
  ///
  /// In en, this message translates to:
  /// **'Home-screen widget'**
  String get settingsWidgetTitle;

  /// No description provided for @settingsWidgetSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Today\'s spending and budget left at a glance'**
  String get settingsWidgetSubtitle;

  /// No description provided for @settingsWidgetManual.
  ///
  /// In en, this message translates to:
  /// **'Long-press your home screen, tap Widgets, then choose P.E.T.'**
  String get settingsWidgetManual;

  /// No description provided for @settingsNotificationPrefs.
  ///
  /// In en, this message translates to:
  /// **'Notification Preferences'**
  String get settingsNotificationPrefs;

  /// No description provided for @settingsNotificationPrefsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage budget, anomaly, bill and report notifications'**
  String get settingsNotificationPrefsSubtitle;

  /// No description provided for @settingsBattery.
  ///
  /// In en, this message translates to:
  /// **'Battery & Autostart Settings'**
  String get settingsBattery;

  /// No description provided for @settingsPremiumHub.
  ///
  /// In en, this message translates to:
  /// **'Premium Hub'**
  String get settingsPremiumHub;

  /// No description provided for @settingsPremiumActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get settingsPremiumActive;

  /// No description provided for @settingsPremiumPreview.
  ///
  /// In en, this message translates to:
  /// **'Preview premium features with your data'**
  String get settingsPremiumPreview;

  /// No description provided for @settingsInvite.
  ///
  /// In en, this message translates to:
  /// **'Invite friends'**
  String get settingsInvite;

  /// No description provided for @settingsInviteSubtitle.
  ///
  /// In en, this message translates to:
  /// **'You both get a month of Premium free'**
  String get settingsInviteSubtitle;

  /// No description provided for @settingsHaptics.
  ///
  /// In en, this message translates to:
  /// **'Haptic Feedback'**
  String get settingsHaptics;

  /// No description provided for @settingsHapticsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Vibration on key actions'**
  String get settingsHapticsSubtitle;

  /// No description provided for @settingsCrashReports.
  ///
  /// In en, this message translates to:
  /// **'Share crash reports'**
  String get settingsCrashReports;

  /// No description provided for @settingsCrashReportsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Send anonymous crash details to help fix bugs'**
  String get settingsCrashReportsSubtitle;

  /// No description provided for @settingsAnalytics.
  ///
  /// In en, this message translates to:
  /// **'Share usage analytics'**
  String get settingsAnalytics;

  /// No description provided for @settingsAnalyticsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Anonymous feature usage, never amounts, merchants or messages'**
  String get settingsAnalyticsSubtitle;

  /// No description provided for @settingsBiometric.
  ///
  /// In en, this message translates to:
  /// **'Biometric Lock'**
  String get settingsBiometric;

  /// No description provided for @settingsPrivacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get settingsPrivacyPolicy;

  /// No description provided for @settingsPrivacyPolicySubtitle.
  ///
  /// In en, this message translates to:
  /// **'How your data is processed and protected'**
  String get settingsPrivacyPolicySubtitle;

  /// No description provided for @settingsTerms.
  ///
  /// In en, this message translates to:
  /// **'Terms of Service'**
  String get settingsTerms;

  /// No description provided for @settingsTermsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Rules for using P.E.T and subscriptions'**
  String get settingsTermsSubtitle;

  /// No description provided for @settingsSupport.
  ///
  /// In en, this message translates to:
  /// **'Contact Support'**
  String get settingsSupport;

  /// No description provided for @settingsManageSubscription.
  ///
  /// In en, this message translates to:
  /// **'Manage Subscription'**
  String get settingsManageSubscription;

  /// No description provided for @settingsManageSubscriptionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Cancel or change your plan on Google Play'**
  String get settingsManageSubscriptionSubtitle;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'hi'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'hi':
      return AppLocalizationsHi();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
