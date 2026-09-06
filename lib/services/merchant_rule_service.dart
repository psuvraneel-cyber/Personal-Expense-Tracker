import 'package:pet/core/utils/app_logger.dart';
import 'package:pet/data/database/database_helper.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

/// Represents a persistent user correction for merchant name, category, or payment type.
/// Scoped strictly to exact UPI IDs or unique merchant identifiers to prevent broad false matches.
class MerchantLearnedRule {
  final String id;
  final String identifier;
  final String learnedMerchantName;
  final String? learnedCategoryId;
  final String? learnedPaymentType;
  final DateTime createdAt;
  final DateTime updatedAt;

  const MerchantLearnedRule({
    required this.id,
    required this.identifier,
    required this.learnedMerchantName,
    this.learnedCategoryId,
    this.learnedPaymentType,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'identifier': identifier.toLowerCase().trim(),
        'learnedMerchantName': learnedMerchantName,
        'learnedCategoryId': learnedCategoryId,
        'learnedPaymentType': learnedPaymentType,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory MerchantLearnedRule.fromMap(Map<String, dynamic> map) =>
      MerchantLearnedRule(
        id: map['id'] as String,
        identifier: (map['identifier'] as String).toLowerCase().trim(),
        learnedMerchantName: map['learnedMerchantName'] as String,
        learnedCategoryId: map['learnedCategoryId'] as String?,
        learnedPaymentType: map['learnedPaymentType'] as String?,
        createdAt: DateTime.parse(map['createdAt'] as String),
        updatedAt: DateTime.parse(map['updatedAt'] as String),
      );
}

/// Service managing persistent learned merchant rules.
/// Evaluated before generic heuristics to honor user corrections deterministically.
class MerchantRuleService {
  static final MerchantRuleService _instance = MerchantRuleService._internal();
  factory MerchantRuleService({DatabaseHelper? dbHelper}) {
    if (dbHelper != null) {
      _instance._dbHelper = dbHelper;
    }
    return _instance;
  }
  MerchantRuleService._internal();

  DatabaseHelper _dbHelper = DatabaseHelper();
  static const Uuid _uuid = Uuid();

  // In-memory lookup map for O(1) matching during parsing
  final Map<String, MerchantLearnedRule> _cache = {};
  bool _isLoaded = false;

  /// Loads all rules into memory cache.
  Future<void> load() async {
    try {
      final db = await _dbHelper.database;
      final rows = await db.query('merchant_learned_rules');
      _cache.clear();
      for (final row in rows) {
        final rule = MerchantLearnedRule.fromMap(row);
        _cache[rule.identifier] = rule;
      }
      _isLoaded = true;
    } catch (e) {
      AppLogger.debug('[MerchantRuleService] Error loading rules: $e');
    }
  }

  /// Attempts to find a learned rule matching the given UPI ID or raw merchant name.
  Future<MerchantLearnedRule?> matchRule({
    String? upiId,
    String? rawMerchant,
  }) async {
    if (!_isLoaded) {
      await load();
    }

    // 1. Match against UPI ID (most authoritative)
    if (upiId != null && upiId.trim().isNotEmpty) {
      final cleanUpi = upiId.toLowerCase().trim();
      final match = _cache[cleanUpi];
      if (match != null) return match;
    }

    // 2. Match against exact raw merchant name
    if (rawMerchant != null && rawMerchant.trim().isNotEmpty) {
      final cleanMerchant = rawMerchant.toLowerCase().trim();
      final match = _cache[cleanMerchant];
      if (match != null) return match;
    }

    return null;
  }

  /// Saves or updates a learned rule for a merchant identifier.
  Future<MerchantLearnedRule> learnRule({
    required String identifier,
    required String learnedMerchantName,
    String? categoryId,
    String? paymentType,
  }) async {
    final db = await _dbHelper.database;
    final now = DateTime.now();
    final cleanIdentifier = identifier.toLowerCase().trim();

    // Check if existing rule for this identifier
    final existing = await matchRule(upiId: cleanIdentifier, rawMerchant: cleanIdentifier);
    final rule = MerchantLearnedRule(
      id: existing?.id ?? _uuid.v4(),
      identifier: cleanIdentifier,
      learnedMerchantName: learnedMerchantName.trim(),
      learnedCategoryId: categoryId,
      learnedPaymentType: paymentType,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );

    await db.insert(
      'merchant_learned_rules',
      rule.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    _cache[cleanIdentifier] = rule;
    AppLogger.info(
      '[MerchantRuleService] Learned rule saved for "$cleanIdentifier" → "$learnedMerchantName"',
    );

    return rule;
  }

  /// Deletes a learned rule by ID.
  Future<void> deleteRule(String id) async {
    final db = await _dbHelper.database;
    await db.delete(
      'merchant_learned_rules',
      where: 'id = ?',
      whereArgs: [id],
    );
    _cache.removeWhere((_, rule) => rule.id == id);
  }

  /// Returns all stored rules.
  Future<List<MerchantLearnedRule>> getAllRules() async {
    if (!_isLoaded) {
      await load();
    }
    return _cache.values.toList();
  }
}
