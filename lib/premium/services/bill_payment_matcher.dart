import 'package:flutter/foundation.dart'
    show ValueNotifier, kIsWeb, visibleForTesting;
import 'package:uuid/uuid.dart';
import 'package:pet/core/utils/app_logger.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/premium/models/recurring_payment.dart';
import 'package:pet/premium/models/recurring_payment_history.dart';
import 'package:pet/premium/repositories/recurring_payment_repository.dart';
import 'package:pet/premium/services/alert_evaluation_coordinator.dart';
import 'package:pet/premium/services/bill_reminder_scheduler.dart';
import 'package:pet/premium/services/recurring_detection_service.dart';
import 'package:pet/services/firestore_sync_service.dart';
import 'package:pet/services/recurrence_calculator.dart';

/// Marks a confirmed bill as paid when a matching payment is recorded
/// (imported from SMS/notifications or added by hand), so autopaid bills
/// don't stay "overdue" and aren't deducted again by the cash-flow forecast.
///
/// A payment matches a bill when the merchant matches, the amount is within
/// [amountTolerance] of the bill, it was made after the last recorded
/// payment, and it falls between [earlyDays] before and [lateDays] after
/// the current due date.
class BillPaymentMatcher {
  BillPaymentMatcher._();

  static const int earlyDays = 5;
  static const int lateDays = 10;
  static const double amountTolerance = 0.10;

  static const _uuid = Uuid();

  /// Bumped whenever a bill is advanced here, so screens holding bills in
  /// memory (RecurringProvider) reload.
  static final ValueNotifier<int> billsRevision = ValueNotifier<int>(0);

  static String _merchantKey(String raw) =>
      RecurringDetectionService.normalizeMerchantName(raw).toLowerCase();

  /// Whether [merchant] names the same payee as [billMerchant].
  @visibleForTesting
  static bool sameMerchant(String? merchant, String billMerchant) {
    if (merchant == null || merchant.trim().isEmpty) return false;
    final a = _merchantKey(merchant);
    final b = _merchantKey(billMerchant);
    if (a == b) return true;
    // "Netflix" vs "Netflix Subscription": allow containment for names long
    // enough not to match by accident.
    final shorter = a.length <= b.length ? a : b;
    final longer = a.length <= b.length ? b : a;
    return shorter.length >= 4 && longer.contains(shorter);
  }

  /// Whether a payment of [amount] to [merchant] on [date] pays the current
  /// cycle of [bill].
  static bool matches(
    RecurringPayment bill, {
    required String? merchant,
    required double amount,
    required DateTime date,
  }) {
    if (bill.status != RecurringStatus.confirmed) return false;
    if (!sameMerchant(merchant, bill.merchantName)) return false;
    final tolerance =
        (bill.amount * amountTolerance).clamp(1.0, double.infinity);
    if ((amount - bill.amount).abs() > tolerance) return false;
    if (!date.isAfter(bill.lastPaidAt)) return false;
    final windowStart =
        bill.nextDueAt.subtract(const Duration(days: earlyDays));
    final windowEnd = bill.nextDueAt.add(const Duration(days: lateDays));
    return !date.isBefore(windowStart) && !date.isAfter(windowEnd);
  }

  /// Advances the bill that [txn] pays, if any. Returns the updated bill.
  /// Best effort: errors are logged, never thrown, so a recording failure
  /// can't block a transaction from being saved.
  static Future<RecurringPayment?> recordIfBillPayment(
    TransactionRecord txn, {
    RecurringPaymentRepository? repository,
    FirestoreSyncService? firestoreSync,
    bool sideEffects = true,
  }) async {
    if (kIsWeb || txn.type != TransactionType.expense) return null;
    try {
      final repo = repository ?? RecurringPaymentRepository();
      final bills = await repo.getAll();
      final bill = bills.where((b) => matches(
            b,
            merchant: txn.merchantName,
            amount: txn.amount,
            date: txn.date,
          ));
      if (bill.isEmpty) return null;
      final paid = bill.first;

      final now = DateTime.now();
      final updated = paid.copyWith(
        lastPaidAt: txn.date,
        nextDueAt: RecurrenceCalculator.advanceNextDueDate(
          currentDue: paid.nextDueAt,
          frequency: paid.frequencyEnum,
          paidDate: txn.date,
        ),
        // A small price rise inside the tolerance becomes the new amount.
        amount: txn.amount,
        previousAmount:
            (txn.amount - paid.amount).abs() >= 1 ? paid.amount : null,
        updatedAt: now,
      );
      final history = RecurringPaymentHistory(
        id: _uuid.v4(),
        recurringPaymentId: paid.id,
        amount: txn.amount,
        paidAt: txn.date,
        source: 'auto_match',
        notes: 'Matched to ${txn.source.name} transaction ${txn.id}',
        createdAt: now,
      );
      await repo.recordPaymentAndAdvance(
        history: history,
        updatedPayment: updated,
      );
      billsRevision.value++;
      AppLogger.debug(
          '[BillPaymentMatcher] ${paid.merchantName} paid; next due ${updated.nextDueAt}');

      if (sideEffects) {
        await _afterPayment(paid, updated, history, firestoreSync);
      }
      return updated;
    } catch (e) {
      AppLogger.debug('[BillPaymentMatcher] failed: $e');
      return null;
    }
  }

  static Future<void> _afterPayment(
    RecurringPayment paid,
    RecurringPayment updated,
    RecurringPaymentHistory history,
    FirestoreSyncService? firestoreSync,
  ) async {
    try {
      await BillReminderScheduler.cancelReminder(paid);
      await BillReminderScheduler.scheduleReminders([updated]);
    } catch (_) {}
    try {
      await AlertEvaluationCoordinator().onBillResolved(paid.id);
    } catch (_) {}
    // Push the new schedule so an older cloud copy can't roll it back.
    try {
      final sync = firestoreSync ?? FirestoreSyncService();
      if (sync.isAuthenticated) {
        await sync.upsertRecurringPayment(updated);
        await sync.upsertRecurringPaymentHistory(history);
      }
    } catch (_) {}
  }
}
