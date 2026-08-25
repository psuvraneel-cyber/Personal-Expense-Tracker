import 'package:uuid/uuid.dart';
import 'package:pet/core/utils/app_logger.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/recurring_rule.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/data/repositories/recurring_transaction_repository.dart';
import 'package:pet/services/recurrence_calculator.dart';

/// Service responsible for orchestrating recurring rule execution, missed occurrence
/// catch-up, occurrence skipping, and rule lifecycle operations.
class RecurringTransactionService {
  final RecurringTransactionRepository _repository;
  final Uuid _uuid = const Uuid();

  RecurringTransactionService({RecurringTransactionRepository? repository})
      : _repository = repository ?? RecurringTransactionRepository();

  /// Scans all active recurring rules, computes due/missed occurrences up to [now],
  /// and atomically generates transactions and occurrences with full idempotency.
  ///
  /// Safe to call concurrently, on app start, on resume, and from background workers.
  Future<List<TransactionRecord>> generateDueOccurrences({
    DateTime? now,
    String? userId,
  }) async {
    final referenceTime = now ?? DateTime.now();
    final dueRules = await _repository.getDueRules(referenceTime, userId: userId);

    if (dueRules.isEmpty) {
      AppLogger.debug(
        '[RecurringService] No due recurring rules found at $referenceTime',
        label: 'Recurring',
      );
      return [];
    }

    AppLogger.info(
      '[RecurringService] Found ${dueRules.length} due recurring rules to process',
      label: 'Recurring',
    );

    final generatedTransactions = <TransactionRecord>[];

    for (final rule in dueRules) {
      try {
        final missedDates = RecurrenceCalculator.computeMissedOccurrences(
          rule: rule,
          now: referenceTime,
          maxOccurrences: 100,
        );

        if (missedDates.isEmpty) continue;

        var currentRule = rule;

        for (final scheduledDate in missedDates) {
          final nextDate = RecurrenceCalculator.computeNextOccurrence(
            anchorDate: currentRule.startDate,
            currentOccurrence: scheduledDate,
            frequency: currentRule.frequency,
            interval: currentRule.interval,
          );

          final newTxnId = _uuid.v4();
          final transaction = TransactionRecord(
            id: newTxnId,
            amount: currentRule.amount,
            type: currentRule.type,
            categoryId: currentRule.categoryId,
            date: scheduledDate,
            note: currentRule.note,
            paymentMethod: currentRule.paymentMethod,
            isRecurring: true,
            recurringFrequency: currentRule.frequency,
            merchantName: currentRule.merchantName,
            taxCategory: currentRule.taxCategory,
            source: currentRule.source,
            accountId: currentRule.accountId,
            updatedAt: DateTime.now(),
            recurringRuleId: currentRule.id,
            occurrenceDate: scheduledDate,
          );

          final result = await _repository.atomicGenerateOccurrence(
            rule: currentRule,
            scheduledDate: scheduledDate,
            transaction: transaction,
            nextOccurrenceDate: nextDate,
            userId: userId ?? currentRule.userId,
          );

          if (result != null) {
            generatedTransactions.add(result);
          }

          // Check if rule reached its endDate
          if (currentRule.endDate != null && nextDate.isAfter(currentRule.endDate!)) {
            AppLogger.info(
              '[RecurringService] Rule ${currentRule.id} reached end date ${currentRule.endDate}. Deactivating.',
              label: 'Recurring',
            );
            await _repository.deactivateRule(currentRule.id);
            break;
          }

          // Update in-memory rule state for next loop iteration
          currentRule = currentRule.copyWith(
            nextOccurrenceDate: nextDate,
            lastGeneratedDate: scheduledDate,
          );
        }
      } catch (e, stack) {
        AppLogger.error(
          '[RecurringService] Error processing rule ${rule.id}',
          error: e,
          stack: stack,
          label: 'Recurring',
        );
      }
    }

    AppLogger.info(
      '[RecurringService] Completed due occurrence generation. Generated ${generatedTransactions.length} transactions.',
      label: 'Recurring',
    );

    return generatedTransactions;
  }

