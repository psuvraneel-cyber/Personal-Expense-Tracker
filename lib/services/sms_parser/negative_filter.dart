/// Negative filter module — multi-layer rejection engine for promotional,
/// scam, OTP, and non-transactional SMS.
///
/// ## Design Principles
/// - **Fail-fast**: Cheapest checks first (sender prefix → keyword → URL).
/// - **Independent rules**: Each filter is a separate method returning a
///   nullable rejection reason string. `null` = pass, `String` = reject.
/// - **Extensible**: Add new filters by adding a method and registering it
///   in [allFilters]. No core code changes needed.
/// - **Explainable**: Every rejection produces a human-readable reason.
///
/// ## Sender Prefix Conventions (TRAI India)
/// - `AD-` / `TA-` → Transactional (banks, UPI apps)
/// - `VM-` / `VD-` → Transactional after DND (banks to DND users)
/// - `VK-` / `VN-` / `HP-` / `TD-` / `BZ-` → Promotional
/// - Numeric senders (e.g., `+919876543210`) → Unknown, need body analysis
///
/// ## Performance
/// Each filter is O(n) in body length (single regex scan). Total for all
/// filters ≈ 12 regex scans, each with non-backtracking alternation.
/// Benchmarked at <0.2ms per SMS on mid-range Android (2023).
library;

/// Result of running negative filters on an SMS.
class NegativeFilterResult {
  /// Whether the message was rejected by a filter.
  final bool rejected;

  /// Human-readable reason for rejection, or null if not rejected.
  final String? reason;

  /// Which filter triggered the rejection.
  final String? filterName;

  /// Sender trust level determined during filtering.
  final SenderTrust senderTrust;

  const NegativeFilterResult.pass({required this.senderTrust})
    : rejected = false,
      reason = null,
      filterName = null;

  const NegativeFilterResult.reject({
    required this.reason,
    required this.filterName,
    required this.senderTrust,
  }) : rejected = true;
}

/// Trust level inferred from the SMS sender ID.
///
/// TRAI (Telecom Regulatory Authority of India) mandates sender ID
/// prefixes for commercial SMS:
/// - Transactional headers start with AD-, TA-, VM-, VD- (bank alerts)
/// - Promotional headers start with VK-, VN-, HP-, TD-, BZ- (marketing)
/// - Personal numbers (+91...) have no TRAI header
enum SenderTrust {
  /// Known transactional prefix (AD-, TA-, VM-, VD-).
  /// High trust — likely a bank or UPI app.
  transactional,

  /// Known promotional prefix (VK-, VN-, HP-, TD-, BZ-).
  /// Low trust — likely marketing. Must pass strict body filters.
  promotional,

  /// Numeric sender or unrecognized prefix.
  /// Medium trust — requires body analysis.
  unknown,
}

/// Multi-layer negative filter engine.
///
/// Usage:
/// ```dart
/// final result = NegativeFilter.apply(smsBody, sender);
/// if (result.rejected) {
///   // Skip this SMS — result.reason explains why
/// }
/// ```
class NegativeFilter {
  NegativeFilter._();

  // ═══════════════════════════════════════════════════════════════════
  //  SENDER TRUST CLASSIFICATION
  // ═══════════════════════════════════════════════════════════════════

  /// TRAI transactional prefixes. These senders are trusted by default.
  /// AD = After DND (transactional), TA = Transactional,
  /// VM/VD = Voice/Data DND exemption (banks).
  static final RegExp _transactionalPrefixes = RegExp(
    r'^(?:AD|TA|VM|VD)-',
    caseSensitive: false,
  );

  /// Known transactional app sender IDs (not TRAI-prefixed but trusted).
  /// Truecaller relays bank transaction SMS with its own sender ID.
  static final RegExp _trustedAppSenders = RegExp(
    r'TRUCLR|TRUCAL|TRUECL|TRUECALLER',
    caseSensitive: false,
  );

