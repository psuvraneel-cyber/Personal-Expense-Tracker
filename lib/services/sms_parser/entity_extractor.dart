library;

import 'package:pet/core/utils/app_logger.dart';

/// Entity extraction module — extracts merchant, bank, reference ID,
/// account tail, UPI ID, and date from SMS bodies.
///
/// Separated from the main parser for testability. Each extractor is
/// a static method that can be unit-tested independently.
///
/// ## Extraction Order (by reliability)
/// 1. Bank — sender ID map (most reliable) → body text map → "Unknown Bank"
/// 2. UPI ID — VPA pattern with known handle validation
/// 3. Reference ID — UPI Ref → Axis format → IMPS/NEFT Ref → generic Ref
/// 4. Merchant — cascading pattern priority (bank-specific → generic)
/// 5. Account tail — A/c XX1234 patterns
/// 6. Date — ISO → month name → dd/mm/yyyy

/// Extracted entity fields from an SMS.

class ExtractedEntities {
  final String bankName;
  final String merchantName;
  final String? upiId;
  final String? referenceId;
  final String? accountTail;
  final DateTime? date;
  final List<String> reasons;

  const ExtractedEntities({
    required this.bankName,
    required this.merchantName,
    this.upiId,
    this.referenceId,
    this.accountTail,
    this.date,
    required this.reasons,
  });
}

class EntityExtractor {
  EntityExtractor._();

  // ═══════════════════════════════════════════════════════════════════
  //  BANK DETECTION
  // ═══════════════════════════════════════════════════════════════════

  /// Sender ID → bank name map. Priority 1 (most reliable).
  ///
  /// Sender IDs like "AD-HDFCBK" are assigned by TRAI and are
  /// authoritative identifiers. Each bank has 1-3 registered sender IDs.
  static final Map<RegExp, String> _senderBankMap = {
    RegExp(r'HDFC|HDFCBK', caseSensitive: false): 'HDFC Bank',
    RegExp(r'ICICI|ICICIB', caseSensitive: false): 'ICICI Bank',
    RegExp(r'AXIS|AXISBK', caseSensitive: false): 'Axis Bank',
    RegExp(r'KOTAK|KOTAKB', caseSensitive: false): 'Kotak Bank',
    RegExp(r'YESBNK|YESBK', caseSensitive: false): 'Yes Bank',
    RegExp(r'INDUS|INDUSB', caseSensitive: false): 'IndusInd Bank',
    RegExp(r'FEDER|FEDBNK', caseSensitive: false): 'Federal Bank',
    RegExp(r'IDFCFB|IDFCBK', caseSensitive: false): 'IDFC First Bank',
    RegExp(r'RBLBNK|RBLBK', caseSensitive: false): 'RBL Bank',
    RegExp(r'BANDHN|BANDHB', caseSensitive: false): 'Bandhan Bank',
    RegExp(r'DBSBNK|DBSBK', caseSensitive: false): 'DBS Bank',
    RegExp(r'\bSBI\b|SBIINB|SBIPSG|SBIBNK', caseSensitive: false): 'SBI',
    RegExp(r'PNB|PNBSMS', caseSensitive: false): 'PNB',
    RegExp(r'BOB|BARODA', caseSensitive: false): 'Bank of Baroda',
    RegExp(r'CANARA|CANBK', caseSensitive: false): 'Canara Bank',
    RegExp(r'UNION|UNIONB', caseSensitive: false): 'Union Bank',
    RegExp(r'IDBI|IDBIBK', caseSensitive: false): 'IDBI Bank',
    RegExp(r'INDIAN|INDBNK', caseSensitive: false): 'Indian Bank',
    RegExp(r'CENTRL|CNTBNK|CENTRALB', caseSensitive: false): 'Central Bank',
    RegExp(r'\bIOB\b|IOBBNK', caseSensitive: false): 'IOB',
    RegExp(r'\bUCO\b|UCOBNK', caseSensitive: false): 'UCO Bank',
    RegExp(r'\bBOI\b|BOIBNK', caseSensitive: false): 'Bank of India',
    RegExp(r'KARNAB|KRNTKB', caseSensitive: false): 'Karnataka Bank',
    RegExp(r'SOUTHI|SIBBNK', caseSensitive: false): 'South Indian Bank',
    RegExp(r'PAYTM', caseSensitive: false): 'Paytm Payments Bank',
    RegExp(r'AIRTEL', caseSensitive: false): 'Airtel Payments Bank',
    RegExp(r'JIOFI|JIOPA', caseSensitive: false): 'Jio Payments Bank',
    RegExp(r'GPAY|GOOGLE', caseSensitive: false): 'Google Pay',
    RegExp(r'PHONEPE|PHNEPE', caseSensitive: false): 'PhonePe',
    RegExp(r'BHIM', caseSensitive: false): 'BHIM',
    RegExp(r'AMAZONP|AMZNPAY', caseSensitive: false): 'Amazon Pay',
    RegExp(r'WHATSAP', caseSensitive: false): 'WhatsApp Pay',
    RegExp(r'STANCHART|SCBANK|SCBNK', caseSensitive: false):
        'Standard Chartered',
    RegExp(r'CITI|CITIBNK', caseSensitive: false): 'Citi Bank',
    RegExp(r'HSBC|HSBCBK', caseSensitive: false): 'HSBC',
    RegExp(r'AUBANK|AUSFB', caseSensitive: false): 'AU Small Finance Bank',
    RegExp(r'JUPITE', caseSensitive: false): 'Jupiter',
    RegExp(r'FIBANK|FIMON', caseSensitive: false): 'Fi Money',
    RegExp(r'SLICE', caseSensitive: false): 'Slice',
    RegExp(r'TRUCLR|TRUCAL|TRUECL|TRUECALLER', caseSensitive: false):
        'Truecaller',
  };