  /// Creates a new recurring rule and optionally generates the initial occurrence immediately.
  Future<({RecurringRule rule, TransactionRecord? firstTransaction})> createRule({
    required double amount,
    required TransactionType type,
    required String categoryId,
    required RecurringFrequency frequency,
    required DateTime startDate,
    DateTime? endDate,
    int interval = 1,
    String note = '',
    PaymentMethod paymentMethod = PaymentMethod.upi,
    String? merchantName,
    String? taxCategory,
    TransactionSource source = TransactionSource.manual,
    String? accountId,
    String? userId,
    bool generateFirstOccurrenceImmediately = true,
  }) async {
    final ruleId = _uuid.v4();
    final now = DateTime.now();

    final nextOccurrenceDate = generateFirstOccurrenceImmediately
        ? RecurrenceCalculator.computeNextOccurrence(
            anchorDate: startDate,
            currentOccurrence: startDate,
            frequency: frequency,
            interval: interval,
          )
        : startDate;

    final rule = RecurringRule(
      id: ruleId,
      amount: amount,
      type: type,
      categoryId: categoryId,
      note: note,
      paymentMethod: paymentMethod,
      frequency: frequency,
      interval: interval,
      startDate: startDate,
      endDate: endDate,
      nextOccurrenceDate: nextOccurrenceDate,
      lastGeneratedDate: generateFirstOccurrenceImmediately ? startDate : null,
      isActive: true,
      merchantName: merchantName,
      taxCategory: taxCategory,
      source: source,
      accountId: accountId,
      createdAt: now,
      updatedAt: now,
      userId: userId,
    );

    TransactionRecord? firstTxn;

    if (generateFirstOccurrenceImmediately) {
      firstTxn = TransactionRecord(
        id: _uuid.v4(),
        amount: amount,
        type: type,
        categoryId: categoryId,
        date: startDate,
        note: note,
        paymentMethod: paymentMethod,
        isRecurring: true,
        recurringFrequency: frequency,
        merchantName: merchantName,
        taxCategory: taxCategory,
        source: source,
        accountId: accountId,
        updatedAt: now,
        recurringRuleId: ruleId,
        occurrenceDate: startDate,
      );

      // Insert rule first so foreign key constraints or queries succeed
      await _repository.insertRule(rule);

      await _repository.atomicGenerateOccurrence(
        rule: rule,
        scheduledDate: startDate,
        transaction: firstTxn,
        nextOccurrenceDate: nextOccurrenceDate,
        userId: userId,
      );
    } else {
      await _repository.insertRule(rule);
    }

    return (rule: rule, firstTransaction: firstTxn);
  }

  /// Skips a single scheduled occurrence.
  Future<void> skipOccurrence({
    required String ruleId,
    required DateTime scheduledDate,
  }) async {
    final rule = await _repository.getRuleById(ruleId);
    DateTime? nextDate;
    if (rule != null && rule.nextOccurrenceDate.isAtSameMomentAs(scheduledDate)) {
      nextDate = RecurrenceCalculator.computeNextOccurrence(
        anchorDate: rule.startDate,
        currentOccurrence: scheduledDate,
        frequency: rule.frequency,
        interval: rule.interval,
      );
    }
    await _repository.markOccurrenceSkipped(
      ruleId: ruleId,
      scheduledDate: scheduledDate,
      nextOccurrenceDate: nextDate,
    );
  }

  /// Deletes a specific occurrence transaction and marks the occurrence as skipped.
  Future<void> deleteOccurrenceTransaction({
    required String transactionId,
    required String ruleId,
    required DateTime scheduledDate,
    String? userId,
  }) async {
    await _repository.deleteOccurrenceAndSkip(
      transactionId: transactionId,
      ruleId: ruleId,
      scheduledDate: scheduledDate,
      userId: userId,
    );
  }

  /// Stops / deactivates a recurring rule. Past generated transactions remain intact.
  Future<void> stopRule(String ruleId) async {
    await _repository.deactivateRule(ruleId);
  }

  /// Updates a recurring rule (for editing future occurrences).
  Future<void> updateRule(RecurringRule rule) async {
    await _repository.updateRule(rule.copyWith(updatedAt: DateTime.now()));
  }

  /// Deletes a recurring rule and all transactions generated by it.
  Future<void> deleteRuleAndAllOccurrences(String ruleId, {String? userId}) async {
    await _repository.deleteRuleAndAllOccurrences(ruleId, userId: userId);
  }
}
