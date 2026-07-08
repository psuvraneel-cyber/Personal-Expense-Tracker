library;

import 'package:pet/core/utils/app_logger.dart';

/// TransactionParser — Production-grade on-device regex engine for extracting
/// UPI/bank transaction details from Indian bank SMS messages.

///
/// ## Architecture
/// A multi-layer pipeline processes each SMS:
///   1. **Quick Rejection** — Skip OTP, promo, balance-only, and non-financial SMS.
///   2. **Amount Extraction** — Parse ₹/Rs/INR amounts with comma/decimal handling.
///   3. **Transaction Type Detection** — Positional keyword analysis for debit/credit.
///   4. **Sub-type Classification** — Refund, cashback, collect request, standard payment.
///   5. **UPI Reference Extraction** — UPI Ref / IMPS Ref / Txn ID patterns.
///   6. **Merchant Extraction** — Ordered: VPA → "at"/"to"/"from" → UPI ID → fallback.
///   7. **Bank Detection** — Sender ID map → body text map → "Unknown Bank".
///   8. **Date Extraction** — ISO / dd-Mon-yy / dd-mm-yyyy formats.
///   9. **Confidence Scoring** — Weighted score based on how many fields extracted.
///
/// ## Supported Banks & Apps
/// HDFC, SBI, ICICI, Axis, Kotak, PNB, BOB, Canara, Yes, IDBI, IndusInd,
/// Union, Federal, IDFC First, RBL, Indian Bank, Central, IOB, UCO, BOI,
/// South Indian, Karnataka, Bandhan, DBS, Standard Chartered, Citi, HSBC.
///
/// UPI Apps: Google Pay, PhonePe, Paytm, BHIM, Amazon Pay, WhatsApp Pay.
///
/// ## Keywords Handled
/// **Debits:** debited, spent, paid, sent, deducted, transferred, purchase,
///   withdrawn, collect request, payment successful.
/// **Credits:** credited, received, deposited, refunded, cashback, reversed,
///   added, money received, payment received.
///
/// SECURITY: All parsing is performed entirely on-device.
/// No SMS data is transmitted to any external server.

// ═════════════════════════════════════════════════════════════════════════════
//  DATA MODELS
// ═════════════════════════════════════════════════════════════════════════════

/// Result of parsing a single SMS message.
class ParsedTransaction {
  final double amount;
  final String merchantName;
  final String bankName;
  final String transactionType; // 'debit' or 'credit'
  final String
  transactionSubType; // 'payment', 'collect', 'refund', 'cashback', 'transfer', 'reversal'
  final DateTime? parsedDate;
  final String? upiId;
  final String? accountTail; // last 4-6 digits of account
  final String? referenceId; // UPI Ref / IMPS Ref / NEFT Ref / Txn ID
  final double confidence; // 0.0 – 1.0

  const ParsedTransaction({
    required this.amount,
    required this.merchantName,
    required this.bankName,
    required this.transactionType,
    this.transactionSubType = 'payment',
    this.parsedDate,
    this.upiId,
    this.accountTail,
    this.referenceId,
    this.confidence = 0.5,
  });

