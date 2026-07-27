/// Amount extraction module — parses monetary amounts from SMS text.
///
/// ## Supported Formats
/// - `Rs.500`, `Rs 1,500.00`, `Rs500` — "Rs" prefix with optional dot/space
/// - `INR 500`, `INR.500` — "INR" prefix
/// - `₹500`, `₹ 1,200` — Unicode rupee symbol
/// - `1,00,000.50` — Indian comma notation (lakh/crore grouping)
/// - No-decimal: `Rs 500` → 500.00
///
/// ## Edge Cases
/// - Multiple amounts in SMS: first amount matching the transaction
///   context is returned. Balance amounts ("Avl Bal Rs 15,000") are
///   explicitly excluded.
/// - Sanity bounds: ₹0.01 – ₹1,00,00,000 (1 crore). Outside = reject.
/// - OTP amounts embedded: "OTP for Rs 500 txn is 123456" — the OTP
///   filter should have already rejected this.
///
/// ## Performance
/// Single pass with pre-compiled regex. O(n) per SMS body.
library;

/// Result of amount extraction.
class AmountResult {
  /// Extracted amount in INR, or null if no valid amount found.
  final double? amount;

  /// Position in the body where the amount was found (for diagnostics).
  final int? position;

  /// Reasons explaining extraction decisions.
  final List<String> reasons;

  const AmountResult({this.amount, this.position, required this.reasons});
}

/// Extracts monetary amounts from Indian bank SMS messages.
class AmountExtractor {
  AmountExtractor._();

  /// Maximum plausible transaction amount: ₹1 crore (10 million).
  /// Beyond this is likely a parsing error or loan offer amount.
  static const double _maxAmount = 10000000;

  /// Minimum plausible transaction amount.
  static const double _minAmount = 0.01;

  // ═══════════════════════════════════════════════════════════════════
  //  REGEX PATTERNS
  // ═══════════════════════════════════════════════════════════════════

  /// Primary amount pattern.
  ///
  /// Matches:
  /// - Rs.500, Rs 1,500.00, Rs500
  /// - INR 500, INR.500
  /// - ₹500, ₹ 1,200.50
  ///
  /// Capture group 1: digit portion (e.g., "1,500.00")
  ///
  /// Regex breakdown:
  ///   (?:Rs\.?\s*|INR\.?\s*|₹\s?)  — currency prefix
  ///   (                              — capture group start
  ///     [0-9]+                       — first digit group
  ///     (?:,[0-9]{2,3})*            — optional comma-separated groups
  ///     (?:\.\d{1,2})?              — optional decimal part
  ///   )                              — capture group end
  ///
  /// No backtracking risk: the quantifiers are on disjoint character
  /// classes (digits vs commas vs dots).
  static final RegExp _amountPattern = RegExp(
    r'(?:Rs\.?\s*|INR\.?\s*|₹\s?)([0-9]+(?:,[0-9]{2,3})*(?:\.\d{1,2})?)',
    caseSensitive: false,
  );

  /// Balance amount pattern — used to EXCLUDE balance amounts.
  ///
  /// If an amount immediately follows a balance keyword, it's not the
  /// transaction amount. Example: "debited Rs 500...Avl Bal Rs 15,000"
  /// → we want 500, not 15,000.
  ///
  /// Matches: "Avl Bal Rs 15,000", "Balance: ₹10,000",
  ///          "Remaining balance Rs 3,500"
  static final RegExp _balanceAmountPattern = RegExp(
    r'(?:avl\.?|available|remaining|current|closing|total)\s*'
    r'(?:bal(?:ance)?|bal\.?)\s*(?:(?:is|:)\s*)?(?:Rs\.?\s*|INR\.?\s*|₹\s?)',
    caseSensitive: false,
  );

  /// "Amount of" pattern — secondary extraction.
  /// Matches: "amount of Rs 500", "amt Rs 500"
  static final RegExp _amountOfPattern = RegExp(
    r'(?:amount\s+(?:of\s+)?|amt\.?\s*)(?:Rs\.?\s*|INR\.?\s*|₹\s?)([0-9]+(?:,[0-9]{2,3})*(?:\.\d{1,2})?)',
    caseSensitive: false,
  );

  // ═══════════════════════════════════════════════════════════════════
  //  PUBLIC API
  // ═══════════════════════════════════════════════════════════════════

  /// Extract the transaction amount from an SMS body.
  ///
  /// Strategy:
  /// 1. Find ALL amount matches in the body.
  /// 2. Exclude any that are preceded by balance keywords.
  /// 3. Return the first non-balance amount within sanity bounds.
  /// 4. If no primary match, try "amount of Rs X" pattern.
  static AmountResult extract(String body) {
    final reasons = <String>[];
    // Sanitize zero-width spaces, LTR/RTL markers, and non-breaking spaces
    final cleanedBody = body
        .replaceAll(RegExp(r'[\u200B-\u200D\uFEFF\u200E\u200F]'), '')
        .replaceAll('\u00A0', ' ');

    // Find all balance keyword positions to exclude their amounts
    final balancePositions = <int>{};
    for (final match in _balanceAmountPattern.allMatches(cleanedBody)) {
      // Mark the end position of the balance keyword as the start
      // of the amount to exclude
      balancePositions.add(match.end);
    }

    // Find all amount matches
    final allMatches = _amountPattern.allMatches(cleanedBody).toList();
    reasons.add('Found ${allMatches.length} amount pattern(s) in body');

    for (final match in allMatches) {
      // Check if this amount is a balance amount
      final isBalance = balancePositions.any(
        (pos) => (match.start - pos).abs() <= 5,
      );

      if (isBalance) {
        reasons.add(
          'Skipping balance amount at position ${match.start}: "${match.group(0)}"',
        );
        continue;
      }

      // Parse the amount
      final raw = match.group(1)!.replaceAll(',', '');
      final amount = double.tryParse(raw);

      if (amount == null) {
        reasons.add('Failed to parse amount: "${match.group(1)}"');
        continue;
      }

      if (amount < _minAmount) {
        reasons.add('Amount ₹$amount below minimum (₹$_minAmount)');
        continue;
      }

      if (amount > _maxAmount) {
        reasons.add(
          'Amount ₹$amount exceeds maximum (₹$_maxAmount) — likely not a transaction',
        );
        continue;
      }

      reasons.add('Extracted amount: ₹$amount at position ${match.start}');
      return AmountResult(
        amount: amount,
        position: match.start,
        reasons: reasons,
      );
    }

    // Fallback: try "amount of Rs X" pattern
    final altMatch = _amountOfPattern.firstMatch(cleanedBody);
    if (altMatch != null) {
      final raw = altMatch.group(1)!.replaceAll(',', '');
      final amount = double.tryParse(raw);
      if (amount != null && amount >= _minAmount && amount <= _maxAmount) {
        reasons.add('Extracted amount via "amount of" pattern: ₹$amount');
        return AmountResult(
          amount: amount,
          position: altMatch.start,
          reasons: reasons,
        );
      }
    }

    reasons.add('No valid transaction amount found');
    return AmountResult(reasons: reasons);
  }
}