  /// TRAI promotional prefixes. Messages from these senders are likely
  /// marketing/offers and need strong positive signals to be accepted.
  ///
  /// VK = Voice Key promotional, VN = Voice Non-DND promo,
  /// HP = Header Promotional, TD = Telemarketer Direct,
  /// BZ = Business promotional.
  static final RegExp _promotionalPrefixes = RegExp(
    r'^(?:VK|VN|HP|TD|BZ)-',
    caseSensitive: false,
  );

  /// Classify sender trust level from the sender ID.
  static SenderTrust classifySender(String sender) {
    final s = sender.trim().toUpperCase();
    if (_transactionalPrefixes.hasMatch(s)) return SenderTrust.transactional;
    if (_trustedAppSenders.hasMatch(s)) return SenderTrust.transactional;
    if (_promotionalPrefixes.hasMatch(s)) return SenderTrust.promotional;
    return SenderTrust.unknown;
  }

  // ═══════════════════════════════════════════════════════════════════
  //  CORE NEGATIVE FILTERS
  // ═══════════════════════════════════════════════════════════════════

  /// Run all negative filters in order. Returns on first rejection.
  ///
  /// Filter order is optimized for early exit:
  /// 1. Length check (instant)
  /// 2. OTP filter (most common non-transaction from bank senders)
  /// 3. Sender-based promo filter (cheap prefix check)
  /// 4. Scam/contest filter (high-confidence rejection)
  /// 5. Promotional keyword filter (broad)
  /// 6. URL/link filter for promotional context
  /// 7. Loan/insurance offer filter
  /// 8. KYC/update filter
  /// 9. App download/install filter
  /// 10. Card offer filter
  /// 11. Mandate/autopay setup filter (not a completed transaction)
  /// 12. Balance-only filter (informational, not transactional)
  static NegativeFilterResult apply(
    String body,
    String sender, {
    bool hasCompletedTransaction = false,
  }) {
    final senderTrust = classifySender(sender);

    // ── Filter 1: Minimum length ─────────────────────────────────
    // Real bank transaction SMS are ≥40 characters.  Shorter messages
    // are noise (delivery reports, status codes).
    if (body.length < 35) {
      return NegativeFilterResult.reject(
        reason: 'Message too short (${body.length} chars < 35 minimum)',
        filterName: 'length_check',
        senderTrust: senderTrust,
      );
    }

    // ── Filter 2: OTP / security code ────────────────────────────
    // OTP messages from banks contain amounts but are NOT transactions.
    // These are the #1 source of false positives from trusted senders.
    final otpReason = _checkOtp(body);
    if (otpReason != null) {
      return NegativeFilterResult.reject(
        reason: otpReason,
        filterName: 'otp_filter',
        senderTrust: senderTrust,
      );
    }

    // ── Filter 3: Promotional sender + no strong intent ──────────
    if (senderTrust == SenderTrust.promotional) {
      final promoReason = _checkPromotionalSender(body);
      if (promoReason != null) {
        return NegativeFilterResult.reject(
          reason: promoReason,
          filterName: 'promo_sender_filter',
          senderTrust: senderTrust,
        );
      }
    }

    // ── Filter 4: Scam / contest / prize ─────────────────────────
    final scamReason = _checkScam(body);
    if (scamReason != null) {
      return NegativeFilterResult.reject(
        reason: scamReason,
        filterName: 'scam_filter',
        senderTrust: senderTrust,
      );
    }

    // ── Filter 5: Promotional keywords ───────────────────────────
    final promoReason = _checkPromoKeywords(body);
    if (promoReason != null) {
      return NegativeFilterResult.reject(
        reason: promoReason,
        filterName: 'promo_keyword_filter',
        senderTrust: senderTrust,
      );
    }

    // ── Filter 6: Suspicious URLs ────────────────────────────────
    final urlReason = _checkSuspiciousUrl(body);
    if (urlReason != null) {
      return NegativeFilterResult.reject(
        reason: urlReason,
        filterName: 'url_filter',
        senderTrust: senderTrust,
      );
    }

    // ── Filter 7: Loan / insurance offer ─────────────────────────
    final loanReason = _checkLoanInsurance(body);
    if (loanReason != null) {
      return NegativeFilterResult.reject(
        reason: loanReason,
        filterName: 'loan_insurance_filter',
        senderTrust: senderTrust,
      );
    }

    // ── Filter 8: KYC / account update ───────────────────────────
    final kycReason = _checkKycUpdate(body);
    if (kycReason != null) {
      return NegativeFilterResult.reject(
        reason: kycReason,
        filterName: 'kyc_update_filter',
        senderTrust: senderTrust,
      );
    }

    // ── Filter 9: App download / install ─────────────────────────
    final appReason = _checkAppDownload(body);
    if (appReason != null) {
      return NegativeFilterResult.reject(
        reason: appReason,
        filterName: 'app_download_filter',
        senderTrust: senderTrust,
      );
    }

    // ── Filter 10: Credit/debit card offer ───────────────────────
    final cardReason = _checkCardOffer(body);
    if (cardReason != null) {
      return NegativeFilterResult.reject(
        reason: cardReason,
        filterName: 'card_offer_filter',
        senderTrust: senderTrust,
      );
    }

    // ── Filter 11: Mandate/autopay SETUP ─────────────────────────
    final mandateReason = _checkMandateSetup(body);
    if (mandateReason != null) {
      return NegativeFilterResult.reject(
        reason: mandateReason,
        filterName: 'mandate_setup_filter',
        senderTrust: senderTrust,
      );
    }

    // ── Filter 12: Overdue / EMI reminder ────────────────────────
    // "Loan overdue: Pay ₹15,000 by 20-Feb" — a pure reminder, not a
    // completed transaction.
    //
    // CRITICAL: Reminder detection executes ONLY IF the SMS has NOT
    // already been classified as a completed financial transaction.
    // Legitimate credit card transactions from HDFC, ICICI, Axis, SBI, etc.
    // often contain footer text like "Pay your bill by 10-AUG-26".
    final reminderReason = _checkPaymentReminder(
      body,
      hasCompletedTransaction: hasCompletedTransaction,
    );
    if (reminderReason != null) {
      return NegativeFilterResult.reject(
        reason: reminderReason,
        filterName: 'reminder_filter',
        senderTrust: senderTrust,
      );
    }

    // All filters passed
    return NegativeFilterResult.pass(senderTrust: senderTrust);
  }

