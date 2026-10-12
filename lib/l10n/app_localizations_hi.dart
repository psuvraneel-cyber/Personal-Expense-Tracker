// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hindi (`hi`).
class AppLocalizationsHi extends AppLocalizations {
  AppLocalizationsHi([String locale = 'hi']) : super(locale);

  @override
  String get cancel => 'रद्द करें';

  @override
  String get back => 'वापस';

  @override
  String get close => 'बंद करें';

  @override
  String get notNow => 'अभी नहीं';

  @override
  String get maybeLater => 'बाद में';

  @override
  String get openSettings => 'सेटिंग्स खोलें';

  @override
  String get readPrivacyPolicy => 'प्राइवेसी पॉलिसी पढ़ें';

  @override
  String get navHome => 'होम';

  @override
  String get navHistory => 'इतिहास';

  @override
  String get navBudget => 'बजट';

  @override
  String get navSettings => 'सेटिंग्स';

  @override
  String navTabSemantics(String tab) {
    return '$tab टैब पर जाएँ';
  }

  @override
  String get addTransactionShort => 'जोड़ें';

  @override
  String get addTransactionSemantics => 'नया लेन-देन जोड़ें';

  @override
  String get onboardingSkip => 'छोड़ें';

  @override
  String get onboardingContinue => 'आगे बढ़ें';

  @override
  String get onboardingGetStarted => 'शुरू करें';

  @override
  String get onboardingAutoTitle => 'लेन-देन अपने-आप पहचानें';

  @override
  String get onboardingAutoBody =>
      'P.E.T आपके बैंक SMS पढ़कर आपका खर्च अपने-आप ट्रैक करता है। मैसेज का टेक्स्ट कभी आपके फ़ोन से बाहर नहीं जाता।';

  @override
  String get onboardingAutoBadge => 'आपके फ़ोन पर ही प्रोसेस';

  @override
  String get onboardingBudgetTitle => 'अपना मासिक बजट तय करें';

  @override
  String get onboardingBudgetBody =>
      'हर खर्च श्रेणी के लिए बजट बनाकर अपने पैसों पर नज़र रखें।';

  @override
  String get onboardingBudgetBadge => 'स्मार्ट अलर्ट';

  @override
  String get onboardingCategoriesTitle => 'अपनी श्रेणियाँ बनाएँ';

  @override
  String get onboardingCategoriesBody =>
      'अपनी ज़रूरत के हिसाब से श्रेणियाँ जोड़ें: खाना, यात्रा, सब्सक्रिप्शन, जो भी चाहिए।';

  @override
  String get onboardingCategoriesBadge => 'पूरी तरह आपके हिसाब से';

  @override
  String get onboardingOemTitle => 'बैकग्राउंड में चलने दें';

  @override
  String onboardingOemBody(String manufacturer) {
    return 'आपका डिवाइस ($manufacturer) बैकग्राउंड में चलने वाले ऐप्स को रोकता है। ताकि P.E.T कोई भी लेन-देन SMS न छोड़े, कृपया P.E.T के लिए बैटरी प्रतिबंध बंद करें।';
  }

  @override
  String get onboardingOemButton => 'बैटरी सेटिंग्स खोलें';

  @override
  String get smsScreenTitle => 'लेन-देन अपने-आप पहचानें';

  @override
  String get smsHeadline => 'UPI लेन-देन\nअपने-आप पहचानें';

  @override
  String get smsIntro =>
      'P.E.T आपको मिलने वाले SMS पढ़कर बैंक और UPI लेन-देन के अलर्ट ढूँढता है, ताकि आपको उन्हें खुद न लिखना पड़े।';

  @override
  String get smsOnDeviceTitle => 'आपके डिवाइस पर ही प्रोसेस';

