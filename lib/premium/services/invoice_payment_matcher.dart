import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:pet/core/utils/app_logger.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/premium/models/invoice.dart';
import 'package:pet/premium/models/invoice_client.dart';
import 'package:pet/premium/models/invoice_payment_suggestion.dart';
import 'package:pet/premium/models/notification_category.dart';
import 'package:pet/premium/repositories/invoice_repository.dart';
import 'package:pet/premium/services/bill_payment_matcher.dart';
import 'package:pet/premium/services/invoice_calculator.dart';
import 'package:pet/premium/services/invoice_reminder_scheduler.dart';
import 'package:pet/premium/services/notification_service.dart';
import 'package:pet/premium/services/premium_entitlement_service.dart';
import 'package:pet/services/firestore_sync_service.dart';
import 'package:uuid/uuid.dart';

enum InvoiceMatchKind {
  /// Right amount from the right client: safe to apply.
  sure,

  /// Could be this invoice; the user decides.
  likely,
}

/// What [InvoicePaymentMatcher.findMatch] concluded for one payment.
class InvoiceMatch {
  const InvoiceMatch(this.kind, this.invoices);

  final InvoiceMatchKind kind;

  /// Oldest due first. A sure match has exactly one.
  final List<Invoice> invoices;
}

/// What happened to a transaction, so the importer knows what to refresh.
enum InvoiceMatchOutcome { paid, suggested }

/// Notices money arriving for an open invoice (on-device, from imported
/// bank SMS and UPI app alerts; message text is never sent anywhere).
///
/// - Sure: the amount equals the balance (within [amountTolerance]) and the
///   payer is the client. Premium: the invoice is marked paid. Free: asks.
/// - Likely: the exact amount from someone else, or part of the balance
///   from the client. Always asks: a wrong edit to an invoice costs more
///   than one tap.
///
/// Payments older than the invoice never match, so a re-scan of old
/// messages can't mark anything paid.
class InvoicePaymentMatcher {
  InvoicePaymentMatcher._();

  static const double amountTolerance = 1;

  /// Most invoices one payment is offered against.
  static const int maxSuggestions = 3;

  static const _uuid = Uuid();

  /// Whether [payer] (or their [upiId]) is [client] / [billToName].
  ///
  /// Banks shorten names, so as well as the bill matcher's name check this
  /// accepts initials ("R Sharma" for "Rahul Sharma"), provided at least
  /// one full word matches and no word disagrees.
  @visibleForTesting
  static bool isClient({
    required String? payer,
    required String? upiId,
    required String billToName,
    InvoiceClient? client,
  }) {
    final clientUpi = client?.upiId.trim().toLowerCase() ?? '';
    final paidFrom = upiId?.trim().toLowerCase() ?? '';
    if (clientUpi.isNotEmpty && clientUpi == paidFrom) return true;

    final name = payer?.trim() ?? '';
    if (name.isEmpty || name.toLowerCase() == 'unknown') return false;
    for (final known in {client?.name ?? '', billToName}) {
      if (known.trim().isEmpty) continue;
      if (BillPaymentMatcher.sameMerchant(name, known)) return true;
      if (_wordsMatch(name, known)) return true;
    }
    return false;
  }

  static List<String> _words(String s) => s
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((w) => w.isNotEmpty)
      .toList();

  static bool _wordsMatch(String a, String b) {
    final x = _words(a), y = _words(b);
    if (x.isEmpty || y.isEmpty) return false;
    final shorter = x.length <= y.length ? x : y;
    final longer = x.length <= y.length ? y : x;
    var fullWord = false;
    for (final w in shorter) {
      if (longer.contains(w)) {
        if (w.length >= 4) fullWord = true;
      } else if (w.length > 1 || !longer.any((l) => l.startsWith(w))) {
        return false;
      }
    }
    return fullWord;
  }

  /// The pure decision: which open invoice, if any, [amount] pays.
  static InvoiceMatch? findMatch({
    required double amount,
    required DateTime date,
    required String? payer,
    required String? upiId,
    required List<Invoice> invoices,
    required List<InvoiceClient> clients,
    required String businessState,
  }) {
    if (amount <= 0) return null;
    final day = DateTime(date.year, date.month, date.day);
    final open = invoices.where((i) {
      if (i.status != InvoiceStatus.sent) return false;
      if (day.isBefore(i.issueDate)) return false;
      return i.balanceDue(businessState) > 0;
    }).toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    if (open.isEmpty) return null;

    bool exact(Invoice i) =>
        (i.balanceDue(businessState) - amount).abs() <= amountTolerance;
    bool fromClient(Invoice i) {
      final client = i.clientId == null
          ? null
          : clients.where((c) => c.id == i.clientId).firstOrNull;
      return isClient(
        payer: payer,
        upiId: upiId,
        billToName: i.billTo.name,
        client: client,
      );
    }

    final ownInvoices = open.where(fromClient).toList();
    final ownExact = ownInvoices.where(exact).toList();
    if (ownExact.isNotEmpty) {
      return InvoiceMatch(InvoiceMatchKind.sure, [ownExact.first]);
    }
    final part = ownInvoices
        .where((i) => amount < i.balanceDue(businessState))
        .take(maxSuggestions)
        .toList();
    if (part.isNotEmpty) return InvoiceMatch(InvoiceMatchKind.likely, part);

    final sameAmount = open.where(exact).take(maxSuggestions).toList();
    if (sameAmount.isNotEmpty) {
      return InvoiceMatch(InvoiceMatchKind.likely, sameAmount);
    }
    return null;
  }

