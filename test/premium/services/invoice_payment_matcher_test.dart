import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pet/data/database/database_helper.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/premium/models/invoice.dart';
import 'package:pet/premium/models/invoice_client.dart';
import 'package:pet/premium/repositories/invoice_repository.dart';
import 'package:pet/premium/services/invoice_payment_matcher.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Invoice _invoice(
  String id, {
  double amount = 29500,
  String client = 'Acme Traders',
  String? clientId,
  InvoiceStatus status = InvoiceStatus.sent,
  DateTime? issued,
  DateTime? due,
  List<InvoicePayment> payments = const [],
}) =>
    Invoice(
      id: id,
      number: 'INV/26-27/$id',
      clientId: clientId,
      billTo: BillTo(name: client),
      issueDate: issued ?? DateTime(2026, 11, 1),
      dueDate: due ?? DateTime(2026, 11, 15),
      status: status,
      items: [InvoiceItem(description: 'Work', rate: amount)],
      payments: payments,
      createdAt: DateTime(2026, 11, 1),
      updatedAt: DateTime(2026, 11, 1),
    );

InvoiceMatch? _match(
  List<Invoice> invoices, {
  double amount = 29500,
  DateTime? date,
  String? payer = 'ACME TRADERS',
  String? upiId,
  List<InvoiceClient> clients = const [],
}) =>
    InvoicePaymentMatcher.findMatch(
      amount: amount,
      date: date ?? DateTime(2026, 11, 6, 10),
      payer: payer,
      upiId: upiId,
      invoices: invoices,
      clients: clients,
      businessState: '27',
    );