  /// Body text → bank name map. Priority 2.
  static final Map<RegExp, String> _bodyBankMap = {
    RegExp(r'HDFC\s*Bank', caseSensitive: false): 'HDFC Bank',
    RegExp(r'\bSBI\b', caseSensitive: false): 'SBI',
    RegExp(r'ICICI\s*Bank', caseSensitive: false): 'ICICI Bank',
    RegExp(r'Axis\s*Bank', caseSensitive: false): 'Axis Bank',
    RegExp(r'Kotak\s*(?:Mahindra\s*)?Bank', caseSensitive: false): 'Kotak Bank',
    RegExp(r'PNB|Punjab\s*National', caseSensitive: false): 'PNB',
    RegExp(r'Bank\s*of\s*Baroda', caseSensitive: false): 'Bank of Baroda',
    RegExp(r'Canara\s*Bank', caseSensitive: false): 'Canara Bank',
    RegExp(r'Union\s*Bank', caseSensitive: false): 'Union Bank',
    RegExp(r'IndusInd\s*Bank', caseSensitive: false): 'IndusInd Bank',
    RegExp(r'Yes\s*Bank', caseSensitive: false): 'Yes Bank',
    RegExp(r'IDBI\s*Bank', caseSensitive: false): 'IDBI Bank',
    RegExp(r'Federal\s*Bank', caseSensitive: false): 'Federal Bank',
    RegExp(r'IDFC\s*First', caseSensitive: false): 'IDFC First Bank',
    RegExp(r'RBL\s*Bank', caseSensitive: false): 'RBL Bank',
    RegExp(r'Indian\s*Bank', caseSensitive: false): 'Indian Bank',
    RegExp(r'Central\s*Bank', caseSensitive: false): 'Central Bank',
    RegExp(r'\bIOB\b|Indian\s*Overseas', caseSensitive: false): 'IOB',
    RegExp(r'UCO\s*Bank', caseSensitive: false): 'UCO Bank',
    RegExp(r'Bank\s*of\s*India\b', caseSensitive: false): 'Bank of India',
    RegExp(r'Bandhan\s*Bank', caseSensitive: false): 'Bandhan Bank',
    RegExp(r'DBS\s*Bank', caseSensitive: false): 'DBS Bank',
    RegExp(r'Standard\s*Chartered', caseSensitive: false): 'Standard Chartered',
    RegExp(r'Citi\s*Bank', caseSensitive: false): 'Citi Bank',
    RegExp(r'\bHSBC\b', caseSensitive: false): 'HSBC',
    RegExp(r'Karnataka\s*Bank', caseSensitive: false): 'Karnataka Bank',
    RegExp(r'South\s*Indian\s*Bank', caseSensitive: false): 'South Indian Bank',
    RegExp(r'Paytm\s*(?:Payments?\s*)?Bank', caseSensitive: false):
        'Paytm Payments Bank',
    RegExp(r'Google\s*Pay', caseSensitive: false): 'Google Pay',
    RegExp(r'PhonePe', caseSensitive: false): 'PhonePe',
    RegExp(r'\bBHIM\b', caseSensitive: false): 'BHIM',
    RegExp(r'Truecaller', caseSensitive: false): 'Truecaller',
  };

