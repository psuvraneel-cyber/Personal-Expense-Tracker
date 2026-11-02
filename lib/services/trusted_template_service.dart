import 'dart:convert';

import 'package:crypto/crypto.dart' show sha256;
import 'package:pet/data/database/database_helper.dart';
import 'package:pet/services/sms_service.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// A kind of message the user said to always add ("Always add messages
/// like this" when accepting in Pending Review).
class TrustedTemplate {
  final String templateHash;
  final String sender;

  /// `credit` or `debit`.
  final String direction;

  /// The message shape with amounts, numbers, dates and names blanked out,
  /// shown in Settings so the user can recognise it. Never the raw text.
  final String example;
  final DateTime createdAt;
  final DateTime? lastUsedAt;
  final int useCount;

  const TrustedTemplate({
    required this.templateHash,
    required this.sender,
    required this.direction,
    required this.example,
    required this.createdAt,
    this.lastUsedAt,
    this.useCount = 0,
  });

  factory TrustedTemplate.fromMap(Map<String, dynamic> map) => TrustedTemplate(
        templateHash: map['templateHash'] as String,
        sender: map['sender'] as String,
        direction: map['direction'] as String,
        example: map['example'] as String,
        createdAt: DateTime.parse(map['createdAt'] as String),
        lastUsedAt: map['lastUsedAt'] == null
            ? null
            : DateTime.parse(map['lastUsedAt'] as String),
        useCount: (map['useCount'] as int?) ?? 0,
      );
}

/// Remembers message *shapes* the user trusts, so later messages of the
/// same shape from the same sender are added without asking again.
///
/// Two messages share a shape when they differ only in amount, account or
/// reference numbers, dates, UPI IDs and the payee name. Everything stays
/// in the local encrypted database; nothing leaves the device.
class TrustedTemplateService {
  TrustedTemplateService({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper();

  final DatabaseHelper _dbHelper;

  static const String _table = 'trusted_templates';

  static final RegExp _senderHeader =
      RegExp(r'^[A-Z]{2}-([A-Z0-9]{3,9})(?:-[STGP])?$');
  static final RegExp _upiId = RegExp(r'\S+@\S+');
  static final RegExp _bracketed = RegExp(r'\([^)]*\)');
  static final RegExp _tokenWithDigit = RegExp(r'\S*\d\S*');
  static final RegExp _month = RegExp(
    r'\b(?:jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\b',
  );
  static final RegExp _spaces = RegExp(r'\s+');

  /// "JM-HDFCBK-S" and "VK-HDFCBK" are the same sender: the first two
  /// letters are the operator/circle and the suffix the message type.
  static String senderKey(String sender) {
    final upper = sender.trim().toUpperCase();
    final m = _senderHeader.firstMatch(upper);
    return m != null ? m.group(1)! : upper;
  }

  /// The message with everything that changes between two alerts of the
  /// same kind blanked out. Redacts first so it gives the same result for
  /// the raw text and the stored (redacted) copy.
  static String shapeOf(String text, {String? payee}) {
    var s = SmsService.redactSensitiveData(text)
        .toLowerCase()
        .replaceAll(_upiId, '<upi>')
        .replaceAll(_bracketed, '(<x>)');
    // Only plain names: a payee parsed as a UPI ID or number can come out
    // differently from the redacted copy, and is blanked above anyway.
    final name = payee?.trim().toLowerCase() ?? '';
    if (name.length >= 3 &&
        name != 'unknown' &&
        !name.contains('@') &&
        !name.contains(RegExp(r'\d'))) {
      s = s.replaceAll(name, ' <payee> ');
    }
    s = s
        .replaceAll(_tokenWithDigit, '#')
        .replaceAll(_month, '<mon>')
        .replaceAll(_spaces, ' ')
        .trim();
    return s;
  }

  static String hashFor({
    required String sender,
    required bool isIncome,
    required String text,
    String? payee,
  }) {
    final key = '${senderKey(sender)}|${isIncome ? 'credit' : 'debit'}|'
        '${shapeOf(text, payee: payee)}';
    return sha256.convert(utf8.encode(key)).toString();
  }

  /// Trusts messages shaped like [text] from [sender]. Returns the hash.
  Future<String> trust({
    required String sender,
    required bool isIncome,
    required String text,
    String? payee,
  }) async {
    final hash =
        hashFor(sender: sender, isIncome: isIncome, text: text, payee: payee);
    final db = await _dbHelper.database;
    await db.insert(
      _table,
      {
        'templateHash': hash,
        'sender': senderKey(sender),
        'direction': isIncome ? 'credit' : 'debit',
        'example': shapeOf(text, payee: payee),
        'createdAt': DateTime.now().toIso8601String(),
        'useCount': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    return hash;
  }

  /// The hash if this message matches a trusted shape (and counts the use),
  /// otherwise null.
  Future<String?> match({
    required String sender,
    required bool isIncome,
    required String text,
    String? payee,
  }) async {
    final hash =
        hashFor(sender: sender, isIncome: isIncome, text: text, payee: payee);
    final db = await _dbHelper.database;
    final rows = await db.query(
      _table,
      columns: ['templateHash'],
      where: 'templateHash = ?',
      whereArgs: [hash],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    await db.rawUpdate(
      'UPDATE $_table SET useCount = useCount + 1, lastUsedAt = ? '
      'WHERE templateHash = ?',
      [DateTime.now().toIso8601String(), hash],
    );
    return hash;
  }

  Future<void> remove(String templateHash) async {
    final db = await _dbHelper.database;
    await db
        .delete(_table, where: 'templateHash = ?', whereArgs: [templateHash]);
  }

  Future<List<TrustedTemplate>> all() async {
    final db = await _dbHelper.database;
    final rows = await db.query(_table, orderBy: 'createdAt DESC');
    return rows.map(TrustedTemplate.fromMap).toList();
  }
}
