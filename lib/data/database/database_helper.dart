import 'dart:async';
import 'dart:io' show Directory, File;
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:meta/meta.dart';
import 'package:pet/services/platform_stub.dart'
    if (dart.library.io) 'package:pet/services/platform_native.dart'
    as platform;
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' hide databaseFactory;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show databaseFactory, databaseFactoryFfi, sqfliteFfiInit;
import 'package:pet/core/constants/categories.dart';
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
        debugPrint('[DB] ⚠️ Plaintext database detected. Migrating to encrypted database...');
        try {
          final password = await SecureStorageService.instance.getDatabaseEncryptionKey();
          await _encryptDatabaseInPlace(path, password);
          debugPrint('[DB] ✅ Migration to encrypted database complete.');
        } catch (e) {
          debugPrint('[DB] ❌ Encryption migration failed: $e');
        }
      }

      final password = await SecureStorageService.instance.getDatabaseEncryptionKey();
      return await openDatabase(
        path,
        version: 12,
        password: password,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
        onOpen: (db) async {
          // Enable foreign key constraint enforcement for every connection.
          await db.execute('PRAGMA foreign_keys = ON');
        },
      );
    } else {
      debugPrint('[DB] SQLCipher is not supported on this platform. Opening in plaintext.');
      return await openDatabase(
        path,
        version: 12,
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

  @visibleForTesting
  Future<void> onCreateForTesting(Database db, int version) async {
    await _onCreate(db, version);
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

    // Create sync queue table
    await _createSyncQueueTable(db);

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
