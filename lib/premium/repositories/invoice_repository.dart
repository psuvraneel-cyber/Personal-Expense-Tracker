import 'dart:convert';

import 'package:pet/data/database/database_helper.dart';
import 'package:pet/premium/models/invoice.dart';
import 'package:pet/premium/models/invoice_client.dart';
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