  /// Detect bank from sender ID and body text.
  static String detectBank(String body, String sender, List<String> reasons) {
    final upperSender = sender.toUpperCase();

    // Priority 1: Sender ID
    for (final entry in _senderBankMap.entries) {
      if (entry.key.hasMatch(upperSender)) {
        reasons.add('Bank detected from sender ID: ${entry.value}');
        return entry.value;
      }
    }

    // Priority 2: Body text
    for (final entry in _bodyBankMap.entries) {
      if (entry.key.hasMatch(body)) {
        reasons.add('Bank detected from body text: ${entry.value}');
        return entry.value;
      }
    }

    reasons.add('Bank: Unknown (no sender or body match)');
    return 'Unknown Bank';
  }

  // ═══════════════════════════════════════════════════════════════════
  //  UPI ID EXTRACTION
  // ═══════════════════════════════════════════════════════════════════

  /// UPI VPA pattern: localpart@handle
  /// Excludes email domains (.com, .in, .org, .net).
  static final RegExp _upiIdPattern = RegExp(
    r'\b([a-zA-Z0-9][a-zA-Z0-9._-]{0,49}@[a-zA-Z][a-zA-Z0-9]{1,20})\b',
  );

  /// Known UPI handle suffixes.
  static const Set<String> _upiHandles = {
    'upi',
    'ybl',
    'okhdfcbank',
    'okaxis',
    'oksbi',
    'okicici',
    'paytm',
    'apl',
    'axl',
    'ibl',
    'sbi',
    'pnb',
    'boi',
    'cnrb',
    'ikwik',
    'freecharge',
    'axisbank',
    'hdfcbank',
    'icici',
    'kotak',
    'indus',
    'federal',
    'idbi',
    'idfcfirst',
    'rbl',
    'dbs',
    'sc',
    'citi',
    'hsbc',
    'bandhan',
    'unionbank',
    'indianbank',
    'cbin',
    'uboi',
    'fino',
    'jio',
    'airtel',
    'postbank',
    'jupiteraxis',
    'slice',
    'fam',
    'waaxis',
    'wahdfcbank',
    'wasbi',
    'dlb',
    'abfspay',
    'ratn',
    'aubank',
    'yesbankltd',
    'yesbank',
    'pingpay',
    'nsdl',
    'barodampay',
    'mahb',
    'axisb',
    'idfb',
    'ubi',
    'centralbank',
    'kbl',
    'sib',
    'iob',
    'uco',
    'pockets',
    'eazypay',
  };

  /// Email domains to reject.
  static const Set<String> _emailDomains = {
    'com',
    'in',
    'org',
    'net',
    'co',
    'edu',
    'gov',
    'io',
    'info',
    'gmail',
    'yahoo',
    'hotmail',
    'outlook',
    'rediffmail',
  };

  /// Extract UPI ID (VPA) from body.
  static String? extractUpiId(String body, List<String> reasons) {
    final matches = _upiIdPattern.allMatches(body);

    for (final match in matches) {
      final candidate = match.group(1)!;
      final parts = candidate.split('@');
      if (parts.length != 2) continue;

      final handle = parts[1].toLowerCase();

      if (_emailDomains.contains(handle)) continue;
      if (handle.contains('.')) continue;

      if (_upiHandles.contains(handle)) {
        reasons.add('UPI ID extracted: $candidate (known handle: $handle)');
        return candidate;
      }

      // Accept plausible handles (2-15 chars, alpha only)
      if (handle.length >= 2 &&
          handle.length <= 15 &&
          RegExp(r'^[a-z]+$').hasMatch(handle)) {
        reasons.add('UPI ID extracted: $candidate (plausible handle: $handle)');
        return candidate;
      }
    }

    return null;
  }