void main() {
  group('isClient', () {
    bool check(String? payer, String name, {String? upi, String? clientUpi}) =>
        InvoicePaymentMatcher.isClient(
          payer: payer,
          upiId: upi,
          billToName: name,
          client: clientUpi == null
              ? null
              : InvoiceClient(
                  id: 'c',
                  name: name,
                  upiId: clientUpi,
                  createdAt: DateTime(2026),
                  updatedAt: DateTime(2026),
                ),
        );

    test('banks shorten and rearrange names', () {
      expect(check('ACME TRADERS PVT LTD', 'Acme Traders'), isTrue);
      expect(check('R SHARMA', 'Rahul Sharma'), isTrue);
      expect(check('Rahul Sharma', 'Rahul Kumar Sharma'), isTrue);
    });

    test('a shared surname or an unknown payer is not the client', () {
      expect(check('Amit Sharma', 'Rahul Sharma'), isFalse);
      expect(check('Unknown', 'Rahul Sharma'), isFalse);
      expect(check(null, 'Rahul Sharma'), isFalse);
      expect(check('R K', 'Rahul Kumar'), isFalse);
    });

    test('the UPI ID they pay from identifies them under any name', () {
      expect(
        check('Someone Else', 'Rahul Sharma',
            upi: 'rahul@OKAXIS', clientUpi: 'rahul@okaxis'),
        isTrue,
      );
    });
  });

  group('findMatch', () {
    test('the right amount from the client is sure', () {
      final m = _match([_invoice('1')])!;
      expect(m.kind, InvoiceMatchKind.sure);
      expect(m.invoices.single.id, '1');
    });

    test('a rupee either way still matches', () {
      expect(
          _match([_invoice('1')], amount: 29499)!.kind, InvoiceMatchKind.sure);
      expect(
          _match([_invoice('1')], amount: 29501)!.kind, InvoiceMatchKind.sure);
    });

    test('the balance counts, not the invoice total', () {
      final part = _invoice('1', payments: [
        InvoicePayment(id: 'p', amount: 10000, date: DateTime(2026, 11, 2)),
      ]);
      expect(_match([part], amount: 19500)!.kind, InvoiceMatchKind.sure);
    });

    test('the oldest of two identical invoices is paid first', () {
      final m = _match([
        _invoice('new', due: DateTime(2026, 12, 1)),
        _invoice('old', due: DateTime(2026, 11, 10)),
      ])!;
      expect(m.invoices.single.id, 'old');
    });

    test('the same amount from someone else needs confirming', () {
      final m = _match(
        [_invoice('1'), _invoice('2', client: 'Beta Ltd')],
        payer: 'Unknown',
      )!;
      expect(m.kind, InvoiceMatchKind.likely);
      expect(m.invoices, hasLength(2));
    });

    test('part of the balance from the client needs confirming', () {
      final m = _match([_invoice('1')], amount: 10000)!;
      expect(m.kind, InvoiceMatchKind.likely);
    });

    test('other amounts from strangers are ignored', () {
      expect(_match([_invoice('1')], amount: 10000, payer: 'Zed'), isNull);
    });

    test('more than the balance is ignored', () {
      expect(_match([_invoice('1')], amount: 40000), isNull);
    });

    test('only sent, unpaid invoices can be paid', () {
      expect(_match([_invoice('1', status: InvoiceStatus.draft)]), isNull);
      expect(_match([_invoice('1', status: InvoiceStatus.cancelled)]), isNull);
      expect(
        _match([
          _invoice('1', payments: [
            InvoicePayment(id: 'p', amount: 29500, date: DateTime(2026, 11, 2)),
          ])
        ]),
        isNull,
      );
    });

    test('money from before the invoice was issued never matches', () {
      expect(_match([_invoice('1')], date: DateTime(2026, 10, 31)), isNull);
      // Paid on the issue day counts.
      expect(
          _match([_invoice('1')], date: DateTime(2026, 11, 1, 9)), isNotNull);
    });

    test('a zero amount does not match', () {
      expect(_match([_invoice('1')], amount: 0), isNull);
    });
  });

  test('a settled balance is cleared in full despite a rupee short', () {
    final paid = InvoicePaymentMatcher.applyPayment(
      _invoice('1'),
      paymentId: 'p',
      amount: 29499,
      date: DateTime(2026, 11, 6),
      transactionId: 't',
      businessState: '27',
      now: DateTime(2026, 11, 6),
    );
    expect(paid.balanceDue('27'), 0);
    expect(paid.payments.single.transactionId, 't');
  });

  group('recordIfInvoicePayment', () {
    late Database db;
    late Directory dir;
    late InvoiceRepository repo;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('inv_match_');
      db = await openDatabase(
        p.join(dir.path, 'pet.db'),
        version: kDatabaseVersion,
        onCreate: (db, v) => DatabaseHelper().onCreateForTesting(db, v),
      );
      repo = InvoiceRepository(database: db);
    });

    tearDown(() async {
      await db.close();
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });

    TransactionRecord credit({
      String id = 't1',
      double amount = 29500,
      String merchant = 'ACME TRADERS',
      TransactionType type = TransactionType.income,
    }) =>
        TransactionRecord(
          id: id,
          amount: amount,
          type: type,
          categoryId: 'cat_other_income',
          date: DateTime(2026, 11, 6, 10),
          merchantName: merchant,
        );

    Future<InvoiceMatchOutcome?> record(TransactionRecord t,
            {bool premium = true}) =>
        InvoicePaymentMatcher.recordIfInvoicePayment(
          t,
          repository: repo,
          isPremium: () async => premium,
          sideEffects: false,
        );

    Future<void> ledger(TransactionRecord t) => db.insert(
          'transactions',
          t.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

    test('Premium: a sure match marks the invoice paid', () async {
      await repo.upsertInvoice(_invoice('1'));
      expect(await record(credit()), InvoiceMatchOutcome.paid);
      final saved = (await repo.getInvoices()).single;
      expect(saved.balanceDue(''), 0);
      expect(saved.payments.single.transactionId, 't1');
      expect(saved.displayStatus('', DateTime(2026, 11, 6)),
          InvoiceDisplayStatus.paid);
    });

    test('the same transaction is never applied twice', () async {
      await repo.upsertInvoice(_invoice('1', amount: 50000));
      await repo.upsertInvoice(_invoice('2'));
      await record(credit());
      expect(await record(credit()), isNull);
      final payments = (await repo.getInvoices()).expand((i) => i.payments);
      expect(payments, hasLength(1));
    });

    test('Free: a sure match asks instead of changing the invoice', () async {
      await repo.upsertInvoice(_invoice('1'));
      await ledger(credit());
      expect(await record(credit(), premium: false),
          InvoiceMatchOutcome.suggested);
      expect((await repo.getInvoices()).single.payments, isEmpty);
      expect((await repo.getSuggestions()).single.invoiceId, '1');
    });

    test('a "no" is not asked again', () async {
      await repo.upsertInvoice(_invoice('1'));
      await ledger(credit());
      await record(credit(merchant: 'Unknown'));
      await repo.decideSuggestions('t1');
      expect(await repo.getSuggestions(), isEmpty);
      expect(await record(credit(merchant: 'Unknown')), isNull);
    });

    test('a payment deleted from the ledger stops being asked about', () async {
      await repo.upsertInvoice(_invoice('1'));
      await ledger(credit());
      await record(credit(merchant: 'Unknown'));
      await db.delete('transactions');
      expect(await repo.getSuggestions(), isEmpty);
    });

    test('money going out is ignored', () async {
      await repo.upsertInvoice(_invoice('1'));
      expect(await record(credit(type: TransactionType.expense)), isNull);
    });

    test('reads the payer UPI ID from the imported message', () async {
      await db.insert('sms_transactions', {
        'id': 'obs1',
        'amount': 29500,
        'merchantName': 'R',
        'bankName': 'HDFC',
        'transactionType': 'credit',
        'timestamp': DateTime(2026, 11, 6).toIso8601String(),
        'rawSmsBody': '',
        'smsSender': 'HDFC',
        'smsHash': 'h',
        'category': 'x',
        'upiId': 'acme@okaxis',
      });
      expect(await repo.upiIdOfObservation('obs1'), 'acme@okaxis');
      expect(await repo.upiIdOfObservation('missing'), isNull);
      expect(await repo.upiIdOfObservation(null), isNull);
    });
  });
}