  // ═══════════════════════════════════════════════════════════════════
  //  INDIVIDUAL FILTER IMPLEMENTATIONS
  // ═══════════════════════════════════════════════════════════════════

  /// Filter 2: OTP / security code detection.
  ///
  /// Regex explanation:
  /// - `\bOTP\b` — literal "OTP" as a word
  /// - `one.?time\s*password` — "one time password", "one-time password"
  /// - `\bCVV\b` — card verification value
  /// - `\b[MT]?PIN\b` — PIN, MPIN (mobile PIN), TPIN (transaction PIN)
  /// - `verif(?:y|ication)\s*(?:code|number)` — "verification code"
  /// - `security\s*code` — ATM/card security code
  /// - `\bpasscode\b` — generic passcode
  ///
  /// No backtracking risk: all alternatives are anchored with \b or
  /// fixed prefixes. Alternation is O(n) worst case.
  static final RegExp _otpPattern = RegExp(
    r'\bOTP\b|one.?time\s*password|'
    r'\bCVV\b|\b[MT]?PIN\b|'
    r'verif(?:y|ication)\s*(?:code|number)?|'
    r'security\s*code|\bpasscode\b|'
    r'do\s*not\s*share\s*(?:this|your|the)?\s*(?:OTP|code|password)',
    caseSensitive: false,
  );

  static String? _checkOtp(String body) {
    final match = _otpPattern.firstMatch(body);
    if (match != null) {
      return 'OTP/security code detected: "${match.group(0)}"';
    }
    return null;
  }

  /// Filter 3: Promotional sender without strong transaction signals.
  ///
  /// A promotional sender (VK-PAYTM, HP-HDFCBK) is allowed through
  /// ONLY if the body contains definitive transaction evidence:
  /// - Both a currency amount AND a debit/credit verb
  /// - AND a reference ID or account number
  ///
  /// This is deliberately strict — promotional senders sending real
  /// transaction alerts is rare (banks use AD-/VM- for those).
  static final RegExp _strongTransactionSignal = RegExp(
    r'(?:debited|credited|paid|received|sent)\b.*(?:Ref|UPI|IMPS|A/c|Acct)',
    caseSensitive: false,
  );

