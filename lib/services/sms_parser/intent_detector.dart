/// Intent detection module — determines whether an SMS describes a
/// completed financial transaction (debit or credit) and classifies
/// the transaction sub-type.
///
/// ## Design
/// Intent detection runs AFTER negative filters and BEFORE amount
/// extraction. This is critical: we must confirm that the message
/// describes a completed money movement before extracting numbers.
///
/// A message like "Get cashback up to ₹500" has an amount but NO
/// transaction intent. Without intent-first detection, it would
/// become a false positive.
///
/// ## Signal Categories
/// - **Debit verbs**: debited, spent, paid, sent, deducted, withdrawn,
///   purchase, transferred, payment successful.
/// - **Credit verbs**: credited, received, deposited, refunded, cashback
///   (as completed action), reversed, added, settled.
/// - **Structural signals**: A/c XX1234, UPI Ref, IMPS, NEFT, RTGS, Txn ID.
/// - **Balance statements**: "Avl Bal" / "Available Balance" — supports
///   but doesn't create intent alone.
///
/// ## Combining Signals
/// Direction is determined by:
/// 1. Exclusive keyword: only debit OR only credit verbs → clear direction.
/// 2. Both present: positional precedence (first verb wins), UNLESS
///    refund/cashback/reversal overrides to credit.
/// 3. Structural signals boost confidence but don't determine direction.
///
/// ## Edge Cases Handled
/// - "Refund of Rs 200 debited" → "refund" overrides "debited" → CREDIT
/// - "Rs 500 debited, balance credited" → positional: debit first → DEBIT
/// - "UPI collect request accepted" → special handling → DEBIT (money left)
/// - "UPI collect request received" → PENDING (no money moved yet)
library;

import 'package:pet/services/sms_parser/transaction_parse_result.dart';

/// Result of intent detection analysis.
class IntentResult {
  /// Whether a transaction intent was detected.
  final bool hasIntent;

  /// Detected direction (debit/credit), or null if ambiguous/none.
  final TransactionDirection? direction;

  /// Transaction sub-type.
  final TransactionSubType subType;

  /// Transaction channel (UPI, NEFT, IMPS, etc.).
  final TransactionChannel channel;

  /// Reasons explaining the intent decision.
  final List<String> reasons;

  /// Whether this is a pending collect request (not yet completed).
  final bool isPendingCollect;

  const IntentResult({
    required this.hasIntent,
    this.direction,
    this.subType = TransactionSubType.unknown,
    this.channel = TransactionChannel.unknown,
    required this.reasons,
    this.isPendingCollect = false,
  });

  const IntentResult.none()
    : hasIntent = false,
      direction = null,
      subType = TransactionSubType.unknown,
      channel = TransactionChannel.unknown,
      reasons = const ['No transaction intent detected'],
      isPendingCollect = false;
}

/// Detects transaction intent in an SMS body.
///
/// Usage:
/// ```dart
/// final intent = IntentDetector.detect(smsBody);
/// if (!intent.hasIntent) {
///   return TransactionParseResult.rejected(reasons: intent.reasons);
/// }
/// ```
class IntentDetector {
  IntentDetector._();

  // ═══════════════════════════════════════════════════════════════════
  //  DEBIT KEYWORD PATTERNS
  // ═══════════════════════════════════════════════════════════════════