  // ═══════════════════════════════════════════════════════════════════
  //  REFERENCE ID EXTRACTION
  // ═══════════════════════════════════════════════════════════════════

  /// UPI Ref pattern.
  static final RegExp _upiRefPattern = RegExp(
    r'(?:UPI\s*[-/]?\s*(?:Ref|Txn|Transaction)\.?\s*(?:No\.?\s*|ID\s*)?[:.]?\s*)(\d{6,16})',
    caseSensitive: false,
  );

  /// Axis Bank: UPI/Name/Ref/ID
  static final RegExp _axisRefPattern = RegExp(
    r'UPI/[^/]+/(?:Ref|ref)/(\d{6,16})',
  );

  /// IMPS/NEFT/RTGS Ref.
  static final RegExp _impsRefPattern = RegExp(
    r'(?:(?:IMPS|NEFT|RTGS)\s*[-/]?\s*(?:Ref|Txn)\.?\s*(?:No\.?\s*)?[:.]?\s*)(\d{6,16})',
    caseSensitive: false,
  );

  /// Generic Ref/TxnId.
  static final RegExp _genericRefPattern = RegExp(
    r'(?:Ref\.?\s*(?:No\.?\s*|ID\s*)?[:.]?\s*|TxnId\s*[:.]?\s*|Txn\s*(?:No\.?\s*)?[:.]?\s*|Transaction\s*(?:ID|No\.?\s*)?[:.]?\s*)(\d{6,16})',
    caseSensitive: false,
  );

  /// Order or Invoice Ref.
  static final RegExp _orderRefPattern = RegExp(
    r'(?:order|invoice)\s*(?:#|no\.?\s*|id\s*)?[:.]?\s*([A-Za-z0-9_-]{5,20})',
    caseSensitive: false,
  );

  /// Extract reference/transaction ID.
  static String? extractReferenceId(String body, List<String> reasons) {
    // Try in order of specificity
    for (final (pattern, name) in [
      (_upiRefPattern, 'UPI Ref'),
      (_axisRefPattern, 'Axis UPI Ref'),
      (_impsRefPattern, 'IMPS/NEFT Ref'),
      (_genericRefPattern, 'Generic Ref'),
      (_orderRefPattern, 'Order/Invoice Ref'),
    ]) {
      final match = pattern.firstMatch(body);
      if (match != null) {
        final ref = match.group(1)!;
        reasons.add('Reference ID ($name): $ref');
        return ref;
      }
    }

    return null;
  }

  // ═══════════════════════════════════════════════════════════════════
  //  MERCHANT EXTRACTION
  // ═══════════════════════════════════════════════════════════════════

