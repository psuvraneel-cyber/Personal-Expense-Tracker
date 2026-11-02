import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pet/core/utils/app_logger.dart';
import 'package:pet/premium/models/invoice.dart';
import 'package:pet/premium/models/invoice_client.dart';
import 'package:pet/premium/repositories/invoice_repository.dart';
import 'package:pet/premium/services/invoice_calculator.dart';
import 'package:pet/services/account_deletion_service.dart';
import 'package:pet/services/firestore_sync_service.dart';
import 'package:uuid/uuid.dart';

/// Amounts shown at the top of the Invoices screen.
@immutable
class InvoiceSummary {
  const InvoiceSummary({
    this.outstanding = 0,
    this.overdueCount = 0,
    this.overdueAmount = 0,
    this.paidThisMonth = 0,
    this.aging = const [0, 0, 0],
  });

  /// Balance due on every sent invoice.
  final double outstanding;
  final int overdueCount;
  final double overdueAmount;
  final double paidThisMonth;

  /// Outstanding by days since the invoice date: 0–30, 31–60, over 60.
  final List<double> aging;
}

/// Invoices, clients and the business profile: local first, mirrored to
/// Firestore for signed-in users (latest edit wins, like saving goals).
class InvoiceProvider extends ChangeNotifier {
  InvoiceProvider({
    InvoiceRepository? repository,
    FirestoreSyncService? firestoreSync,
    DateTime Function()? clock,
  })  : _repository = repository ?? InvoiceRepository(),
        _sync = firestoreSync ?? FirestoreSyncService(),
        _now = clock ?? DateTime.now;

  final InvoiceRepository _repository;
  final FirestoreSyncService _sync;
  final DateTime Function() _now;
  static const _uuid = Uuid();

  /// Free accounts can issue this many invoices; Premium is unlimited.
  static const int freeInvoiceLimit = 3;

  List<Invoice> _invoices = [];
  List<InvoiceClient> _clients = [];
  InvoiceProfile _profile = const InvoiceProfile();
  bool _loaded = false;
  bool _disposed = false;
  final List<StreamSubscription<Object?>> _subs = [];

  List<Invoice> get invoices => _invoices;
  List<InvoiceClient> get clients => _clients;
  InvoiceProfile get profile => _profile;
  bool get isLoaded => _loaded;

  Future<void> load({bool force = false}) async {
    if (_disposed || (_loaded && !force)) return;
    try {
      if (!kIsWeb) {
        _invoices = await _repository.getInvoices();
        _clients = await _repository.getClients();
        _profile = await _repository.getProfile();
      }
      _loaded = true;
      _notify();
      await _subscribe();
    } catch (e, st) {
      AppLogger.error('Failed to load invoices',
          error: e, stack: st, label: 'InvoiceProvider');
    }
  }

  // ── Business profile ──────────────────────────────────────────────────

  Future<void> saveProfile(InvoiceProfile profile) async {
    _profile = profile.copyWith(updatedAt: _now());
    if (!kIsWeb) await _repository.saveProfile(_profile);
    _notify();
    _upload(() => _sync.upsertInvoiceProfile(_profile));
  }

  // ── Clients ───────────────────────────────────────────────────────────

  InvoiceClient? clientById(String? id) =>
      id == null ? null : _clients.where((c) => c.id == id).firstOrNull;

  Future<InvoiceClient> saveClient(InvoiceClient client) async {
    final saved = client.copyWith(updatedAt: _now());
    _clients = [..._clients.where((c) => c.id != saved.id), saved]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (!kIsWeb) await _repository.upsertClient(saved);
    _notify();
    _upload(() => _sync.upsertInvoiceClient(saved));
    return saved;
  }

  InvoiceClient newClient(String name) {
    final now = _now();
    return InvoiceClient(
        id: _uuid.v4(), name: name.trim(), createdAt: now, updatedAt: now);
  }

  Future<void> deleteClient(String id) async {
    _clients = _clients.where((c) => c.id != id).toList();
    if (!kIsWeb) await _repository.deleteClient(id);
    _notify();
    _upload(() => _sync.deleteInvoiceClient(id));
  }

  // ── Invoices ──────────────────────────────────────────────────────────

  Invoice? invoiceById(String id) =>
      _invoices.where((i) => i.id == id).firstOrNull;

  /// Issued (non-cancelled) invoices count toward the free limit.
  int get issuedCount =>
      _invoices.where((i) => i.status != InvoiceStatus.cancelled).length;