  /// Exhaustive list of debit intent verbs/phrases found in Indian bank SMS.
  ///
  /// Regex design:
  /// - Word boundaries (\b) prevent partial matches ("credited" ≠ "debit")
  /// - Optional suffixes handle tense variants ("purchase" / "purchased")
  /// - Phrase patterns ("payment successful") catch UPI app confirmations
  ///
  /// No backtracking risk: all alternatives use \b anchors and fixed text.
  static final RegExp debitKeywords = RegExp(
    r'(?:'
    r'\b(?:'
    r'debited|debit(?:ed)?|'
    r'spent|'
    r'paid|'
    r'purchase[d]?|'
    r'withdrawn|'
    r'sent\s+to|'
    r'deducted|'
    r'transferred|'
    r'money\s+sent|'
    r'you\s+paid|'
    r'txn\s+of|'
    r'paying|'
    r'paid\s+to|'
    r'auto.?pay|'
    r'emi\s+(?:paid|debited|deducted)|'
    r'used\s+(?:for|at)|'
    r'card\s+(?:txn|transaction)|'
    r'swip(?:ed|e)\s+at'
    r')\b|'
    r'\b(?:sent|charged|transaction\s+of)\s+(?:Rs\.?|INR|₹)|'
    r'\bpayment\s+(?:successful|made|done|completed|processed)|'
    r'\bdr\.|'
    r'(?:^|[\s\p{P}\W])(?:निकासी|नामे|भुगतान|कटौती|खाते\s+से|भेजा)(?=$|[\s\p{P}\W])'
    r')',
    caseSensitive: false,
    unicode: true,
  );

  // ═══════════════════════════════════════════════════════════════════
  //  CREDIT KEYWORD PATTERNS
  // ═══════════════════════════════════════════════════════════════════

  /// Exhaustive list of credit intent verbs/phrases.
  ///
  /// Note on "cashback": We match "cashback" only when followed by
  /// credit-confirming context — "cashback credited" or "cashback of Rs X
  /// received". Standalone "cashback" could be promotional.
  static final RegExp creditKeywords = RegExp(
    r'(?:'
    r'\b(?:'
    r'credited|credit(?:ed)?|'
    r'received|'
    r'deposited?|'
    r'refund(?:ed)?|'
    r'cashback|cash\s*back|'
    r'reversed?|reversal|'
    r'added|'
    r'money\s+received|'
    r'payment\s+received|'
    r'settled|'
    r'reimburs(?:ed|ement)|'
    r'(?:amount|money)\s+credited'
    r')\b|'
    r'(?:^|[\s\p{P}\W])(?:जमा|प्राप्त|खाते\s+में|वापसी)(?=$|[\s\p{P}\W])'
    r')',
    caseSensitive: false,
    unicode: true,
  );

  // ═══════════════════════════════════════════════════════════════════
  //  SUB-TYPE PATTERNS
  // ═══════════════════════════════════════════════════════════════════

  /// Collect request patterns — these need special handling.
  /// "collect request" can be both debit (accepted) and pending (received).
  static final RegExp _collectAccepted = RegExp(
    r'collect\s*(?:request\s*)?.*?(?:accept|approv|paid|success)',
    caseSensitive: false,
  );

  static final RegExp _collectPending = RegExp(
    r'collect\s*(?:request\s*)?.*?(?:received|from|pending|raised)',
    caseSensitive: false,
  );

  static final RegExp _collectDeclined = RegExp(
    r'collect\s*(?:request\s*)?.*?(?:declin|reject|cancel|expir)',
    caseSensitive: false,
  );

  /// Refund patterns (always force credit direction).
  static final RegExp _refundPattern = RegExp(
    r'\brefund(?:ed)?\b|\breversal\b|\breversed\b|\bcharge\s*back\b',
    caseSensitive: false,
  );

  /// Cashback patterns (always force credit direction).
  static final RegExp _cashbackPattern = RegExp(
    r'\bcashback\b|\bcash\s*back\b',
    caseSensitive: false,
  );

  /// IMPS/NEFT/RTGS patterns (transfer sub-type if no UPI indicator).
  static final RegExp _impsNeftRtgs = RegExp(
    r'\b(?:IMPS|NEFT|RTGS)\b',
    caseSensitive: false,
  );

  /// UPI indicator.
  static final RegExp _upiIndicator = RegExp(
    r'\bUPI\b|@[a-zA-Z]{2,}',
    caseSensitive: false,
  );

  // ═══════════════════════════════════════════════════════════════════
  //  STRUCTURAL SIGNAL PATTERNS
  // ═══════════════════════════════════════════════════════════════════

  /// Account number patterns — strong signal that SMS is financial.
  /// Matches: A/c XX1234, Acct XX9876, Account ending 5678, card **1234
  static final RegExp accountPattern = RegExp(
    r'\b(?:A\/?c|Acct|Account|AC|card)\b\s*(?:no\.?\s*)?(?:ending\s+)?[*xX]+\s*\d{3,6}',
    caseSensitive: false,
  );