  static String? _checkPromotionalSender(String body) {
    if (_strongTransactionSignal.hasMatch(body)) {
      return null; // Strong signal overrides promotional sender
    }
    return 'Promotional sender prefix without strong transaction signals';
  }

  /// Filter 4: Scam / contest / prize detection.
  ///
  /// Pattern targets:
  /// - "congratulations" — contest/prize bait
  /// - "you have won" / "you've won" — fake prize
  /// - "lucky winner" / "selected" — lottery scam
  /// - "claim your" / "claim now" — action bait
  /// - "prize" / "reward" / "bonus" (without "cashback credited" context)
  /// - "call now to claim" — phone scam
  ///
  /// Performance: Simple alternation, no quantifiers on capture groups,
  /// no backtracking risk.
  static final RegExp _scamPattern = RegExp(
    r'congratulat(?:ions|e)|'
    r"you\s*(?:have\s*)?(?:'ve\s*)?won\b|"
    r'lucky\s*(?:winner|draw|customer)|'
    r'claim\s*(?:your|now|the|this)|'
    r'\bprize\b|'
    r'selected\s*(?:for|as)\s*(?:a\s*)?(?:winner|reward)|'
    r'call\s*(?:now\s*)?(?:to\s*)?claim|'
    r'wire\s*transfer.*(?:million|lakh|crore)',
    caseSensitive: false,
  );

  static String? _checkScam(String body) {
    final match = _scamPattern.firstMatch(body);
    if (match != null) {
      return 'Scam/contest pattern detected: "${match.group(0)}"';
    }
    return null;
  }

  /// Filter 5: Promotional keyword detection.
  ///
  /// These keywords indicate marketing intent, NOT a completed transaction.
  ///
  /// Why each keyword:
  /// - "offer" / "limited time/period" — time-pressure marketing
  /// - "discount" / "% off" / "cashback up to" — promotional pricing
  /// - "apply now" / "sign up" / "register now" — call-to-action
  /// - "subscribe" / "unsubscribe" — mailing list
  /// - "voucher" / "coupon" — promotional codes
  /// - "free" + "trial/credit/delivery" — freemium bait
  /// - "SPAM" — self-labeled spam
  /// - "exclusive" + "deal/offer" — urgency marketing
  ///
  /// EXCEPTION: "cashback" alone is NOT filtered here because
  /// "Rs 50 cashback credited" IS a valid transaction. The filter
  /// targets "cashback up to ₹100" which is promotional.
  static final RegExp _promoKeywordPattern = RegExp(
    r'\boffer\s*(?:for|on|of|!)|\blimited\s*(?:time|period)|'
    r'(?:get|earn|win|avail)\s*(?:up\s*to|flat)\s*(?:Rs\.?|INR|₹)|'
    r'%\s*(?:off|discount|cashback)|'
    r'apply\s*now|sign\s*up|register\s*now|'
    r'\bunsubscri|\bSPAM\b|'
    r'\bvoucher\b|\bcoupon\b|'
    r'free\s*(?:trial|credit|delivery)|'
    r'exclusive\s*(?:deal|offer)|'
    r'use\s*(?:code|coupon|promo)|'
    r'shop\s*(?:now|today)|'
    r'hurry\b.*(?:offer|sale|deal)|'
    r'last\s*(?:day|chance|few)',
    caseSensitive: false,
  );

  static String? _checkPromoKeywords(String body) {
    final match = _promoKeywordPattern.firstMatch(body);
    if (match != null) {
      // Bypass: if the body has strong transaction evidence (debit/credit
      // verb + reference ID), allow it through despite promo keywords.
      // Example: "Rs 500 debited... offer cashback... UPI Ref 12345"
      if (_txnWithRef.hasMatch(body)) return null;
      return 'Promotional keyword detected: "${match.group(0)}"';
    }
    return null;
  }

