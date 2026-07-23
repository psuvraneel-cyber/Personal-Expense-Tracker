/// Self-consistency checker — dual-parser consensus mechanism.
///
/// Implements the multi-method parsing approach requested for SMS parsing:
/// 1. Runs both the modular pipeline (SmsTransactionParser) and the legacy
///    regex engine (TransactionParser) on the same SMS.
/// 2. Compares results field-by-field.
/// 3. Selects the best result using field-level voting and confidence adjustments.
///
/// ## Consensus Rules
/// - BOTH agree on direction + amount → high confidence → use result with
///   more extracted fields.
/// - BOTH detect transaction but disagree on direction → prefer modular
///   pipeline (better keyword precedence logic).
/// - Only ONE succeeds → use that result with a small confidence penalty.
/// - NEITHER succeeds → reject.
///
/// ## Confidence Adjustments
/// - Both agree: +5 boost (dual confirmation)
/// - Disagreement on direction: -5 penalty
/// - Only one parser succeeds: -3 penalty
///
/// SECURITY: Pure function, no side effects, no external calls.
library;

import 'package:pet/services/sms_parser/sms_transaction_parser.dart';
import 'package:pet/services/sms_parser/transaction_parse_result.dart';
import 'package:pet/services/sms_parser/user_feedback_store.dart';
import 'package:pet/services/transaction_parser.dart';

/// Result of the self-consistency check.
class ConsistencyResult {
  /// The chosen final parse result.
  final TransactionParseResult result;

  /// Which parser(s) contributed to the final result.
  final ConsistencySource source;

  /// Agreement level between the two parsers.
  final AgreementLevel agreement;

  /// Explanation of the consistency decision.
  final List<String> consistencyReasons;

  const ConsistencyResult({
    required this.result,
    required this.source,
    required this.agreement,
    required this.consistencyReasons,
  });
}

/// Which parser was the source of the final result.
enum ConsistencySource {
  /// Both parsers agreed, modular pipeline result used.
  consensus,

  /// Only the modular pipeline succeeded.
  modularOnly,

  /// Only the legacy parser succeeded.
  legacyOnly,

  /// Parsers disagreed, modular pipeline preferred.
  modularPreferred,

  /// Neither parser detected a transaction.
  noneDetected,
}

/// Level of agreement between the two parsers.
enum AgreementLevel {
  /// Both agree on direction, amount, and key fields.
  full,

  /// Both detect a transaction but disagree on direction or amount.
  partial,

  /// Only one parser detected a transaction.
  single,

  /// Neither detected a transaction.
  none,
}

/// Self-consistency checker that compares results from two independent
/// parsing methods to produce a more reliable final result.
class SelfConsistencyChecker {
  SelfConsistencyChecker._();

  // ═══════════════════════════════════════════════════════════════════
  //  CONFIDENCE ADJUSTMENTS
  // ═══════════════════════════════════════════════════════════════════

  /// Bonus when both parsers agree.
  static const int _consensusBoost = 5;

  /// Penalty when parsers disagree on direction.
  static const int _disagreementPenalty = 5;

  /// Penalty when only one parser succeeds.
  static const int _singleParserPenalty = 3;

  // ═══════════════════════════════════════════════════════════════════
  //  MAIN API
  // ═══════════════════════════════════════════════════════════════════

