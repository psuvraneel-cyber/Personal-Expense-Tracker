import 'package:flutter/material.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/sms_transaction.dart';
import 'package:pet/premium/models/recurring_payment.dart';
import 'package:pet/premium/models/recurring_payment_history.dart';
import 'package:pet/premium/repositories/recurring_payment_repository.dart';
import 'package:pet/premium/services/bill_reminder_scheduler.dart';
import 'package:pet/premium/services/recurring_detection_service.dart';
import 'package:pet/services/recurrence_calculator.dart';
import 'package:pet/premium/services/alert_evaluation_coordinator.dart';
import 'package:uuid/uuid.dart';

class RecurringProvider extends ChangeNotifier {
  final RecurringPaymentRepository _repository = RecurringPaymentRepository();
  final Uuid _uuid = const Uuid();

  List<RecurringPayment> _recurring = [];
  bool _isLoading = false;
  bool _isInitialized = false;
  List<SmsTransaction>? _lastSmsForRecurring;

  List<RecurringPayment> get recurring => _recurring;
  bool get isLoading => _isLoading;
  bool get isInitialized => _isInitialized;

  /// Confirmed active recurring commitments, sorted with soonest due first.
  List<RecurringPayment> get confirmedBills {
    final list = _recurring.where((r) => r.status == RecurringStatus.confirmed).toList();
    list.sort((a, b) => a.nextDueAt.compareTo(b.nextDueAt));
    return list;
  }

  /// Inferred unconfirmed recurring payment candidates.
  List<RecurringPayment> get detectedBills {
    final list = _recurring.where((r) => r.status == RecurringStatus.detected).toList();
    list.sort((a, b) => b.confidence.compareTo(a.confidence));
    return list;
  }