  /// Ordered list of merchant extraction patterns.
  /// Each pattern is tried in sequence; first match wins.
  ///
  /// Order rationale:
  /// 1. Bank-specific patterns (highest accuracy)
  /// 2. UPI app patterns (GPay, PhonePe style)
  /// 3. Generic patterns ("at", "to", "from")
  /// 4. Fallback to UPI ID
  static final List<(RegExp, String)> _merchantPatterns = [
    // HDFC: "Info: Payment to merchant"
    (
      RegExp(
        r'Info\s*:\s*(?:Payment\s+to|UPI[-/]?\s*)\s*([A-Za-z0-9][\w\s&.*@/-]{1,60}?)(?:\.\s|$)',
        caseSensitive: false,
      ),
      'HDFC Info pattern',
    ),
    // BOB: "Cr. to VPA" — Bank of Baroda debit messages show credit target
    (
      RegExp(
        r'Cr\.?\s+to\s+([A-Za-z0-9][\w\s&.*@/-]{1,60}?)(?:\.\s|\s+Ref|\s+ref|$)',
        caseSensitive: false,
      ),
      'BOB Cr. to pattern',
    ),
    // ICICI: "for UPI-merchant@upi"
    (
      RegExp(
        r'for\s+UPI[-/]?\s*([A-Za-z0-9][\w\s&.*@/-]{1,60}?)(?:\s*\.?\s*UPI\s*Ref|\.\s|$)',
        caseSensitive: false,
      ),
      'ICICI UPI pattern',
    ),
    // GPay/PhonePe: "You paid ₹500 to Merchant"
    (
      RegExp(
        r'You\s+paid\s+(?:Rs\.?\s*|INR\.?\s*|₹\s?)[0-9,]+(?:\.\d{1,2})?\s+to\s+([A-Za-z0-9][\w\s&.*@/-]{1,60}?)(?:\.\s|$)',
        caseSensitive: false,
      ),
      'You paid to pattern',
    ),
    // "₹X received from Person"
    (
      RegExp(
        r'(?:Rs\.?\s*|INR\.?\s*|₹\s?)[0-9,]+(?:\.\d{1,2})?\s+received\s+from\s+([A-Za-z0-9][\w\s&.*@/-]{1,60}?)(?:\.\s|$)',
        caseSensitive: false,
      ),
      'Amount received from pattern',
    ),
    // "Money sent to merchant"
    (
      RegExp(
        r'Money\s+sent\s+(?:Rs\.?\s*|INR\.?\s*|₹\s?)?[0-9,]*(?:\.\d{1,2})?\s*(?:to\s+)?([A-Za-z0-9][\w\s&.*@/-]{1,60}?)(?:\.\s|$)',
        caseSensitive: false,
      ),
      'Money sent to pattern',
    ),
    // SBI: "by transfer to X"
    (
      RegExp(
        r'(?:by\s+transfer\s+to|transfer\s+to)\s+([A-Za-z0-9][\w\s&.*@/-]{1,60}?)(?:\s*[-(/]|\s+on\b|\s+ref\b|\.\s|$)',
        caseSensitive: false,
      ),
      'Transfer to pattern',
    ),
    // Truecaller: "₹X paid to Merchant | Bank" or "₹X received from Person | Bank"
    (
      RegExp(
        r'(?:paid\s+to|sent\s+to|received\s+from)\s+([A-Za-z0-9][\w\s&.*@/-]{1,60}?)\s*\|',
        caseSensitive: false,
      ),
      'Truecaller pipe-separated pattern',
    ),
    // Generic: "at MERCHANT on"
    (
      RegExp(
        r'\bat\s+([A-Za-z0-9][\w\s&.*-]{1,50}?)(?:\s+on\b|\s+ref\b|\s+Ref\b|\s+UPI\b|\s+via\b|\.(?:\s|$)|$)',
        caseSensitive: false,
      ),
      'At merchant pattern',
    ),
    // "paid to X" / "sent to X"
    (
      RegExp(
        r'(?:paid\s+to|to\s+VPA|transfer(?:red)?\s+to|sent\s+to|payment\s+to|paying\s+to)\s+([A-Za-z0-9][\w\s&.*@/-]{1,60}?)(?:\s+on\b|\s+from\b|\s+ref\b|\s+Ref\b|\s+UPI\b|\s+via\b|\.\s|$)',
        caseSensitive: false,
      ),
      'Paid/sent to pattern',
    ),
    // "received from X" / "from X"
    (
      RegExp(
        r'(?:received\s+from|from\s+VPA|from)\s+([A-Za-z0-9][\w\s&.*@/-]{1,60}?)(?:\s+on\b|\s+to\b|\s+in\b|\s+ref\b|\s+Ref\b|\s+UPI\b|\s+via\b|\.\s|$)',
        caseSensitive: false,
      ),
      'From pattern',
    ),
  ];

  /// Extract merchant name from body.
  static String extractMerchant(
    String body,
    String? upiId,
    String txnType,
    List<String> reasons,
  ) {
    for (final (pattern, name) in _merchantPatterns) {
      final match = pattern.firstMatch(body);
      if (match != null) {
        final raw = match.group(1)?.trim();
        if (raw == null || raw.length < 2) continue;
        if (RegExp(r'^\d+$').hasMatch(raw)) continue;

        final cleaned = _cleanMerchant(raw);
        if (cleaned != 'Unknown') {
          reasons.add('Merchant extracted via $name: "$cleaned"');
          return cleaned;
        }
      }
    }

    // Fallback: use UPI ID
    if (upiId != null) {
      final localPart = upiId.split('@').first;
      final name = RegExp(r'^\d{10}$').hasMatch(localPart)
          ? upiId
          : _cleanMerchant(localPart.replaceAll('.', ' '));
      reasons.add('Merchant from UPI ID fallback: "$name"');
      return name;
    }

    reasons.add('Merchant: Unknown (no pattern matched)');
    return 'Unknown';
  }