  /// Reference ID pattern — very strong signal.
  /// Matches: UPI Ref 12345, Ref No 12345, Txn ID 12345, IMPS Ref 12345
  static final RegExp referencePattern = RegExp(
    r'(?:UPI\s*)?(?:Ref|Txn|Transaction)\s*(?:No\.?\s*|ID\s*)?[:.]?\s*\d{6,16}',
    caseSensitive: false,
  );

  /// Balance mention — supporting signal but NOT sufficient alone.
  /// "Balance: Rs 5000" confirms financial context but doesn't prove
  /// a transaction happened.
  static final RegExp balancePattern = RegExp(
    r'(?:avl\.?|available|remaining|current|closing|total)\s*(?:bal(?:ance)?|bal\.?)',
    caseSensitive: false,
  );

  /// Currency indicator — required minimum for any financial SMS.
  static final RegExp currencyPattern = RegExp(
    r'(?:Rs\.?\s*|INR\.?\s*|₹\s?)\d',
    caseSensitive: false,
  );

  // ═══════════════════════════════════════════════════════════════════
  //  CHANNEL DETECTION PATTERNS
  // ═══════════════════════════════════════════════════════════════════

  /// Card-specific patterns — POS, ATM, credit/debit card keywords.
  static final RegExp _cardIndicator = RegExp(
    r'\b(?:'
    r'card\s+(?:ending|no\.?|xx|\*\*)|'
    r'credit\s+card|'
    r'debit\s+card|'
    r'(?:pos|ecom)\s+(?:txn|transaction|purchase)|'
    r'atm\s+(?:withdrawal|cash|txn)|'
    r'swip(?:ed|e)\s+at|'
    r'card\s+used|'
    r'merchant\s+(?:pos|terminal)|'
    r'pos\s+\d'
    r')\b',
    caseSensitive: false,
  );

  /// Wallet-specific patterns.
  static final RegExp _walletIndicator = RegExp(
    r'\b(?:wallet|paytm\s+wallet|mobikwik|freecharge|phonepe\s+wallet)\b',
    caseSensitive: false,
  );

  /// Pure payment reminder patterns — messages containing these without
  /// completed execution verbs (debited, spent, paid to, credited, swiped, charged)
  /// are reminders for future/pending payments, not completed transactions.
  static final RegExp pureReminderPattern = RegExp(
    r'(?:'
    r'\b(?:is|are)\s+due\b|'
    r'\bdue\s+(?:date|by|on|amount)\b|'
    r'\b(?:payment|bill|emi|installment|dues?)\s+(?:due|reminder|pending|overdue)\b|'
    r'\breminder\s*[:|-]?\s*(?:to\s*)?(?:pay|for)?\b|'
    r'\boverdue\b|'
    r'\bmin(?:imum)?\s*amt\s*due\b|'
    r'\btotal\s*dues?\b|'
    r'\bpay\s*(?:your|the)\s*(?:bill|dues?|amount)\s*(?:by|before|on)\b'
    r')',
    caseSensitive: false,
  );

  /// Completed execution verbs required to override a pure reminder phrase.
  /// Note: avoids bare "credit" or "debit" which would falsely match "credit card" or "debit card".
  static final RegExp completedExecutionVerbs = RegExp(
    r'\b(?:debited|debit\s+(?:of|from|a/c|account)|credited|credit\s+(?:of|to|into|a/c|account)|spent|paid\s+to|you\s+paid|swip(?:ed|e)|charged|transferred|withdrawn|refunded|reversed|dr\.|cr\.)\b',
    caseSensitive: false,
  );

  // ═══════════════════════════════════════════════════════════════════
  //  PUBLIC API
  // ═══════════════════════════════════════════════════════════════════

