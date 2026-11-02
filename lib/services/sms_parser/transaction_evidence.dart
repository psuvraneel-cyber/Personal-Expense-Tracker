/// Tells a real money movement apart from an offer that only *looks* like
/// one ("Get ₹500 cashback credited to your account!").
///
/// Ads can copy transaction words, but not the details a bank includes when
/// money really moved: your account or card ending, a transaction reference
/// (UPI ref / UTR / RRN) and the balance afterwards. So the decision weighs
/// offer language against that hard evidence:
///
/// - no offer language                       → [OfferVerdict.clean]
/// - ≥2 pieces of hard evidence              → [OfferVerdict.clean]
///   (real alerts often carry an ad footer: "… Avl Bal Rs 5,000. Get a
///   pre-approved loan up to 5L")
/// - ≥2 offer signals and no hard evidence   → [OfferVerdict.reject]
/// - anything in between                     → [OfferVerdict.review]
library;

enum OfferVerdict {
  /// No reason to doubt it: decide as usual.
  clean,

  /// Offer-like wording with too little evidence: let the user decide.
  review,

  /// An offer, not a transaction.
  reject,
}

class TransactionEvidence {
  TransactionEvidence._();

  /// Wording that promises or invites rather than reports.
  static final List<RegExp> _offerSignals = [
    RegExp(r'\b(?:get|win|earn|avail|unlock|enjoy|grab)\b',
        caseSensitive: false),
    RegExp(r'\bup\s*to\b|\bupto\b', caseSensitive: false),
    RegExp(r'\boffer\b|\bcoupon\b|\bvoucher\b|\bpromo\s*code\b|\buse\s+code\b',
        caseSensitive: false),
    RegExp(
        r'\b(?:hurry|limited\s+(?:time|period)|valid\s+(?:till|until|upto))\b',
        caseSensitive: false),
    RegExp(r'\b(?:apply|click|tap|download|shop|book)\s+now\b|\bT\s*&\s*C\b',
        caseSensitive: false),
    RegExp(r'https?://|\bbit\.ly\b|\bwww\.', caseSensitive: false),
  ];

  /// How many distinct kinds of offer wording [text] contains.
  static int offerSignals(String text) =>
      _offerSignals.where((p) => p.hasMatch(text)).length;

  /// Hard evidence that money moved: account/card ending, reference number
  /// and balance after the transaction.
  static int hardEvidence({
    String? accountTail,
    String? referenceId,
    double? balanceAfter,
  }) =>
      [
        accountTail != null && accountTail.trim().isNotEmpty,
        referenceId != null && referenceId.trim().length >= 6,
        balanceAfter != null,
      ].where((present) => present).length;

  static OfferVerdict assess(
    String text, {
    String? accountTail,
    String? referenceId,
    double? balanceAfter,
  }) {
    final offers = offerSignals(text);
    if (offers == 0) return OfferVerdict.clean;
    final evidence = hardEvidence(
      accountTail: accountTail,
      referenceId: referenceId,
      balanceAfter: balanceAfter,
    );
    if (evidence >= 2) return OfferVerdict.clean;
    if (offers >= 2 && evidence == 0) return OfferVerdict.reject;
    return OfferVerdict.review;
  }
}
