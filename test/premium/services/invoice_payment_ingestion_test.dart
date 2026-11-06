import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pet/core/constants/categories.dart';
import 'package:pet/data/database/database_helper.dart';
import 'package:pet/data/models/transaction.dart';
import 'package:pet/premium/models/invoice.dart';
import 'package:pet/premium/models/invoice_client.dart';
import 'package:pet/premium/repositories/invoice_repository.dart';
import 'package:pet/services/financial_ingestion_service.dart';
import 'package:pet/services/native_sms_reader.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// From a real bank message through to the invoice, on the production
/// schema. (Debug builds count as Premium.)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late Directory dir;
  late FinancialIngestionService service;
  late InvoiceRepository repo;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({'notifications_enabled': false});
    dir = Directory.systemTemp.createTempSync('inv_ingest_');
    db = await openDatabase(
      p.join(dir.path, 'pet.db'),
      version: kDatabaseVersion,
      onCreate: (db, v) => DatabaseHelper().onCreateForTesting(db, v),
    );
    DatabaseHelper.setTestDatabase(db);
    service = FinancialIngestionService();
    repo = InvoiceRepository();
  });

  tearDown(() async {
    DatabaseHelper.setTestDatabase(null);
    await db.close();
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Invoice invoice({required double amount, String client = 'Rahul Sharma'}) =>
      Invoice(
        id: 'i1',
        number: 'INV/26-27/0001',
        billTo: BillTo(name: client),
        issueDate: DateTime(2026, 8, 1),
        dueDate: DateTime(2026, 8, 15),
        status: InvoiceStatus.sent,
        items: [InvoiceItem(description: 'Work', rate: amount)],
        createdAt: DateTime(2026, 8, 1),
        updatedAt: DateTime(2026, 8, 1),
      );

  NativeSmsMessage credit(String amount) => NativeSmsMessage(
        address: 'JM-HDFCBK-S',
        body: 'Rs $amount credited to HDFC Bank A/c XX1234 on 24-Aug-26 '
            'from VPA 9876543210@ybl (RAHUL SHARMA). UPI Ref 412345678901.',
        dateMillis: DateTime(2026, 8, 24, 20).millisecondsSinceEpoch,
        source: 'sms',
      );

  Future<TransactionRecord> ledgerRow(String id) async =>
      TransactionRecord.fromMap((await db
              .query('transactions', where: 'id = ?', whereArgs: [id]))
          .single);

  test(
      'a client paying in full marks the invoice paid and files it as '
      'Freelance, not "From people"', () async {
    await repo.upsertInvoice(invoice(amount: 1500));
    final txn = await service.ingestMessage(credit('1,500.00'));
    expect(txn, isNotNull);

    final saved = (await repo.getInvoices()).single;
    expect(saved.balanceDue(''), 0);
    expect(saved.payments.single.transactionId, txn!.id);

    final row = await ledgerRow(txn.id);
    expect(row.categoryId, 'cat_freelance');
    expect(row.countsAsIncome, isTrue);
    // Created, then re-filed: both go to the cloud.
    expect(await db.query('transaction_sync_queue'), hasLength(2));
  });

  test(
      'a part payment leaves the invoice and the category alone until '
      'confirmed', () async {
    await repo.upsertInvoice(invoice(amount: 5000));
    final txn = await service.ingestMessage(credit('1,500.00'));

    expect((await repo.getInvoices()).single.payments, isEmpty);
    expect((await repo.getSuggestions()).single.amount, 1500);
    expect((await ledgerRow(txn!.id)).categoryId, kFromPeopleCategoryId);
  });

  test('confirming files the payment as client income', () async {
    await repo.upsertInvoice(invoice(amount: 5000));
    final txn = await service.ingestMessage(credit('1,500.00'));
    await service.fileAsClientIncome(txn!.id);
    expect((await ledgerRow(txn.id)).categoryId, 'cat_freelance');
  });

  test('money from someone unconnected changes nothing', () async {
    await repo.upsertInvoice(invoice(amount: 9000, client: 'Beta Ltd'));
    final txn = await service.ingestMessage(credit('1,500.00'));
    expect(txn, isNotNull);
    expect((await repo.getInvoices()).single.payments, isEmpty);
    expect(await repo.getSuggestions(), isEmpty);
  });

  test('a salary credit keeps its category even when it pays an invoice',
      () async {
    await repo
        .upsertInvoice(invoice(amount: 50000, client: 'Acme Technologies'));
    final txn = await service.ingestMessage(NativeSmsMessage(
      address: 'JM-HDFCBK-S',
      body: 'Rs 50,000.00 credited to HDFC Bank A/c XX1234 on 24-Aug-26 by '
          'NEFT from ACME TECHNOLOGIES - SALARY.',
      dateMillis: DateTime(2026, 8, 24, 20).millisecondsSinceEpoch,
      source: 'sms',
    ));
    expect((await repo.getInvoices()).single.balanceDue(''), 0);
    expect((await ledgerRow(txn!.id)).categoryId, 'cat_salary');
  });

  test('the client UPI ID identifies a payer whose name does not match',
      () async {
    final now = DateTime(2026, 8, 1);
    await repo.upsertClient(InvoiceClient(
      id: 'c1',
      name: 'Blue Lotus Studio',
      upiId: '9876543210@ybl',
      createdAt: now,
      updatedAt: now,
    ));
    await repo.upsertInvoice(Invoice(
      id: 'i1',
      number: 'INV/26-27/0001',
      clientId: 'c1',
      billTo: const BillTo(name: 'Blue Lotus Studio'),
      issueDate: now,
      dueDate: DateTime(2026, 8, 15),
      status: InvoiceStatus.sent,
      items: const [InvoiceItem(description: 'Work', rate: 1500)],
      createdAt: now,
      updatedAt: now,
    ));
    await service.ingestMessage(credit('1,500.00'));
    expect((await repo.getInvoices()).single.balanceDue(''), 0);
  });
}