  bool canCreateInvoice({required bool isPremium}) =>
      isPremium || issuedCount < freeInvoiceLimit;

  String nextNumber(DateTime date) => InvoiceCalculator.nextNumber(
      _profile.prefix, date, _invoices.map((i) => i.number));

  /// A blank draft for [client] with the profile's defaults.
  Invoice newDraft({InvoiceClient? client}) {
    final now = _now();
    final today = DateTime(now.year, now.month, now.day);
    return Invoice(
      id: _uuid.v4(),
      number: nextNumber(today),
      clientId: client?.id,
      billTo: client?.toBillTo() ?? const BillTo(name: ''),
      issueDate: today,
      dueDate: today.add(Duration(days: _profile.dueDays)),
      gstEnabled: _profile.gstEnabled,
      placeOfSupply: client?.stateCode ?? '',
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<Invoice> saveInvoice(Invoice invoice) async {
    final saved = invoice.copyWith(updatedAt: _now());
    _invoices = [..._invoices.where((i) => i.id != saved.id), saved];
    _sortInvoices();
    if (!kIsWeb) await _repository.upsertInvoice(saved);
    _notify();
    _upload(() => _sync.upsertInvoice(saved));
    return saved;
  }

  Future<Invoice> markSent(Invoice invoice) =>
      saveInvoice(invoice.copyWith(status: InvoiceStatus.sent));

  Future<Invoice> cancel(Invoice invoice) =>
      saveInvoice(invoice.copyWith(status: InvoiceStatus.cancelled));

  Future<Invoice> recordPayment(
    Invoice invoice, {
    required double amount,
    DateTime? date,
    String method = 'UPI',
    String? transactionId,
    String note = '',
  }) {
    final payment = InvoicePayment(
      id: _uuid.v4(),
      amount: InvoiceCalculator.round2(amount),
      date: date ?? _now(),
      method: method,
      transactionId: transactionId,
      note: note,
    );
    return saveInvoice(invoice.copyWith(
      payments: [...invoice.payments, payment],
      // Recording a payment means it was sent.
      status: invoice.status == InvoiceStatus.draft
          ? InvoiceStatus.sent
          : invoice.status,
    ));
  }

  Future<Invoice> removePayment(Invoice invoice, String paymentId) =>
      saveInvoice(invoice.copyWith(
          payments: invoice.payments.where((p) => p.id != paymentId).toList()));

  /// Only drafts are deleted; issued invoices are cancelled instead, so
  /// numbers stay consecutive (GST rules).
  Future<void> deleteDraft(Invoice invoice) async {
    if (invoice.status != InvoiceStatus.draft) return;
    _invoices = _invoices.where((i) => i.id != invoice.id).toList();
    if (!kIsWeb) await _repository.deleteInvoice(invoice.id);
    _notify();
    _upload(() => _sync.deleteInvoice(invoice.id));
  }

  InvoiceDisplayStatus statusOf(Invoice invoice) =>
      invoice.displayStatus(_profile.stateCode, _now());

  double balanceOf(Invoice invoice) => invoice.balanceDue(_profile.stateCode);

  InvoiceTotals totalsOf(Invoice invoice) => invoice.totals(_profile.stateCode);

  InvoiceSummary get summary {
    final now = _now();
    final today = DateTime(now.year, now.month, now.day);
    double outstanding = 0, overdueAmount = 0, paidThisMonth = 0;
    var overdueCount = 0;
    final aging = [0.0, 0.0, 0.0];
    for (final inv in _invoices) {
      for (final p in inv.payments) {
        if (p.date.year == now.year && p.date.month == now.month) {
          paidThisMonth += p.amount;
        }
      }
      if (inv.status != InvoiceStatus.sent) continue;
      final balance = balanceOf(inv);
      if (balance <= 0) continue;
      outstanding += balance;
      if (inv.dueDate.isBefore(today)) {
        overdueCount++;
        overdueAmount += balance;
      }
      final age = today.difference(inv.issueDate).inDays;
      aging[age <= 30 ? 0 : (age <= 60 ? 1 : 2)] += balance;
    }
    return InvoiceSummary(
      outstanding: InvoiceCalculator.round2(outstanding),
      overdueCount: overdueCount,
      overdueAmount: InvoiceCalculator.round2(overdueAmount),
      paidThisMonth: InvoiceCalculator.round2(paidThisMonth),
      aging: aging.map(InvoiceCalculator.round2).toList(),
    );
  }

  // ── Sync ──────────────────────────────────────────────────────────────

  void _upload(Future<void> Function() write) {
    if (!_sync.isAuthenticated) return;
    unawaited(write().catchError((Object e) {
      AppLogger.debug('[InvoiceProvider] Upload failed: $e');
    }));
  }

  Future<void> _subscribe() async {
    await _cancelSubscriptions();
    if (AccountDeletionService.isDeletionInProgress || !_sync.isAuthenticated) {
      return;
    }
    final session = _sync.currentSession;
    bool current() =>
        !_disposed &&
        !AccountDeletionService.isDeletionInProgress &&
        _sync.currentSession.matches(session);

    _subs.add(_sync.invoicesStream().listen((remote) async {
      if (!current()) return;
      final merged = await _mergeLatest<Invoice>(
        local: _invoices,
        remote: remote,
        id: (i) => i.id,
        updatedAt: (i) => i.updatedAt,
        saveLocal: _repository.upsertInvoice,
        upload: _sync.upsertInvoice,
      );
      if (merged != null) {
        _invoices = merged;
        _sortInvoices();
        _notify();
      }
    }));
    _subs.add(_sync.invoiceClientsStream().listen((remote) async {
      if (!current()) return;
      final merged = await _mergeLatest<InvoiceClient>(
        local: _clients,
        remote: remote,
        id: (c) => c.id,
        updatedAt: (c) => c.updatedAt,
        saveLocal: _repository.upsertClient,
        upload: _sync.upsertInvoiceClient,
      );
      if (merged != null) {
        _clients = merged
          ..sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        _notify();
      }
    }));
    _subs.add(_sync.invoiceProfileStream().listen((remote) async {
      if (!current()) return;
      final localAt = _profile.updatedAt;
      final remoteAt = remote?.updatedAt;
      if (remote != null &&
          remoteAt != null &&
          (localAt == null || remoteAt.isAfter(localAt))) {
        _profile = remote;
        if (!kIsWeb) await _repository.saveProfile(remote);
        _notify();
      } else if (_profile.isSetUp &&
          (remoteAt == null ||
              (localAt != null && localAt.isAfter(remoteAt)))) {
        _upload(() => _sync.upsertInvoiceProfile(_profile));
      }
    }));
  }

  /// Latest edit wins per id. Items only on this device are uploaded (made
  /// offline); nothing is deleted because it's missing from a snapshot.
  /// Returns the merged list, or null when nothing changed locally.
  @visibleForTesting
  Future<List<T>?> mergeLatestForTesting<T>({
    required List<T> local,
    required List<T> remote,
    required String Function(T) id,
    required DateTime Function(T) updatedAt,
  }) =>
      _mergeLatest(
        local: local,
        remote: remote,
        id: id,
        updatedAt: updatedAt,
        saveLocal: (_) async {},
        upload: (_) async {},
      );

  Future<List<T>?> _mergeLatest<T>({
    required List<T> local,
    required List<T> remote,
    required String Function(T) id,
    required DateTime Function(T) updatedAt,
    required Future<void> Function(T) saveLocal,
    required Future<void> Function(T) upload,
  }) async {
    final byId = {for (final l in local) id(l): l};
    final remoteIds = <String>{};
    var changed = false;
    for (final r in remote) {
      remoteIds.add(id(r));
      final l = byId[id(r)];
      if (l == null || updatedAt(r).isAfter(updatedAt(l))) {
        byId[id(r)] = r;
        if (!kIsWeb) await saveLocal(r);
        changed = true;
      } else if (updatedAt(l).isAfter(updatedAt(r))) {
        _upload(() => upload(l));
      }
    }
    for (final l in local) {
      if (!remoteIds.contains(id(l))) _upload(() => upload(l));
    }
    return changed ? byId.values.toList() : null;
  }

  Future<void> _cancelSubscriptions() async {
    final subs = List.of(_subs);
    _subs.clear();
    for (final s in subs) {
      await s.cancel();
    }
  }

  void _sortInvoices() => _invoices.sort((a, b) {
        final byDate = b.issueDate.compareTo(a.issueDate);
        return byDate != 0 ? byDate : b.number.compareTo(a.number);
      });

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Sign-out: forget everything in memory (the local wipe clears tables).
  Future<void> clearData() async {
    _invoices = [];
    _clients = [];
    _profile = const InvoiceProfile();
    _loaded = false;
    await _cancelSubscriptions();
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}