  /// A new payment built the same way everywhere: a balance within the
  /// tolerance is settled in full, so ₹29,499 clears ₹29,500.
  static Invoice applyPayment(
    Invoice invoice, {
    required String paymentId,
    required double amount,
    required DateTime date,
    required String transactionId,
    required String businessState,
    required DateTime now,
  }) {
    final balance = invoice.balanceDue(businessState);
    final settles = (balance - amount).abs() <= amountTolerance;
    return invoice.copyWith(
      payments: [
        ...invoice.payments,
        InvoicePayment(
          id: paymentId,
          amount: InvoiceCalculator.round2(settles ? balance : amount),
          date: date,
          transactionId: transactionId,
          note: 'Matched from bank message',
        ),
      ],
      updatedAt: now,
    );
  }

  /// Checks a newly recorded [txn] against open invoices. Best effort:
  /// errors are logged, never thrown, so it can't block an import. Runs in
  /// whichever isolate imported the message, so it works from the database,
  /// not from InvoiceProvider.
  static Future<InvoiceMatchOutcome?> recordIfInvoicePayment(
    TransactionRecord txn, {
    String? userId,
    InvoiceRepository? repository,
    FirestoreSyncService? firestoreSync,
    Future<bool> Function()? isPremium,
    bool sideEffects = true,
    DateTime Function()? clock,
  }) async {
    if (kIsWeb || txn.type != TransactionType.income) return null;
    try {
      final repo = repository ?? InvoiceRepository();
      final invoices = await repo.getInvoices();
      if (invoices.isEmpty) return null;
      // Each payment is looked at once, whatever was decided about it.
      if (invoices
          .any((i) => i.payments.any((p) => p.transactionId == txn.id))) {
        return null;
      }
      if (await repo.hasSuggestionFor(txn.id)) return null;

      final profile = await repo.getProfile();
      final match = findMatch(
        amount: txn.amount,
        date: txn.date,
        payer: txn.merchantName,
        upiId: await repo.upiIdOfObservation(txn.sourceObservationId),
        invoices: invoices,
        clients: await repo.getClients(),
        businessState: profile.stateCode,
      );
      if (match == null) return null;

      final now = (clock ?? DateTime.now)();
      final automatic = match.kind == InvoiceMatchKind.sure &&
          await (isPremium ?? () => _isPremium(userId))();
      if (automatic) {
        final paid = applyPayment(
          match.invoices.single,
          paymentId: _uuid.v4(),
          amount: txn.amount,
          date: txn.date,
          transactionId: txn.id,
          businessState: profile.stateCode,
          now: now,
        );
        await repo.upsertInvoice(paid);
        if (sideEffects) await _afterPaid(paid, profile, firestoreSync);
        return InvoiceMatchOutcome.paid;
      }

      for (final invoice in match.invoices) {
        await repo.addSuggestion(InvoicePaymentSuggestion(
          id: _uuid.v4(),
          invoiceId: invoice.id,
          transactionId: txn.id,
          amount: txn.amount,
          date: txn.date,
          payer: _displayPayer(txn.merchantName),
        ));
      }
      if (sideEffects) await _notifySuggestion(txn, match.invoices.first);
      return InvoiceMatchOutcome.suggested;
    } catch (e) {
      AppLogger.debug('[InvoicePaymentMatcher] failed: $e');
      return null;
    }
  }

  static Future<bool> _isPremium(String? userId) async {
    try {
      return await PremiumEntitlementService.isPremiumEnabled(uid: userId);
    } catch (_) {
      return false;
    }
  }

  static String _displayPayer(String? merchant) {
    final name = merchant?.trim() ?? '';
    return name.toLowerCase() == 'unknown' ? '' : name;
  }

  static String _rupees(double v) => '₹${v.toStringAsFixed(0)}';

  static Future<void> _afterPaid(
    Invoice paid,
    InvoiceProfile profile,
    FirestoreSyncService? firestoreSync,
  ) async {
    final balance = paid.balanceDue(profile.stateCode);
    try {
      await InvoiceReminderScheduler.sync(paid, balance: balance);
      await NotificationService.showInstant(
        id: NotificationService.collisionSafeId('inv_paid_${paid.id}'),
        title: 'Invoice paid',
        body: '${paid.number} from ${paid.billTo.name}: '
            '${_rupees(paid.amountPaid)} received.',
        category: NotificationCategory.invoice,
        payload: 'invoice:${paid.id}',
      );
    } catch (_) {}
    // Push it now: this may be a background isolate with no provider.
    try {
      final sync = firestoreSync ?? FirestoreSyncService();
      if (sync.isAuthenticated) await sync.upsertInvoice(paid);
    } catch (_) {}
  }

  static Future<void> _notifySuggestion(
    TransactionRecord txn,
    Invoice invoice,
  ) async {
    try {
      final payer = _displayPayer(txn.merchantName);
      await NotificationService.showInstant(
        id: NotificationService.collisionSafeId('inv_match_${txn.id}'),
        title: 'Is this an invoice payment?',
        body: '${_rupees(txn.amount)}${payer.isEmpty ? '' : ' from $payer'} '
            'may be for ${invoice.number}. Tap to confirm.',
        category: NotificationCategory.invoice,
        payload: 'invoice:${invoice.id}',
      );
    } catch (_) {}
  }
}