  @override
  String get smsOnDeviceBody =>
      'मैसेज का टेक्स्ट इसी फ़ोन पर जाँचा जाता है और कभी अपलोड नहीं होता। सिर्फ़ निकाली गई राशि, व्यापारी, तारीख और श्रेणी सेव होती है, और Google से साइन इन करने पर आपके खाते में बैकअप होती है।';

  @override
  String get smsPersonalTitle => 'निजी मैसेज नज़रअंदाज़';

  @override
  String get smsPersonalBody =>
      'निजी फ़ोन नंबरों से आए मैसेज और बिना भुगतान राशि वाले मैसेज तुरंत हटा दिए जाते हैं। जो मैसेज लेन-देन नहीं हैं, वे कभी सेव नहीं होते।';

  @override
  String get smsRealtimeTitle => 'तुरंत ट्रैकिंग';

  @override
  String get smsRealtimeBody =>
      'बैंक SMS आते ही नए लेन-देन तुरंत दर्ज हो जाते हैं, ऐप बंद होने पर भी।';

  @override
  String get smsMaskedTitle => 'नंबर छिपे, टेक्स्ट अपने-आप हटे';

  @override
  String get smsMaskedBody =>
      'खाता, कार्ड और फ़ोन नंबर छिपा दिए जाते हैं। सेव किया गया मैसेज टेक्स्ट 90 दिन बाद हटा दिया जाता है। इसे कभी भी सेटिंग्स में बंद करें।';

  @override
  String get smsPermissionsRequired => 'ज़रूरी अनुमतियाँ';

  @override
  String get smsReadSmsDescription =>
      'पिछले लेन-देन ढूँढने के लिए मिले हुए मैसेज (पिछले 90 दिन) पढ़ना';

  @override
  String get smsReceiveSmsDescription => 'नए लेन-देन तुरंत पहचानना';

  @override
  String get smsGrant => 'SMS अनुमति दें';

  @override
  String get smsGranted => 'SMS अनुमति मिल गई! आपके मैसेज स्कैन हो रहे हैं…';

  @override
  String get smsDenied =>
      'SMS अनुमति नहीं मिली। आप इसे सेटिंग्स से चालू कर सकते हैं।';

  @override
  String get smsBlockedTitle => 'अनुमति ज़रूरी है';

  @override
  String get smsBlockedBody =>
      'P.E.T के लिए SMS अनुमति बंद है। अपने-आप पहचान के लिए इसे सिस्टम सेटिंग्स में चालू करें।';

  @override
  String get notifAccessTitle => 'क्या P.E.T को भुगतान नोटिफ़िकेशन पढ़ने दें?';

  @override
  String get notifAccessIntro =>
      'कुछ भुगतान सिर्फ़ ऐप नोटिफ़िकेशन में दिखते हैं, बैंक SMS में नहीं। आपकी अनुमति से P.E.T इन भुगतान और बैंकिंग ऐप्स के नोटिफ़िकेशन पढ़कर लेन-देन अपने-आप दर्ज करता है:';

  @override
  String get notifAccessBankApps =>
      'और प्रमुख बैंक ऐप्स (SBI, HDFC, ICICI, Axis, Kotak आदि)';

  @override
  String get notifAccessOthersIgnored =>
      'बाकी सभी ऐप्स (चैट और सोशल ऐप्स सहित) के नोटिफ़िकेशन नज़रअंदाज़ किए जाते हैं और कभी सेव नहीं होते।';

  @override
  String get notifAccessOnDevice =>
      'नोटिफ़िकेशन का टेक्स्ट इसी डिवाइस पर प्रोसेस होता है। सिर्फ़ निकाली गई राशि, व्यापारी, तारीख और श्रेणी सेव होती है, और साइन इन होने पर आपके खाते में सिंक होती है।';

  @override
  String get notifAccessTurnOff =>
      'आप इसे कभी भी Android सेटिंग्स → नोटिफ़िकेशन एक्सेस में बंद कर सकते हैं।';