  /// Filter 6: Suspicious URL detection.
  ///
  /// Real bank transaction SMS rarely contain URLs. Promotional SMS
  /// almost always do. This filter rejects messages with:
  /// - http:// or https:// links
  /// - bit.ly / tinyurl / goo.gl / short URLs
  /// - "click here" / "tap here" / "visit" language
  ///
  /// EXCEPTION: Messages with BOTH a URL AND strong transaction signals
  /// (debit/credit + ref) are allowed through, because some banks include
  /// "Report fraud at https://bank.com" in transaction alerts.
  ///
  /// Failure mode: A bank that puts tracking URLs in every transaction
  /// SMS would be rejected. Mitigation: user can create a dynamic rule.
  static final RegExp _urlPattern = RegExp(
    r'https?://|bit\.ly/|tinyurl|goo\.gl/|'
    r'click\s*(?:here|link|on|below)|tap\s*(?:here|link|on|below)|'
    r'visit\s+(?:https?|www|our)',
    caseSensitive: false,
  );

  /// Strong transaction evidence (debited/credited + reference) that
  /// overrides URL-based rejection.
  static final RegExp _txnWithRef = RegExp(
    r'(?:debited|credited|paid|received)\b.*(?:Ref|UPI\s*Ref|Txn\s*ID)',
    caseSensitive: false,
  );

  static String? _checkSuspiciousUrl(String body) {
    if (!_urlPattern.hasMatch(body)) return null;

    // Allow if there's strong transaction evidence alongside the URL
    if (_txnWithRef.hasMatch(body)) return null;

    final match = _urlPattern.firstMatch(body);
    return 'Suspicious URL/link in message: "${match!.group(0)}"';
  }

  /// Filter 7: Loan / insurance / investment offer.
  ///
  /// "Pre-approved loan of Rs 5,00,000" and "Insurance cover of Rs 50L"
  /// contain large amounts but are marketing, not transactions.
  ///
  /// Why each pattern:
  /// - "pre-approved" + "loan/credit" — unsolicited loan offers
  /// - "loan" + "offer/of/eligib" — loan marketing
  /// - "insurance" + "cover/plan/premium" — insurance push
  /// - "mutual fund" / "invest" + "now/today" — investment marketing
  /// - "EMI" + "starts/available/as low" — financing marketing
  /// - "credit limit" + "increased/enhanced" — limit change notification
  static final RegExp _loanInsurancePattern = RegExp(
    r'(?:pre.?)?approv(?:ed|al)\s*(?:for\s*)?(?:loan|credit|limit)|'
    r'\bloan\s*(?:of(?:fer)?|eligib|amount|disburse)|'
    r'insurance\s*(?:cover|plan|premium|policy)|'
    r'mutual\s*fund|'
    r'(?:invest|trading)\s*(?:now|today|in)|'
    r'EMI\s*(?:start|availab|as\s*low|from\s*Rs)|'
    r'credit\s*limit\s*(?:increas|enhanc|upgrad)',
    caseSensitive: false,
  );

  static String? _checkLoanInsurance(String body) {
    final match = _loanInsurancePattern.firstMatch(body);
    if (match != null) {
      return 'Loan/insurance offer detected: "${match.group(0)}"';
    }
    return null;
  }

  /// Filter 8: KYC / account update notification.
  ///
  /// "Update your KYC" messages are compliance notifications,
  /// not transactions. They sometimes mention "Rs 0" charges.
  static final RegExp _kycPattern = RegExp(
    r'KYC\s*(?:update|expir|pending|mandatory|verif|complet)|'
    r'update\s*(?:your\s*)?KYC|'
    r'(?:PAN|Aadhaar)\s*(?:link|update|verif)|'
    r'account\s*(?:will\s*be\s*)?(?:block|freez|suspend|restrict)',
    caseSensitive: false,
  );

  static String? _checkKycUpdate(String body) {
    final match = _kycPattern.firstMatch(body);
    if (match != null) {
      return 'KYC/account update notification: "${match.group(0)}"';
    }
    return null;
  }

