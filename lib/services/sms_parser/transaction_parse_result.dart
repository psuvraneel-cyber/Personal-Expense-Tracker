/// Production-grade result model for SMS transaction parsing.
///
/// Every parse attempt returns a [TransactionParseResult] that is fully
/// explainable — the [reasons] list records each decision the parser made,
/// and [confidence] quantifies certainty on a 0–100 integer scale.
///
/// Design rationale:
/// - [isTransaction] + [isUncertain] split the tri-state logic so callers
///   can decide to surface uncertain results for user verification.
/// - [reasons] makes debugging and telemetry trivial.
/// - [direction] uses an enum (not a string) to prevent typo bugs.
/// - Immutable value class with copyWith for safe state transformation.
library;

/// Transaction direction (debit lowers balance, credit raises it).
enum TransactionDirection {
  debit,
  credit;

  /// Human-readable label for UI.
  String get label => switch (this) {
    TransactionDirection.debit => 'Debit',
    TransactionDirection.credit => 'Credit',
  };
}

/// Sub-type classification for richer analytics.
enum TransactionSubType {
  payment,
  transfer,
  collect,
  refund,
  cashback,
  reversal,
  unknown;

  String get label => name[0].toUpperCase() + name.substring(1);
}

/// Transaction channel — how the money moved.
enum TransactionChannel {
  upi,
  neft,
  imps,
  rtgs,
  card,
  wallet,
  unknown;

  String get label => switch (this) {
    TransactionChannel.upi => 'UPI',
    TransactionChannel.neft => 'NEFT',
    TransactionChannel.imps => 'IMPS',
    TransactionChannel.rtgs => 'RTGS',
    TransactionChannel.card => 'Card',
    TransactionChannel.wallet => 'Wallet',
    TransactionChannel.unknown => 'Unknown',
  };
}

/// The output of parsing a single SMS body.
///
/// When [isTransaction] is false and [isUncertain] is false, the message
/// was definitively rejected. When [isUncertain] is true, confidence fell
/// between the reject and accept thresholds — surface it for user review
/// ("Possible transaction — verify").
class TransactionParseResult {
  /// Whether the parser considers this a real transaction.
  final bool isTransaction;

  /// `true` if confidence is between the reject and accept thresholds.
  /// The UI should show "Possible transaction — verify" for these.
  final bool isUncertain;

  /// Debit / Credit / null (unknown or rejected).
  final TransactionDirection? direction;

  /// Extracted monetary amount, or null if not a transaction.
  final double? amount;

  /// Merchant or counterparty name, or null.
  final String? merchant;

  /// UPI VPA (e.g., merchant@ybl), or null.
  final String? upiId;

  /// Reference/transaction ID (UPI Ref, IMPS Ref, etc.), or null.
  final String? reference;

  /// Detected bank name, or null.
  final String? bank;

  /// Last 3–6 digits of the account, or null.
  final String? accountTail;

  /// Parsed transaction date, or null.
  final DateTime? date;

  /// Parsed transaction time components (hour, minute, second), or null.
  /// When available, this is more accurate than the SMS OS timestamp.
  final ({int hour, int minute, int? second})? time;

  /// Transaction channel (UPI, NEFT, IMPS, RTGS, Card, Wallet).
  final TransactionChannel channel;

  /// Transaction sub-type (payment, refund, cashback, etc.).
  final TransactionSubType subType;

  /// Available balance observed after the transaction, or null.
  final double? balanceAfter;

  /// Whether this observation describes a bill or statement (not an immediate expense).
  final bool isBill;

  /// Amount due for the bill / statement, or null.
  final double? billAmountDue;

  /// Due date for the bill / statement, or null.
  final DateTime? billDueDate;

  /// Confidence score 0–100. Higher = more certain.
  ///
  /// Recommended thresholds (configurable):
  ///   ≥ 55 → accept as transaction
  ///   35–54 → uncertain (surface for user verification)
  ///   < 35 → reject
  final int confidence;