  @override
  String get notifAccessAgree => 'सहमत हूँ, आगे बढ़ें';

  @override
  String get consentTitle => 'P.E.T को बेहतर बनाने में मदद करें?';

  @override
  String get consentIntro =>
      'आप चाहें तो गुमनाम उपयोग डेटा साझा कर सकते हैं, ताकि हम देख सकें कि कौन-सी सुविधाएँ काम आती हैं और ऐप में कहाँ दिक्कत आती है।';

  @override
  String get consentShared =>
      'क्या साझा होता है: ऐप इवेंट जैसे \"Premium स्क्रीन खोली\" या \"पहला अपने-आप इम्पोर्ट\", साथ ही डिवाइस मॉडल, ऐप वर्ज़न और अनुमानित क्षेत्र।';

  @override
  String get consentNeverShared =>
      'कभी साझा नहीं होता: राशियाँ, व्यापारी, मैसेज, श्रेणियाँ या आपका लिखा कुछ भी। कोई विज्ञापन ID नहीं।';

  @override
  String get consentChangeLater =>
      'आप कभी भी सेटिंग्स → प्राइवेसी में अपनी पसंद बदल सकते हैं।';

  @override
  String get consentDecline => 'नहीं, धन्यवाद';

  @override
  String get consentAccept => 'उपयोग डेटा साझा करें';

  @override
  String get paywallHeadline => 'P.E.T Premium अनलॉक करें';

  @override
  String get paywallSubtitle =>
      'AI सलाह, टैक्स ट्रैकिंग, कैश-फ़्लो अनुमान और फ़ोकस मोड पाएँ।';

  @override
  String get paywallRestore => 'रीस्टोर करें';

  @override
  String get paywallChoosePlan => 'अपना प्लान चुनें';

  @override
  String get paywallNoPackages => 'अभी कोई प्लान उपलब्ध नहीं है।';

  @override
  String get paywallSubscribe => 'सब्सक्राइब करें';

  @override
  String get paywallFeatureAiTitle => 'AI फ़ाइनेंशियल कोपायलट';

  @override
  String get paywallFeatureAiBody =>
      'अपने खर्च के बारे में आसान भाषा में सवाल पूछें।';

  @override
  String get paywallFeatureTaxTitle => 'टैक्स बकेट';

  @override
  String get paywallFeatureTaxBody => '80C, 80D और HRA कटौतियाँ ट्रैक करें।';

  @override
  String get paywallFeatureCashflowTitle => 'कैश-फ़्लो अनुमान';

  @override
  String get paywallFeatureCashflowBody =>
      'पैसा कितने दिन चलेगा, कितना खर्च सुरक्षित है, और आगे का अनुमान।';

  @override
  String get paywallFeatureFocusTitle => 'खर्च फ़ोकस मोड';

  @override
  String get paywallFeatureFocusBody =>
      'जिन श्रेणियों से ब्रेक चाहिए उन्हें रोकें। उनमें कोई भुगतान दर्ज होने या आने पर आपको याद दिलाया जाएगा।';

  @override
  String get trustNoBankLogin => 'बैंक लॉगिन नहीं';

  @override
  String get trustEncrypted => 'आपके फ़ोन पर एन्क्रिप्टेड';

  @override
  String get trustNeverSell => 'हम आपका डेटा कभी नहीं बेचते';

  @override
  String get gateUnlock => 'Premium अनलॉक करें';

  @override
  String get settingsAppearance => 'दिखावट';

  @override
  String get settingsNotifications => 'नोटिफ़िकेशन';

  @override
  String get settingsPremium => 'प्रीमियम';

  @override
  String get settingsCurrency => 'मुद्रा';

  @override
  String get settingsDefaultPayment => 'डिफ़ॉल्ट भुगतान तरीका';

  @override
  String get settingsCategories => 'श्रेणियाँ';

  @override
  String get settingsAutoDetect => 'लेन-देन अपने-आप पहचानें';