  /// Detect transaction intent in an SMS body.
  ///
  /// Returns [IntentResult] with:
  /// - [hasIntent] = true if a completed transaction is described
  /// - [direction] = debit or credit
  /// - [subType] = payment, refund, cashback, collect, transfer
  /// - [reasons] = explanation of each signal found
  static IntentResult detect(String body) {
    final reasons = <String>[];

    // ── Step 1: Currency check ───────────────────────────────────
    // Without a currency indicator, it can't be a financial transaction.
    if (!currencyPattern.hasMatch(body)) {
      return const IntentResult.none();
    }

    // ── Step 1.5: Pure Payment Reminder check ───────────────────
    // Messages that express bill/EMI due dates without completed execution
    // verbs are reminders, NOT completed financial transactions.
    if (pureReminderPattern.hasMatch(body) &&
        !completedExecutionVerbs.hasMatch(body)) {
      return const IntentResult(
        hasIntent: false,
        reasons: [
          'Pure payment reminder/due notice without completed transaction execution verb',
        ],
      );
    }

    // ── Step 2: Check for collect request special cases ──────────
    final collectResult = _handleCollectRequest(body, reasons);
    if (collectResult != null) return collectResult;

    // ── Step 3: Find debit and credit keywords ───────────────────
    final debitMatch = debitKeywords.firstMatch(body);
    final creditMatch = creditKeywords.firstMatch(body);
    final hasDebit = debitMatch != null;
    final hasCredit = creditMatch != null;

    if (hasDebit) {
      reasons.add(
        'Debit keyword "${debitMatch.group(0)}" at position ${debitMatch.start}',
      );
    }
    if (hasCredit) {
      reasons.add(
        'Credit keyword "${creditMatch.group(0)}" at position ${creditMatch.start}',
      );
    }

    // ── Step 4: Determine direction ──────────────────────────────
    TransactionDirection? direction;

    if (hasDebit && !hasCredit) {
      direction = TransactionDirection.debit;
      reasons.add('Direction: DEBIT (exclusive debit keyword)');
    } else if (hasCredit && !hasDebit) {
      direction = TransactionDirection.credit;
      reasons.add('Direction: CREDIT (exclusive credit keyword)');
    } else if (hasDebit && hasCredit) {
      // Both present — check for overrides first
      if (_refundPattern.hasMatch(body)) {
        direction = TransactionDirection.credit;
        reasons.add(
          'Direction: CREDIT (refund/reversal overrides debit keyword)',
        );
      } else if (_cashbackPattern.hasMatch(body)) {
        direction = TransactionDirection.credit;
        reasons.add('Direction: CREDIT (cashback overrides debit keyword)');
      } else {
        // Positional precedence: whichever keyword appears first
        final debitPos = debitMatch.start;
        final creditPos = creditMatch.start;
        if (debitPos < creditPos) {
          direction = TransactionDirection.debit;
          reasons.add(
            'Direction: DEBIT (debit at pos $debitPos before credit at pos $creditPos)',
          );
        } else {
          direction = TransactionDirection.credit;
          reasons.add(
            'Direction: CREDIT (credit at pos $creditPos before debit at pos $debitPos)',
          );
        }
      }
    } else {
      // No debit or credit keywords
      reasons.add('No debit/credit keywords found — no transaction intent');
      return IntentResult(hasIntent: false, reasons: reasons);
    }

    // ── Step 5: Classify sub-type ────────────────────────────────
    final subType = _classifySubType(body, direction, reasons);

    // ── Step 5b: Detect transaction channel ──────────────────────
    final channel = detectChannel(body, reasons);

    // ── Step 6: Add structural signal info ───────────────────────
    if (accountPattern.hasMatch(body)) {
      reasons.add('Structural: Account number pattern found');
    }
    if (referencePattern.hasMatch(body)) {
      reasons.add('Structural: Reference/transaction ID found');
    }
    if (balancePattern.hasMatch(body)) {
      reasons.add('Structural: Balance mention found (supporting signal)');
    }

    return IntentResult(
      hasIntent: true,
      direction: direction,
      subType: subType,
      channel: channel,
      reasons: reasons,
    );
  }