  /// Run both parsers on the same SMS and return the consensus result.
  ///
  /// [body]      — The full SMS text.
  /// [sender]    — The SMS sender ID.
  /// [timestamp] — The OS timestamp of the SMS.
  static ConsistencyResult check({
    required String body,
    required String sender,
    required DateTime timestamp,
  }) {
    final reasons = <String>[];

    // ── Check User Feedback Store Override ───────────────────────
    final userFeedbackOverride = UserFeedbackStore.applyFeedback(
      TransactionParseResult.rejected(reasons: []),
      body,
      timestamp,
    );
    if (userFeedbackOverride != null) {
      final isTxn = userFeedbackOverride.isTransaction;
      reasons.add(
        'USER FEEDBACK OVERRIDE: ${isTxn ? "User-confirmed transaction" : "Marked as not a transaction"}',
      );
      return ConsistencyResult(
        result: userFeedbackOverride,
        source: ConsistencySource.consensus,
        agreement: AgreementLevel.full,
        consistencyReasons: reasons,
      );
    }

    // ── Run Method A: Modular pipeline ──────────────────────────
    final modularResult = SmsTransactionParser.parse(
      body: body,
      sender: sender,
      timestamp: timestamp,
    );
    final modularIsTransaction =
        modularResult.isTransaction || modularResult.isUncertain;

    // ── Run Method B: Legacy regex engine ────────────────────────
    final legacyParsed = TransactionParser.parse(body, sender, timestamp);
    final legacyIsTransaction = legacyParsed != null;

    reasons.add(
      'Modular: ${modularIsTransaction ? "DETECTED" : "REJECTED"} '
      '(confidence=${modularResult.confidence})',
    );
    reasons.add(
      'Legacy: ${legacyIsTransaction ? "DETECTED" : "REJECTED"}'
      '${legacyParsed != null ? " (confidence=${(legacyParsed.confidence * 100).round()})" : ""}',
    );

    // ── Case 1: Neither detected ─────────────────────────────────
    if (!modularIsTransaction && !legacyIsTransaction) {
      reasons.add('CONSENSUS: Neither parser detected a transaction');
      return ConsistencyResult(
        result: modularResult, // Use modular for rejection reasons
        source: ConsistencySource.noneDetected,
        agreement: AgreementLevel.none,
        consistencyReasons: reasons,
      );
    }

    // ── Case 2: Only modular detected ────────────────────────────
    if (modularIsTransaction && !legacyIsTransaction) {
      reasons.add(
        'SINGLE: Only modular pipeline detected (−$_singleParserPenalty)',
      );
      final adjusted = _adjustConfidence(modularResult, -_singleParserPenalty);
      return ConsistencyResult(
        result: adjusted,
        source: ConsistencySource.modularOnly,
        agreement: AgreementLevel.single,
        consistencyReasons: reasons,
      );
    }

    // ── Case 3: Only legacy detected ─────────────────────────────
    if (!modularIsTransaction && legacyIsTransaction) {
      reasons.add(
        'SINGLE: Only legacy parser detected (−$_singleParserPenalty)',
      );
      final legacyAsResult = _legacyToResult(legacyParsed, timestamp);
      final adjusted = _adjustConfidence(legacyAsResult, -_singleParserPenalty);
      return ConsistencyResult(
        result: adjusted,
        source: ConsistencySource.legacyOnly,
        agreement: AgreementLevel.single,
        consistencyReasons: reasons,
      );
    }

    // ── Case 4: Both detected — compare fields ──────────────────
    final legacyDirection = legacyParsed!.transactionType == 'credit'
        ? TransactionDirection.credit
        : TransactionDirection.debit;
    final modularDirection = modularResult.direction;

    final amountsMatch = legacyParsed.amount == modularResult.amount;
    final directionsMatch = modularDirection == legacyDirection;

    // Case 4a: Full agreement
    if (directionsMatch && amountsMatch) {
      reasons.add(
        'CONSENSUS: Both agree on direction=${modularDirection?.name} '
        'and amount=${modularResult.amount} (+$_consensusBoost)',
      );

      // Use the result with more extracted fields
      final modularFields = _countFields(modularResult);
      final legacyFields = _countLegacyFields(legacyParsed);

      TransactionParseResult chosen;
      if (modularFields >= legacyFields) {
        chosen = modularResult;
        reasons.add(
          'Using modular result ($modularFields fields vs $legacyFields)',
        );
      } else {
        // Even if legacy has more fields, prefer modular for its richer
        // result model (channel, time, etc.)
        chosen = _mergeFields(modularResult, legacyParsed);
        reasons.add(
          'Merged modular+legacy ($modularFields + $legacyFields fields)',
        );
      }

      final boosted = _adjustConfidence(chosen, _consensusBoost);
      return ConsistencyResult(
        result: boosted,
        source: ConsistencySource.consensus,
        agreement: AgreementLevel.full,
        consistencyReasons: reasons,
      );
    }

    // Case 4b: Partial agreement (disagreement on direction or amount)
    if (!directionsMatch) {
      reasons.add(
        'DISAGREEMENT: modular=${modularDirection?.name}, '
        'legacy=${legacyDirection.name}. Preferring modular (−$_disagreementPenalty)',
      );
    }
    if (!amountsMatch) {
      reasons.add(
        'DISAGREEMENT: modular amount=${modularResult.amount}, '
        'legacy amount=${legacyParsed.amount}. Preferring modular.',
      );
    }

    final adjusted = _adjustConfidence(modularResult, -_disagreementPenalty);
    return ConsistencyResult(
      result: adjusted,
      source: ConsistencySource.modularPreferred,
      agreement: AgreementLevel.partial,
      consistencyReasons: reasons,
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  HELPERS
  // ═══════════════════════════════════════════════════════════════════

  /// Adjust confidence score, clamping to 0–100.
  static TransactionParseResult _adjustConfidence(
    TransactionParseResult result,
    int delta,
  ) {
    final newConf = (result.confidence + delta).clamp(0, 100);
    return result.copyWith(confidence: newConf);
  }

  /// Count non-null extracted fields in a modular result.
  static int _countFields(TransactionParseResult r) {
    int count = 0;
    if (r.amount != null) count++;
    if (r.merchant != null && r.merchant != 'Unknown') count++;
    if (r.upiId != null) count++;
    if (r.reference != null) count++;
    if (r.bank != null && r.bank != 'Unknown Bank') count++;
    if (r.accountTail != null) count++;
    if (r.date != null) count++;
    if (r.time != null) count++;
    if (r.channel != TransactionChannel.unknown) count++;
    return count;
  }

  /// Count non-null extracted fields in a legacy result.
  static int _countLegacyFields(ParsedTransaction r) {
    int count = 0;
    if (r.merchantName.isNotEmpty && r.merchantName != 'Unknown') count++;
    if (r.upiId != null) count++;
    if (r.referenceId != null) count++;
    if (r.bankName.isNotEmpty && r.bankName != 'Unknown Bank') count++;
    if (r.accountTail != null) count++;
    if (r.parsedDate != null) count++;
    return count;
  }

  /// Convert a legacy parser result to the modular result format.
  static TransactionParseResult _legacyToResult(
    ParsedTransaction legacy,
    DateTime timestamp,
  ) {
    final direction = legacy.transactionType == 'credit'
        ? TransactionDirection.credit
        : TransactionDirection.debit;

    final subType = _mapSubType(legacy.transactionSubType);

    return TransactionParseResult(
      isTransaction: true,
      direction: direction,
      amount: legacy.amount,
      merchant: legacy.merchantName,
      upiId: legacy.upiId,
      reference: legacy.referenceId,
      bank: legacy.bankName,
      accountTail: legacy.accountTail,
      date: legacy.parsedDate ?? timestamp,
      subType: subType,
      confidence: (legacy.confidence * 100).round(),
      reasons: ['Converted from legacy parser'],
    );
  }

  /// Merge missing fields from legacy into the modular result.
  static TransactionParseResult _mergeFields(
    TransactionParseResult modular,
    ParsedTransaction legacy,
  ) {
    return modular.copyWith(
      merchant: (modular.merchant == null || modular.merchant == 'Unknown')
          ? legacy.merchantName
          : modular.merchant,
      upiId: modular.upiId ?? legacy.upiId,
      reference: modular.reference ?? legacy.referenceId,
      bank: (modular.bank == null || modular.bank == 'Unknown Bank')
          ? legacy.bankName
          : modular.bank,
      accountTail: modular.accountTail ?? legacy.accountTail,
      date: modular.date ?? legacy.parsedDate,
    );
  }

  /// Map legacy sub-type string to enum.
  static TransactionSubType _mapSubType(String subType) {
    return switch (subType) {
      'payment' => TransactionSubType.payment,
      'transfer' => TransactionSubType.transfer,
      'collect' => TransactionSubType.collect,
      'refund' => TransactionSubType.refund,
      'cashback' => TransactionSubType.cashback,
      'reversal' => TransactionSubType.reversal,
      _ => TransactionSubType.unknown,
    };
  }
}