  /// Cancelled or paused recurring commitments.
  List<RecurringPayment> get cancelledBills {
    final list = _recurring.where((r) => r.status == RecurringStatus.cancelled).toList();
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  /// Monthly equivalent run-rate across all confirmed commitments.
  double get totalMonthlyEquivalent =>
      confirmedBills.fold(0.0, (sum, b) => sum + b.monthlyEquivalentAmount);

  /// Annual commitment across all confirmed commitments.
  double get totalAnnualCommitment =>
      confirmedBills.fold(0.0, (sum, b) => sum + b.annualAmount);

  /// Confirmed bills due within the next 7 days.
  List<RecurringPayment> get weekAheadBills {
    final now = DateTime.now();
    return confirmedBills
        .where(
          (b) =>
              b.nextDueAt.isAfter(now) &&
              b.nextDueAt.difference(now).inDays <= 7,
        )
        .toList();
  }

  /// Total amount due within the next 7 days.
  double get weekAheadTotal =>
      weekAheadBills.fold(0.0, (sum, b) => sum + b.amount);

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();

    try {
      _recurring = await _repository.getAll();
      await BillReminderScheduler.scheduleReminders(confirmedBills);
      _isInitialized = true;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Add a manually entered recurring commitment.
  Future<void> addManual({
    required String merchantName,
    required double amount,
    required String frequency,
    required DateTime nextDueAt,
    String categoryId = 'other',
    bool isAutopay = false,
    String? notes,
  }) async {
    final now = DateTime.now();
    final payment = RecurringPayment(
      id: _uuid.v4(),
      merchantName: merchantName.trim(),
      amount: amount,
      frequency: frequency,
      lastPaidAt: now,
      nextDueAt: nextDueAt,
      categoryId: categoryId,
      confidence: 1.0,
      source: 'manual',
      status: RecurringStatus.confirmed,
      isAutopay: isAutopay,
      notes: notes,
      createdAt: now,
      updatedAt: now,
    );

    await _repository.undismissCandidate(merchantName);
    await _repository.upsert(payment);
    _recurring = [payment, ..._recurring];
    await BillReminderScheduler.scheduleReminders([payment]);
    notifyListeners();
  }

  /// Confirms an inferred recurring detection candidate into an active commitment.
  Future<void> confirmDetected(
    String id, {
    String? merchantName,
    double? amount,
    String? frequency,
    DateTime? nextDueAt,
    String? categoryId,
    bool? isAutopay,
    String? notes,
  }) async {
    final index = _recurring.indexWhere((r) => r.id == id);
    if (index == -1) return;
    final original = _recurring[index];

    final effectiveName = merchantName?.trim() ?? original.merchantName;
    await _repository.undismissCandidate(effectiveName);

    final updated = original.copyWith(
      merchantName: effectiveName,
      amount: amount ?? original.amount,
      frequency: frequency ?? original.frequency,
      nextDueAt: nextDueAt ?? original.nextDueAt,
      categoryId: categoryId ?? original.categoryId,
      isAutopay: isAutopay ?? original.isAutopay,
      notes: notes ?? original.notes,
      status: RecurringStatus.confirmed,
      confidence: 1.0,
      updatedAt: DateTime.now(),
    );

    await _repository.upsert(updated);
    _recurring = List<RecurringPayment>.from(_recurring)..[index] = updated;
    await BillReminderScheduler.scheduleReminders([updated]);
    notifyListeners();
  }

  /// Dismisses an unconfirmed recurring detection candidate.
  Future<void> dismissDetected(String id) async {
    final index = _recurring.indexWhere((r) => r.id == id);
    if (index != -1) {
      await _repository.dismissCandidate(_recurring[index].merchantName);
    }
    await _repository.delete(id);
    _recurring = _recurring.where((r) => r.id != id).toList();
    notifyListeners();
  }

  /// Records that the current occurrence has been paid and advances the schedule.
  Future<void> markAsPaid(
    String id, {
    DateTime? paidAt,
    double? amount,
    String? note,
    String source = 'manual',
  }) async {
    final index = _recurring.indexWhere((r) => r.id == id);
    if (index == -1) return;
    final bill = _recurring[index];
    final paymentDate = paidAt ?? DateTime.now();
    final paymentAmount = amount ?? bill.amount;

    // 1. Record immutable payment history audit entry
    final historyEntry = RecurringPaymentHistory(
      id: _uuid.v4(),
      recurringPaymentId: bill.id,
      amount: paymentAmount,
      paidAt: paymentDate,
      source: source,
      notes: note,
      createdAt: DateTime.now(),
    );

    // 2. Cancel pending reminder for the paid cycle
    await BillReminderScheduler.cancelReminder(bill);

    // 3. Compute calendar-accurate next due date
    final nextDue = RecurrenceCalculator.advanceNextDueDate(
      currentDue: bill.nextDueAt,
      frequency: bill.frequencyEnum,
      paidDate: paymentDate,
    );

    // 4. Update bill record
    final updated = bill.copyWith(
      lastPaidAt: paymentDate,
      nextDueAt: nextDue,
      updatedAt: DateTime.now(),
      status: RecurringStatus.confirmed,
    );

    // 5. Commit history and bill schedule update atomically in SQLite
    await _repository.recordPaymentAndAdvance(
      history: historyEntry,
      updatedPayment: updated,
    );
    _recurring = List<RecurringPayment>.from(_recurring)..[index] = updated;

    // 6. Schedule reminder for the next cycle
    await BillReminderScheduler.scheduleReminders([updated]);
    AlertEvaluationCoordinator().onBillResolved(bill.id);
    notifyListeners();
  }

  /// Edits an existing recurring commitment.
  Future<void> editBill(
    String id, {
    required String merchantName,
    required double amount,
    required String frequency,
    required DateTime nextDueAt,
    required String categoryId,
    bool? isAutopay,
    String? notes,
  }) async {
    final index = _recurring.indexWhere((r) => r.id == id);
    if (index == -1) return;
    final bill = _recurring[index];

    await BillReminderScheduler.cancelReminder(bill);

    final updated = bill.copyWith(
      merchantName: merchantName.trim(),
      amount: amount,
      frequency: frequency,
      nextDueAt: nextDueAt,
      categoryId: categoryId,
      isAutopay: isAutopay ?? bill.isAutopay,
      notes: notes ?? bill.notes,
      updatedAt: DateTime.now(),
    );

    await _repository.upsert(updated);
    _recurring = List<RecurringPayment>.from(_recurring)..[index] = updated;
    await BillReminderScheduler.scheduleReminders([updated]);
    notifyListeners();
  }

  /// Push the next due date by one billing cycle (snooze).
  Future<void> snoozeBill(String id) async {
    final index = _recurring.indexWhere((r) => r.id == id);
    if (index == -1) return;
    final bill = _recurring[index];

    await BillReminderScheduler.cancelReminder(bill);

    final nextDue = RecurrenceCalculator.computeNextOccurrence(
      anchorDate: bill.nextDueAt,
      currentOccurrence: bill.nextDueAt,
      frequency: bill.frequencyEnum,
    );

    final updated = bill.copyWith(
      nextDueAt: nextDue,
      updatedAt: DateTime.now(),
    );

    await _repository.upsert(updated);
    _recurring = List<RecurringPayment>.from(_recurring)..[index] = updated;
    await BillReminderScheduler.scheduleReminders([updated]);
    notifyListeners();
  }

  /// Cancels a recurring commitment, retaining history while stopping future reminders.
  Future<void> cancelBill(String id) async {
    final index = _recurring.indexWhere((r) => r.id == id);
    if (index == -1) return;
    final bill = _recurring[index];

    await BillReminderScheduler.cancelReminder(bill);

    final updated = bill.copyWith(
      status: RecurringStatus.cancelled,
      updatedAt: DateTime.now(),
    );

    await _repository.upsert(updated);
    _recurring = List<RecurringPayment>.from(_recurring)..[index] = updated;
    AlertEvaluationCoordinator().onBillResolved(bill.id);
    notifyListeners();
  }

  /// Reopens a previously cancelled recurring commitment.
  Future<void> reopenBill(String id) async {
    final index = _recurring.indexWhere((r) => r.id == id);
    if (index == -1) return;
    final bill = _recurring[index];
    final now = DateTime.now();

    var nextDue = bill.nextDueAt;
    if (nextDue.isBefore(now)) {
      nextDue = RecurrenceCalculator.advanceNextDueDate(
        currentDue: bill.nextDueAt,
        frequency: bill.frequencyEnum,
        paidDate: now,
      );
    }

    final updated = bill.copyWith(
      status: RecurringStatus.confirmed,
      nextDueAt: nextDue,
      updatedAt: now,
    );

    await _repository.upsert(updated);
    _recurring = List<RecurringPayment>.from(_recurring)..[index] = updated;
    await BillReminderScheduler.scheduleReminders([updated]);
    notifyListeners();
  }

  /// Permanently removes a recurring commitment and its history.
  Future<void> deleteBill(String id) async {
    final index = _recurring.indexWhere((r) => r.id == id);
    if (index != -1) {
      await BillReminderScheduler.cancelReminder(_recurring[index]);
    }
    await _repository.delete(id);
    _recurring = _recurring.where((r) => r.id != id).toList();
    AlertEvaluationCoordinator().onBillResolved(id);
    notifyListeners();
  }

  /// Fetches payment history records for a bill.
  Future<List<RecurringPaymentHistory>> getHistory(String recurringPaymentId) async {
    return await _repository.getHistory(recurringPaymentId);
  }

  /// Analyzes SMS transactions and syncs newly detected candidates.
  Future<void> refreshFromSms(List<SmsTransaction> sms) async {
    if (identical(_lastSmsForRecurring, sms)) return;
    _lastSmsForRecurring = sms;
    _isLoading = true;
    notifyListeners();

    final detected = RecurringDetectionService.detect(sms);
    await _repository.syncDetectedPayments(detected);

    _recurring = await _repository.getAll();
    await _notifyUpcomingBills(confirmedBills);

    _isLoading = false;
    notifyListeners();
  }

  Future<void> _notifyUpcomingBills(List<RecurringPayment> recurring) async {
    await AlertEvaluationCoordinator().onRecurringChanged(recurring);
    await BillReminderScheduler.scheduleReminders(recurring);
  }

  void clearData() {
    _recurring = [];
    _isLoading = false;
    _isInitialized = false;
    _lastSmsForRecurring = null;
    notifyListeners();
  }
}