  /// Filter 9: App download / install push.
  static final RegExp _appDownloadPattern = RegExp(
    r'download\s*(?:the\s*)?(?:app|now)|'
    r'install\s*(?:the\s*)?(?:app|now)|'
    r'available\s*on\s*(?:Play\s*Store|App\s*Store|Google\s*Play)',
    caseSensitive: false,
  );

  static String? _checkAppDownload(String body) {
    final match = _appDownloadPattern.firstMatch(body);
    if (match != null) {
      return 'App download/install push: "${match.group(0)}"';
    }
    return null;
  }

  /// Filter 10: Credit/debit card offer/eligibility.
  ///
  /// "You are eligible for HDFC Diners Club" — marketing, not transaction.
  static final RegExp _cardOfferPattern = RegExp(
    r'(?:credit|debit)\s*card\s*(?:offer|apply|eligib|upgrade|activ)|'
    r'eligible\s*for\s*(?:a\s*)?(?:credit|debit)\s*card|'
    r'card\s*(?:upgrade|activation)\s*(?:offer|available)',
    caseSensitive: false,
  );

  static String? _checkCardOffer(String body) {
    final match = _cardOfferPattern.firstMatch(body);
    if (match != null) {
      return 'Card offer/eligibility: "${match.group(0)}"';
    }
    return null;
  }

  /// Filter 11: Mandate / autopay SETUP (not execution).
  ///
  /// "Mandate creation successful" means a future payment was authorized,
  /// not that money moved. Actual mandate executions use "debited" and
  /// will pass through as regular debit transactions.
  static final RegExp _mandateSetupPattern = RegExp(
    r'mandate\s*(?:creat|registr|setup|set\s*up|activ)|'
    r'auto.?(?:debit|pay)\s*(?:setup|registr|creat|activ)|'
    r'standing\s*instruction\s*(?:creat|registr|setup)',
    caseSensitive: false,
  );

  static String? _checkMandateSetup(String body) {
    final match = _mandateSetupPattern.firstMatch(body);
    if (match != null) {
      return 'Mandate/autopay setup (not a transaction): "${match.group(0)}"';
    }
    return null;
  }

  /// Filter 12: Payment reminder / overdue notice.
  ///
  /// "Loan overdue: Pay ₹15,000 by 20-Feb" — this is a reminder, not
  /// evidence that money moved. The actual debit will have "debited".
  static final RegExp _reminderPattern = RegExp(
    r'(?:overdue|due\s*(?:date|by|on)|'
    r'(?:EMI|payment|installment)\s*(?:due|reminder|pending)|'
    r'reminder\s*(?:to\s*)?(?:pay|for)|'
    r'please\s*(?:pay|clear|settle)\s*(?:your|the)\s*(?:due|outstanding|pending))|'
    r'pay\s*(?:your|the)\s*(?:bill|dues?|amount)\s*(?:by|before|on)',
    caseSensitive: false,
  );

  /// Strong completed transaction execution signal check (debit/credit verb + structural signal).
  static final RegExp _completedTxnSignal = RegExp(
    r'\b(?:debited|credited|paid|spent|transferred|withdrawn|swiped|charged|sent\s+to|received|txn\s+of|dr\.?|cr\.?)\b.*'
    r'(?:A/c|Acct|Card|Ref|UPI|IMPS|NEFT|POS|at\s+[A-Za-z0-9]|to\s+[A-Za-z0-9]|from\s+[A-Za-z0-9]|vpa|naame|nikasi)',
    caseSensitive: false,
  );

  static String? _checkPaymentReminder(
    String body, {
    bool hasCompletedTransaction = false,
  }) {
    // CRITICAL: Reminder detection MUST ONLY execute if the SMS has NOT
    // already been classified as a completed financial transaction.
    if (hasCompletedTransaction || _completedTxnSignal.hasMatch(body)) {
      return null;
    }

    final match = _reminderPattern.firstMatch(body);
    if (match != null) {
      return 'Payment reminder/overdue notice: "${match.group(0)}"';
    }
    return null;
  }
}
