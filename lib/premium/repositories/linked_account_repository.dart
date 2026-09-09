import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:pet/data/database/database_helper.dart';
import 'package:pet/premium/models/linked_account.dart';

class LinkedAccountRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  Future<List<LinkedAccount>> getAll() async {
    final db = await _dbHelper.database;
    final maps = await db.query('linked_accounts', orderBy: 'accountName ASC');
    return maps.map((m) => LinkedAccount.fromMap(m)).toList();
  }

  Future<LinkedAccount?> getById(String id) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'linked_accounts',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return LinkedAccount.fromMap(maps.first);
  }

  /// Conservative matching against existing linked accounts using bank identity and account tail.
  Future<LinkedAccount?> findByBankAndTail(
      String bankName, String? tail) async {
    final all = await getAll();
    if (all.isEmpty) return null;

    final cleanBank = bankName.toLowerCase().replaceAll('bank', '').trim();

    for (final acct in all) {
      final acctNameLower = acct.accountName.toLowerCase();
      final acctBankLower = acct.bankName?.toLowerCase() ?? '';

      final matchesBank = acctNameLower.contains(cleanBank) ||
          cleanBank.contains(acctNameLower) ||
          (acctBankLower.isNotEmpty &&
              (acctBankLower.contains(cleanBank) ||
                  cleanBank.contains(acctBankLower)));

      if (!matchesBank) continue;

      // If tail is provided, ensure tail matches or account has no tail recorded yet
      if (tail != null && tail.isNotEmpty) {
        if (acct.accountTail != null && acct.accountTail!.isNotEmpty) {
          if (acct.accountTail == tail ||
              acct.accountTail!.endsWith(tail) ||
              tail.endsWith(acct.accountTail!)) {
            return acct;
          }
        } else {
          // Bank matches and account didn't have a tail recorded yet
          return acct;
        }
      } else {
        // No tail in observation, bank matches
        return acct;
      }
    }

    return null;
  }

  /// Observational balance update.
  Future<void> updateObservedBalance(
      String id, double balance, DateTime observedAt) async {
    final db = await _dbHelper.database;
    await db.update(
      'linked_accounts',
      {
        'lastObservedBalance': balance,
        'lastObservedAt': observedAt.toIso8601String(),
        'lastSyncedAt': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> upsert(LinkedAccount account) async {
    final db = await _dbHelper.database;
    await db.insert(
      'linked_accounts',
      account.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> delete(String id) async {
    final db = await _dbHelper.database;
    await db.delete('linked_accounts', where: 'id = ?', whereArgs: [id]);
  }
}
