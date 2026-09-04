import 'dart:async';
import 'dart:io' show Directory, File;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:meta/meta.dart';
import 'package:pet/core/utils/app_logger.dart';
import 'package:pet/services/platform_stub.dart'
    if (dart.library.io) 'package:pet/services/platform_native.dart'
    as platform;
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' hide databaseFactory;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show databaseFactory, databaseFactoryFfi, sqfliteFfiInit;
import 'package:pet/core/constants/categories.dart';
import 'package:pet/data/models/enums.dart';
import 'package:pet/services/recurrence_calculator.dart';
import 'package:pet/services/secure_storage_service.dart';
import 'package:pet/services/sms_service.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  static Completer<Database>? _dbCompleter;

  factory DatabaseHelper() => _instance;

  DatabaseHelper._internal();

  static void setTestDatabase(Database? db) {
    _database = db;
    if (db != null) {
      _dbCompleter = Completer<Database>()..complete(db);
    } else {
      _dbCompleter = null;
    }
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    
    if (_dbCompleter != null) {
      return _dbCompleter!.future;
    }

    final completer = Completer<Database>();
    _dbCompleter = completer;
    try {
      _database = await _initDatabase();
      completer.complete(_database);
      return _database!;
    } catch (e) {
      _dbCompleter = null;
      rethrow;
    }
  }

  /// Check if SQLCipher is supported at runtime.
  Future<bool> isSqlCipherSupported() async {
    try {
      final db = await openDatabase(inMemoryDatabasePath);
      final result = await db.rawQuery('PRAGMA cipher_version');
      await db.close();
      return result.isNotEmpty && result.first['cipher_version'] != null;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _isDatabasePlaintext(String path) async {
    try {
      final db = await openDatabase(path);
      await db.rawQuery('PRAGMA user_version');
      await db.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _encryptDatabaseInPlace(String path, String password) async {
    final tempPath = '$path.tmp';
    final db = await openDatabase(path);
    // Note: SQLite ATTACH DATABASE statement does not support parameterized query syntax (?)
    // for path and key arguments. Manual single-quote escaping (replaceAll("'", "''")) is the
    // deliberate, correct mitigation to safely construct this ATTACH command.
    final escapedTempPath = tempPath.replaceAll("'", "''");
    final escapedPassword = password.replaceAll("'", "''");
    
    await db.execute("ATTACH DATABASE '$escapedTempPath' AS encrypted KEY '$escapedPassword'");
    await db.execute("SELECT sqlcipher_export('encrypted')");
    await db.execute("DETACH DATABASE encrypted");
    await db.close();
    
    final file = File(path);
    final tempFile = File(tempPath);
    if (await file.exists()) {
      await file.delete();
    }
    await tempFile.rename(path);
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

    final cipherSupported = await isSqlCipherSupported();
    if (cipherSupported) {
      final File dbFile = File(path);
      if (await dbFile.exists() && await _isDatabasePlaintext(path)) {
        AppLogger.warn('Plaintext database detected. Migrating to encrypted database...', label: 'DB');
        try {
          final password = await SecureStorageService.instance.getDatabaseEncryptionKey();
          await _encryptDatabaseInPlace(path, password);
          AppLogger.info('Migration to encrypted database complete.', label: 'DB');
        } catch (e) {
          AppLogger.error('Encryption migration failed', error: e, label: 'DB');
        }
      }

      final password = await SecureStorageService.instance.getDatabaseEncryptionKey();
      return await openDatabase(
        path,
        version: 17,
        password: password,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
        onOpen: (db) async {
          // Enable foreign key constraint enforcement for every connection.
          await db.execute('PRAGMA foreign_keys = ON');
        },
      );
    } else {
      AppLogger.warn('SQLCipher is not supported on this platform. Opening in plaintext.', label: 'DB');
      return await openDatabase(
        path,
        version: 17,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
        onOpen: (db) async {
          // Enable foreign key constraint enforcement for every connection.
          await db.execute('PRAGMA foreign_keys = ON');
        },
      );
    }
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
        AppLogger.info('Integrity check: ok', label: 'DB');
        return true;
      } else {
        AppLogger.error('Integrity check FAILED: $status', label: 'DB');
        return false;
      }
    } catch (e) {
      AppLogger.error('Integrity check error', error: e, label: 'DB');
      return false;
    }
  }

  @visibleForTesting
  Future<void> onCreateForTesting(Database db, int version) async {
    await _onCreate(db, version);
  }

  @visibleForTesting
  Future<void> onUpgradeForTesting(Database db, int oldVersion, int newVersion) async {
    await _onUpgrade(db, oldVersion, newVersion);
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
        updatedAt TEXT,
        recurringRuleId TEXT,
        occurrenceDate TEXT
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_txn_recurring
      ON transactions (recurringRuleId)
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

    // Create sms_processing_state table
    await _createSmsProcessingStateTable(db);

    // Create classification system tables
    await _createClassificationTables(db);

    // Create user feedback table
    await _createUserFeedbackTable(db);

    // Create premium feature tables
    await _createPremiumTables(db);

    // Create recurring transaction tables (rules and occurrences)
    await _createRecurringTables(db);

    // Create sync queue table
    await _createSyncQueueTable(db);

    // Create system watermarks table
    await _createSystemWatermarksTable(db);

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
    if (oldVersion < 11) {
      // Create transaction sync queue table
      await _createSyncQueueTable(db);

      // Backfill legacy transactions where updatedAt is null or empty
      await db.execute('''
        UPDATE transactions 
        SET updatedAt = date 
        WHERE updatedAt IS NULL OR updatedAt = ''
      ''');
    }
    if (oldVersion < 12) {
      await _migrateUnknownFormatLogsV12(db);
    }
    if (oldVersion < 13) {
      await _createSmsProcessingStateTable(db);
      await db.execute('''
        INSERT OR IGNORE INTO sms_processing_state (id, smsHash, status, processedAt, reason)
        SELECT id, smsHash, 'accepted', timestamp, 'migrated_from_sms_transactions'
        FROM sms_transactions
      ''');
    }
    if (oldVersion < 14) {
      await _createSystemWatermarksTable(db);
    }
    if (oldVersion < 15) {
      await _migrateToV15(db);
    }
    if (oldVersion < 16) {
      await _migrateToV16(db);
    }
    if (oldVersion < 17) {
      await _migrateToV17(db);
    }
  }

  /// Create recurring_rules and recurring_occurrences tables for recurring transaction scheduling.
  Future<void> _createRecurringTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS recurring_rules (
        id TEXT PRIMARY KEY,
        amount REAL NOT NULL,
        type TEXT NOT NULL,
        categoryId TEXT NOT NULL,
        note TEXT DEFAULT '',
        paymentMethod TEXT DEFAULT 'UPI',
        frequency TEXT NOT NULL,
        interval INTEGER DEFAULT 1,
        startDate TEXT NOT NULL,
        endDate TEXT,
        nextOccurrenceDate TEXT NOT NULL,
        lastGeneratedDate TEXT,
        isActive INTEGER DEFAULT 1,
        merchantName TEXT,
        taxCategory TEXT,
        source TEXT DEFAULT 'manual',
        accountId TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        userId TEXT
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_recurring_rules_active
      ON recurring_rules (isActive, nextOccurrenceDate)
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS recurring_occurrences (
        id TEXT PRIMARY KEY,
        ruleId TEXT NOT NULL,
        scheduledDate TEXT NOT NULL,
        status TEXT NOT NULL,
        transactionId TEXT,
        generatedAt TEXT,
        updatedAt TEXT NOT NULL,
        UNIQUE(ruleId, scheduledDate)
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_recurring_occ_rule
      ON recurring_occurrences (ruleId)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_recurring_occ_txn
      ON recurring_occurrences (transactionId)
    ''');
  }

  /// Migration v15: Add recurring columns to transactions, create recurring_rules
  /// and recurring_occurrences tables, and safely backfill legacy recurring transactions.
  Future<void> _migrateToV15(Database db) async {
    // 1. Add recurringRuleId and occurrenceDate columns to transactions if missing
    final txnCols = await db.rawQuery('PRAGMA table_info(transactions)');
    final hasRecurringRuleId = txnCols.any((c) => c['name'] == 'recurringRuleId');
    if (!hasRecurringRuleId) {
      await db.execute('ALTER TABLE transactions ADD COLUMN recurringRuleId TEXT');
    }
    final hasOccurrenceDate = txnCols.any((c) => c['name'] == 'occurrenceDate');
    if (!hasOccurrenceDate) {
      await db.execute('ALTER TABLE transactions ADD COLUMN occurrenceDate TEXT');
    }
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_txn_recurring
      ON transactions (recurringRuleId)
    ''');

    // 2. Create recurring tables
    await _createRecurringTables(db);

    // 3. Backfill legacy recurring transactions
    try {
      final legacyRows = await db.query(
        'transactions',
        where: 'isRecurring = 1 AND recurringFrequency IS NOT NULL AND (recurringRuleId IS NULL OR recurringRuleId = \'\')',
      );

      for (final row in legacyRows) {
        final txnId = row['id'] as String;
        final amount = (row['amount'] as num).toDouble();
        final type = row['type'] as String? ?? 'expense';
        final categoryId = row['categoryId'] as String? ?? 'other';
        final dateStr = row['date'] as String;
        final note = row['note'] as String? ?? '';
        final paymentMethod = row['paymentMethod'] as String? ?? 'UPI';
        final freqStr = row['recurringFrequency'] as String?;
        final merchantName = row['merchantName'] as String?;
        final taxCategory = row['taxCategory'] as String?;
        final source = row['source'] as String? ?? 'manual';
        final accountId = row['accountId'] as String?;

        final date = DateTime.tryParse(dateStr) ?? DateTime.now();
        final freq = RecurringFrequency.fromJson(freqStr) ?? RecurringFrequency.monthly;
        final nextDate = RecurrenceCalculator.computeNextOccurrence(
          anchorDate: date,
          currentOccurrence: date,
          frequency: freq,
        );

        final ruleId = 'rule_legacy_$txnId';
        final nowStr = DateTime.now().toIso8601String();

        await db.insert('recurring_rules', {
          'id': ruleId,
          'amount': amount,
          'type': type,
          'categoryId': categoryId,
          'note': note,
          'paymentMethod': paymentMethod,
          'frequency': freq.toJson(),
          'interval': 1,
          'startDate': date.toIso8601String(),
          'endDate': null,
          'nextOccurrenceDate': nextDate.toIso8601String(),
          'lastGeneratedDate': date.toIso8601String(),
          'isActive': 1,
          'merchantName': merchantName,
          'taxCategory': taxCategory,
          'source': source,
          'accountId': accountId,
          'createdAt': date.toIso8601String(),
          'updatedAt': nowStr,
          'userId': null,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);

        final occId = '${ruleId}_${date.toIso8601String()}';
        await db.insert('recurring_occurrences', {
          'id': occId,
          'ruleId': ruleId,
          'scheduledDate': date.toIso8601String(),
          'status': 'generated',
          'transactionId': txnId,
          'generatedAt': date.toIso8601String(),
          'updatedAt': nowStr,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);

        await db.update(
          'transactions',
          {
            'recurringRuleId': ruleId,
            'occurrenceDate': date.toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [txnId],
        );
      }
    } catch (e) {
      AppLogger.error('Failed to backfill legacy recurring transactions', error: e, label: 'DB');
    }
  }

  /// Create system_watermarks table for atomic transaction-bound watermark persistence.
  Future<void> _createSystemWatermarksTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS system_watermarks (
        key TEXT PRIMARY KEY,
        value INTEGER NOT NULL,
        updatedAt TEXT NOT NULL
      )
    ''');
  }

  /// Create sms_processing_state table for tracking processed, ignored, rejected, and deleted SMS messages.
  Future<void> _createSmsProcessingStateTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sms_processing_state (
        id TEXT PRIMARY KEY,
        smsHash TEXT NOT NULL UNIQUE,
        status TEXT NOT NULL,
        processedAt TEXT NOT NULL,
        reason TEXT
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_sms_processing_hash ON sms_processing_state (smsHash)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_sms_processing_status ON sms_processing_state (status)
    ''');
  }

  /// Migrate to v16: Recurring Financial Commitments upgrade (status, autopay, price changes, payment history).
  Future<void> _migrateToV16(Database db) async {
    try {
      final cols = await db.rawQuery('PRAGMA table_info(recurring_payments)');
      final colNames = cols.map((c) => c['name'] as String).toSet();

      if (!colNames.contains('status')) {
        await db.execute("ALTER TABLE recurring_payments ADD COLUMN status TEXT DEFAULT 'confirmed'");
      }
      if (!colNames.contains('isAutopay')) {
        await db.execute('ALTER TABLE recurring_payments ADD COLUMN isAutopay INTEGER DEFAULT 0');
      }
      if (!colNames.contains('previousAmount')) {
        await db.execute('ALTER TABLE recurring_payments ADD COLUMN previousAmount REAL');
      }
      if (!colNames.contains('priceChangeDetectedAt')) {
        await db.execute('ALTER TABLE recurring_payments ADD COLUMN priceChangeDetectedAt TEXT');
      }
      if (!colNames.contains('notes')) {
        await db.execute('ALTER TABLE recurring_payments ADD COLUMN notes TEXT');
      }
      if (!colNames.contains('createdAt')) {
        await db.execute('ALTER TABLE recurring_payments ADD COLUMN createdAt TEXT');
        await db.execute('UPDATE recurring_payments SET createdAt = lastPaidAt WHERE createdAt IS NULL');
      }
      if (!colNames.contains('updatedAt')) {
        await db.execute('ALTER TABLE recurring_payments ADD COLUMN updatedAt TEXT');
        await db.execute('UPDATE recurring_payments SET updatedAt = lastPaidAt WHERE updatedAt IS NULL');
      }
      if (!colNames.contains('detectionReason')) {
        await db.execute('ALTER TABLE recurring_payments ADD COLUMN detectionReason TEXT');
      }

      await db.execute('''
        CREATE TABLE IF NOT EXISTS recurring_payment_history (
          id TEXT PRIMARY KEY,
          recurringPaymentId TEXT NOT NULL,
          amount REAL NOT NULL,
          paidAt TEXT NOT NULL,
          source TEXT DEFAULT 'manual',
          transactionId TEXT,
          notes TEXT,
          createdAt TEXT NOT NULL
        )
      ''');

      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_rec_hist_payment_id
        ON recurring_payment_history (recurringPaymentId)
      ''');
    } catch (e) {
      AppLogger.error('Failed to run v16 database migration', error: e, label: 'DB');
    }
  }

  /// Migrate to v17: Alerts Centre 2.0 (production-grade financial intelligence upgrade).
  Future<void> _migrateToV17(Database db) async {
    try {
      final cols = await db.rawQuery('PRAGMA table_info(alerts)');
      final colNames = cols.map((c) => c['name'] as String).toSet();

      final newColumns = <String, String>{
        'stage': 'TEXT',
        'severity': "TEXT NOT NULL DEFAULT 'warning'",
        'isDismissed': 'INTEGER DEFAULT 0',
        'amount': 'REAL',
        'targetAmount': 'REAL',
        'ratio': 'REAL',
        'transactionId': 'TEXT',
        'recurringPaymentId': 'TEXT',
        'goalId': 'TEXT',
        'period': 'TEXT',
        'actionType': 'TEXT',
        'actionPayload': 'TEXT',
        'updatedAt': 'TEXT',
        'resolvedAt': 'TEXT',
        'expiresAt': 'TEXT',
      };

      for (final entry in newColumns.entries) {
        if (!colNames.contains(entry.key)) {
          await db.execute('ALTER TABLE alerts ADD COLUMN ${entry.key} ${entry.value}');
        }
      }

      // Backfill existing alerts with sensible defaults
      await db.execute('''
        UPDATE alerts 
        SET severity = CASE 
          WHEN type = 'budget' AND title LIKE '%exceeded%' THEN 'critical'
          WHEN type = 'cashflow' THEN 'critical'
          WHEN type = 'bill' THEN 'info'
          ELSE 'warning'
        END
        WHERE severity IS NULL OR severity = ''
      ''');

      // Deduplicate any historical identical alertKeys before enforcing unique index
      await db.execute('''
        DELETE FROM alerts 
        WHERE rowid NOT IN (
          SELECT MIN(rowid) FROM alerts GROUP BY alertKey
        ) AND alertKey IS NOT NULL AND alertKey != ''
      ''');

      // Drop old non-unique index and create unique index on alertKey
      await db.execute('DROP INDEX IF EXISTS idx_alert_key');
      await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_alert_key ON alerts (alertKey)');

      // Create composite and filtering indexes
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_alerts_active 
        ON alerts (isDismissed, isRead, createdAt DESC)
      ''');
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_alerts_type 
        ON alerts (type, createdAt DESC)
      ''');
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_alerts_period 
        ON alerts (period)
      ''');
    } catch (e) {
      AppLogger.error('Failed to run v17 database migration', error: e, label: 'DB');
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
        source TEXT DEFAULT 'sms',
        status TEXT DEFAULT 'confirmed',
        isAutopay INTEGER DEFAULT 0,
        previousAmount REAL,
        priceChangeDetectedAt TEXT,
        notes TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        detectionReason TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS recurring_payment_history (
        id TEXT PRIMARY KEY,
        recurringPaymentId TEXT NOT NULL,
        amount REAL NOT NULL,
        paidAt TEXT NOT NULL,
        source TEXT DEFAULT 'manual',
        transactionId TEXT,
        notes TEXT,
        createdAt TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_rec_hist_payment_id
      ON recurring_payment_history (recurringPaymentId)
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
        stage TEXT,
        severity TEXT NOT NULL DEFAULT 'warning',
        title TEXT NOT NULL,
        message TEXT NOT NULL,
        alertKey TEXT UNIQUE,
        categoryId TEXT,
        amount REAL,
        targetAmount REAL,
        ratio REAL,
        transactionId TEXT,
        recurringPaymentId TEXT,
        goalId TEXT,
        period TEXT,
        isRead INTEGER DEFAULT 0,
        isDismissed INTEGER DEFAULT 0,
        actionType TEXT,
        actionPayload TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT,
        resolvedAt TEXT,
        expiresAt TEXT
      )
    ''');

    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_alert_key
      ON alerts (alertKey)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_alerts_active
      ON alerts (isDismissed, isRead, createdAt DESC)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_alerts_type
      ON alerts (type, createdAt DESC)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_alerts_period
      ON alerts (period)
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
        userNote TEXT,
        created_at INTEGER
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

  Future<void> _createSyncQueueTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS transaction_sync_queue (
        id TEXT PRIMARY KEY,
        transactionId TEXT NOT NULL,
        action TEXT NOT NULL,
        payload TEXT,
        timestamp INTEGER NOT NULL,
        userId TEXT NOT NULL,
        retryCount INTEGER DEFAULT 0,
        lastAttemptAt INTEGER DEFAULT 0,
        lastError TEXT
      )
    ''');
  }

  /// Migration v12: Add created_at column to unknown_format_logs, redact existing rows,
  /// enforce 30-day TTL and 500-row cap.
  Future<void> _migrateUnknownFormatLogsV12(Database db) async {
    // 1. Ensure created_at column exists
    final columns = await db.rawQuery('PRAGMA table_info(unknown_format_logs)');
    final hasCreatedAt = columns.any((c) => c['name'] == 'created_at');
    if (!hasCreatedAt) {
      await db.execute(
        'ALTER TABLE unknown_format_logs ADD COLUMN created_at INTEGER',
      );
    }

    // 2. Migrate existing unredacted rows and backfill created_at
    final rows = await db.query('unknown_format_logs');
    for (final row in rows) {
      final id = row['id'] as String;
      final rawBody = row['smsBody'] as String? ?? '';
      final timestampStr = row['timestamp'] as String? ?? '';
      final existingCreatedAt = row['created_at'] as int?;

      final redactedBody = SmsService.redactSensitiveData(rawBody);

      final int createdAtMillis;
      if (existingCreatedAt != null) {
        createdAtMillis = existingCreatedAt;
      } else {
        final parsedTime = DateTime.tryParse(timestampStr);
        createdAtMillis = parsedTime != null
            ? parsedTime.millisecondsSinceEpoch
            : DateTime.now().millisecondsSinceEpoch;
      }

      await db.update(
        'unknown_format_logs',
        {
          'smsBody': redactedBody,
          'created_at': createdAtMillis,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    }

    // 3. Enforce 30-day TTL cleanup
    final cutoffMillis =
        DateTime.now().subtract(const Duration(days: 30)).millisecondsSinceEpoch;
    await db.delete(
      'unknown_format_logs',
      where: 'created_at < ?',
      whereArgs: [cutoffMillis],
    );

    // 4. Enforce 500-row cap (evict oldest)
    await db.execute('''
      DELETE FROM unknown_format_logs 
      WHERE id NOT IN (
        SELECT id FROM unknown_format_logs 
        ORDER BY COALESCE(created_at, 0) DESC, timestamp DESC 
        LIMIT 500
      )
    ''');
  }

  Future<void> close() async {
    final db = await database;
    db.close();
    _database = null;
    _dbCompleter = null;
  }
}