  @override
  String toString() {
    return 'ParsedTransaction(₹$amount, $transactionType/$transactionSubType, '
        'merchant: $merchantName, bank: $bankName, '
        'upi: $upiId, ref: $referenceId, '
        'confidence: ${(confidence * 100).toStringAsFixed(0)}%, '
        'date: $parsedDate)';
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  TRANSACTION PARSER ENGINE
// ═════════════════════════════════════════════════════════════════════════════

class TransactionParser {
  TransactionParser._();

  // ─── STAGE 0: Pre-compiled Regex Patterns ─────────────────────────
  // All patterns are static final to avoid re-compilation per SMS.

  // ── Amount ────────────────────────────────────────────────────────
  /// Matches: Rs.500, Rs 1,500.00, INR 500, ₹500, INR.500, Rs500
  /// Also handles: Rs. 1,00,000.50 (Indian comma notation)
  static final RegExp _amountPattern = RegExp(
    r'(?:Rs\.?\s*|INR\.?\s*|₹\s?)([0-9]+(?:,[0-9]{2,3})*(?:\.\d{1,2})?)',
    caseSensitive: false,
  );

  /// Secondary amount pattern for formats like "amount of Rs 500"
  static final RegExp _amountOfPattern = RegExp(
    r'(?:amount\s+(?:of\s+)?|amt\.?\s*)(?:Rs\.?\s*|INR\.?\s*|₹\s?)([0-9]+(?:,[0-9]{2,3})*(?:\.\d{1,2})?)',
    caseSensitive: false,
  );

  // ── Transaction Type Keywords ─────────────────────────────────────
  static final RegExp _debitKeywords = RegExp(
    r'\b(?:debited|debit|spent|paid|purchase[d]?|withdrawn|sent|deducted|transferred|payment\s+(?:of|successful)|money\s+sent|you\s+paid|txn\s+of|paying|paid\s+to|auto.?pay|dr\.)(?:\b|(?<=\.))',
    caseSensitive: false,
  );

  static final RegExp _creditKeywords = RegExp(
    r'\b(?:credited|credit|received|deposited|deposit|refund(?:ed)?|cashback|cash\s*back|reversed|reversal|added|money\s+received|payment\s+received|settled|reimburs(?:ed|ement))\b',
    caseSensitive: false,
  );

  // ── Sub-type Detection ────────────────────────────────────────────
  static final RegExp _collectRequestPattern = RegExp(
    r'\b(?:collect\s*(?:request|req)?|UPI\s*collect|mandate)\b',
    caseSensitive: false,
  );

  static final RegExp _refundPattern = RegExp(
    r'\b(?:refund(?:ed)?|reversal|reversed|charge\s*back)\b',
    caseSensitive: false,
  );

  static final RegExp _cashbackPattern = RegExp(
    r'\b(?:cashback|cash\s*back|reward|bonus|scratch\s*card|promotional\s*credit)\b',
    caseSensitive: false,
  );

  static final RegExp _impsNeftPattern = RegExp(
    r'\b(?:IMPS|NEFT|RTGS)\b',
    caseSensitive: false,
  );

  // ── UPI Detection ─────────────────────────────────────────────────
  /// Broad UPI indicator — if SMS mentions "UPI" or contains a UPI VPA
  static final RegExp _upiIndicator = RegExp(
    r'\bUPI\b|@[a-zA-Z]{2,}(?:\b|$)',
    caseSensitive: false,
  );

  // ── UPI ID / VPA ──────────────────────────────────────────────────
  /// Matches: merchant@ybl, john@okaxis, shop@paytm, etc.
  /// Excludes common email domains (.com, .in, .org, .net)
  static final RegExp _upiIdPattern = RegExp(
    r'\b([a-zA-Z0-9][a-zA-Z0-9._-]{0,49}@[a-zA-Z][a-zA-Z0-9]{1,20})\b',
  );

  /// Known UPI handle suffixes for validation
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

  /// Email domains to exclude (not UPI IDs)
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

  // ── Reference ID Patterns ─────────────────────────────────────────
  /// UPI Ref No / UPI Ref: / UPI Ref / UPI-Ref
  static final RegExp _upiRefPattern = RegExp(
    r'(?:UPI\s*[-/]?\s*(?:Ref|Txn|Transaction)\.?\s*(?:No\.?\s*|ID\s*)?[:.]?\s*)(\d{6,16})',
    caseSensitive: false,
  );

  /// Standalone Ref / Ref No / TxnId / Transaction ID
  static final RegExp _refPattern = RegExp(
    r'(?:Ref\.?\s*(?:No\.?\s*|ID\s*)?[:.]?\s*|TxnId\s*[:.]?\s*|Txn\s*(?:No\.?\s*)?[:.]?\s*|Transaction\s*(?:ID|No\.?\s*)?[:.]?\s*)(\d{6,16})',
    caseSensitive: false,
  );

  /// IMPS Ref / NEFT Ref / RTGS Ref
  static final RegExp _impsRefPattern = RegExp(
    r'(?:(?:IMPS|NEFT|RTGS)\s*[-/]?\s*(?:Ref|Txn)\.?\s*(?:No\.?\s*)?[:.]?\s*)(\d{6,16})',
    caseSensitive: false,
  );

  /// Axis Bank style: UPI/MerchantName/Ref/412345678901
  static final RegExp _axisUpiRefPattern = RegExp(
    r'UPI/[^/]+/(?:Ref|ref)/(\d{6,16})',
  );

  // ── Merchant / Payee Extraction ───────────────────────────────────
  /// "at MERCHANT on" / "at MERCHANT."
  static final RegExp _merchantAtPattern = RegExp(
    r'\bat\s+([A-Za-z0-9][\w\s&.*-]{1,50}?)(?:\s+on\b|\s+ref\b|\s+Ref\b|\s+UPI\b|\s+via\b|\.(?:\s|$)|$)',
    caseSensitive: false,
  );

  /// "paid to X" / "sent to X" / "transferred to X" / "to VPA X" / "Cr. to X"
  static final RegExp _merchantToPattern = RegExp(
    r'(?:paid\s+to|to\s+VPA|transfer(?:red)?\s+to|sent\s+to|payment\s+to|paying\s+to|Cr\.?\s+to)\s+([A-Za-z0-9][\w\s&.*@/-]{1,60}?)(?:\s+on\b|\s+from\b|\s+ref\b|\s+Ref\b|\s+UPI\b|\s+via\b|\.\s|$)',
    caseSensitive: false,
  );

  /// "received from X" / "from VPA X" / "credited.*from X"
  static final RegExp _merchantFromPattern = RegExp(
    r'(?:received\s+from|from\s+VPA|from)\s+([A-Za-z0-9][\w\s&.*@/-]{1,60}?)(?:\s+on\b|\s+to\b|\s+in\b|\s+ref\b|\s+Ref\b|\s+UPI\b|\s+via\b|\.\s|$)',
    caseSensitive: false,
  );

  /// "by transfer to X" (SBI style: "debited by Rs. ... by transfer to X")
  static final RegExp _merchantByTransferToPattern = RegExp(
    r'(?:by\s+transfer\s+to|transfer\s+to)\s+([A-Za-z0-9][\w\s&.*@/-]{1,60}?)(?:\s*[-(/]|\s+on\b|\s+ref\b|\.\s|$)',
    caseSensitive: false,
  );

  /// "for UPI-merchant@upi" (ICICI style)
  static final RegExp _merchantForUpiPattern = RegExp(
    r'for\s+UPI[-/]?\s*([A-Za-z0-9][\w\s&.*@/-]{1,60}?)(?:\s*\.?\s*UPI\s*Ref|\.\s|$)',
    caseSensitive: false,
  );

  /// "Info: Payment to merchant@upi" (HDFC style)
  static final RegExp _merchantInfoPattern = RegExp(
    r'Info\s*:\s*(?:Payment\s+to|UPI[-/]?\s*)\s*([A-Za-z0-9][\w\s&.*@/-]{1,60}?)(?:\.\s|$)',
    caseSensitive: false,
  );

  /// Google Pay / PhonePe style: "You paid ₹500 to Merchant Name"
  static final RegExp _merchantYouPaidToPattern = RegExp(
    r'You\s+paid\s+(?:Rs\.?\s*|INR\.?\s*|₹\s?)[0-9,]+(?:\.\d{1,2})?\s+to\s+([A-Za-z0-9][\w\s&.*@/-]{1,60}?)(?:\.\s|$)',
    caseSensitive: false,
  );

  /// "₹500 received from Person Name"
  static final RegExp _merchantReceivedFromPattern = RegExp(
    r'(?:Rs\.?\s*|INR\.?\s*|₹\s?)[0-9,]+(?:\.\d{1,2})?\s+received\s+from\s+([A-Za-z0-9][\w\s&.*@/-]{1,60}?)(?:\.\s|$)',
    caseSensitive: false,
  );

  /// "Money sent ₹500 to merchant@upi"
  static final RegExp _merchantMoneySentToPattern = RegExp(
    r'Money\s+sent\s+(?:Rs\.?\s*|INR\.?\s*|₹\s?)?[0-9,]*(?:\.\d{1,2})?\s*(?:to\s+)?([A-Za-z0-9][\w\s&.*@/-]{1,60}?)(?:\.\s|$)',
    caseSensitive: false,
  );

  // ── Account Number Tail ───────────────────────────────────────────
  static final RegExp _accountPattern = RegExp(
    r'(?:A\/?c|Acct|Account|AC|card|a\/?c)\s*(?:no\.?\s*)?(?:ending\s+(?:with\s+)?|ending\.?\s*)?[*xX]*\s*(\d{3,6})',
    caseSensitive: false,
  );

  /// Alternate: "from XX1234" / "to XX1234" (where XX is masked)
  static final RegExp _accountAltPattern = RegExp(
    r'(?:from|to|in)\s+(?:A\/?c\s*)?[*xX]{2,}\s*(\d{3,6})',
    caseSensitive: false,
  );

  // ── Date Patterns ─────────────────────────────────────────────────
  /// dd-mm-yy, dd-mm-yyyy, dd/mm/yy, dd/mm/yyyy
  static final RegExp _dateDashSlash = RegExp(
    r'(\d{1,2})[-/](\d{1,2})[-/](\d{2,4})',
  );

  /// Colon-separated: yyyy:mm:dd (Bank of Baroda style)
  static final RegExp _dateColonYmd = RegExp(
    r'(?<!\d)(\d{4}):(\d{1,2}):(\d{1,2})',
  );

  /// dd-Mon-yy, dd-Mon-yyyy, ddMonyy, ddMonyyyy, dd Mon yy
  static final RegExp _dateMonthName = RegExp(
    r'(\d{1,2})[-\s]?(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*[-\s]?(\d{2,4})',
    caseSensitive: false,
  );

  /// yyyy-mm-dd (ISO)
  static final RegExp _dateIso = RegExp(r'(\d{4})-(\d{2})-(\d{2})');

  // ── Bank Detection from Sender ID ─────────────────────────────────
  static final Map<RegExp, String> _senderBankMap = {
    // Major private banks
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
    // Major public banks
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
    // Payments banks & UPI apps
    RegExp(r'PAYTM', caseSensitive: false): 'Paytm Payments Bank',
    RegExp(r'AIRTEL', caseSensitive: false): 'Airtel Payments Bank',
    RegExp(r'JIOFI|JIOPA', caseSensitive: false): 'Jio Payments Bank',
    RegExp(r'GPAY|GOOGLE', caseSensitive: false): 'Google Pay',
    RegExp(r'PHONEPE|PHNEPE', caseSensitive: false): 'PhonePe',
    RegExp(r'BHIM', caseSensitive: false): 'BHIM',
    RegExp(r'AMAZONP|AMZNPAY', caseSensitive: false): 'Amazon Pay',
    RegExp(r'WHATSAP', caseSensitive: false): 'WhatsApp Pay',
    // Foreign banks in India
    RegExp(r'STANCHART|SCBANK|SCBNK', caseSensitive: false):
        'Standard Chartered',
    RegExp(r'CITI|CITIBNK', caseSensitive: false): 'Citi Bank',
    RegExp(r'HSBC|HSBCBK', caseSensitive: false): 'HSBC',
    // Small Finance Banks
    RegExp(r'AUBANK|AUSFB', caseSensitive: false): 'AU Small Finance Bank',
    RegExp(r'EQITAS|EQUITS', caseSensitive: false): 'Equitas SFB',
    RegExp(r'UJJIVN|UJJVAN', caseSensitive: false): 'Ujjivan SFB',
    // Neo-banks / Fintech
    RegExp(r'JUPITE', caseSensitive: false): 'Jupiter',
    RegExp(r'FIBANK|FIMON', caseSensitive: false): 'Fi Money',
    RegExp(r'SLICE', caseSensitive: false): 'Slice',
    RegExp(r'NIYOBN', caseSensitive: false): 'Niyo',
    // Truecaller (relays bank transaction SMS)
    RegExp(r'TRUCLR|TRUCAL|TRUECL|TRUECALLER', caseSensitive: false):
        'Truecaller',
  };

  /// Bank names detected from SMS body text.
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
    RegExp(r'AU\s*(?:Small\s*Finance\s*)?Bank', caseSensitive: false):
        'AU Small Finance Bank',
    RegExp(r'Karnataka\s*Bank', caseSensitive: false): 'Karnataka Bank',
    RegExp(r'South\s*Indian\s*Bank', caseSensitive: false): 'South Indian Bank',
    RegExp(r'Paytm\s*(?:Payments?\s*)?Bank', caseSensitive: false):
        'Paytm Payments Bank',
  };

  // ── Filtering: Reject non-transaction SMS ─────────────────────────

  /// OTP, promo, and non-financial noise patterns.
  static final RegExp _rejectPattern = RegExp(
    r'\bOTP\b|one.?time\s*password|CVV\b|PIN\b|'
    r'verif(?:y|ication)|promo(?:tion)?|limited\s*(?:time|period)|'
    r'offer\b|reward\s*point|apply\s*now|congratulat|'
    r'click\s*(?:here|link)|unsubscri|SPAM|'
    r'insurance|mutual\s*fund|(?:pre.?)?approv(?:ed|al)\s*(?:loan|credit)|'
    r'free\s*(?:trial|credit)|loan\s*(?:of|offer)|'
    r'(?:credit|debit)\s*card\s*(?:offer|apply|eligib)|'
    r'KYC\s*(?:update|expir)|update\s*(?:your|KYC)|'
    r'download\s*(?:app|now)|install\b|'
    r'mandate\s*(?:creation|registration|auto.?debit\s*(?:setup|registration))',
    caseSensitive: false,
  );

  /// Must contain a monetary amount indicator.
  static final RegExp _transactionIndicator = RegExp(
    r'(?:Rs\.?\s*|INR\.?\s*|₹\s?)\d',
    caseSensitive: false,
  );

  /// Balance-only SMS (no actual transaction).
  static final RegExp _balanceOnlyPattern = RegExp(
    r'(?:available|avl\.?|current|closing|total)\s*(?:bal(?:ance)?|bal\.?)\s*(?:is|:)?\s*(?:Rs\.?\s*|INR\.?\s*|₹\s?)',
    caseSensitive: false,
  );

  /// Minimum transaction SMS length (shorter messages are likely noise).
  static const int _minSmsLength = 30;

  // ── Month Name → Number ───────────────────────────────────────────
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

  // ═══════════════════════════════════════════════════════════════════
  //  PUBLIC API
  // ═══════════════════════════════════════════════════════════════════

  /// Parse a bank SMS message and extract transaction details.
  ///
  /// Returns `null` if the SMS is not recognized as a valid transaction.
  ///
  /// [smsBody]       — The full SMS text.
  /// [sender]        — The SMS sender ID (e.g., "AD-HDFCBK", "+919876543210").
  /// [smsTimestamp]  — The timestamp attached to the SMS by the OS.
  static ParsedTransaction? parse(
    String smsBody,
    String sender,
    DateTime smsTimestamp,
  ) {
    // Step 1: Quick rejection — skip OTP, promo, or non-financial SMS
    if (!_isLikelyTransaction(smsBody)) return null;

    // Step 2: Extract amount
    final amount = _extractAmount(smsBody);
    if (amount == null || amount <= 0) return null;

    // Step 3: Determine transaction type (debit / credit)
    final txnType = _detectTransactionType(smsBody);
    if (txnType == null) return null;

    // Step 4: Determine sub-type (refund, cashback, collect, standard)
    final subType = _detectSubType(smsBody, txnType);

    // Step 5: Extract bank name
    final bankName = _detectBank(smsBody, sender);

    // Step 6: Extract UPI ID / VPA
    final upiId = _extractUpiId(smsBody);

    // Step 7: Extract merchant / payee name
    final merchantName = _extractMerchant(smsBody, upiId, txnType);

    // Step 8: Extract reference ID
    final referenceId = _extractReferenceId(smsBody);

    // Step 9: Extract date (preserve time from OS timestamp)
    final parsedDate = _extractDate(smsBody, smsTimestamp) ?? smsTimestamp;

    // Step 10: Extract account tail
    final accountTail = _extractAccountTail(smsBody);

    // Step 11: Calculate confidence score
    final confidence = _calculateConfidence(
      amount: amount,
      txnType: txnType,
      bankName: bankName,
      merchantName: merchantName,
      upiId: upiId,
      referenceId: referenceId,
      smsBody: smsBody,
    );

    return ParsedTransaction(
      amount: amount,
      merchantName: merchantName,
      bankName: bankName,
      transactionType: txnType,
      transactionSubType: subType,
      parsedDate: parsedDate,
      upiId: upiId,
      accountTail: accountTail,
      referenceId: referenceId,
      confidence: confidence,
    );
  }

  /// Check if an SMS message looks like a bank transaction.
  /// Useful for pre-filtering before full parsing.
  static bool isTransactionSms(String smsBody) {
    return _isLikelyTransaction(smsBody);
  }

  /// Check if an SMS is specifically a UPI transaction.
  /// More specific than [isTransactionSms].
  static bool isUpiTransaction(String smsBody) {
    if (!_isLikelyTransaction(smsBody)) return false;
    return _upiIndicator.hasMatch(smsBody);
  }

  /// Batch parse multiple SMS messages efficiently.
  /// Skips non-transaction SMS and returns only successfully parsed results.
  ///
  /// Optimized for processing thousands of messages:
  /// - Applies quick rejection first (O(1) per message)
  /// - Avoids object allocations for rejected messages
  static List<({ParsedTransaction transaction, int index})> parseBatch(
    List<({String body, String sender, DateTime timestamp})> messages,
  ) {
    final results = <({ParsedTransaction transaction, int index})>[];
    for (var i = 0; i < messages.length; i++) {
      final msg = messages[i];
      final parsed = parse(msg.body, msg.sender, msg.timestamp);
      if (parsed != null) {
        results.add((transaction: parsed, index: i));
      }
    }
    return results;
  }

  // ═══════════════════════════════════════════════════════════════════
  //  INTERNAL HELPERS
  // ═══════════════════════════════════════════════════════════════════

  // ── Stage 1: Quick Rejection ──────────────────────────────────────

  static bool _isLikelyTransaction(String body) {
    // Too short to be a transaction SMS
    if (body.length < _minSmsLength) return false;

    // Must contain a currency/amount indicator
    if (!_transactionIndicator.hasMatch(body)) return false;

    // Must not be OTP/promo/noise
    if (_rejectPattern.hasMatch(body)) return false;

    // Must contain a debit or credit keyword
    if (!_debitKeywords.hasMatch(body) && !_creditKeywords.hasMatch(body)) {
      return false;
    }

    // Reject balance-only SMS that don't describe a transaction
    // But allow if it ALSO has a debit/credit keyword (some banks include
    // balance info alongside transaction details)
    if (_balanceOnlyPattern.hasMatch(body)) {
      final hasDebit = _debitKeywords.hasMatch(body);
      final hasCredit = _creditKeywords.hasMatch(body);
      if (!hasDebit && !hasCredit) return false;
    }

    return true;
  }

  // ── Stage 2: Amount Extraction ────────────────────────────────────

  static double? _extractAmount(String body) {
    // Try primary pattern first
    final match = _amountPattern.firstMatch(body);
    if (match != null) {
      final raw = match.group(1)!.replaceAll(',', '');
      final amount = double.tryParse(raw);
      if (amount != null && amount > 0 && amount < 10000000) {
        // Sanity: reject amounts > ₹1 crore (likely parsing error)
        return amount;
      }
    }

    // Try "amount of Rs X" pattern
    final altMatch = _amountOfPattern.firstMatch(body);
    if (altMatch != null) {
      final raw = altMatch.group(1)!.replaceAll(',', '');
      return double.tryParse(raw);
    }

    return null;
  }

  // ── Stage 3: Transaction Type Detection ───────────────────────────

  static String? _detectTransactionType(String body) {
    final hasDebit = _debitKeywords.hasMatch(body);
    final hasCredit = _creditKeywords.hasMatch(body);

    if (hasDebit && !hasCredit) return 'debit';
    if (hasCredit && !hasDebit) return 'credit';

    // Both present — use positional precedence (whichever appears first
    // in the SMS is typically the primary action)
    if (hasDebit && hasCredit) {
      final debitPos = _debitKeywords.firstMatch(body)!.start;
      final creditPos = _creditKeywords.firstMatch(body)!.start;

      // Special case: refund/cashback always means credit regardless of position
      if (_refundPattern.hasMatch(body) || _cashbackPattern.hasMatch(body)) {
        return 'credit';
      }

      return debitPos < creditPos ? 'debit' : 'credit';
    }

    return null;
  }

  // ── Stage 4: Sub-type Classification ──────────────────────────────

  static String _detectSubType(String body, String txnType) {
    if (_refundPattern.hasMatch(body)) return 'refund';
    if (_cashbackPattern.hasMatch(body)) return 'cashback';
    if (_collectRequestPattern.hasMatch(body)) return 'collect';

    if (_impsNeftPattern.hasMatch(body)) {
      // IMPS/NEFT can be triggered via UPI or directly
      return _upiIndicator.hasMatch(body) ? 'payment' : 'transfer';
    }

    // Reversal detection
    if (RegExp(
      r'\breversal\b|\breversed\b',
      caseSensitive: false,
    ).hasMatch(body)) {
      return 'reversal';
    }

    return 'payment';
  }

  // ── Stage 5: Bank Detection ───────────────────────────────────────

  static String _detectBank(String body, String sender) {
    // Priority 1: Detect from sender ID (most reliable)
    final upperSender = sender.toUpperCase();
    for (final entry in _senderBankMap.entries) {
      if (entry.key.hasMatch(upperSender)) return entry.value;
    }

    // Priority 2: Detect from SMS body text
    for (final entry in _bodyBankMap.entries) {
      if (entry.key.hasMatch(body)) return entry.value;
    }

    return 'Unknown Bank';
  }

  // ── Stage 6: UPI ID Extraction ────────────────────────────────────

  static String? _extractUpiId(String body) {
    // Find all potential UPI IDs in the body
    final matches = _upiIdPattern.allMatches(body);

    for (final match in matches) {
      final candidate = match.group(1)!;
      final parts = candidate.split('@');
      if (parts.length != 2) continue;

      final handle = parts[1].toLowerCase();

      // Reject if it looks like an email address
      if (_emailDomains.contains(handle)) continue;
      if (handle.contains('.')) continue;

      // Accept if the handle is a known UPI suffix
      if (_upiHandles.contains(handle)) return candidate;

      // Accept if it looks like a plausible UPI handle (2-15 chars, alpha only)
      if (handle.length >= 2 &&
          handle.length <= 15 &&
          RegExp(r'^[a-z]+$').hasMatch(handle)) {
        return candidate;
      }
    }

    return null;
  }

  // ── Stage 7: Merchant Extraction ──────────────────────────────────

  static String _extractMerchant(String body, String? upiId, String txnType) {
    String? merchant;

    // Try bank-specific patterns first (higher accuracy)

    // 1. "Info: Payment to merchant" (HDFC style)
    merchant = _tryPattern(_merchantInfoPattern, body);
    if (merchant != null) return _cleanMerchantName(merchant);

    // 2. "for UPI-merchant@upi" (ICICI style)
    merchant = _tryPattern(_merchantForUpiPattern, body);
    if (merchant != null) return _cleanMerchantName(merchant);

    // 3. "You paid ₹X to Merchant" (GPay / PhonePe style)
    merchant = _tryPattern(_merchantYouPaidToPattern, body);
    if (merchant != null) return _cleanMerchantName(merchant);

    // 4. "₹X received from Person" (GPay / PhonePe style)
    merchant = _tryPattern(_merchantReceivedFromPattern, body);
    if (merchant != null) return _cleanMerchantName(merchant);

    // 5. "Money sent to merchant" pattern
    merchant = _tryPattern(_merchantMoneySentToPattern, body);
    if (merchant != null) return _cleanMerchantName(merchant);

    // 6. "by transfer to" (SBI style)
    merchant = _tryPattern(_merchantByTransferToPattern, body);
    if (merchant != null) return _cleanMerchantName(merchant);

    // 7. "at MERCHANT" pattern (generic)
    merchant = _tryPattern(_merchantAtPattern, body);
    if (merchant != null) return _cleanMerchantName(merchant);

    // 8. "paid to / sent to" for debits
    if (txnType == 'debit') {
      merchant = _tryPattern(_merchantToPattern, body);
      if (merchant != null) return _cleanMerchantName(merchant);
    }

    // 9. "received from" for credits
    if (txnType == 'credit') {
      merchant = _tryPattern(_merchantFromPattern, body);
      if (merchant != null) return _cleanMerchantName(merchant);
    }

    // 10. Fallback: use the UPI ID as merchant name
    if (upiId != null) {
      // Try to extract a readable name from UPI ID
      final localPart = upiId.split('@').first;
      // If it's a phone number, keep the full UPI ID
      if (RegExp(r'^\d{10}$').hasMatch(localPart)) return upiId;
      // Otherwise use the local part as name
      return _cleanMerchantName(localPart.replaceAll('.', ' '));
    }

    return 'Unknown';
  }

  static String? _tryPattern(RegExp pattern, String body) {
    final match = pattern.firstMatch(body);
    if (match == null) return null;
    final value = match.group(1)?.trim();
    if (value == null || value.length < 2) return null;
    // Reject if it's just a number (account number, not a name)
    if (RegExp(r'^\d+$').hasMatch(value)) return null;
    return value;
  }

  static String _cleanMerchantName(String name) {
    var cleaned = name
        // Remove trailing/leading punctuation and whitespace
        .replaceAll(RegExp(r'^[\s.,;:!?-]+|[\s.,;:!?-]+$'), '')
        // Collapse whitespace
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // If it's a UPI ID, keep as-is
    if (cleaned.contains('@')) return cleaned;

    // Remove common noise suffixes
    cleaned = cleaned
        .replaceAll(RegExp(r'\s+on$', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+from$', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+to$', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+ref$', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+via$', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+UPI$', caseSensitive: false), '')
        .trim();

    // Truncate overly long names
    if (cleaned.length > 60) cleaned = cleaned.substring(0, 60).trim();

    return cleaned.isEmpty ? 'Unknown' : cleaned;
  }

  // ── Stage 8: Reference ID Extraction ──────────────────────────────

  static String? _extractReferenceId(String body) {
    // Try patterns in order of specificity

    // 1. UPI Ref
    final upiRef = _upiRefPattern.firstMatch(body);
    if (upiRef != null) return upiRef.group(1);

    // 2. Axis Bank style: UPI/Name/Ref/ID
    final axisRef = _axisUpiRefPattern.firstMatch(body);
    if (axisRef != null) return axisRef.group(1);

    // 3. IMPS / NEFT / RTGS Ref
    final impsRef = _impsRefPattern.firstMatch(body);
    if (impsRef != null) return impsRef.group(1);

    // 4. Generic Ref / TxnId
    final genericRef = _refPattern.firstMatch(body);
    if (genericRef != null) return genericRef.group(1);

    return null;
  }

  // ── Stage 9: Account Tail ─────────────────────────────────────────

  static String? _extractAccountTail(String body) {
    final match = _accountPattern.firstMatch(body);
    if (match != null) return match.group(1);

    final altMatch = _accountAltPattern.firstMatch(body);
    return altMatch?.group(1);
  }

  // ── Stage 10: Date Extraction ─────────────────────────────────────

  /// Extract date from SMS body, preserving the time component from [smsTime].
  ///
  /// SMS bodies contain only the date (e.g., '21-05-2026') without time.
  /// The OS-level SMS timestamp [smsTime] has the accurate reception time,
  /// so we copy its hour/minute/second onto the extracted date.
  static DateTime? _extractDate(String body, DateTime smsTime) {
    // Try ISO format first (yyyy-mm-dd) — most unambiguous
    final isoMatch = _dateIso.firstMatch(body);
    if (isoMatch != null) {
      return _safeDate(
        int.parse(isoMatch.group(1)!),
        int.parse(isoMatch.group(2)!),
        int.parse(isoMatch.group(3)!),
        smsTime,
      );
    }

    // Colon-separated format: yyyy:mm:dd (Bank of Baroda style)
    final colonMatch = _dateColonYmd.firstMatch(body);
    if (colonMatch != null) {
      final dt = _safeDate(
        int.parse(colonMatch.group(1)!),
        int.parse(colonMatch.group(2)!),
        int.parse(colonMatch.group(3)!),
        smsTime,
      );
      if (dt != null) return dt;
    }

    // Try month name format (dd-Mon-yy or ddMonyyyy)
    final monthMatch = _dateMonthName.firstMatch(body);
    if (monthMatch != null) {
      final day = int.parse(monthMatch.group(1)!);
      final monthStr = monthMatch.group(2)!.substring(0, 3).toLowerCase();
      final month = _monthMap[monthStr];
      var year = int.parse(monthMatch.group(3)!);
      if (year < 100) year += 2000;
      if (month != null) {
        return _safeDate(year, month, day, smsTime);
      }
    }

    // Try numeric format (dd-mm-yy or dd/mm/yyyy)
    final numMatch = _dateDashSlash.firstMatch(body);
    if (numMatch != null) {
      final a = int.parse(numMatch.group(1)!);
      final b = int.parse(numMatch.group(2)!);
      var c = int.parse(numMatch.group(3)!);
      if (c < 100) c += 2000;

      // Indian SMS uses dd-mm-yyyy (not mm-dd-yyyy)
      if (a <= 31 && b <= 12) {
        return _safeDate(c, b, a, smsTime);
      }
      // Fallback: try mm-dd-yyyy if dd-mm fails
      if (b <= 31 && a <= 12) {
        return _safeDate(c, a, b, smsTime);
      }
    }

    return null;
  }

  /// Build a DateTime from extracted date components, preserving the time
  /// from [smsTime]. If [smsTime] falls on a different calendar day than
  /// the extracted date, the time is still copied — the date from the SMS
  /// body is authoritative for the day, but the OS timestamp's time is the
  /// most accurate source for hour/minute/second.
  static DateTime? _safeDate(int year, int month, int day, DateTime smsTime) {
    try {
      if (month < 1 || month > 12 || day < 1 || day > 31) return null;
      final dt = DateTime(
        year, month, day,
        smsTime.hour, smsTime.minute, smsTime.second,
      );
      // Reject dates more than 2 years in the future or 10 years in the past
      final now = DateTime.now();
      if (dt.isAfter(now.add(const Duration(days: 730)))) return null;
      if (dt.isBefore(now.subtract(const Duration(days: 3650)))) return null;
      return dt;
    } catch (e, stack) {
      AppLogger.debug(
        '[TransactionParser] Error parsing safe date: $e\n$stack',
      );
      return null;
    }
  }

  // ── Stage 11: Confidence Scoring ──────────────────────────────────

  static double _calculateConfidence({
    required double amount,
    required String txnType,
    required String bankName,
    required String merchantName,
    required String? upiId,
    required String? referenceId,
    required String smsBody,
  }) {
    double score = 0.3; // Base: we found amount + type = minimum viable

    // Bank identified → +0.1
    if (bankName != 'Unknown Bank') score += 0.1;

    // Merchant identified (not "Unknown") → +0.15
    if (merchantName != 'Unknown') score += 0.15;

    // UPI ID found → +0.15
    if (upiId != null) score += 0.15;

    // Reference ID found → +0.15
    if (referenceId != null) score += 0.15;

    // UPI keyword in body → +0.1
    if (_upiIndicator.hasMatch(smsBody)) score += 0.1;

    // Account number found → +0.05
    if (_accountPattern.hasMatch(smsBody) ||
        _accountAltPattern.hasMatch(smsBody)) {
      score += 0.05;
    }

    return score.clamp(0.0, 1.0);
  }
}
