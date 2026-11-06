import 'dart:convert';

import 'package:pet/data/database/database_helper.dart';
import 'package:pet/premium/models/invoice.dart';
import 'package:pet/premium/models/invoice_client.dart';
import 'package:pet/premium/models/invoice_payment_suggestion.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// Local (encrypted SQLite) storage for invoices, clients and the business
/// profile.
class InvoiceRepository {
  InvoiceRepository({DatabaseHelper? dbHelper, Database? database})
      : _dbHelper = dbHelper ?? DatabaseHelper(),
        _database = database;

  final DatabaseHelper _dbHelper;
  final Database? _database;

  static const _profileId = 'default';

  Future<Database> get _db async => _database ?? await _dbHelper.database;

  // ── Invoices ──────────────────────────────────────────────────────────

  Future<List<Invoice>> getInvoices() async {
    final rows = await (await _db)
        .query('invoices', orderBy: 'issueDate DESC, number DESC');
    return rows.map(Invoice.fromRow).toList();
  }

  Future<void> upsertInvoice(Invoice invoice) async {
    await (await _db).insert('invoices', invoice.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteInvoice(String id) async {
    await (await _db).delete('invoices', where: 'id = ?', whereArgs: [id]);
  }

  // ── Clients ───────────────────────────────────────────────────────────

  Future<List<InvoiceClient>> getClients() async {
    final rows = await (await _db)
        .query('invoice_clients', orderBy: 'name COLLATE NOCASE');
    return rows.map(InvoiceClient.fromMap).toList();
  }

  Future<void> upsertClient(InvoiceClient client) async {
    await (await _db).insert('invoice_clients', client.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteClient(String id) async {
    await (await _db)
        .delete('invoice_clients', where: 'id = ?', whereArgs: [id]);
  }

  // ── Payment suggestions ───────────────────────────────────────────────

  /// Open questions, newest first. Payments the user has since deleted from
  /// the ledger drop out on their own.
  Future<List<InvoicePaymentSuggestion>> getSuggestions() async {
    final rows = await (await _db).rawQuery('''
      SELECT s.* FROM invoice_payment_suggestions s
      JOIN transactions t ON t.id = s.transactionId
      WHERE s.decided = 0
      ORDER BY s.date DESC
    ''');
    return rows.map(InvoicePaymentSuggestion.fromRow).toList();
  }

  Future<void> addSuggestion(InvoicePaymentSuggestion suggestion) async {
    await (await _db).insert(
      'invoice_payment_suggestions',
      suggestion.toRow(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Whether this payment was already looked at, whatever the answer was.
  Future<bool> hasSuggestionFor(String transactionId) async {
    final rows = await (await _db).query(
      'invoice_payment_suggestions',
      columns: ['id'],
      where: 'transactionId = ?',
      whereArgs: [transactionId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Answered (yes or no): every invoice it was offered against is settled,
  /// and it isn't asked again.
  Future<void> decideSuggestions(String transactionId) async {
    await (await _db).update(
      'invoice_payment_suggestions',
      {'decided': 1},
      where: 'transactionId = ?',
      whereArgs: [transactionId],
    );
  }

  /// The payer's UPI ID as read from the message, when there was one.
  Future<String?> upiIdOfObservation(String? observationId) async {
    if (observationId == null) return null;
    final rows = await (await _db).query(
      'sms_transactions',
      columns: ['upiId'],
      where: 'id = ?',
      whereArgs: [observationId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['upiId'] as String?;
  }

  // ── Business profile ──────────────────────────────────────────────────

  Future<InvoiceProfile> getProfile() async {
    final rows = await (await _db).query('invoice_profile',
        where: 'id = ?', whereArgs: [_profileId], limit: 1);
    if (rows.isEmpty) return const InvoiceProfile();
    return InvoiceProfile.fromMap(
        jsonDecode(rows.first['data'] as String) as Map<String, dynamic>);
  }

  Future<void> saveProfile(InvoiceProfile profile) async {
    await (await _db).insert(
      'invoice_profile',
      {'id': _profileId, 'data': jsonEncode(profile.toMap())},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