  @override
  String get settingsExport => 'लेन-देन एक्सपोर्ट करें';

  @override
  String get settingsAccessibility => 'सुगम्यता';

  @override
  String get settingsPrivacy => 'प्राइवेसी';

  @override
  String get settingsSecurity => 'सुरक्षा';

  @override
  String get settingsDeveloper => 'डेवलपर विकल्प';

  @override
  String get settingsAbout => 'जानकारी';

  @override
  String get settingsLanguage => 'भाषा';

  @override
  String get settingsLanguageHint =>
      'हिन्दी बीटा में है: कुछ स्क्रीन अभी अंग्रेज़ी में हैं।';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageHindi => 'हिन्दी (Beta)';

  @override
  String get settingsWidgetTitle => 'होम-स्क्रीन विजेट';

  @override
  String get settingsWidgetSubtitle => 'आज का खर्च और बचा हुआ बजट एक नज़र में';

  @override
  String get settingsWidgetManual =>
      'होम स्क्रीन को देर तक दबाएँ, विजेट चुनें, फिर P.E.T चुनें।';

  @override
  String get settingsNotificationPrefs => 'नोटिफ़िकेशन पसंद';

  @override
  String get settingsNotificationPrefsSubtitle =>
      'बजट, असामान्य खर्च, बिल और रिपोर्ट नोटिफ़िकेशन';

  @override
  String get settingsBattery => 'बैटरी और ऑटोस्टार्ट सेटिंग्स';

  @override
  String get settingsPremiumHub => 'प्रीमियम हब';

  @override
  String get settingsPremiumActive => 'चालू';

  @override
  String get settingsPremiumPreview =>
      'अपने डेटा के साथ प्रीमियम सुविधाएँ देखें';

  @override
  String get settingsInvite => 'दोस्तों को बुलाएँ';

  @override
  String get settingsInviteSubtitle => 'आप दोनों को एक महीना प्रीमियम मुफ़्त';

  @override
  String get settingsHaptics => 'हैप्टिक फ़ीडबैक';

  @override
  String get settingsHapticsSubtitle => 'ज़रूरी कामों पर हल्का कंपन';

  @override
  String get settingsCrashReports => 'क्रैश रिपोर्ट भेजें';

  @override
  String get settingsCrashReportsSubtitle =>
      'गड़बड़ियाँ ठीक करने के लिए गुमनाम क्रैश जानकारी भेजें';

  @override
  String get settingsAnalytics => 'उपयोग की जानकारी साझा करें';

  @override
  String get settingsAnalyticsSubtitle =>
      'गुमनाम सुविधा उपयोग; कभी राशि, व्यापारी या मैसेज नहीं';

  @override
  String get settingsBiometric => 'बायोमेट्रिक लॉक';

  @override
  String get settingsPrivacyPolicy => 'प्राइवेसी पॉलिसी';

  @override
  String get settingsPrivacyPolicySubtitle =>
      'आपका डेटा कैसे प्रोसेस और सुरक्षित होता है';

  @override
  String get settingsTerms => 'सेवा की शर्तें';

  @override
  String get settingsTermsSubtitle =>
      'P.E.T और सब्सक्रिप्शन के इस्तेमाल के नियम';

  @override
  String get settingsSupport => 'सहायता से संपर्क करें';

  @override
  String get settingsManageSubscription => 'सब्सक्रिप्शन मैनेज करें';

  @override
  String get settingsManageSubscriptionSubtitle =>
      'Google Play पर अपना प्लान रद्द करें या बदलें';

  @override
  String get settingsHideAmounts => 'नोटिफ़िकेशन में राशि छिपाएँ';

  @override
  String get settingsHideAmountsSubtitle =>
      'राशि की जगह ₹••• दिखाएँ। बायोमेट्रिक लॉक चालू होने पर अपने-आप चालू।';
}
