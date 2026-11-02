import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pet/data/database/database_helper.dart';
import 'package:pet/premium/models/invoice.dart';
import 'package:pet/premium/models/invoice_client.dart';
import 'package:pet/premium/providers/invoice_provider.dart';
import 'package:pet/premium/repositories/invoice_repository.dart';
import 'package:pet/premium/services/invoice_pdf_service.dart';
import 'package:pet/services/firestore_sync_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Signed out: nothing is uploaded or streamed.
class _OfflineSync implements FirestoreSyncService {
  @override
  bool get isAuthenticated => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late Directory dir;
  late InvoiceProvider provider;
  var now = DateTime(2026, 11, 10, 9);

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('invoices_');
    db = await openDatabase(
      p.join(dir.path, 'pet.db'),
      version: kDatabaseVersion,
      onCreate: (db, v) => DatabaseHelper().onCreateForTesting(db, v),
    );
    now = DateTime(2026, 11, 10, 9);
    provider = InvoiceProvider(
      repository: InvoiceRepository(database: db),
      firestoreSync: _OfflineSync(),
      clock: () => now,
    );
    await provider.load();
  });

  tearDown(() async {
    provider.dispose();
    await db.close();
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<Invoice> issue(String client, List<InvoiceItem> items,
      {DateTime? due}) async {
    final c = await provider.saveClient(provider.newClient(client));
    final draft = provider.newDraft(client: c);
    return provider.saveInvoice(draft.copyWith(
      items: items,
      status: InvoiceStatus.sent,
      dueDate: due,
    ));
  }

  test('profile, clients and invoices survive a reload', () async {
    await provider.saveProfile(const InvoiceProfile(
        businessName: 'Alice Studio', upiId: 'alice@okaxis', stateCode: '27'));
    await issue('Acme', const [InvoiceItem(description: 'Design', rate: 5000)]);

    final fresh = InvoiceProvider(
        repository: InvoiceRepository(database: db),
        firestoreSync: _OfflineSync(),
        clock: () => now);
    await fresh.load();
    expect(fresh.profile.businessName, 'Alice Studio');
    expect(fresh.clients.single.name, 'Acme');
    expect(fresh.invoices.single.items.single.description, 'Design');
    fresh.dispose();
  });

  test('numbers are consecutive within the financial year', () async {
    final a = await issue('A', const [InvoiceItem(description: 'x', rate: 1)]);
    final b = await issue('B', const [InvoiceItem(description: 'x', rate: 1)]);
    expect(a.number, 'INV/26-27/0001');
    expect(b.number, 'INV/26-27/0002');
  });

  test('payments move an invoice from sent to partly paid to paid', () async {
    var inv =
        await issue('Acme', const [InvoiceItem(description: 'x', rate: 1000)]);
    expect(provider.statusOf(inv), InvoiceDisplayStatus.sent);
    inv = await provider.recordPayment(inv, amount: 400);
    expect(provider.statusOf(inv), InvoiceDisplayStatus.partiallyPaid);
    expect(provider.balanceOf(inv), 600);
    inv = await provider.recordPayment(inv, amount: 600, method: 'Cash');
    expect(provider.statusOf(inv), InvoiceDisplayStatus.paid);
    inv = await provider.removePayment(inv, inv.payments.last.id);
    expect(provider.balanceOf(inv), 600);
  });

  test('the free limit counts issued invoices, not cancelled ones', () async {
    for (var i = 0; i < 3; i++) {
      await issue('C$i', const [InvoiceItem(description: 'x', rate: 1)]);
    }
    expect(provider.canCreateInvoice(isPremium: false), isFalse);
    expect(provider.canCreateInvoice(isPremium: true), isTrue);
    await provider.cancel(provider.invoices.first);
    expect(provider.canCreateInvoice(isPremium: false), isTrue);
  });

  test('only drafts can be deleted; issued invoices are cancelled', () async {
    final sent =
        await issue('A', const [InvoiceItem(description: 'x', rate: 1)]);
    await provider.deleteDraft(sent);
    expect(provider.invoiceById(sent.id), isNotNull);
    final draft = await provider.saveInvoice(provider.newDraft());
    await provider.deleteDraft(draft);
    expect(provider.invoiceById(draft.id), isNull);
  });

  test('summary: outstanding, overdue, paid this month and aging', () async {
    final overdue = await issue(
        'Old', const [InvoiceItem(description: 'x', rate: 3000)],
        due: DateTime(2026, 11, 1));
    final current =
        await issue('New', const [InvoiceItem(description: 'x', rate: 2000)]);
    await provider.recordPayment(current, amount: 500);
    // Something paid last month doesn't count as this month.
    await provider.recordPayment(overdue,
        amount: 1000, date: DateTime(2026, 10, 20));

    final s = provider.summary;
    expect(s.outstanding, 2000 + 1500);
    expect(s.overdueCount, 1);
    expect(s.overdueAmount, 2000);
    expect(s.paidThisMonth, 500);
    expect(s.aging, [3500, 0, 0]);

    now = DateTime(2027, 1, 20);
    expect(provider.summary.aging, [0, 0, 3500]);
  });

  test('cloud merge: the latest edit wins and nothing is dropped', () async {
    final a = Invoice(
      id: 'a',
      number: 'INV/26-27/0001',
      billTo: const BillTo(name: 'Local'),
      issueDate: DateTime(2026, 11, 1),
      dueDate: DateTime(2026, 11, 15),
      createdAt: DateTime(2026, 11, 1),
      updatedAt: DateTime(2026, 11, 2),
    );
    final remoteNewer = a.copyWith(
        billTo: const BillTo(name: 'Remote'), updatedAt: DateTime(2026, 11, 3));
    final remoteOnly = a.copyWith(number: 'INV/26-27/0002');
    final merged = await provider.mergeLatestForTesting<Invoice>(
      local: [a],
      remote: [
        remoteNewer,
        Invoice.fromMap({...remoteOnly.toMap(), 'id': 'b'})
      ],
      id: (i) => i.id,
      updatedAt: (i) => i.updatedAt,
    );
    expect(merged!.map((i) => i.id).toSet(), {'a', 'b'});
    expect(merged.firstWhere((i) => i.id == 'a').billTo.name, 'Remote');

    final unchanged = await provider.mergeLatestForTesting<Invoice>(
      local: [remoteNewer],
      remote: [a],
      id: (i) => i.id,
      updatedAt: (i) => i.updatedAt,
    );
    expect(unchanged, isNull);
  });

  test('the PDF builds, with a UPI QR only when something is due', () async {
    await provider.saveProfile(const InvoiceProfile(
      businessName: 'Alice Studio',
      upiId: 'alice@okaxis',
      gstEnabled: true,
      gstin: '27AAPFU0939F1ZV',
      stateCode: '27',
    ));
    var inv = await issue('Acme', const [
      InvoiceItem(
          description: 'Design', rate: 10000, gstRate: 18, hsnSac: '998391'),
    ]);
    inv = await provider
        .saveInvoice(inv.copyWith(gstEnabled: true, placeOfSupply: '29'));

    final bytes =
        await InvoicePdfService.build(inv, provider.profile, now: now);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    final link = InvoicePdfService.paymentLink(inv, provider.profile)!;
    expect(Uri.parse(link).queryParameters['am'], '11800.00');
    expect(InvoicePdfService.fileName(inv), 'Invoice_INV-26-27-0001.pdf');

    inv = await provider.recordPayment(inv, amount: 11800);
    expect(InvoicePdfService.paymentLink(inv, provider.profile), isNull);
    final paidPdf =
        await InvoicePdfService.build(inv, provider.profile, now: now);
    expect(paidPdf, isNotEmpty);
  });
}
