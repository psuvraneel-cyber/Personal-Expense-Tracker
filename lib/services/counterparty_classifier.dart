import 'package:pet/premium/services/merchant_normalizer.dart';

/// Who was on the other side of a payment.
enum CounterpartyType {
  /// A brand or registered business (Swiggy, Apollo, "XYZ Pvt Ltd").
  company,

  /// A local business: kirana, chai stall, pharmacy counter, QR merchant.
  shop,

  /// A friend, relative or any other individual.
  person,

  /// Not enough to tell.
  unknown,
}

/// Classifies the counterparty of a parsed payment from the evidence in the
/// message, strongest first:
///
/// 1. Known brand (from [MerchantNormalizer]'s brand list) → company
/// 2. Legal-entity words ("Pvt Ltd", "LLP", "Technologies") → company
/// 3. Trade words in the name ("Stores", "Kirana", "Medicals") → shop
/// 4. Merchant-style UPI ID (QR codes, business handles) → shop
/// 5. Card / POS payment → shop
/// 6. Phone-number UPI ID → person
/// 7. A name that looks like a person's ("SUNITA DEVI") → person
///
/// Person vs small shop is the hard case: many kirana owners take payments
/// on their personal UPI ID. The user's correction for a payee (a learned
/// rule) always overrides this.
class CounterpartyClassifier {
  CounterpartyClassifier._();

  static final RegExp _legalEntity = RegExp(
    r'\b(?:pvt|private|ltd|limited|llp|inc|corp|corporation|company|co\b|'
    r'technolog(?:y|ies)|solutions|industries|enterprises|insurance|'
    r'finance|financial|securities|capital|infotech|ventures|holdings|'
    r'bank|payments|mutual\s*fund|broking|exchange)\b',
    caseSensitive: false,
  );

  static final RegExp _tradeWords = RegExp(
    r'\b(?:store|stores|kirana|mart|supermarket|general|provisions?|'
    r'traders?|trading|agency|agencies|medical|medicals|medicos|pharmacy|'
    r'chemists?|bakery|bakers|sweets?|dairy|fruits?|vegetables?|tea|chai|'
    r'cafe|canteen|hotel|restaurant|dhaba|bhojnalaya|tiffin|juice|paan|pan\s*shop|'
    r'stationery|xerox|electricals?|electronics|hardware|garments|textiles?|'
    r'salon|saloon|parlou?r|tailors?|motors|automobiles?|petrol|fuels?|'
    r'filling|shop|bazaa?r|emporium|collections?|cent(?:er|re)|clinic|'
    r'hospital|diagnostics?|labs?|opticals?|jewell?ers?|footwear|mobiles?)\b',
    caseSensitive: false,
  );

  /// UPI IDs issued to merchants: QR codes and business handles.
  static final RegExp _merchantVpaLocal = RegExp(
    r'^(?:paytmqr|paytm\.s|bharatpe|q\d{6,}|mab\.|gpay-\d|'
    r'.*merchant|.*\.rzp$|rzp|razorpay|pinelabs|mswipe|ezetap|yespay|'
    r'phonepemerchant|.*\.qr$|qr\.)',
    caseSensitive: false,
  );
  static const Set<String> _merchantVpaHandles = {
    'okbizaxis',
    'okbizicici',
    'okbizhdfc',
    'okbizsbi',
    'fbpe', // BharatPe
    'paytmqr',
  };

  static final RegExp _phoneVpaLocal = RegExp(r'^(?:\+?91)?[6-9]\d{9}(?:-\d)?$');

  /// Words that are never part of a person's name in these messages.
  static const Set<String> _notNameWords = {
    'upi', 'imps', 'neft', 'rtgs', 'payment', 'payments', 'transfer', 'bank',
    'credit', 'debit', 'card', 'account', 'wallet', 'unknown', 'refund',
    'cashback', 'salary', 'interest', 'charges', 'charge', 'fee', 'atm',
    'cash', 'online', 'india', 'the', 'and', 'for', 'via', 'ref', 'txn',
  };

  static final RegExp _honorific =
      RegExp(r'^(?:mr|mrs|ms|miss|shri|sri|smt|dr|kumari)\.?\s+',
          caseSensitive: false);

  /// Classifies the other party of a payment.
  ///
  /// [payeeName] is the raw name from the message (before normalisation,
  /// which strips words like "Store" and "Ltd"). [channel] is the parser's
  /// payment channel (e.g. `UPI`, `CARD`, `POS`, `NEFT`). [text] is the
  /// message, used for salary/card cues.
  static CounterpartyType classify({
    required String payeeName,
    String? upiId,
    String channel = '',
    String text = '',
  }) {
    final name = payeeName.trim();
    final lowerText = text.toLowerCase();

    if (name.isNotEmpty && name.toLowerCase() != 'unknown') {
      if (MerchantNormalizer.isKnownBrand(name)) return CounterpartyType.company;
      if (_legalEntity.hasMatch(name)) return CounterpartyType.company;
      if (_tradeWords.hasMatch(name)) return CounterpartyType.shop;
    }
    if (upiId != null && upiId.contains('@')) {
      final parts = upiId.toLowerCase().split('@');
      final local = parts.first;
      final handle = parts.last;
      // QR / business IDs first: "paytmqr…@paytm" is a shop's Paytm QR,
      // not Paytm the company.
      if (_merchantVpaHandles.contains(handle) ||
          _merchantVpaLocal.hasMatch(local)) {
        return CounterpartyType.shop;
      }
      if (MerchantNormalizer.isKnownBrand(local)) {
        return CounterpartyType.company;
      }
    }
    if (lowerText.contains('salary')) return CounterpartyType.company;
    final ch = channel.toLowerCase();
    if (ch.contains('card') || ch.contains('pos') ||
        RegExp(r'\b(?:pos|card\s+(?:xx|ending))').hasMatch(lowerText)) {
      return CounterpartyType.shop;
    }
    if (upiId != null && upiId.contains('@')) {
      final local = upiId.split('@').first;
      if (_phoneVpaLocal.hasMatch(local)) return CounterpartyType.person;
    }
    if (looksLikePersonName(name)) return CounterpartyType.person;
    return CounterpartyType.unknown;
  }

  /// "SUNITA DEVI", "Rahul K", "Mr R Sharma": 1–4 alphabetic words, no
  /// business or payment words, no digits.
  static bool looksLikePersonName(String raw) {
    var name = raw.trim();
    if (name.isEmpty || RegExp(r'\d|@').hasMatch(name)) return false;
    name = name.replaceFirst(_honorific, '');
    final words = name
        .split(RegExp(r'[\s.]+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty || words.length > 4) return false;
    if (!words.every((w) => RegExp(r"^[A-Za-z']{1,15}$").hasMatch(w))) {
      return false;
    }
    // A single word ("SWEETHOME") is too ambiguous to call a person; initials
    // are fine ("PRIYA S", "R Sharma") as long as one word is a real name.
    if (words.length < 2 || !words.any((w) => w.length >= 3)) return false;
    return !words.any((w) => _notNameWords.contains(w.toLowerCase())) &&
        !_legalEntity.hasMatch(name) &&
        !_tradeWords.hasMatch(name) &&
        !MerchantNormalizer.isKnownBrand(name);
  }
}
