import 'dart:async';
import 'dart:io' show Directory;
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:pet/services/platform_stub.dart'
    if (dart.library.io) 'package:pet/services/platform_native.dart'
    as platform;
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pet/core/constants/categories.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  static Completer<Database>? _dbCompleter;

  factory DatabaseHelper() => _instance;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    
    if (_dbCompleter == null) {
      _dbCompleter = Completer<Database>();
      try {
        _database = await _initDatabase();
        _dbCompleter!.complete(_database);
      } catch (e) {
        _dbCompleter!.completeError(e);
        _dbCompleter = null;
        rethrow;
      }
    }
    return _dbCompleter!.future;
  }

  Future<Database> _initDatabase() async {
    // Use FFI for Windows/Linux/macOS desktop (not needed on web or mobile)
    if (!kIsWeb &&
        (platform.isWindows || platform.isLinux || platform.isMacOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final Directory documentsDirectory =
        await getApplicationDocumentsDirectory();
    final String path = join(documentsDirectory.path, 'pet_tracker.db');

    return await openDatabase(
      path,
      version: 10,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onOpen: (db) async {
        // Enable foreign key constraint enforcement for every connection.
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  /// Run SQLite integrity check on startup.
  ///
  /// Returns `true` if the database is healthy, `false` if corruption
  /// is detected. On corruption, a SharedPreferences flag is set so
  /// the app can offer a database reset while preserving cloud data.
  Future<bool> runIntegrityCheck() async {
    try {
      final db = await database;
      final result = await db.rawQuery('PRAGMA integrity_check');
      final status = result.firstOrNull?['integrity_check'] as String? ?? '';
      if (status == 'ok') {
        debugPrint('[DB] Integrity check: ok');
        return true;
      } else {
        debugPrint('[DB] ⚠️ Integrity check FAILED: $status');
        return false;
      }
    } catch (e) {
      debugPrint('[DB] Integrity check error: $e');
      return false;
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    // Create transactions table
    await db.execute('''
      CREATE TABLE transactions (
        id TEXT PRIMARY KEY,
        amount REAL NOT NULL,
        type TEXT NOT NULL,
        categoryId TEXT NOT NULL,
        date TEXT NOT NULL,
        note TEXT DEFAULT '',
        paymentMethod TEXT DEFAULT 'UPI',
        isRecurring INTEGER DEFAULT 0,
        recurringFrequency TEXT,
        merchantName TEXT,
        taxCategory TEXT,
        source TEXT DEFAULT 'manual',
        accountId TEXT,
        updatedAt TEXT
      )
    ''');

    // Create categories table
    await db.execute('''
      CREATE TABLE categories (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        iconCodePoint INTEGER NOT NULL,
        iconFontFamily TEXT,
        colorValue INTEGER NOT NULL,
        isCustom INTEGER DEFAULT 0,
        type TEXT DEFAULT 'expense'
      )
    ''');

    // Create budgets table
    await db.execute('''
      CREATE TABLE budgets (
        id TEXT PRIMARY KEY,
        categoryId TEXT NOT NULL,
        amount REAL NOT NULL,
        month INTEGER NOT NULL,
        year INTEGER NOT NULL,
        UNIQUE(categoryId, month, year)
      )
    ''');

    // Create sms_transactions table
    await _createSmsTransactionsTable(db);

    // Create classification system tables
    await _createClassificationTables(db);

    // Create user feedback table
    await _createUserFeedbackTable(db);

    // Create premium feature tables
    await _createPremiumTables(db);

    // Seed default categories
    await _seedDefaultCategories(db);
  }

  /// Handle database version upgrades.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createSmsTransactionsTable(db);
    }
    if (oldVersion < 3) {
      // Add new columns for enhanced UPI parsing
      await db.execute(
        'ALTER TABLE sms_transactions ADD COLUMN transactionSubType TEXT DEFAULT \'payment\'',
      );
      await db.execute(
        'ALTER TABLE sms_transactions ADD COLUMN referenceId TEXT',
      );
      await db.execute('ALTER TABLE sms_transactions ADD COLUMN upiId TEXT');
      await db.execute(
        'ALTER TABLE sms_transactions ADD COLUMN confidence REAL DEFAULT 0.5',
      );
    }
    if (oldVersion < 4) {
      await _createClassificationTables(db);
    }
    if (oldVersion < 5) {
      // Add source column for tracking SMS vs notification origin
      await db.execute(
        'ALTER TABLE sms_transactions ADD COLUMN source TEXT DEFAULT \'sms\'',
      );
      // Create user feedback table for persisting parser corrections
      await _createUserFeedbackTable(db);
      // Index on referenceId for cross-source dedup
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_sms_reference_id
        ON sms_transactions (referenceId)
      ''');
    }
    if (oldVersion < 6) {
      await db.execute('ALTER TABLE transactions ADD COLUMN merchantName TEXT');
      await db.execute('ALTER TABLE transactions ADD COLUMN taxCategory TEXT');
      await db.execute(
        'ALTER TABLE transactions ADD COLUMN source TEXT DEFAULT \'manual\'',
      );
      await db.execute('ALTER TABLE transactions ADD COLUMN accountId TEXT');

      await _createPremiumTables(db);
    }
    if (oldVersion < 7) {
      // Add emoji column to saving_goals (added when emoji picker was introduced)
      final goalCols = await db.rawQuery('PRAGMA table_info(saving_goals)');
      final hasEmoji = goalCols.any((c) => c['name'] == 'emoji');
      if (!hasEmoji) {
        await db.execute('ALTER TABLE saving_goals ADD COLUMN emoji TEXT');
      }
    }
    if (oldVersion < 8) {
      final smsCols = await db.rawQuery('PRAGMA table_info(sms_transactions)');
      final hasApprox = smsCols.any((c) => c['name'] == 'timestamp_is_approximate');
      if (!hasApprox) {
        await db.execute(
          'ALTER TABLE sms_transactions ADD COLUMN timestamp_is_approximate INTEGER DEFAULT 0',
        );
      }
      // Flag legacy transactions with exact midnight timestamps as approximate
      await db.execute('''
        UPDATE sms_transactions 
        SET timestamp_is_approximate = 1 
        WHERE timestamp LIKE '%T00:00:00.000%' OR timestamp LIKE '%T00:00:00%'
      ''');
    }
    if (oldVersion < 9) {
      final txnCols = await db.rawQuery('PRAGMA table_info(transactions)');
      final hasUpdatedAt = txnCols.any((c) => c['name'] == 'updatedAt');
      if (!hasUpdatedAt) {
        await db.execute(
          'ALTER TABLE transactions ADD COLUMN updatedAt TEXT',
        );
      }
    }
    if (oldVersion < 10) {
      // Performance indexes for common query patterns
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_txn_date ON transactions(date)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_txn_category ON transactions(categoryId)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_txn_type ON transactions(type)',
      );
    }
  }

  Future<void> _createPremiumTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS recurring_payments (
        id TEXT PRIMARY KEY,
        merchantName TEXT NOT NULL,
        amount REAL NOT NULL,
        frequency TEXT NOT NULL,
        lastPaidAt TEXT NOT NULL,
        nextDueAt TEXT NOT NULL,
        categoryId TEXT NOT NULL,
        confidence REAL DEFAULT 0.6,
        source TEXT DEFAULT 'sms'
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS saving_goals (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        targetAmount REAL NOT NULL,
        currentAmount REAL NOT NULL,
        targetDate TEXT,
        createdAt TEXT NOT NULL,
        isPaused INTEGER DEFAULT 0,
        emoji TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS alerts (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        title TEXT NOT NULL,
        message TEXT NOT NULL,
        categoryId TEXT,
        createdAt TEXT NOT NULL,
        isRead INTEGER DEFAULT 0,
        alertKey TEXT
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_alert_key
      ON alerts (alertKey)
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS linked_accounts (
        id TEXT PRIMARY KEY,
        provider TEXT NOT NULL,
        accountName TEXT NOT NULL,
        accountType TEXT NOT NULL,
        lastSyncedAt TEXT,
        status TEXT DEFAULT 'active'
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS family_members (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        role TEXT DEFAULT 'member',
        monthlyLimit REAL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS tax_categories (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT
      )
    ''');
  }

  /// Create the sms_transactions table for storing auto-detected UPI transactions.
  Future<void> _createSmsTransactionsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sms_transactions (
        id TEXT PRIMARY KEY,
        amount REAL NOT NULL,
        merchantName TEXT NOT NULL,
        bankName TEXT NOT NULL DEFAULT 'Unknown Bank',
        transactionType TEXT NOT NULL,
        transactionSubType TEXT DEFAULT 'payment',
        timestamp TEXT NOT NULL,
        rawSmsBody TEXT NOT NULL,
        smsSender TEXT DEFAULT '',
        smsHash TEXT NOT NULL UNIQUE,
        category TEXT DEFAULT 'Uncategorized',
        isVerified INTEGER DEFAULT 0,
        referenceId TEXT,
        upiId TEXT,
        confidence REAL DEFAULT 0.5,
        source TEXT DEFAULT 'sms',
        timestamp_is_approximate INTEGER DEFAULT 0
      )
    ''');

    // Index on smsHash for fast duplicate lookups
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_sms_hash ON sms_transactions (smsHash)
    ''');

    // Index on timestamp for date-range queries
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_sms_timestamp ON sms_transactions (timestamp)
    ''');

    // Index on referenceId for cross-source dedup
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_sms_reference_id ON sms_transactions (referenceId)
    ''');
  }

  /// Create classification rules and unknown format logs tables.
  Future<void> _createClassificationTables(Database db) async {
    // User-defined classification rules
    await db.execute('''
      CREATE TABLE IF NOT EXISTS classification_rules (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        smsPattern TEXT NOT NULL,
        senderPattern TEXT,
        category TEXT NOT NULL,
        transactionType TEXT,
        priority INTEGER DEFAULT 0,
        isEnabled INTEGER DEFAULT 1,
        matchCount INTEGER DEFAULT 0,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        description TEXT,
        sourceLogId TEXT
      )
    ''');

    // Index for faster enabled-rule lookups
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_rules_enabled
      ON classification_rules (isEnabled, priority DESC)
    ''');

    // Unknown SMS format logs
    await db.execute('''
      CREATE TABLE IF NOT EXISTS unknown_format_logs (
        id TEXT PRIMARY KEY,
        smsBody TEXT NOT NULL,
        smsSender TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        rejectionReason TEXT DEFAULT 'unknown',
        isReviewed INTEGER DEFAULT 0,
        isResolved INTEGER DEFAULT 0,
        resolvedRuleId TEXT,
        occurrenceCount INTEGER DEFAULT 1,
        bodyHash TEXT NOT NULL,
        userNote TEXT
      )
    ''');

    // Index for body hash dedup lookups
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_unknown_body_hash
      ON unknown_format_logs (bodyHash)
    ''');

    // Index for unresolved logs
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_unknown_unresolved
      ON unknown_format_logs (isResolved, occurrenceCount DESC)
    ''');
  }

  /// Create user_feedback table for persisting parser corrections.
  Future<void> _createUserFeedbackTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS user_feedback (
        smsHash TEXT PRIMARY KEY,
        action TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        confirmedAmount REAL
      )
    ''');
  }

  Future<void> _seedDefaultCategories(Database db) async {
    final defaults = defaultCategories;
    for (final category in defaults) {
      await db.insert('categories', category.toMap());
    }
  }

  Future<void> close() async {
    final db = await database;
    db.close();
    _database = null;
    _dbCompleter = null;
  }
}