  static String _cleanMerchant(String name) {
    var cleaned = name
        .replaceAll(RegExp(r'^[\s.,;:!?-]+|[\s.,;:!?-]+$'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (cleaned.contains('@')) return cleaned;

    cleaned = cleaned
        .replaceAll(RegExp(r'\s+on$', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+from$', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+to$', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+ref$', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+via$', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+UPI$', caseSensitive: false), '')
        .trim();

    if (cleaned.length > 60) cleaned = cleaned.substring(0, 60).trim();
    return cleaned.isEmpty ? 'Unknown' : cleaned;
  }

  // ═══════════════════════════════════════════════════════════════════
  //  ACCOUNT TAIL EXTRACTION
  // ═══════════════════════════════════════════════════════════════════

  static final RegExp _accountPattern = RegExp(
    r'(?:A\/?c|Acct|Account|AC|card|a\/?c)\s*(?:no\.?\s*)?(?:ending\s+(?:with\s+)?|ending\.?\s*)?[*xX]*\s*(\d{3,6})',
    caseSensitive: false,
  );

  static final RegExp _accountAltPattern = RegExp(
    r'(?:from|to|in)\s+(?:A\/?c\s*)?[*xX]{2,}\s*(\d{3,6})',
    caseSensitive: false,
  );

  /// Extract last 3–6 digits of account number.
  static String? extractAccountTail(String body, List<String> reasons) {
    final match = _accountPattern.firstMatch(body);
    if (match != null) {
      final tail = match.group(1)!;
      reasons.add('Account tail extracted: XX$tail');
      return tail;
    }

    final altMatch = _accountAltPattern.firstMatch(body);
    if (altMatch != null) {
      final tail = altMatch.group(1)!;
      reasons.add('Account tail extracted (alt): XX$tail');
      return tail;
    }

    return null;
  }

  // ═══════════════════════════════════════════════════════════════════
  //  DATE EXTRACTION
  // ═══════════════════════════════════════════════════════════════════

  static final RegExp _dateIso = RegExp(r'(\d{4})-(\d{2})-(\d{2})');

  /// Colon-separated date: yyyy:mm:dd (Bank of Baroda style).
  /// Negative lookbehind ensures the year is not part of a longer number.
  static final RegExp _dateColonYmd = RegExp(
    r'(?<!\d)(\d{4}):(\d{1,2}):(\d{1,2})',
  );
  static final RegExp _dateMonthName = RegExp(
    r'(\d{1,2})[-\s]?(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*[-\s]?(\d{2,4})',
    caseSensitive: false,
  );
  static final RegExp _dateDashSlash = RegExp(
    r'(\d{1,2})[-/](\d{1,2})[-/](\d{2,4})',
  );

  static final Map<String, int> _monthMap = {
    'jan': 1,
    'feb': 2,
    'mar': 3,
    'apr': 4,
    'may': 5,
    'jun': 6,
    'jul': 7,
    'aug': 8,
    'sep': 9,
    'oct': 10,
    'nov': 11,
    'dec': 12,
  };

  /// Extract date from SMS body, preserving the time from [smsTime].
  ///
  /// SMS bodies contain only the date (e.g., '21-05-2026') without time.
  /// The OS-level SMS timestamp [smsTime] has the accurate reception time,
  /// so we copy its hour/minute/second onto the extracted date.
  static DateTime? extractDate(
    String body,
    List<String> reasons, {
    required DateTime smsTimestamp,
  }) {
    // ISO format (yyyy-mm-dd)
    final isoMatch = _dateIso.firstMatch(body);
    if (isoMatch != null) {
      final dt = _safeDate(
        int.parse(isoMatch.group(1)!),
        int.parse(isoMatch.group(2)!),
        int.parse(isoMatch.group(3)!),
        smsTimestamp,
      );
      if (dt != null) {
        reasons.add(
          'Date extracted (ISO): ${dt.toIso8601String().split("T")[0]}',
        );
        return dt;
      }
    }

    // Colon-separated format: yyyy:mm:dd (Bank of Baroda style)
    final colonMatch = _dateColonYmd.firstMatch(body);
    if (colonMatch != null) {
      final dt = _safeDate(
        int.parse(colonMatch.group(1)!),
        int.parse(colonMatch.group(2)!),
        int.parse(colonMatch.group(3)!),
        smsTimestamp,
      );
      if (dt != null) {
        reasons.add(
          'Date extracted (colon-separated): ${dt.toIso8601String().split("T")[0]}',
        );
        return dt;
      }
    }

    // Month name format (dd-Mon-yy)
    final monthMatch = _dateMonthName.firstMatch(body);
    if (monthMatch != null) {
      final day = int.parse(monthMatch.group(1)!);
      final monthStr = monthMatch.group(2)!.substring(0, 3).toLowerCase();
      final month = _monthMap[monthStr];
      var year = int.parse(monthMatch.group(3)!);
      if (year < 100) year += 2000;
      if (month != null) {
        final dt = _safeDate(year, month, day, smsTimestamp);
        if (dt != null) {
          reasons.add(
            'Date extracted (month name): ${dt.toIso8601String().split("T")[0]}',
          );
          return dt;
        }
      }
    }

    // Numeric format (dd-mm-yy or dd/mm/yyyy)
    final numMatch = _dateDashSlash.firstMatch(body);
    if (numMatch != null) {
      final a = int.parse(numMatch.group(1)!);
      final b = int.parse(numMatch.group(2)!);
      var c = int.parse(numMatch.group(3)!);
      if (c < 100) c += 2000;

      // Indian format: dd-mm-yyyy
      if (a <= 31 && b <= 12) {
        final dt = _safeDate(c, b, a, smsTimestamp);
        if (dt != null) {
          reasons.add(
            'Date extracted (dd-mm-yyyy): ${dt.toIso8601String().split("T")[0]}',
          );
          return dt;
        }
      }
    }

    return null;
  }

  /// Build a DateTime from extracted date components, preserving the time
  /// from [smsTime]. The date from the SMS body is authoritative for the
  /// calendar day, but the OS timestamp's time is the most accurate
  /// source for hour/minute/second.
  static DateTime? _safeDate(int year, int month, int day, DateTime smsTime) {
    try {
      if (month < 1 || month > 12 || day < 1 || day > 31) return null;
      final dt = DateTime(
        year,
        month,
        day,
        smsTime.hour,
        smsTime.minute,
        smsTime.second,
      );
      final now = DateTime.now();
      if (dt.isAfter(now.add(const Duration(days: 730)))) return null;
      if (dt.isBefore(now.subtract(const Duration(days: 3650)))) return null;
      return dt;
    } catch (e, stack) {
      AppLogger.debug('[EntityExtractor] Error parsing safe date: $e\n$stack');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  //  COMBINED EXTRACTION
  // ═══════════════════════════════════════════════════════════════════

  /// Extract all entities from an SMS body.
  ///
  /// [smsTimestamp] is the OS-level timestamp of the SMS, used to preserve
  /// the time component when extracting a date from the SMS body.
  static ExtractedEntities extractAll(
    String body,
    String sender,
    String txnType, {
    required DateTime smsTimestamp,
  }) {
    final reasons = <String>[];

    final bank = detectBank(body, sender, reasons);
    final upiId = extractUpiId(body, reasons);
    final ref = extractReferenceId(body, reasons);
    final merchant = extractMerchant(body, upiId, txnType, reasons);
    final account = extractAccountTail(body, reasons);
    final date = extractDate(body, reasons, smsTimestamp: smsTimestamp);

    return ExtractedEntities(
      bankName: bank,
      merchantName: merchant,
      upiId: upiId,
      referenceId: ref,
      accountTail: account,
      date: date,
      reasons: reasons,
    );
  }
}