  /// Human-readable reasons explaining each parsing decision.
  /// Example: ["+20 debit keyword 'debited' at position 15",
  ///           "+15 UPI reference found: 412345678901",
  ///           "-100 OTP keyword detected → rejected"]
  final List<String> reasons;

  const TransactionParseResult({
    required this.isTransaction,
    this.isUncertain = false,
    this.direction,
    this.amount,
    this.merchant,
    this.upiId,
    this.reference,
    this.bank,
    this.accountTail,
    this.date,
    this.time,
    this.channel = TransactionChannel.unknown,
    this.subType = TransactionSubType.unknown,
    this.balanceAfter,
    this.isBill = false,
    this.billAmountDue,
    this.billDueDate,
    required this.confidence,
    required this.reasons,
  });

  /// Quick constructor for a definitively rejected message.
  const TransactionParseResult.rejected({
    required this.reasons,
    this.confidence = 0,
  }) : isTransaction = false,
       isUncertain = false,
       direction = null,
       amount = null,
       merchant = null,
       upiId = null,
       reference = null,
       bank = null,
       accountTail = null,
       date = null,
       time = null,
       channel = TransactionChannel.unknown,
       subType = TransactionSubType.unknown,
       balanceAfter = null,
       isBill = false,
       billAmountDue = null,
       billDueDate = null;

  /// Quick constructor for an uncertain message (needs user verification).
  const TransactionParseResult.uncertain({
    required this.reasons,
    required this.confidence,
    this.direction,
    this.amount,
    this.merchant,
    this.upiId,
    this.reference,
    this.bank,
    this.accountTail,
    this.date,
    this.time,
    this.channel = TransactionChannel.unknown,
    this.subType = TransactionSubType.unknown,
    this.balanceAfter,
    this.isBill = false,
    this.billAmountDue,
    this.billDueDate,
  }) : isTransaction = false,
       isUncertain = true;

  TransactionParseResult copyWith({
    bool? isTransaction,
    bool? isUncertain,
    TransactionDirection? direction,
    double? amount,
    String? merchant,
    String? upiId,
    String? reference,
    String? bank,
    String? accountTail,
    DateTime? date,
    ({int hour, int minute, int? second})? time,
    TransactionChannel? channel,
    TransactionSubType? subType,
    double? balanceAfter,
    bool? isBill,
    double? billAmountDue,
    DateTime? billDueDate,
    int? confidence,
    List<String>? reasons,
  }) {
    return TransactionParseResult(
      isTransaction: isTransaction ?? this.isTransaction,
      isUncertain: isUncertain ?? this.isUncertain,
      direction: direction ?? this.direction,
      amount: amount ?? this.amount,
      merchant: merchant ?? this.merchant,
      upiId: upiId ?? this.upiId,
      reference: reference ?? this.reference,
      bank: bank ?? this.bank,
      accountTail: accountTail ?? this.accountTail,
      date: date ?? this.date,
      time: time ?? this.time,
      channel: channel ?? this.channel,
      subType: subType ?? this.subType,
      balanceAfter: balanceAfter ?? this.balanceAfter,
      isBill: isBill ?? this.isBill,
      billAmountDue: billAmountDue ?? this.billAmountDue,
      billDueDate: billDueDate ?? this.billDueDate,
      confidence: confidence ?? this.confidence,
      reasons: reasons ?? this.reasons,
    );
  }

  @override
  String toString() {
    if (!isTransaction && !isUncertain) {
      return 'TransactionParseResult.REJECTED(confidence=$confidence, '
          'reasons=${reasons.length})';
    }
    return 'TransactionParseResult('
        '${isUncertain ? "UNCERTAIN" : "OK"}, '
        '${direction?.label ?? "?"}, '
        '₹$amount, '
        'merchant=$merchant, '
        'ref=$reference, '
        'channel=${channel.label}, '
        'confidence=$confidence)';
  }
}