  /// Special handling for UPI collect requests.
  ///
  /// Collect request semantics:
  /// - "Collect request accepted/paid" → DEBIT (money left your account)
  /// - "Collect request received/from" → PENDING (no money moved yet)
  /// - "Collect request declined/rejected" → NOT A TRANSACTION
  static IntentResult? _handleCollectRequest(
    String body,
    List<String> reasons,
  ) {
    if (_collectDeclined.hasMatch(body)) {
      reasons.add('UPI collect request declined/rejected — not a transaction');
      return IntentResult(hasIntent: false, reasons: reasons);
    }

    if (_collectAccepted.hasMatch(body)) {
      reasons.add('UPI collect request accepted — DEBIT (money sent)');
      return IntentResult(
        hasIntent: true,
        direction: TransactionDirection.debit,
        subType: TransactionSubType.collect,
        channel: TransactionChannel.upi,
        reasons: reasons,
      );
    }

    if (_collectPending.hasMatch(body)) {
      reasons.add('UPI collect request received — PENDING (no money moved)');
      return IntentResult(
        hasIntent: false,
        isPendingCollect: true,
        reasons: reasons,
      );
    }

    return null; // Not a collect request
  }

  /// Classify transaction sub-type.
  static TransactionSubType _classifySubType(
    String body,
    TransactionDirection direction,
    List<String> reasons,
  ) {
    if (_refundPattern.hasMatch(body)) {
      reasons.add('Sub-type: REFUND');
      return TransactionSubType.refund;
    }
    if (_cashbackPattern.hasMatch(body)) {
      reasons.add('Sub-type: CASHBACK');
      return TransactionSubType.cashback;
    }
    if (_impsNeftRtgs.hasMatch(body)) {
      if (_upiIndicator.hasMatch(body)) {
        reasons.add('Sub-type: PAYMENT (IMPS/NEFT via UPI)');
        return TransactionSubType.payment;
      }
      reasons.add('Sub-type: TRANSFER (IMPS/NEFT/RTGS)');
      return TransactionSubType.transfer;
    }
    reasons.add('Sub-type: PAYMENT (default)');
    return TransactionSubType.payment;
  }

  /// Check if a body contains any transaction intent keywords at all.
  /// Quick check for pre-filtering (cheaper than full [detect]).
  static bool hasAnyIntent(String body) {
    return debitKeywords.hasMatch(body) || creditKeywords.hasMatch(body);
  }

  // ═══════════════════════════════════════════════════════════════════
  //  CHANNEL DETECTION
  // ═══════════════════════════════════════════════════════════════════

  /// Detect the transaction channel from SMS body keywords.
  ///
  /// Priority order (most specific first):
  /// 1. Card (POS, ATM, card ending) — most specific indicators
  /// 2. RTGS — usually for large transfers
  /// 3. NEFT — common bank transfer
  /// 4. IMPS — common instant transfer
  /// 5. Wallet — paytm wallet, mobikwik
  /// 6. UPI — VPA patterns, UPI keyword
  /// 7. Unknown — fallback
  static TransactionChannel detectChannel(String body, List<String> reasons) {
    if (_cardIndicator.hasMatch(body)) {
      reasons.add('Channel: CARD (card/POS/ATM indicator)');
      return TransactionChannel.card;
    }
    if (RegExp(r'\bRTGS\b', caseSensitive: false).hasMatch(body)) {
      reasons.add('Channel: RTGS');
      return TransactionChannel.rtgs;
    }
    if (RegExp(r'\bNEFT\b', caseSensitive: false).hasMatch(body)) {
      reasons.add('Channel: NEFT');
      return TransactionChannel.neft;
    }
    if (RegExp(r'\bIMPS\b', caseSensitive: false).hasMatch(body)) {
      reasons.add('Channel: IMPS');
      return TransactionChannel.imps;
    }
    if (_walletIndicator.hasMatch(body)) {
      reasons.add('Channel: WALLET');
      return TransactionChannel.wallet;
    }
    if (_upiIndicator.hasMatch(body)) {
      reasons.add('Channel: UPI');
      return TransactionChannel.upi;
    }
    return TransactionChannel.unknown;
  }
}
